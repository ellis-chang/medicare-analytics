/*
   05_integrity_checks.sql
   Verifies the star schema is a faithful restructuring of staging. Same
   discipline as 02_quality_checks.sql: every check has an expected value.
   Stage 3 is complete when all checks pass.
*/

-- 1. Dimension row counts
-- Expect: dim_hospital 3063, dim_drg 588, dim_year 3
SELECT 'dim_hospital' AS table_name, COUNT(*) AS rows FROM analytics.dim_hospital
UNION ALL
SELECT 'dim_drg', COUNT(*) FROM analytics.dim_drg
UNION ALL
SELECT 'dim_year', COUNT(*) FROM analytics.dim_year;

-- Source-of-truth counts for the above, straight from staging.
SELECT
    COUNT(DISTINCT rndrng_prvdr_ccn) AS distinct_ccns,
    COUNT(DISTINCT drg_cd) AS distinct_drgs,
    COUNT(DISTINCT data_year) AS distinct_years
FROM staging.inpatient_provider_service;

-- Stable DRG codes present in all three years
-- Expect: 488
SELECT COUNT(*) AS in_all_years
FROM analytics.dim_drg
WHERE in_all_years;

-- 2. Fact row counts
-- Expect: fact_hospital_drg 438048, fact_hospital_quality 17682
SELECT 'fact_hospital_drg' AS table_name, COUNT(*) AS rows FROM analytics.fact_hospital_drg
UNION ALL
SELECT 'fact_hospital_quality', COUNT(*) FROM analytics.fact_hospital_quality;

-- 3. Referential integrity
-- The foreign keys enforce this at insert time, so these are zero by
-- construction. The check documents the guarantee and catches the case where a
-- constraint was dropped to get past an error.
-- Expect: 0 on all four rows.
SELECT 'fact_drg orphan ccn' AS check_name, COUNT(*) AS orphans
FROM analytics.fact_hospital_drg f
WHERE NOT EXISTS (SELECT 1 FROM analytics.dim_hospital d WHERE d.ccn = f.ccn)
UNION ALL
SELECT 'fact_drg orphan drg', COUNT(*)
FROM analytics.fact_hospital_drg f
WHERE NOT EXISTS (SELECT 1 FROM analytics.dim_drg d WHERE d.drg_cd = f.drg_cd)
UNION ALL
SELECT 'fact_drg orphan year', COUNT(*)
FROM analytics.fact_hospital_drg f
WHERE NOT EXISTS (SELECT 1 FROM analytics.dim_year d WHERE d.data_year = f.data_year)
UNION ALL
SELECT 'fact_quality orphan ccn', COUNT(*)
FROM analytics.fact_hospital_quality q
WHERE NOT EXISTS (SELECT 1 FROM analytics.dim_hospital d WHERE d.ccn = q.ccn);

-- 4. Orphaned dimension rows
-- Dimension rows no fact references. Not an error, but the counts must be
-- explainable.
-- Expect: 0 with no cost rows, since dim_hospital is built from the claims
-- data; 116 with no quality rows, being the hospitals absent from HRRP.
SELECT 'hospitals with no cost rows' AS check_name, COUNT(*) AS hospitals
FROM analytics.dim_hospital h
WHERE NOT EXISTS (SELECT 1 FROM analytics.fact_hospital_drg f WHERE f.ccn = h.ccn)
UNION ALL
SELECT 'hospitals with no quality rows', COUNT(*)
FROM analytics.dim_hospital h
WHERE NOT EXISTS (SELECT 1 FROM analytics.fact_hospital_quality q WHERE q.ccn = h.ccn);

-- 5. No fact rows lost moving from staging
-- Expect: 0 in both difference columns, all three years.
SELECT
    s.data_year,
    s.rows - f.rows AS row_diff,
    s.discharges - f.discharges AS discharge_diff
FROM (
    SELECT data_year, COUNT(*) AS rows, SUM(tot_dschrgs) AS discharges
    FROM staging.inpatient_provider_service
    GROUP BY data_year
) s
JOIN (
    SELECT data_year, COUNT(*) AS rows, SUM(tot_dschrgs) AS discharges
    FROM analytics.fact_hospital_drg
    GROUP BY data_year
) f ON f.data_year = s.data_year
ORDER BY s.data_year;

-- 6. ANCHOR: discharge-weighted national average payment per discharge
-- Expect: 2022 | 17772.244791
--         2023 | 17823.650656
--         2024 | 18359.985541
-- If these match, the star schema is faithful and Stage 3 is done. If not, a
-- join lost or duplicated rows, and no dashboard work will fix it. These are
-- also the values every DAX measure in Stage 6 must reproduce.
SELECT
    data_year,
    SUM(tot_dschrgs * avg_tot_pymt_amt) / SUM(tot_dschrgs) AS weighted_avg_payment
FROM analytics.fact_hospital_drg
GROUP BY data_year ORDER BY data_year;

-- 7. Case-mix sanity check
-- The project rests on hospitals having different DRG mixes. If they did not,
-- there would be nothing to adjust for.
-- Expect (2024): min 1, median 32, max 387
WITH per_hospital AS (
    SELECT ccn, COUNT(DISTINCT drg_cd) AS drg_count
    FROM analytics.fact_hospital_drg
    WHERE data_year = 2024
    GROUP BY ccn
)
SELECT
    MIN(drg_count) AS min_drgs,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY drg_count) AS median_drgs,
    MAX(drg_count) AS max_drgs
FROM per_hospital;

-- 8. Surgical flag distribution
-- Expect: 35-55% of codes flagged surgical, with a lower share of discharges
-- than of codes. Outside that range, revisit the keyword list in 03.
WITH drg_side AS (
    SELECT d.drg_cd, d.is_surgical, SUM(f.tot_dschrgs) AS discharges
    FROM analytics.dim_drg d
    JOIN analytics.fact_hospital_drg f
      ON f.drg_cd = d.drg_cd AND f.data_year = 2024
    GROUP BY d.drg_cd, d.is_surgical
)
SELECT
    is_surgical,
    COUNT(*) AS drg_codes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_codes,
    SUM(discharges) AS discharges,
    ROUND(100.0 * SUM(discharges) / SUM(SUM(discharges)) OVER (), 1) AS pct_discharges
FROM drg_side
GROUP BY is_surgical;