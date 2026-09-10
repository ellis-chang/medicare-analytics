/*
   04_facts.sql
   Builds the two fact tables. Foreign keys to the dimensions are declared so a
   load that would orphan a fact row fails loudly rather than producing a
   dashboard with silently missing data.
   Run after 03_dimensions.sql.
*/

DROP TABLE IF EXISTS analytics.fact_hospital_drg CASCADE;
DROP TABLE IF EXISTS analytics.fact_hospital_quality CASCADE;

-- 1. fact_hospital_drg
-- Grain: one row per hospital per DRG per year, from
-- staging.inpatient_provider_service (438,048 rows).
--
-- The payment columns are per-discharge averages within the hospital-DRG cell,
-- not totals. They cannot be averaged directly at any higher grain. Every
-- aggregate must weight by tot_dschrgs:
--     SUM(tot_dschrgs * avg_tot_pymt_amt) / SUM(tot_dschrgs)
-- The naive mean overstates the national figure by roughly 4%, because
-- low-volume DRGs skew expensive.
--
-- Weighted totals are not precomputed here. The weighting is implemented as a
-- DAX measure in Stage 6, which is where the iterator pattern is learned.
--
-- No filtering happens in this table. The 25% coverage exclusion and any
-- volume thresholds depend on user context and belong in DAX where they can
-- respond to slicers. This is a faithful copy of the source at the same grain.

CREATE TABLE analytics.fact_hospital_drg (
    ccn TEXT NOT NULL REFERENCES analytics.dim_hospital(ccn),
    drg_cd TEXT NOT NULL REFERENCES analytics.dim_drg(drg_cd),
    data_year SMALLINT NOT NULL REFERENCES analytics.dim_year(data_year),
    tot_dschrgs INT NOT NULL,
    avg_submtd_cvrd_chrg NUMERIC(14, 6) NOT NULL,
    avg_tot_pymt_amt NUMERIC(14, 6) NOT NULL,
    avg_mdcr_pymt_amt NUMERIC(14, 6) NOT NULL,
    PRIMARY KEY (ccn, drg_cd, data_year)
);

INSERT INTO analytics.fact_hospital_drg (
    ccn, 
    drg_cd, 
    data_year, 
    tot_dschrgs,
    avg_submtd_cvrd_chrg, 
    avg_tot_pymt_amt, 
    avg_mdcr_pymt_amt
)
SELECT
    rndrng_prvdr_ccn,
    drg_cd,
    data_year,
    tot_dschrgs,
    avg_submtd_cvrd_chrg,
    avg_tot_pymt_amt,
    avg_mdcr_pymt_amt
FROM staging.inpatient_provider_service;

-- 2. fact_hospital_quality
-- Grain: one row per hospital per HRRP measure, from staging.hrrp.
--
-- Not year-partitioned. All rows share one performance period, 2021-07-01 to
-- 2024-06-30, which overlaps but does not match the claims years. That
-- mismatch is a documented limitation, not something to engineer around.
--
-- Suppression is heavy and uneven: 6,610 rows have no excess_readmission_ratio,
-- 10,088 have no denominator, only 8,037 have both. Every measure column is
-- nullable. Nothing is imputed.
--
-- All six measures are loaded. Filtering to the two with adequate coverage
-- (pneumonia 88.9%, heart failure 85.8%) happens in the dashboard, not the
-- model, so the choice stays visible and reversible.
--
-- HRRP rows whose CCN has no dim_hospital match are excluded: a hospital with
-- no claims data contributes nothing to a cost-quality comparison.
--
-- condition holds a readable label, because READM-30-HIP-KNEE-HRRP does not
-- belong on a dashboard axis. Six values do not justify a separate dimension.

CREATE TABLE analytics.fact_hospital_quality (
    ccn TEXT NOT NULL REFERENCES analytics.dim_hospital(ccn),
    measure_name TEXT NOT NULL,
    condition TEXT NOT NULL,
    number_of_discharges INT,
    excess_readmission_ratio NUMERIC(8, 4),
    predicted_readmission_rate NUMERIC(8, 4),
    expected_readmission_rate NUMERIC(8, 4),
    number_of_readmissions INT,
    footnote SMALLINT,
    PRIMARY KEY (ccn, measure_name)
);

-- condition is NOT NULL, so an unmapped measure_name fails the insert. That is
-- intentional: a seventh measure in a future release should break the load
-- rather than appear as a blank label on the dashboard.
INSERT INTO analytics.fact_hospital_quality (
    ccn, 
    measure_name, 
    condition, 
    number_of_discharges,
    excess_readmission_ratio, 
    predicted_readmission_rate,
    expected_readmission_rate, 
    number_of_readmissions, 
    footnote
)
SELECT
    q.facility_id,
    q.measure_name,
    CASE q.measure_name
        WHEN 'READM-30-AMI-HRRP' THEN 'Heart attack'
        WHEN 'READM-30-CABG-HRRP' THEN 'Coronary artery bypass'
        WHEN 'READM-30-COPD-HRRP' THEN 'COPD'
        WHEN 'READM-30-HF-HRRP' THEN 'Heart failure'
        WHEN 'READM-30-HIP-KNEE-HRRP' THEN 'Hip/knee replacement'
        WHEN 'READM-30-PN-HRRP' THEN 'Pneumonia'
    END,
    q.number_of_discharges,
    q.excess_readmission_ratio,
    q.predicted_readmission_rate,
    q.expected_readmission_rate,
    q.number_of_readmissions,
    q.footnote
FROM staging.hrrp q
WHERE EXISTS (
    SELECT 1 FROM analytics.dim_hospital h WHERE h.ccn = q.facility_id
);

-- How many HRRP rows were dropped for having no claims data? Figures 
-- recorded in docs/cleaning_decisions.md.
SELECT
    (SELECT COUNT(*) FROM staging.hrrp) AS staging_rows,
    (SELECT COUNT(*) FROM analytics.fact_hospital_quality) AS loaded_rows,
    (SELECT COUNT(*) FROM staging.hrrp) - (SELECT COUNT(*) FROM analytics.fact_hospital_quality) AS excluded_rows;

-- 3. Indexes
-- The primary keys cover the joins Power BI issues on import. No additional
-- indexes: at 438k rows on a local database, sequential scans are fast, and
-- indexes added speculatively are noise in the repo.