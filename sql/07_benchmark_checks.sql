/*
   07_benchmark_checks.sql
   Validates the benchmark. Check 4 is the one that matters: national O/E must
   be exactly 1.0 by construction, and if it is not, the weighting is wrong.
   Run after 06_benchmarks.sql.
*/

-- 1. Benchmark row counts
-- One row per DRG per year. 533 + 534 + 540 = 1607 across the three years.
-- Expect: 2022 533, 2023 534, 2024 540, total 1607
SELECT data_year, COUNT(*) AS drg_benchmarks
FROM analytics.drg_benchmark
GROUP BY data_year
UNION ALL
SELECT NULL, COUNT(*) FROM analytics.drg_benchmark
ORDER BY data_year NULLS LAST;

-- 2. Every fact row has a benchmark
-- Expect: 0
SELECT COUNT(*) AS fact_rows_without_benchmark
FROM analytics.fact_hospital_drg f
WHERE NOT EXISTS (
    SELECT 1 FROM analytics.drg_benchmark b
    WHERE b.drg_cd = f.drg_cd AND b.data_year = f.data_year
);

-- 3. Benchmark rolls back up to the anchors
-- Aggregating the per-DRG benchmarks, weighted by national discharges, must
-- reproduce the national average exactly. This confirms the benchmark is a
-- decomposition of the same total rather than a separate calculation.
-- Expect: 2022 | 17772.244791
--         2023 | 17823.650656
--         2024 | 18359.985541
SELECT
    data_year,
    SUM(national_discharges * national_avg_payment) / SUM(national_discharges)
        AS rolled_up_national_avg
FROM analytics.drg_benchmark
GROUP BY data_year ORDER BY data_year;

-- 4. NATIONAL O/E = 1.0
-- Computed as the ratio of aggregate totals: total observed payment over total
-- expected payment. This is exactly 1.0 by construction, because the expected
-- total is the sum over DRGs of (national benchmark x national discharges),
-- which is the national payment total restated.
--
-- Note the second column. The discharge-weighted MEAN of each hospital's O/E
-- ratio is close to 1.0 but not exactly 1.0, because a weighted mean of ratios
-- is not the ratio of weighted sums. The same "do not average a ratio" trap as
-- the payment averages, one level up. The first column is the correct
-- validation; the second is reported to show the gap is small.
-- Expect: national_oe exactly 1.000000, mean_hospital_oe slightly above 1.0
WITH hospital AS (
    SELECT
        f.ccn,
        f.data_year,
        SUM(f.tot_dschrgs)                            AS discharges,
        SUM(f.tot_dschrgs * f.avg_tot_pymt_amt)       AS observed_total,
        SUM(f.tot_dschrgs * b.national_avg_payment)   AS expected_total
    FROM analytics.fact_hospital_drg f
    JOIN analytics.drg_benchmark b
      ON b.drg_cd = f.drg_cd AND b.data_year = f.data_year
    GROUP BY f.ccn, f.data_year
)
SELECT
    data_year,
    SUM(observed_total) / SUM(expected_total) AS national_oe,
    SUM(discharges * (observed_total / expected_total)) / SUM(discharges)
        AS mean_hospital_oe
FROM hospital
GROUP BY data_year ORDER BY data_year;

-- 5. Hospital O/E distribution, 2024
-- Sanity check before any of this reaches a dashboard. The median should sit
-- near 1.0. Extreme values at either tail are expected and are the low-coverage
-- hospitals check 7 addresses.
WITH hospital AS (
    SELECT
        f.ccn,
        SUM(f.tot_dschrgs * f.avg_tot_pymt_amt)
          / SUM(f.tot_dschrgs * b.national_avg_payment) AS oe
    FROM analytics.fact_hospital_drg f
    JOIN analytics.drg_benchmark b
      ON b.drg_cd = f.drg_cd AND b.data_year = f.data_year
    WHERE f.data_year = 2024
    GROUP BY f.ccn
)
SELECT
    COUNT(*)                                             AS hospitals,
    MIN(oe)                                              AS min_oe,
    PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY oe)     AS p10,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY oe)     AS median,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY oe)     AS p90,
    MAX(oe)                                              AS max_oe
