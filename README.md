# Medicare Inpatient Cost Variation & Quality

Measuring how much Medicare payment varies across US hospitals for the same
clinical conditions, how much of that variation patient case mix actually
explains, and whether the unexplained portion buys better outcomes.

> **Status: Stage 1 of 10 complete.** Data acquisition and profiling done.
> Database load, dimensional model, and dashboard in progress. See
> [Progress](#progress).

---

## The problem

Medicare pays different amounts to different hospitals for inpatient care. Most
of that difference is explained by which patients each hospital treats. A
hospital doing cardiac surgery costs more than one doing pneumonia admissions,
and that is not a finding.

This project separates the variation explained by case mix from the variation
that is not, then tests whether higher-cost hospitals deliver lower readmission
rates.

**Stakeholder framing:** a payer's network strategy team or a health system's
finance leadership, asking where payment differences reflect efficiency rather
than patient population.

---

## Established so far

From profiling 438,048 hospital-DRG records covering roughly 3,000 hospitals and
14.9 million discharges across data years 2022 to 2024:

**Case mix explains roughly half the variation in hospital payment.** Raw
payment per discharge spans a p90/p10 ratio of 2.34x across hospitals in 2024
($10,262 to $24,040). After adjusting each hospital for its own DRG mix, the
ratio falls to 1.68x. National O/E validates to exactly 1.0 by construction.

**The typical hospital costs less than its case mix predicts.** Median O/E is
0.890 against a national aggregate of 1.0, so the distribution is right-skewed
and a minority of high-cost hospitals accounts for the balance.

**Ownership predicts residual cost.** Median O/E runs from 1.139 at state
government hospitals down to 0.848 at proprietary and 0.754 at physician-owned.
The nine highest-O/E hospitals are all major public safety-net systems, which is
where DSH and uncompensated care payments concentrate. Descriptive rather than
causal: DRG-level adjustment does not capture within-DRG severity.

**28% of Medicare inpatient discharges are invisible in the public service-level file.** 
Aggregating to hospital level recovers 71.8% of the discharges reported in the 
provider-level file. The rest sit in cells suppressed below the 11-discharge threshold. 
Payment impact is small: the visible subset runs 1.3% cheaper, because suppressed cells 
skew toward rare, expensive cases.

**Estimate reliability degrades sharply at low coverage.** Payment ratio standard
deviation runs 0.371 for hospitals below 25% coverage against 0.034 above 75%.
This drives a documented exclusion rule rather than an arbitrary volume cutoff.

**Quality measure availability constrains the analysis.** Only 21% of hospitals
carry all six HRRP readmission measures. Pneumonia (88.9%) and heart failure
(85.8%) are the only two with coverage adequate for broad comparison.

National discharge-weighted average payment per discharge: $17,772 (2022),
$17,824 (2023), $18,360 (2024).

---

## Method

Indirect standardization. For each DRG, compute the national discharge-weighted
average payment. For each hospital, compute what it would be paid if every DRG
performed at that benchmark given its actual case mix. Divide observed by
expected.

An O/E ratio above 1.0 means the hospital costs more than its patient mix
explains. Quality is measured with the HRRP excess readmission ratio, itself an
observed-over-expected figure, so both axes share a framing.

Full detail, including the payment-measure choice and what the adjustment does
*not* remove (IME, DSH, capital, outlier payments, wage index), in
[`docs/methodology.md`](docs/methodology.md).

---

## Data

All sources are public CMS data requiring no registration.

| Source | Role | Grain |
|---|---|---|
| [Medicare Inpatient Hospitals by Provider and Service](https://data.cms.gov/provider-summary-by-type-of-service/medicare-inpatient-hospitals/medicare-inpatient-hospitals-by-provider-and-service) | Fact table | hospital × DRG × year |
| [Medicare Inpatient Hospitals by Provider](https://data.cms.gov/provider-summary-by-type-of-service/medicare-inpatient-hospitals) | Validation | hospital × year |
| [Hospital General Information](https://data.cms.gov/provider-data/dataset/xubh-q36u) | Dimension | hospital |
| [Hospital Readmissions Reduction Program](https://data.cms.gov/provider-data/datasets?theme%5B0%5D=Hospitals) | Quality | hospital × measure |

**Vintages matter.** Data years 2022, 2023, and 2024 come from the RY24, RY25,
and RY26 releases respectively. CMS restates prior years across releases, so
figures reproduce only against these specific vintages.

Raw files are gitignored. See [Reproducing](#reproducing).

---

## Stack

```
CMS CSV  ->  Python (pandas)  ->  PostgreSQL  ->  SQL views (star schema)  ->  Power BI
```

Cleaning and the national benchmark are computed in SQL. Expected payment and
the O/E ratio are computed in DAX so they recalculate under user filtering. A
precomputed column would be frozen and would return wrong answers when a user
filters to a subset of DRGs or a single state.

---

## Repository

```
medicare-analytics/
├── docs/
│   ├── data_dictionary.md        # every column, CMS definition + observed values
│   ├── cleaning_decisions.md     # every transformation, with reasoning
│   └── methodology.md            # measure selection, O/E method, limitations
├── notebooks/
│   └── profiling.ipynb           # structure, keys, types, suppression, validation
├── sql/                          # (planned) schema, staging, dimensions, benchmarks
├── src/                          # (planned) Postgres load
├── powerbi/                      # (planned) .pbix
├── screenshots/                  # (planned)
└── .gitignore
```

---

## Reproducing

**Requirements:** Python 3.11+, PostgreSQL 16+, Power BI Desktop (Windows).

1. Download the four datasets linked above into `data/raw/`. Take data years
   2022 to 2024 for the two claims files.
2. Create the database and schemas:
   ```sql
   CREATE DATABASE medicare_analytics;
   \c medicare_analytics
   CREATE SCHEMA staging;
   CREATE SCHEMA analytics;
   ```
3. Copy `.env.example` to `.env` and fill in credentials. **Note:** this project
   uses port **5433**, not the default 5432.
4. `pip install -r requirements.txt`
5. Run `notebooks/profiling.ipynb` to verify the source files.

Two source-file quirks worth knowing before loading. The RY24 and RY25 releases
are Windows-1252 encoded and fail UTF-8 decoding. CCN, DRG code, and ZIP are all
zero-padded and must be read as strings, or every join silently breaks.

---

## Progress

- [x] **Stage 1. Acquisition and profiling.** Grain verified unique on
      (CCN, DRG). Suppression threshold confirmed at 11 discharges. Service-level
      aggregation reconciled against provider-level totals. Cleaning decisions
      documented.
- [x] **Stage 2. Database.** Staging tables, typed load, quality checks.
- [x] **Stage 3. Dimensional model.** Star schema: `dim_hospital`, `dim_drg`,
      `dim_year`, `fact_hospital_drg`, `fact_hospital_quality`.
- [x] **Stage 4. Benchmarks.** National per-DRG per-year payment benchmark.
- [ ] **Stage 5. Power BI model.** Import, relationships, formatting.
- [ ] **Stage 6. DAX measures.** Weighted averages, expected payment, O/E.
- [ ] **Stage 7. Dashboard pages 1 to 3.** Executive summary, variation explorer,
      case-mix adjustment.
- [ ] **Stage 8. Dashboard pages 4 to 5.** Cost vs quality, hospital
      drill-through.
- [ ] **Stage 9. Findings.**
- [ ] **Stage 10. Screenshots and write-up.**

---

## Limitations

Medicare fee-for-service only. Medicare Advantage, now roughly half of Medicare
enrollment, is entirely excluded. Acute care IPPS hospitals only. Cost and
quality are measured over overlapping but non-identical windows. Case-mix
adjustment operates at DRG level and cannot see within-DRG severity variation.

Full list in [`docs/methodology.md`](docs/methodology.md).

---

## License

Analysis code MIT. Underlying data is US government work in the public domain.