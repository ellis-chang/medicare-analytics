/*
   02_quality_checks.sql
   Verifies the staging load against figures established in
   notebooks/profiling.ipynb. Every check has a known expected value.
   Run after src/load_postgres.py. Any mismatch means investigate before Stage 3.
*/

-- 1. Row counts and discharge totals by year
-- Expect: 2022 | 145742 | 5009102
--         2023 | 146427 | 4960325
--         2024 | 145879 | 4952481
SELECT data_year, COUNT(*) AS rows, SUM(tot_dschrgs) AS discharges
FROM staging.inpatient_provider_service
GROUP BY data_year ORDER BY data_year;

-- 2. Provider-level row counts
-- Expect: 3120 / 3093 / 3044
SELECT data_year, COUNT(*) AS rows
FROM staging.inpatient_provider
GROUP BY data_year ORDER BY data_year;

-- 3. Reference table row counts
-- Expect: 5419 and 18330
SELECT 'hospital_general_information' AS table_name, COUNT(*) AS rows
FROM staging.hospital_general_information
UNION ALL
SELECT 'hrrp', COUNT(*) FROM staging.hrrp;

-- 4. Grain uniqueness on the fact source
-- Expect: 0
SELECT COUNT(*) AS duplicate_grain FROM (
    SELECT rndrng_prvdr_ccn, drg_cd, data_year
    FROM staging.inpatient_provider_service
    GROUP BY 1,2,3 HAVING COUNT(*) > 1
) d;

-- 5. Suppression threshold
-- Expect: 11 in every year
SELECT data_year, MIN(tot_dschrgs) AS min_discharges
FROM staging.inpatient_provider_service
GROUP BY data_year ORDER BY data_year;

-- 6. CCN format consistency across all four sources
-- Expect: every row length 6
SELECT 'prvsvc' AS src, LENGTH(rndrng_prvdr_ccn) AS len, COUNT(*)
FROM staging.inpatient_provider_service GROUP BY 1,2
UNION ALL
SELECT 'prv', LENGTH(rndrng_prvdr_ccn), COUNT(*)
FROM staging.inpatient_provider GROUP BY 1,2
UNION ALL
SELECT 'hgi', LENGTH(facility_id), COUNT(*)
FROM staging.hospital_general_information GROUP BY 1,2
UNION ALL
SELECT 'hrrp', LENGTH(facility_id), COUNT(*)
FROM staging.hrrp GROUP BY 1,2
ORDER BY 1,2;

-- 7. Join coverage against 2024 claims, and star rating nulls within it
-- Expect: 2867 matched, 226 null_rating
SELECT COUNT(*) AS matched,
       COUNT(*) FILTER (WHERE hospital_overall_rating IS NULL) AS null_rating
FROM staging.hospital_general_information h
WHERE EXISTS (
    SELECT 1 FROM staging.inpatient_provider_service s
    WHERE s.rndrng_prvdr_ccn = h.facility_id AND s.data_year = 2024
);

-- 8. HRRP suppression by measure
-- Expect: PN 2715, HF 2621, COPD 2323, AMI 1736, HIP-KNEE 1447, CABG 878
SELECT measure_name,
       COUNT(*) AS rows,
       COUNT(excess_readmission_ratio) AS usable
FROM staging.hrrp
GROUP BY measure_name ORDER BY usable DESC;

-- 9. ANCHOR: discharge-weighted national average payment per discharge
-- Expect: 2022 | 17772.244791
--         2023 | 17823.650656
--         2024 | 18359.985541
-- This is the value every DAX measure in Stage 6 must reproduce.
SELECT data_year,
       SUM(tot_dschrgs * avg_tot_pymt_amt) / SUM(tot_dschrgs) AS weighted_avg_payment
FROM staging.inpatient_provider_service
GROUP BY data_year ORDER BY data_year;