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

The discharge-weighted national average of O/E across all hospitals must equal
1.0 to within rounding. If it does not, the weighting is wrong.

> Record the validated figure here once the DAX measure is built (Stage 6).

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

**Ownership type is tested instead** - proprietary against voluntary non-profit
against government, after case-mix adjustment. Ten categories with usable
distribution, and independently interesting: whether ownership predicts cost
after adjusting for patient mix is a live question in health policy.

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

**Low-coverage hospitals excluded.** 157 hospitals below 25% coverage are dropped
because their estimates are unreliable. Payment ratio standard deviation of
0.371 against 0.034 in the top coverage band. These are disproportionately small
facilities, so conclusions apply to mid-size and large hospitals more strongly
than to the smallest.

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