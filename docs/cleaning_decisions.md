# Cleaning Decisions

Every non-obvious transformation applied to the raw CMS files, with reasoning.
Files in `data/raw/` are treated as read-only; all changes happen downstream.

---

## Scope

**Three data years (2022–2024) selected from twelve available.** Enough for
trend analysis without pulling in pre-COVID discharge patterns or older file
schemas. Documented because the choice is arbitrary in isolation.

**Release vintages differ.** DY22 from RY24, DY23 from RY25, DY24 from RY26.
CMS restates prior years across releases, so figures here may not match the same
data year as published in a later release. First thing to check if a trend looks
implausible.

---

## Encoding

**RY24 and RY25 files are Windows-1252; RY26 and the Provider Data Catalog files
are ASCII-only.**

The RY24/RY25 files contain byte `0x96` (en dash), which fails UTF-8 decoding.
Read with `encoding="cp1252"`. The RY26 files decode cleanly as UTF-8 only
because they contain no bytes above 127. That proves they are ASCII, not that
they are UTF-8.

PostgreSQL is UTF-8, so conversion happens at load.

---

## Type handling

**CCN, DRG code, and ZIP load as strings.** All three are zero-padded; loading as
integers strips the leading zero (`010001` becomes `10001`) and silently breaks
every join. Enforced with an explicit `dtype` dict and verified with an assertion
after load, because pandas silently ignores `dtype` entries naming columns that
do not exist.

**`low_memory=False` on the six large files** to prevent chunk-wise type
inference producing inconsistent dtypes when sentinel values appear only partway
through a file.

---

## Suppression

**Verified: minimum discharge count is 11 in all three years**, matching the CMS
methodology. Hospital-DRG cells below that are absent from the published file.

Effect of additional volume thresholds (2024):

| Threshold | Rows kept | Discharges kept |
|---|---|---|
| 11 (as published) | 100.0% | 100.0% |
| 25 | 40.0% | 72.0% |
| 50 | 14.9% | 46.9% |

**Decision: no additional DRG-cell volume filter is applied.**

A 25-discharge cutoff would discard 60% of rows to remove 28% of discharges, and
the discarded rows are real case mix. Dropping a hospital's low-volume DRGs
distorts the very thing the case-mix adjustment is meant to capture. CMS has
already applied the only filter privacy requires. Filtering is applied at the
hospital level instead, on coverage.

---

## Coverage of the service-level file

Aggregating the service-level file to hospital level recovers **71.81%** of the
discharges reported in the provider-level file for 2022. Per-hospital coverage:
median 60.3%, range 5.4% to 100.0%. **No hospital exceeds 100%**, confirming
suppression as the mechanism and ruling out a grain misunderstanding.

Payment impact is small. The service-level national average runs 1.3% below the
provider-level figure ($17,772.24 against $18,004.54, ratio 0.987). The two 2022
hospitals with suppressed payment totals drop out of the payment comparison but
remain in the discharge coverage figure above, which does not depend on payment.
Suppressed cells skew expensive, since rare complex cases are exactly the ones 
with few discharges at any single hospital, so the visible subset is slightly 
cheaper than reality.

**Low-coverage hospitals produce unreliable estimates.** Payment ratio dispersion
by coverage band:

| Coverage | Hospitals | Mean ratio | Std |
|---|---|---|---|
| 0–25% | 158 | 1.210 | 0.371 |
| 25–50% | 756 | 1.026 | 0.128 |
| 50–75% | 1,531 | 0.955 | 0.057 |
| 75–100% | 570 | 0.974 | 0.034 |

Correlation between coverage and payment ratio: −0.365.

**Decision: hospitals below 25% coverage are excluded** - 157 hospitals, roughly
5% of the sample. The band table above shows 158 because its upper edge is
inclusive of exactly 25%; the exclusion filter is strictly less than. Below that 
threshold a hospital's measured average payment reflects whichever handful of DRGs 
cleared suppression rather than its actual cost profile, and dispersion is an order 
of magnitude wider than in the top band. The cut is set at the point where the 
standard deviation drops from 0.371 to 0.128 rather than at a round number.

