# Data Dictionary

Source files, column definitions, and observed characteristics. Definitions come
from the CMS data dictionaries; observed values come from
`notebooks/profiling.ipynb`.

---

## Source files

| File | Grain | Rows | Cols | Encoding |
|---|---|---|---|---|
| `MUP_INP_RY24_P03_V10_DY22_PrvSvc.csv` | hospital × DRG | 145,742 | 15 | Windows-1252 |
| `MUP_INP_RY25_P03_V10_DY23_PrvSvc.csv` | hospital × DRG | 146,427 | 15 | Windows-1252 |
| `MUP_INP_RY26_P03_V10_DY24_PrvSvc.csv` | hospital × DRG | 145,879 | 15 | ASCII |
| `MUP_INP_RY24_P04_V10_DY22_Prv.csv` | hospital | 3,120 | 57 | Windows-1252 |
| `MUP_INP_RY25_P04_V10_DY23_Prv.csv` | hospital | 3,093 | 57 | Windows-1252 |
| `MUP_INP_RY26_P04_V10_DY24_Prv.csv` | hospital | 3,044 | 57 | ASCII |
| `hospital_general_information.csv` | hospital | 5,419 | 38 | ASCII |
| `hrrp_fy2026.csv` | hospital × measure | 18,330 | 12 | ASCII |

Data year (DY) and release year (RY) differ. DY22 comes from the RY24 release,
DY23 from RY25, DY24 from RY26. CMS restates prior years across releases, so a
DY22 figure taken from a later release may not match this one.

---

## Inpatient Hospitals - by Provider and Service (fact source)

One row per hospital per MS-DRG per year. Verified unique on
`(Rndrng_Prvdr_CCN, DRG_Cd)`. Zero duplicates in all three years.

### Identity and geography

| Column | Type | Notes |
|---|---|---|
| `Rndrng_Prvdr_CCN` | string | CMS Certification Number. Six characters, zero-padded. Must load as string. Join key to HGI and HRRP. |
| `Rndrng_Prvdr_Org_Name` | string | Hospital name |
| `Rndrng_Prvdr_City` | string | |
| `Rndrng_Prvdr_St` | string | Street address |
| `Rndrng_Prvdr_State_FIPS` | int | State FIPS code |
| `Rndrng_Prvdr_Zip5` | string | Zero-padded; must load as string |
| `Rndrng_Prvdr_State_Abrvtn` | string | Two-letter state |
| `Rndrng_Prvdr_RUCA` | float | Rural-Urban Commuting Area code. Values change between years; see cleaning_decisions.md |
| `Rndrng_Prvdr_RUCA_Desc` | string | RUCA description |

### Service

| Column | Type | Notes |
|---|---|---|
| `DRG_Cd` | string | MS-DRG code, three characters, zero-padded. 533 / 534 / 540 distinct by year; 488 common to all three. |
| `DRG_Desc` | string | DRG description |
| `Tot_Dschrgs` | int | Discharge count. Minimum 11 across all years; CMS suppression threshold, verified. |

### Payment

All three are **per-discharge averages within the hospital-DRG cell**, not totals.

| Column | Definition |
|---|---|
| `Avg_Submtd_Cvrd_Chrg` | Average submitted covered charge. Chargemaster list price; not what anyone pays. |
| `Avg_Tot_Pymt_Amt` | Average total payment to the provider. Includes the MS-DRG amount, teaching (IME), disproportionate share (DSH), capital, and outlier payments, plus beneficiary coinsurance and deductible and any third-party coordination-of-benefits payments. |
| `Avg_Mdcr_Pymt_Amt` | Average Medicare payment. Same components but **excludes** beneficiary cost-sharing and third-party payments. |

**Selected for analysis: `Avg_Tot_Pymt_Amt`.** Rationale in methodology.md.

Because these are averages, any hospital-level or national aggregate must be
weighted by `Tot_Dschrgs`.

---

## Inpatient Hospitals - by Provider (validation source)

One row per hospital, verified unique on CCN. Used to validate the service-level
aggregation, not as an analysis input.

