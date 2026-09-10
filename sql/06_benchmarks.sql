/*
   06_benchmarks.sql
   Builds the national DRG payment benchmark and the hospital-year coverage
   table. Both are fixed references: the benchmark must not shift with user
   filters, and coverage is a property of the source data rather than of any
   analysis. Expected payment and the O/E ratio are computed in DAX, not here.

   Tables, not materialized views: Power BI's PostgreSQL connector does not
   surface materialized views in its Navigator. Both are rebuilt by rerunning
   this file, so nothing is lost.

   drg_year_key exists because Power BI relationships join on a single column
   while the benchmark's grain is (drg_cd, data_year).

   Run after 05_integrity_checks.sql passes.
*/

DROP TABLE IF EXISTS analytics.drg_benchmark CASCADE;
DROP TABLE IF EXISTS analytics.fact_hospital_year CASCADE;

-- 1. Composite key on the fact table
-- A generated column, so Postgres maintains it and it cannot drift out of sync
-- with the two columns it derives from.
ALTER TABLE analytics.fact_hospital_drg
    DROP COLUMN IF EXISTS drg_year_key;

ALTER TABLE analytics.fact_hospital_drg
    ADD COLUMN drg_year_key TEXT
    GENERATED ALWAYS AS (drg_cd || '-' || data_year) STORED;

CREATE INDEX fact_hospital_drg_benchmark_fk
    ON analytics.fact_hospital_drg (drg_year_key);

-- 2. drg_benchmark
-- Grain: one row per DRG per year.
--
-- The discharge-weighted national average payment for each DRG. This is the
-- reference a hospital is compared against: a hospital performing at national
-- average for every DRG it treats has an O/E of exactly 1.0.
--
-- Benchmarks are per-year, so DRG code churn resolves itself. A code appearing
-- only in 2024 gets a 2024 benchmark, and O/E stays comparable across years
-- because it is normalised within year by construction.
--
-- Note the weighting. Averaging avg_tot_pymt_amt across hospitals would treat a
-- 12-discharge hospital the same as a 1,200-discharge one and produce a
-- benchmark no hospital is actually measured against.

CREATE TABLE analytics.drg_benchmark AS
SELECT
    drg_cd || '-' || data_year                             AS drg_year_key,
    drg_cd,
    data_year,
    COUNT(*)                                               AS hospitals,
    SUM(tot_dschrgs)                                       AS national_discharges,
    SUM(tot_dschrgs * avg_tot_pymt_amt) / SUM(tot_dschrgs) AS national_avg_payment
FROM analytics.fact_hospital_drg
GROUP BY drg_cd, data_year;

ALTER TABLE analytics.drg_benchmark
    ADD PRIMARY KEY (drg_year_key);

-- 3. fact_hospital_year
-- Grain: one row per hospital per year.
--
-- Carries the coverage figure the 25% exclusion rule depends on: what share of
-- a hospital's actual Medicare discharges survived CMS suppression and appear
-- in the service-level file. fact_hospital_drg cannot express this, because the
-- denominator comes from the provider-level file.
--
-- The filter is applied in DAX so it stays visible and adjustable; this table
-- only supplies the number.
--
-- provider_payment is nullable: two 2022 hospitals at the 11-discharge
-- threshold have payment totals withheld while their discharge counts are
-- published.

CREATE TABLE analytics.fact_hospital_year AS
SELECT
    f.ccn,
    f.data_year,
    SUM(f.tot_dschrgs)                                     AS service_discharges,
    p.tot_dschrgs                                          AS provider_discharges,
    SUM(f.tot_dschrgs)::NUMERIC / NULLIF(p.tot_dschrgs, 0) AS coverage,
    p.tot_pymt_amt                                         AS provider_payment,
    COUNT(*)                                               AS drg_count
FROM analytics.fact_hospital_drg f
JOIN staging.inpatient_provider p
  ON p.rndrng_prvdr_ccn = f.ccn
 AND p.data_year = f.data_year
GROUP BY f.ccn, f.data_year, p.tot_dschrgs, p.tot_pymt_amt;

ALTER TABLE analytics.fact_hospital_year
    ADD PRIMARY KEY (ccn, data_year);

ALTER TABLE analytics.fact_hospital_year
    ADD FOREIGN KEY (ccn) REFERENCES analytics.dim_hospital(ccn);

ALTER TABLE analytics.fact_hospital_year
    ADD FOREIGN KEY (data_year) REFERENCES analytics.dim_year(data_year);

-- 4. Verify
-- Expect: 1607 benchmark rows, 8866 hospital-years, 0 unmatched fact rows.
SELECT 'drg_benchmark' AS table_name, COUNT(*) AS rows FROM analytics.drg_benchmark
UNION ALL
SELECT 'fact_hospital_year', COUNT(*) FROM analytics.fact_hospital_year;

SELECT COUNT(*) AS fact_rows_unmatched
FROM analytics.fact_hospital_drg f
WHERE NOT EXISTS (
    SELECT 1 FROM analytics.drg_benchmark b
    WHERE b.drg_year_key = f.drg_year_key
);