Measured against the finished benchmark, the filter turns out to be weaker than
this reasoning suggests. Excluding the 172 hospitals below 25% coverage in 2024
moves the O/E percentiles by less than 0.01 (p10 0.736 to 0.737, median 0.890 to
0.889, p90 1.236 to 1.227), and it does not remove the extreme values either:
the highest-O/E hospital in 2024 sits at 26.5% coverage, just above the cut. The
rule is retained because individually unreliable hospital-level estimates should
not appear in a table someone might act on, not because it corrects the national
picture. The count varies by year: 157 in 2022, 171 in 2023, 172 in 2024.

---

## Nulls

**RUCA is the only column with nulls in the claims files**, and it is
inconsistent across years: 677 nulls in 2022, 4 in 2023, 0 in 2024.

RUCA values also change for the same hospital between years. Southeast Health
Medical Center (CCN 010001) is coded 1.0 in 2022 and 2.0 in 2023.

**Decision: `dim_hospital` uses the 2024 RUCA value as a static attribute.** The
2024 file has complete coverage, and treating RUCA as year-varying would require
either a type-2 slowly-changing dimension or moving it onto the fact table. That
is complexity that a rural/urban flag does not justify. Reclassification between
years is recorded as a limitation.

No nulls in any payment or discharge column, in any year.

---

## Provider-level payment nulls

Two hospitals in the 2022 provider-level file have null payment totals:
CCN 010110 (Bullock County Hospital, AL) and CCN 050796 (West Coast Surgery
Inc, CA). Both report exactly 11 discharges, the CMS suppression threshold, so
payment amounts were withheld while the discharge count was published. No nulls
in 2023 or 2024.

**Decision: retained as null, not imputed.** Zero would be wrong; the payments
exist but were not published. `tot_pymt_amt` and `tot_mdcr_pymt_amt` are
therefore nullable in the staging schema. Affects 2 of 9,257 rows and excludes
both hospitals from the Section 7 payment comparison. Their discharge counts are
published, so they remain in the coverage figure.

This surfaced as a load failure rather than in profiling, because the original
Section 4 null check covered the service-level file only. NOT NULL constraints
on the provider-level, HGI, and HRRP tables were written against untested
assumptions. The constraint caught it, which is what constraints are for, but
the profiling notebook has since been extended to cover all four sources.

---

## HRRP sentinel values

Two suppression markers, handled differently by pandas:

- `"N/A"` - in the ratio and rate columns. **Silently converted to NaN by
  `read_csv`**, because it appears in pandas' default `na_values` list.
- `"Too Few to Report"` - in `Number of Readmissions`. Not converted; survives as
  a string and forces the column to string dtype.

Both mean CMS declined to publish. Neither is zero; null is the honest
representation. Coerced with `pd.to_numeric(errors="coerce")` so the treatment is
explicit rather than incidental.

### Suppression is not uniform across columns

Of 18,330 rows, 11,720 carry a usable excess readmission ratio, but only 8,037
of those also carry a published discharge count. A further 3,683 have a ratio
with the denominator suppressed, and 205 have a denominator with the ratio
suppressed.

|  | ratio present | ratio null |
|---|---|---|
| **discharges present** | 8,037 | 205 |
| **discharges null** | 3,683 | 6,405 |

Volume-weighted quality analysis is therefore possible for 69% of usable ratios.
The ratio, predicted rate, expected rate, and readmission count columns suppress
together (6,610 nulls each), so measure-block suppression is consistent even
though the denominator is handled separately.

> TODO - Stage 8: decide whether the cost-quality scatter is unweighted across
> all 11,720 ratios, restricted to the 8,037 with a denominator, or weighted
> using total discharges from the claims data as a volume proxy. Check first
> whether the 3,683 denominator-suppressed hospitals are systematically smaller.

