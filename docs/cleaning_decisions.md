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
provider-level figure ($17,772.24 against $18,004.54, ratio 0.987). Suppressed
cells skew expensive, since rare complex cases are exactly the ones with few
discharges at any single hospital, so the visible subset is slightly cheaper than
reality.

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
5% of the sample. Below that threshold a hospital's measured average payment
reflects whichever handful of DRGs cleared suppression rather than its actual
cost profile, and dispersion is an order of magnitude wider than in the top band.
The cut is set at the point where the standard deviation drops from 0.371 to
0.128 rather than at a round number.

---

## Nulls

**RUCA is the only column with nulls in the claims files**, and it is
inconsistent across years: 677 nulls in 2022, 4 in 2023, 0 in 2024.

RUCA values also change for the same hospital between years. Southeast Health
Medical Center (CCN 010001) is coded 1.0 in 2022 and 2.0 in 2023.

**Decision: `dim_hospital` uses the 2024 RUCA value as a static attribute.** The
2024 file has complete coverage, and treating RUCA as year-varying would require
either a type-2 slowly-changing dimension or moving it onto the fact table —
complexity that a rural/urban flag does not justify. Reclassification between
years is recorded as a limitation.

No nulls in any payment or discharge column, in any year.

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
2,867 matched hospitals (Acute Care Hospitals). Recorded instead as a scope
statement: the IPPS inpatient file contains only acute care facilities.

**`Hospital overall rating` carries a "Not Available" sentinel** for 226
hospitals (7.9%), coerced to null. Star-rating filters must handle nulls
explicitly rather than dropping those hospitals silently.

**`Hospital Ownership` is the primary segmentation attribute** - ten categories
with usable distribution.