FROM hospital;

-- 6. How much variation does case mix explain?
-- The headline result. Compares the spread in raw payment per discharge against
-- the spread in O/E, both at hospital level for 2024. The drop in the p90/p10
-- ratio is the share of raw variation that case mix accounts for; what remains
-- is the variation case mix does not explain.
WITH hospital AS (
    SELECT
        f.ccn,
        SUM(f.tot_dschrgs * f.avg_tot_pymt_amt) / SUM(f.tot_dschrgs)  AS raw_payment,
        SUM(f.tot_dschrgs * f.avg_tot_pymt_amt)
          / SUM(f.tot_dschrgs * b.national_avg_payment)               AS oe
    FROM analytics.fact_hospital_drg f
    JOIN analytics.drg_benchmark b
      ON b.drg_cd = f.drg_cd AND b.data_year = f.data_year
    WHERE f.data_year = 2024
    GROUP BY f.ccn
)
SELECT
    'raw payment per discharge' AS metric,
    ROUND(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY raw_payment)::NUMERIC, 3) AS p10,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY raw_payment)::NUMERIC, 3) AS median,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY raw_payment)::NUMERIC, 3) AS p90,
    ROUND((PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY raw_payment)
         / PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY raw_payment))::NUMERIC, 3) AS p90_p10
FROM hospital
UNION ALL
SELECT
    'case-mix adjusted O/E',
    ROUND(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3),
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3),
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3),
    ROUND((PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY oe)
         / PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY oe))::NUMERIC, 3)
FROM hospital;

-- 7. Coverage table
-- Expect: one row per hospital-year present in the service-level file, so
-- 3015 + 2945 + 2906 = 8866 rows if every hospital also appears in the
-- provider-level file. A shortfall means the inner join dropped hospital-years.
SELECT data_year, COUNT(*) AS hospital_years
FROM analytics.fact_hospital_year
GROUP BY data_year ORDER BY data_year;

-- Coverage never exceeds 100%: the service-level file is a suppressed subset of
-- the provider-level totals, so anything above 1.0 means a grain error.
-- Expect: 0
SELECT COUNT(*) AS coverage_above_100pct
FROM analytics.fact_hospital_year
WHERE coverage > 1.0;

-- Overall coverage by year. 2022 was measured at 71.81% in profiling.
SELECT
    data_year,
    ROUND(100.0 * SUM(service_discharges) / SUM(provider_discharges), 2) AS overall_coverage_pct,
    COUNT(*) FILTER (WHERE coverage < 0.25)                              AS below_25pct
FROM analytics.fact_hospital_year
GROUP BY data_year ORDER BY data_year;

-- 8. Does the coverage filter change the picture?
-- Validates the 25% exclusion rule. If dropping low-coverage hospitals barely
-- moves the O/E distribution, the rule is cheap insurance. If it moves it a
-- lot, those hospitals were driving the tails and the exclusion matters.
WITH hospital AS (
    SELECT
        f.ccn,
        y.coverage,
        SUM(f.tot_dschrgs * f.avg_tot_pymt_amt)
          / SUM(f.tot_dschrgs * b.national_avg_payment) AS oe
    FROM analytics.fact_hospital_drg f
    JOIN analytics.drg_benchmark b
      ON b.drg_cd = f.drg_cd AND b.data_year = f.data_year
    JOIN analytics.fact_hospital_year y
      ON y.ccn = f.ccn AND y.data_year = f.data_year
    WHERE f.data_year = 2024
    GROUP BY f.ccn, y.coverage
)
SELECT
    'all hospitals' AS cohort,
    COUNT(*) AS hospitals,
    ROUND(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3) AS p10,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3) AS median,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3) AS p90
FROM hospital
UNION ALL
SELECT
    'coverage >= 25%',
    COUNT(*),
    ROUND(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3),
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3),
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY oe)::NUMERIC, 3)
FROM hospital
WHERE coverage >= 0.25;