---

## Charge-below-payment anomalies

Submitted charges fall below total payment in a small number of rows: 235 (0.16%)
in 2022, 281 (0.19%) in 2023, 223 (0.15%) in 2024.

Total payment never falls below Medicare payment. Zero violations in any year,
which confirms the payment field definitions were read correctly.

The violations concentrate in Indian Health Service and tribally-operated
facilities (Fort Defiance Indian Hospital, Tuba City Regional Health Care
Corporation) and small rural hospitals, with DRG 895 (alcohol/drug abuse with
rehabilitation therapy) recurring.

**Explanation.** This is not a different payment system. IHS hospital inpatient
services are paid under IPPS like any other acute care hospital; the IHS
all-inclusive rate applies to outpatient services. The anomaly is on the charge
side. Facilities that do not set aggressive chargemaster prices, because they do
not operate a commercial billing model, can post charges below what IPPS pays
once add-ons are included; DSH, uncompensated care, and (from FY 2024) the
supplemental payment for IHS and tribal hospitals under 42 CFR 412.106(h).

**Decision: rows are retained, not excluded.** Submitted charges are not the
analysis measure, so these rows do not affect the O/E calculation at all. They
matter only for the charge-to-payment ratio metric, where they should be flagged
rather than dropped. A hospital whose charges sit below its payments is a real
observation about chargemaster behavior, not a data error.

---

## DRG code churn

Only 488 DRG codes appear in all three years, against 533 / 534 / 540 per year.
Roughly 50 codes enter or leave, reflecting annual MS-DRG revisions.

**Decision: national benchmarks are computed separately for each year.** Each
year's DRGs are benchmarked against that same year's national data, so code
churn resolves itself. A code that exists only in 2024 simply gets a 2024
benchmark. Because O/E is normalised within year (the discharge-weighted national
mean is 1.0 in every year by construction), cross-year O/E comparison remains
valid without a common code set.

DRG-level trend visuals, where a specific code is tracked across years, are
restricted to the 488 stable codes.

---

## Hospital attrition

Hospitals appearing in all three years: 2,850. Per-year totals fall steadily:
3,015 / 2,945 / 2,906 in the service-level file, 3,120 / 3,093 / 3,044 in the
provider-level file. The service-level file has fewer hospitals because a small
enough hospital can have every one of its DRG cells suppressed.

**Decision: year-over-year visuals use the stable 2,850-hospital cohort;
single-year views use all hospitals present in that year.** A trend line drawn
over a changing denominator confuses composition change with performance change.
Both figures are labelled on the dashboard so the distinction is visible.

---

## HGI attributes

**`Hospital Type` is excluded from `dim_hospital`** - single-valued across all
2,867 hospitals matching the 2024 claims file (Acute Care Hospitals).

**`Hospital overall rating` carries a "Not Available" sentinel** for 226 of the
2,867 hospitals matching the 2024 claims file (7.9%), coerced to null. In
`dim_hospital`, which spans all three years, the null count is higher because
the 134 hospitals with no HGI match also carry a null rating. Star-rating filters 
must handle nulls explicitly rather than dropping those hospitals silently.

**`Hospital Ownership` is the primary segmentation attribute** - ten categories
with usable distribution.

---

## Staging load

**No text-staging layer.** The original plan was to load every column as text
and cast in SQL, the standard defence against currency-formatted source data.
Profiling made that unnecessary: the payment columns arrive as clean floats with
no `$` or thousands separators, and the claims files carry no sentinel values.
Data loads directly into typed columns, with coercion applied in pandas only
where sentinels exist (HGI star rating, four HRRP measure columns).

**`pandas.to_sql` over `COPY`.** Profiling timed the three service-level files
at roughly 36 MB each and 0.3 seconds to read. At that scale `to_sql` with
`chunksize=10000, method="multi"` loads 438,048 rows in about 87 seconds, which
is acceptable for an annually-refreshed source. `copy_expert` would be faster but
adds complexity the data volume does not justify.

