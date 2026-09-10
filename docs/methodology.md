# Methodology

How cost variation is measured, adjusted, and compared against quality.

---

## The question

Medicare pays different amounts to different hospitals for inpatient care. Most
of that difference is explained by which patients each hospital treats. A
hospital doing cardiac surgery costs more than one doing pneumonia admissions,
and that is not a finding.

This analysis separates the variation explained by case mix from the variation
that is not, then asks whether the unexplained portion buys better outcomes.

---

## Measure selection

### Payment: `Avg_Tot_Pymt_Amt` (total payment to provider)

Three candidates were available. Submitted covered charges were rejected
outright. They are chargemaster list prices that no payer actually pays, and
treating them as cost would measure billing posture rather than resource use.

The real choice is between total payment and Medicare payment. They differ by
beneficiary coinsurance and deductible plus any third-party coordination-of-
benefits payments.

**Total payment was selected** because the stakeholder question is what an
episode of inpatient care costs, not what one payer's share of it happens to be.
Total payment is the complete resource transfer to the hospital for the
admission. Medicare payment alone would exclude cost-sharing that is genuinely
part of the episode's cost, merely borne by someone else.

**The counter-argument, stated honestly:** beneficiary cost-sharing varies with
supplemental coverage, Medigap, employer retiree plans, Medicaid dual
eligibility, which is a property of a hospital's patient population rather than
of the hospital itself. Total payment therefore carries some variation unrelated
to hospital behaviour. That variation is small relative to DRG-driven variation
and is recorded under limitations.

Two practical points support the choice. The provider-level validation file
reports `Tot_Pymt_Amt`, making the cross-file reconciliation direct. And the
analysis can be re-run on `Avg_Mdcr_Pymt_Amt` as a sensitivity check; if the O/E
rankings are stable across both measures, the choice does not drive the
conclusions.

### Quality: HRRP excess readmission ratio, pneumonia and heart failure only

Those two measures are available for 88.9% and 85.8% of hospitals. The other four
range from 76.0% down to 28.7%, and only 21.2% of hospitals carry all six. A
composite across all six would sacrifice four fifths of the sample to gain four
conditions.

All six measures are loaded into `fact_hospital_quality`. Filtering to these two
happens in the dashboard rather than the model, so the choice stays visible and
reversible.

### Medical vs surgical classification

`is_surgical` is derived by case-insensitive keyword matching on the DRG
description, using: PROCEDURE, SURGERY, SURGICAL, REPLACEMENT, IMPLANT,
TRANSPLANT, BYPASS, RESECTION, CRANIOTOMY, AMPUTATION, REVISION, FUSION, GRAFT,
EXCISION, REATTACHMENT, DEBRIDEMENT.

This is an approximation. The authoritative method maps each MS-DRG to its
Major Diagnostic Category and uses the published medical/surgical split, which
requires a reference table not included in the four source files.

Spot-checking the finished dimension confirms the approximation's failure
mode. DRG 003 (ECMO or tracheostomy with mechanical ventilation) and DRG 011
(tracheostomy for face, mouth, and neck diagnoses) are classified medical,
because no keyword matches "tracheostomy" or "ECMO". These are low-volume,
high-cost codes, so the aggregate split is barely affected, but individual
misclassifications exist and the flag should not be treated as authoritative
at DRG level.

The result is plausible: 283 of 588 codes (48.1%) are flagged surgical. Within
2024, medical DRGs carry 78.4% of discharges on 54.6% of codes, while surgical
DRGs carry 21.8% on 46.3%. A hospital's surgical share therefore moves its raw
cost position far more than its share of codes suggests, which is the asymmetry
case-mix adjustment corrects for.

---

## Weighted averages

The payment columns are per-discharge averages within each hospital-DRG cell.
**They cannot be averaged directly** - doing so weights a 4-discharge DRG
identically to a 400-discharge DRG.

```
weighted_avg = Σ(Tot_Dschrgs × Avg_Tot_Pymt_Amt) / Σ(Tot_Dschrgs)
```

The error is not trivial. National average payment per discharge:

| Year | Weighted (correct) | Naive mean | Overstatement |
|---|---|---|---|
| 2022 | $17,772.24 | $18,505.73 | 4.1% |
| 2023 | $17,823.65 | $18,512.96 | 3.9% |
| 2024 | $18,359.99 | $19,151.32 | 4.3% |

The naive figure runs high because low-volume DRGs skew expensive.

**These are the anchor values.** Every DAX measure producing a national average
must reproduce them.

---

## Case-mix adjustment: indirect standardization

**Step 1 - national benchmark.** For each DRG in each year, the discharge-weighted
national average payment per discharge. Computed in SQL as a materialized view;
it is a fixed reference and must not shift with user filters.

**Step 2 - expected payment.** For each hospital, what it would be paid if every
DRG performed at the national benchmark, given its actual case mix:

```
expected = Σ(hospital_discharges_in_DRG × national_benchmark_for_DRG)
           / Σ(hospital_discharges)
```

**Step 3 - observed over expected.**

```
O/E = observed_weighted_avg / expected
```

Above 1.0 means the hospital costs more than its case mix explains.

**Expected and O/E are computed in DAX, not SQL.** If a user filters to surgical
DRGs or to a single state, the expected value must recompute within that context.
A precomputed SQL column is frozen and would return wrong answers under filtering.

### Validation

National O/E is exactly 1.0 by construction, computed as the ratio of aggregate
totals: total observed payment over total expected. The expected total is the sum
over DRGs of (national benchmark x national discharges), which restates the
national payment total. Verified to 19 decimal places in all three years.

The discharge-weighted mean of individual hospital O/E ratios is 0.978, not 1.0,
and the gap is informative rather than an error. A weighted mean of ratios is not
the ratio of weighted sums; national O/E is implicitly weighted by expected
dollars while the mean is weighted by discharges. That it lands below 1.0 means
hospitals with high expected payment per discharge run above expected,
consistent with IME, DSH, and outlier add-ons concentrating at large complex
facilities.

The Stage 6 DAX measures must reproduce both figures. Confirmed in Power BI: 
the `DAX O/E Ratio` measure returns exactly 1.00 nationally, and `Avg Payment per Discharge` 
reproduces all three annual anchors.

### How much variation does case mix explain?

Hospital-level payment per discharge in 2024 spans a p90/p10 ratio of 2.34x
($10,262 to $24,040). After case-mix adjustment the O/E ratio spans 1.68x (0.736
to 1.236). Roughly half of raw variation is explained by which patients a
hospital treats; the remainder is not.

The adjusted figure is consistent with the within-DRG spread measured during
profiling (1.67x to 1.77x across the five highest-volume DRGs). Holding DRG
constant and adjusting for DRG mix arrive at the same answer by different routes.

Median O/E is 0.890 against a national aggregate of exactly 1.0. The typical
hospital costs 11% less than its case mix predicts, and the distribution is
right-skewed, so a minority of high-cost hospitals accounts for the balance.

---

## What the adjustment does not remove

Total payment includes components tied to hospital characteristics rather than to
the clinical work of a case. These remain in the residual after DRG adjustment
and are the known contributors to unexplained variation:

- **Indirect medical education (IME)** - paid on every Medicare discharge at
  teaching hospitals. A deliberate federal subsidy, not inefficiency.
- **Disproportionate share (DSH) and uncompensated care** - paid to hospitals
  serving a high share of low-income patients.
- **Capital payments** - vary with facility investment.
- **Outlier payments** - triggered by unusually costly individual cases. Captures
  within-DRG severity variation that DRG-level adjustment cannot see.
- **Geographic wage index** - payment rates adjust for local labour costs.

### Testing the hospital-characteristic hypothesis

Teaching status is **not available** in the current source set. HGI carries no
residency or GME indicator, and `Hospital Type` is single-valued across the IPPS
universe. The IME hypothesis therefore cannot be tested directly.

**Ownership type is tested instead**, and the result stands on its own rather
than as a substitute. Median O/E by ownership in 2024 runs monotonically from
government down to for-profit:

| Ownership | Hospitals | Median O/E | Discharge-weighted mean |
|---|---|---|---|
| Tribal | 3 | 1.230 | 1.279 |
| Government - Federal | 14 | 1.213 | 1.103 |
| Government - State | 38 | 1.139 | 1.175 |
| Government - Hospital District or Authority | 196 | 0.921 | 0.986 |
| Voluntary non-profit - Other | 235 | 0.918 | 1.047 |
| Government - Local | 129 | 0.904 | 1.098 |
| Voluntary non-profit - Church | 197 | 0.902 | 0.949 |
| Voluntary non-profit - Private | 1,431 | 0.894 | 0.978 |
| Proprietary | 566 | 0.848 | 0.894 |
| Physician | 58 | 0.754 | 0.874 |

The gap between the two columns is itself informative. Government - Local has a
median of 0.904 but a weighted mean of 1.098: its large hospitals cost far more
than its typical one. Proprietary barely moves (0.848 to 0.894), so for-profit
hospitals are more uniform in cost regardless of size.

**This is descriptive, not causal.** Physician-owned hospitals are typically
small specialty facilities with narrow elective case mixes, and DRG-level
adjustment does not capture within-DRG severity. The defensible claim is that
ownership predicts residual cost after case-mix adjustment, with the government
premium concentrated in large safety-net systems where DSH and uncompensated
care payments land - not that for-profit hospitals are more efficient.

The nine highest-O/E hospitals in 2024 are all major public safety-net systems:
Harris Health (Houston), Parkland (Dallas), John H. Stroger and Provident (Cook
County), four NYC Health + Hospitals facilities, and Rancho Los Amigos (LA
County). That is the DSH and uncompensated care residual appearing exactly where
this section predicted it would.

> Future work - adding the CMS IPPS Impact File would supply teaching status and
> resident-to-bed ratio, allowing the IME contribution to be isolated.

---

## Known limitations

**Medicare fee-for-service only.** Medicare Advantage is excluded entirely. MA
now covers roughly half of Medicare enrollees and penetration varies sharply by
market, so a hospital in a high-MA market is represented by a smaller and
potentially unrepresentative share of its Medicare population.

**28% of discharges are invisible.** Service-level aggregation recovers 71.81% of
provider-level discharges; the rest sit in suppressed low-volume cells. Payment
impact is small (1.3% low), but a hospital's measured case mix is not exactly its
practised case mix.

**Low-coverage hospitals excluded.** 157 hospitals below 25% coverage will be
excluded at the measure layer, not in the model: `dim_hospital` holds all 3,063
so the exclusion stays visible and adjustable. Their estimates are unreliable. 
Payment ratio standard deviation of 0.371 against 0.034 in the top coverage band. 
These are disproportionately small facilities, so conclusions apply to mid-size 
and large hospitals more strongly than to the smallest.

**Cost-sharing variation.** Total payment includes beneficiary coinsurance and
deductible, which vary with supplemental coverage rather than with the hospital.

**Different measurement windows.** Cost covers data years 2022–2024. HRRP excess
readmission ratios cover 2021-07-01 through 2024-06-30. The windows overlap
substantially but are not identical, so the cost-quality relationship is
associational across a shared period rather than a matched comparison.

**DRG definitions change.** Only 488 codes are common to all three years.
Per-year benchmarking handles this for O/E; DRG-level trend visuals are
restricted to the stable set.

**Suppression biases toward high-volume service lines**, since low-volume DRGs
are preferentially removed.

**Acute care hospitals only.** The IPPS inpatient file excludes critical access,
psychiatric, and other facility types. Findings do not generalise to them.

---

## Reproducibility

Source files: `data/raw/` (gitignored; download instructions in the README).
Vintages: RY24 / RY25 / RY26 releases for data years 2022 / 2023 / 2024.
Profiling: `notebooks/profiling.ipynb`.
Transformations: `sql/01`–`sql/05`.

CMS republishes annually and restates prior years, so figures reproduce only
against these specific release vintages.