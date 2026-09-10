# Findings

Six findings from the analysis, each with the number, the confidence, and the
limitation. The questions an interviewer would ask are answered here rather than
left for them to raise.

All figures are data year 2024 unless stated. National O/E validates to exactly
1.0 by construction, so every hospital-level ratio is measured against a
benchmark that reproduces the national total.

---

## 1. Case mix explains roughly half the variation in hospital payment

Payment per discharge across 2,906 hospitals spans a p90/p10 ratio of **2.34x**,
from $10,262 to $24,040. After adjusting each hospital for its own DRG mix, the
O/E ratio spans **1.68x**, from 0.736 to 1.236.

So slightly over half of raw variation is explained by which patients a hospital
treats. The remainder is not.

**Confidence: high.** The result is internally corroborated. Profiling measured
the payment spread *within* five individual high-volume DRGs at 1.67x to 1.77x,
holding the clinical condition completely constant. Adjusting for DRG mix across
all 540 codes lands at 1.68x. Two different routes to the same answer.

**Limitation.** DRG is a coarse severity proxy. Two hospitals treating the same
DRG can face genuinely different patient complexity, and outlier payments partly
capture that. The 1.68x residual is an upper bound on true unexplained variation,
not a measurement of inefficiency.

---

## 2. The typical hospital costs less than its case mix predicts

Median O/E is **0.890** against a national aggregate of exactly 1.000. The
distribution is right-skewed: minimum 0.478, p10 0.736, p90 1.236, maximum 8.81.

The typical hospital costs 11% less than expected. A minority of high-cost
hospitals accounts for the entire national balance.

**Confidence: high.** This follows from the arithmetic. National O/E is the ratio
of aggregate totals and is therefore dollar-weighted, while the median treats
every hospital equally. The gap between them *is* the skew.

**Worth knowing:** the discharge-weighted mean of hospital O/E ratios is 0.978,
also below 1.0. A weighted mean of ratios is not the ratio of weighted sums. That
it sits below 1.0 means hospitals with high expected payment per discharge run
above expected, which is consistent with add-on payments concentrating at large
complex facilities.

---

## 3. Ownership predicts residual cost, monotonically

Median O/E by ownership runs from government at the top to for-profit at the
bottom:

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

The gap between the two columns is informative on its own. Government - Local
has a median of 0.904 but a weighted mean of 1.098: its large hospitals cost far
more than its typical one. Proprietary barely moves, 0.848 to 0.894, so for-profit
hospitals are more uniform in cost regardless of size.

**Confidence: moderate.** The ordering is stable across both statistics and the
categories with few hospitals (Tribal at 3, Federal at 14) should not be read
individually. The large categories carry the finding.

**Limitation, and this matters.** This is descriptive, not causal. Physician-owned
hospitals are typically small specialty facilities with narrow elective case
mixes, and DRG-level adjustment does not capture within-DRG severity. The
defensible claim is that ownership predicts residual cost after case-mix
adjustment. Not that for-profit hospitals are more efficient.

---

## 4. The highest-cost hospitals are public safety-net systems

The nine highest-O/E hospitals in 2024:

| Hospital | State | O/E | Coverage |
|---|---|---|---|
| Harris Health | TX | 8.81 | 26.5% |
| Provident Hospital of Chicago | IL | 7.20 | 14.3% |
| Rancho Los Amigos National Rehabilitation Center | CA | 5.13 | 12.6% |
| John H Stroger Jr Hospital | IL | 4.58 | 27.5% |
| Kings County Hospital Center | NY | 3.69 | 57.1% |
| Levindale Hebrew Geriatric Center | MD | 3.63 | 83.8% |
| Metropolitan Hospital Center | NY | 3.62 | 16.0% |
| Woodhull Medical & Mental Health Center | NY | 3.48 | 38.7% |
| Parkland Health and Hospital System | TX | 3.36 | 54.3% |

Harris Health, Parkland, Stroger and Provident (Cook County), four NYC Health +
Hospitals facilities, and an LA County rehabilitation centre.

