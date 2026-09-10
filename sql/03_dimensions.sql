/*
   03_dimensions.sql
   Builds the three dimension tables in analytics from the staging tables.
   Natural keys throughout (CCN, DRG code, year): all three are stable CMS
   identifiers, so surrogate keys add indirection without value at this scale.
   Run after 02_quality_checks.sql passes.
*/

DROP TABLE IF EXISTS analytics.dim_hospital CASCADE;
DROP TABLE IF EXISTS analytics.dim_drg CASCADE;
DROP TABLE IF EXISTS analytics.dim_year CASCADE;

-- 1. dim_year
-- One column. Power BI needs a table on the "one" side of the relationship to
-- filter years cleanly; a single-column dimension is the correct minimum.

CREATE TABLE analytics.dim_year (
    data_year SMALLINT PRIMARY KEY
);

INSERT INTO analytics.dim_year (data_year)
SELECT DISTINCT data_year
FROM staging.inpatient_provider_service
ORDER BY data_year;

-- 2. dim_hospital
-- Grain: one row per hospital (CCN) across all three years. A hospital present
-- in 2022 and gone by 2024 still has fact rows and must resolve here.
--
-- Attributes come from the most recent year in which the hospital appears:
-- names and addresses change, and the latest value is the most useful to
-- display. RUCA is the exception, taken from 2024 only, because 2024 has zero
-- nulls against 677 in 2022 and the value is unstable across years for the
-- same hospital (CCN 010001 is 1.0 in 2022 and 2.0 in 2023). Hospitals absent
-- from 2024 get NULL rather than a stale value.
--
-- Hospitals with no HGI match are carried with NULL HGI attributes rather than
-- excluded: dropping hospitals from a cost analysis because a reference file
-- lacks their ownership type would distort national totals.
--
-- hospital_type is excluded - single-valued (Acute Care Hospitals) across all
-- matched hospitals, so it is a scope statement rather than an attribute.

CREATE TABLE analytics.dim_hospital (
    ccn TEXT PRIMARY KEY,
    hospital_name TEXT NOT NULL,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    zip5 TEXT NOT NULL,
    state_fips SMALLINT NOT NULL,
    ruca NUMERIC(4,1),
    ruca_desc TEXT,
    county_name TEXT,
    hospital_ownership TEXT,
    emergency_services TEXT,
    hospital_overall_rating SMALLINT
);

WITH latest AS (
    SELECT DISTINCT ON (rndrng_prvdr_ccn)
        rndrng_prvdr_ccn AS ccn,
        rndrng_prvdr_org_name AS hospital_name,
        rndrng_prvdr_city AS city,
        rndrng_prvdr_state_abrvtn AS state,
        rndrng_prvdr_zip5 AS zip5,
        rndrng_prvdr_state_fips AS state_fips
    FROM staging.inpatient_provider_service
    ORDER BY rndrng_prvdr_ccn, data_year DESC
),
ruca_2024 AS (
    SELECT DISTINCT ON (rndrng_prvdr_ccn)
        rndrng_prvdr_ccn AS ccn,
        rndrng_prvdr_ruca AS ruca,
        rndrng_prvdr_ruca_desc AS ruca_desc
    FROM staging.inpatient_provider_service
    WHERE data_year = 2024
    ORDER BY rndrng_prvdr_ccn
)
INSERT INTO analytics.dim_hospital (
    ccn, 
    hospital_name, 
    city, 
    state, 
    zip5, 
    state_fips,
    ruca, 
    ruca_desc,
    county_name, 
    hospital_ownership, 
    emergency_services, 
    hospital_overall_rating
)
SELECT
    l.ccn,
    l.hospital_name,
    l.city,
    l.state,
    l.zip5,
    l.state_fips,
    r.ruca,
    r.ruca_desc,
    h.county_name,
    h.hospital_ownership,
    h.emergency_services,
    h.hospital_overall_rating
FROM latest l
LEFT JOIN ruca_2024 r ON r.ccn = l.ccn
LEFT JOIN staging.hospital_general_information h ON h.facility_id = l.ccn;

-- Coverage of the two optional sources. Figures recorded in 
-- docs/cleaning_decisions.md.
SELECT
    COUNT(*) AS hospitals,
    COUNT(*) FILTER (WHERE ruca IS NULL) AS no_2024_ruca,
    COUNT(*) FILTER (WHERE hospital_ownership IS NULL) AS no_hgi_match
FROM analytics.dim_hospital;

-- Are the unmatched hospitals systematically smaller? Compares total
-- discharges for hospitals with and without an HGI match.
SELECT
    h.hospital_ownership IS NULL AS unmatched,
    COUNT(*) AS hospitals,
    ROUND(AVG(v.discharges), 1) AS mean_discharges,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.discharges) AS median_discharges
FROM analytics.dim_hospital h
JOIN (
    SELECT rndrng_prvdr_ccn AS ccn, SUM(tot_dschrgs) AS discharges
    FROM staging.inpatient_provider_service
    GROUP BY rndrng_prvdr_ccn
) v ON v.ccn = h.ccn
GROUP BY 1;

-- 3. dim_drg
-- Grain: one row per DRG code. Holds the union across all three years
-- (533 / 534 / 540 per year, 488 common to all three), because every DRG
-- referenced by any fact row must resolve.
--
-- Descriptions come from the most recent year the code appears, matching the
-- rule used for hospital attributes.
--
-- is_surgical is derived by keyword matching on the description. This is an
-- approximation: the correct method maps each DRG to its MDC and uses the
-- published medical/surgical split, which needs a reference table not included
-- in the four source files. The keyword list and its resulting split are
-- recorded in docs/methodology.md.
--
-- in_all_years flags the 488 codes present in every year, so DRG-level trend
-- visuals can filter to a stable set without hardcoding a list.

CREATE TABLE analytics.dim_drg (
    drg_cd TEXT PRIMARY KEY,
    drg_desc TEXT NOT NULL,
    is_surgical BOOLEAN NOT NULL,
    in_all_years BOOLEAN NOT NULL
);

WITH latest AS (
    SELECT DISTINCT ON (drg_cd)
        drg_cd,
        drg_desc
    FROM staging.inpatient_provider_service
    ORDER BY drg_cd, data_year DESC
),
year_span AS (
    SELECT drg_cd, COUNT(DISTINCT data_year) AS year_count
    FROM staging.inpatient_provider_service
    GROUP BY drg_cd
)
INSERT INTO analytics.dim_drg (drg_cd, drg_desc, is_surgical, in_all_years)
SELECT
    l.drg_cd,
    l.drg_desc,
    l.drg_desc ILIKE ANY (ARRAY[
        '%PROCEDURE%', '%SURGERY%', '%SURGICAL%', '%REPLACEMENT%',
        '%IMPLANT%', '%TRANSPLANT%', '%BYPASS%', '%RESECTION%',
        '%CRANIOTOMY%', '%AMPUTATION%', '%REVISION%', '%FUSION%',
        '%GRAFT%', '%EXCISION%', '%REATTACHMENT%', '%DEBRIDEMENT%',
        '%TRACHEOSTOM%', '%ECMO%'
    ]),
    y.year_count = 3
FROM latest l
JOIN year_span y ON y.drg_cd = l.drg_cd;

-- Surgical split. Expect 35-55% of codes flagged surgical, with a lower share
-- of discharges than of codes, since medical DRGs are higher volume. Outside
-- that range, inspect descriptions on both sides and adjust the keyword list.
SELECT
    is_surgical,
    COUNT(*) AS drg_codes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_codes
FROM analytics.dim_drg
GROUP BY is_surgical;