| Column | Definition |
|---|---|
| `Tot_Dschrgs` | Total discharges for the hospital |
| `Tot_Pymt_Amt` | Total payments, same components as `Avg_Tot_Pymt_Amt`, summed rather than averaged |
| `Tot_Mdcr_Pymt_Amt` | Total Medicare payments, same components as `Avg_Mdcr_Pymt_Amt`, summed |

Definitions are consistent across the two files, so `Tot_Pymt_Amt / Tot_Dschrgs`
is directly comparable to a discharge-weighted service-level average.

---

## Hospital General Information (dimension source)

5,419 rows, one per Medicare-registered hospital. Broader universe than the
claims files which includes facility types that never appear in IPPS inpatient data.

Join key: `Facility ID`, same six-character zero-padded CCN format.
2,867 of 2,906 hospitals in the 2024 claims file (98.7%) have a match.

### Observed values, 2,867 matched hospitals

**Hospital Type** - single-valued. All 2,867 are Acute Care Hospitals. Excluded
from `dim_hospital`; recorded instead as a scope statement about the universe.

**Hospital Ownership** - the usable segmentation attribute.

| Category | Count | Share |
|---|---|---|
| Voluntary non-profit - Private | 1,431 | 49.9% |
| Proprietary | 566 | 19.7% |
| Voluntary non-profit - Other | 235 | 8.2% |
| Voluntary non-profit - Church | 197 | 6.9% |
| Government - Hospital District or Authority | 196 | 6.8% |
| Government - Local | 129 | 4.5% |
| Physician | 58 | 2.0% |
| Government - State | 38 | 1.3% |
| Government - Federal | 14 | 0.5% |
| Tribal | 3 | 0.1% |

**Emergency Services** - Yes 2,644, No 223.

**Hospital overall rating**

| Rating | Count |
|---|---|
| 5 ★ | 288 |
| 4 ★ | 775 |
| 3 ★ | 843 |
| 2 ★ | 567 |
| 1 ★ | 168 |
| Not Available | 226 (7.9%) |

92.1% coverage - adequate for filtering. "Not Available" coerces to null.

**No teaching status field.** HGI carries no residency or GME indicator. See
methodology.md for how this changes the analysis plan.

---

## Hospital Readmissions Reduction Program (quality source)

18,330 rows across 3,055 hospitals; six measures each. Performance period
**2021-07-01 through 2024-06-30**.

| Column | Notes |
|---|---|
| `Facility ID` | Join key |
| `Measure Name` | One of six condition-specific measures |
| `Number of Discharges` | Denominator |
| `Footnote` | Sparse numeric codes explaining suppression |
| `Excess Readmission Ratio` | Observed / expected readmissions, risk-adjusted by CMS. Above 1.0 = more readmissions than case mix predicts. |
| `Predicted Readmission Rate` | |
| `Expected Readmission Rate` | |
| `Number of Readmissions` | Numerator |
| `Start Date`, `End Date` | Performance period |

### Measure availability

| Measure | Condition | Usable | % of 3,055 |
|---|---|---|---|
| `READM-30-PN-HRRP` | Pneumonia | 2,715 | 88.9% |
| `READM-30-HF-HRRP` | Heart failure | 2,621 | 85.8% |
| `READM-30-COPD-HRRP` | COPD | 2,323 | 76.0% |
| `READM-30-AMI-HRRP` | Heart attack | 1,736 | 56.8% |
| `READM-30-HIP-KNEE-HRRP` | Hip/knee replacement | 1,447 | 47.4% |
| `READM-30-CABG-HRRP` | Coronary artery bypass | 878 | 28.7% |

Hospitals with all six: 647 of 3,055 (21.2%). With none: 222.

The excess readmission ratio is itself an observed-over-expected ratio, matching
the framing used for cost in this project.

---

## Model relationships

```
dim_hospital (CCN)
    |
    +-- fact_hospital_drg (CCN, DRG_Cd, year)   <- PrvSvc
    |         |
    |         +-- dim_drg (DRG_Cd)
    |
    +-- fact_hospital_quality (CCN, measure)    <- HRRP
```

Join coverage against 2024 claims (2,906 hospitals): HGI 2,867 matched (98.7%),
HRRP 2,883 present in file (99.2%). Unmatched hospitals are small. Mean 98.8
discharges against 1,717 for matched. Note that HRRP presence is not the same as
usable data.