**This is the residual appearing exactly where the methodology predicts.**
Disproportionate share and uncompensated care payments go to hospitals serving
high shares of low-income patients, and they remain in total payment after DRG
adjustment. These hospitals are not inefficient; they are receiving federal
supplements tied to their patient population.

**Confidence: moderate on the pattern, low on individual values.** The
concentration in public safety-net systems is unambiguous. The specific ratios
are not reliable — most of these hospitals have coverage under 40%, meaning their
figures rest on a minority of their discharges.

**Limitation.** The IME contribution cannot be separated. Teaching status is not
available in the source files, so DSH and IME effects are confounded here. Adding
the CMS IPPS Impact File would resolve it.

---

## 5. Surgical share drives raw cost position more than code counts suggest

Surgical DRGs account for **46.3% of codes but only 21.8% of discharges**.
Medical DRGs carry 78.2% of volume on 53.7% of codes.

A hospital's surgical share therefore moves its raw payment per discharge far
more than its share of the code set implies, and it is a large part of what
case-mix adjustment corrects for.

**Confidence: moderate.** The direction is certain; the exact split depends on a
derived classification.

**Limitation.** `is_surgical` is derived by keyword matching on DRG descriptions,
not by the authoritative MDC mapping, which requires a reference table not
included in the four source files. Spot-checking found ECMO and tracheostomy
codes initially misclassified as medical; both were corrected. Other
misclassifications likely remain, so the flag should not be treated as
authoritative at individual DRG level.

---

## 6. Cost and readmission performance are unrelated

Across **2,708 hospitals** with usable pneumonia or heart failure readmission
data, the correlation between O/E ratio and excess readmission ratio is
**r = 0.023**.

Higher spending does not predict fewer readmissions.

**Confidence: high on the null result.** A correlation of 0.023 across 2,708
observations is indistinguishable from zero. The scatter shows a dense vertical
cloud with no diagonal tilt in either direction.

**Limitation, and it is a real one.** Readmission is one narrow outcome.
Mortality, complications, patient experience, and functional recovery are not in
this data. A hospital could be expensive and genuinely excellent on dimensions
not measured here. The claim is bounded: on this measure, cost buys nothing.

The two windows also differ. Cost covers data year 2024; HRRP excess readmission
ratios cover 2021-07-01 through 2024-06-30. Overlapping but not matched, so this
is an association across a shared period.

---

## Questions to expect, and answers

**"How do you know the adjustment is correct?"**
National O/E is exactly 1.0 by construction, verified to 19 decimal places in all
three years. That is a necessary condition, not a sufficient one, but it rules
out the weighting errors that would otherwise be invisible. The independent check
is the within-DRG spread: 1.67x to 1.77x measured with DRG held constant, against
1.68x after adjusting for DRG mix.

**"Why not risk-adjust properly?"**
DRG-level indirect standardization is what this data supports. Patient-level risk
adjustment needs claims with diagnoses and demographics, which the public files do
not contain — they are already aggregated to hospital-DRG cells.

**"Aren't these hospitals just in expensive markets?"**
Partly, yes. Geographic wage index adjustments are inside total payment and are
not removed. CMS publishes a standardized payment field in some file versions
that strips geographic adjustment; using it would be the natural next step and is
listed as future work.

**"Why is the median 0.89 if the national figure is 1.0?"**
Because they weight differently. The national ratio is dollar-weighted; the median
treats every hospital equally. The gap is the right-skew, and it is the finding in
item 2 rather than an inconsistency.

**"What is the biggest weakness?"**
That 28% of discharges are invisible. Aggregating the service-level file recovers
71.8% of provider-level discharges; the rest sit in cells suppressed below 11
discharges. Payment impact is small at 1.3%, but a hospital's measured case mix
is not exactly its practised case mix, and for the low-coverage hospitals it is
not close.

---

## Future work

- Add the CMS IPPS Impact File to separate IME from DSH effects
- Use the standardized payment field to remove geographic wage adjustment
- Map DRGs to MDC for an authoritative medical/surgical split
- Extend to mortality and patient experience measures from Care Compare