**Idempotent by TRUNCATE, not `if_exists="replace"`.** Each loader truncates its
target before inserting with `if_exists="append"`. Using `replace` would drop the
table and let pandas recreate it with inferred types, discarding the primary
keys, check constraint, and `numeric(14,6)` precision defined in `01_schema.sql`.

**One table per source, not per year.** All three years land in a single table
with a `data_year` column added at load. Three near-identical tables would force
a UNION into every downstream query.

**Column subsetting.** The provider-level file has 57 columns and 5 are loaded;
HGI has 38 and 9 are loaded. Explicit rename dictionaries in
`src/load_postgres.py` document what was kept. Any column not in the mapping is
dropped at select time, so a schema change in a future CMS release fails visibly
rather than silently inserting into the wrong column.

**Payment precision.** Service-level payment columns use `numeric(14,6)`,
preserving the six decimal places in the source. These are per-discharge averages
that get multiplied back by discharge counts to recover weighted totals, so
rounding to cents before multiplying introduces drift that compounds across
438,048 rows. Provider-level columns use `numeric(16,2)` because those are
already summed dollar totals.

All nine checks in `sql/02_quality_checks.sql` pass against the loaded data.

---

## Dimensional model

**dim_hospital holds 3,063 hospitals**, the union of CCNs across all three
claims years. Higher than any single year (3,015 / 2,945 / 2,906) because a
hospital present in 2022 and gone by 2024 still has fact rows that must resolve.

**Hospital attributes come from the most recent year in which the hospital
appears.** Names and addresses change between releases; the latest value is the
most useful to display.

**RUCA comes from 2024 only.** The 157 hospitals absent from the 2024 file
(3,063 total less the 2,906 present in 2024) carry NULL rather than a stale
earlier value. Unrelated to the 157 low-coverage exclusions above, which happen
to be the same count.

**134 hospitals have no Hospital General Information match** and carry NULL
ownership, county, emergency services, and star rating. These are
systematically small: mean 526 discharges against 5,070 for matched hospitals,
median 121 against 2,637. Any analysis segmented by ownership or star rating
therefore describes mid-size and large hospitals. Recorded as a limitation.

**648 HRRP rows excluded**, covering 108 hospitals present in HRRP but absent
from the service-level claims file. A hospital with no cost data contributes
nothing to a cost-quality comparison. Separately, 116 of the 3,063 hospitals in
`dim_hospital` have no HRRP rows at all: the two sets differ because exclusion
is measured in rows and absence in hospitals.

**dim_drg holds 588 codes**, the union across all three years. 488 appear in
every year and are flagged `in_all_years` for DRG-level trend visuals.

---

## Benchmark

**Coverage exceeds 100% for one hospital-year.** Turning Point Hospital
(CCN 110209, GA) reports 540 service-level discharges against 539 at provider
level in 2024, across three DRGs. One discharge on a behavioral health facility;
a CMS reporting inconsistency rather than a grain error, given that referential
integrity and the anchor values both hold. Retained and documented; check 7 in
`07_benchmark_checks.sql` expects exactly this one row.

**Benchmarks are tables, not materialized views.** Power BI's PostgreSQL
connector does not surface materialized views in its Navigator, so both were
built as tables. Nothing is lost: they are derived entirely from the analytics
and staging tables, so rerunning `06_benchmarks.sql` rebuilds them, and tables
can carry the primary and foreign keys a materialized view cannot.

**`drg_year_key`** is a generated column on `fact_hospital_drg` and a stored
column on `drg_benchmark`. Power BI relationships join on a single column while
the benchmark's grain is (drg_cd, data_year).

**`fact_hospital_year` exists to hold coverage.** The 25% exclusion rule needs
service-level discharges over provider-level discharges, and `fact_hospital_drg`
cannot express that because the denominator lives in the provider-level file.
Hospital-year grain, 8,866 rows, related to `dim_hospital` and `dim_year`.