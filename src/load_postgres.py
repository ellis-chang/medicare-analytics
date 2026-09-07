import os
import pandas as pd
import time
import urllib.parse
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW = PROJECT_ROOT / "data" / "raw"

SERVICE_FILES = [
    (2022, RAW / "inpatient_provider_service/2022/MUP_INP_RY24_P03_V10_DY22_PrvSvc.csv", "cp1252"),
    (2023, RAW / "inpatient_provider_service/2023/MUP_INP_RY25_P03_V10_DY23_PrvSvc.csv", "cp1252"),
    (2024, RAW / "inpatient_provider_service/2024/MUP_INP_RY26_P03_V10_DY24_PrvSvc.csv", "utf-8"),
]

PROVIDER_FILES = [
    (2022, RAW / "inpatient_provider/2022/MUP_INP_RY24_P04_V10_DY22_Prv.csv", "cp1252"),
    (2023, RAW / "inpatient_provider/2023/MUP_INP_RY25_P04_V10_DY23_Prv.csv", "cp1252"),
    (2024, RAW / "inpatient_provider/2024/MUP_INP_RY26_P04_V10_DY24_Prv.csv", "utf-8"),
]

HGI_FILE = RAW / "hospital_general_information.csv"
HRRP_FILE = RAW / "hrrp_fy2026.csv"

SERVICE_COLS = {
    "Rndrng_Prvdr_CCN": "rndrng_prvdr_ccn",
    "Rndrng_Prvdr_Org_Name": "rndrng_prvdr_org_name",
    "Rndrng_Prvdr_City": "rndrng_prvdr_city",
    "Rndrng_Prvdr_St": "rndrng_prvdr_st",
    "Rndrng_Prvdr_State_FIPS": "rndrng_prvdr_state_fips",
    "Rndrng_Prvdr_Zip5": "rndrng_prvdr_zip5",
    "Rndrng_Prvdr_State_Abrvtn": "rndrng_prvdr_state_abrvtn",
    "Rndrng_Prvdr_RUCA": "rndrng_prvdr_ruca",
    "Rndrng_Prvdr_RUCA_Desc": "rndrng_prvdr_ruca_desc",
    "DRG_Cd": "drg_cd",
    "DRG_Desc": "drg_desc",
    "Tot_Dschrgs": "tot_dschrgs",
    "Avg_Submtd_Cvrd_Chrg": "avg_submtd_cvrd_chrg",
    "Avg_Tot_Pymt_Amt": "avg_tot_pymt_amt",
    "Avg_Mdcr_Pymt_Amt": "avg_mdcr_pymt_amt"
}

PROVIDER_COLS = {
    "Rndrng_Prvdr_CCN": "rndrng_prvdr_ccn",
    "Tot_Dschrgs": "tot_dschrgs",
    "Tot_Pymt_Amt": "tot_pymt_amt",
    "Tot_Mdcr_Pymt_Amt": "tot_mdcr_pymt_amt"
}

HGI_COLS = {
    "Facility ID": "facility_id",
    "Facility Name": "facility_name",
    "City/Town": "city",
    "State": "state",
    "ZIP Code": "zip_code",
    "County/Parish": "county_name",
    "Hospital Ownership": "hospital_ownership",
    "Emergency Services": "emergency_services",
    "Hospital overall rating": "hospital_overall_rating"
}

HRRP_COLS = {
    "Facility ID": "facility_id",
    "Measure Name": "measure_name",
    "Facility Name": "facility_name",
    "State": "state",
    "Number of Discharges": "number_of_discharges",
    "Footnote": "footnote",
    "Excess Readmission Ratio": "excess_readmission_ratio",
    "Predicted Readmission Rate": "predicted_readmission_rate",
    "Expected Readmission Rate": "expected_readmission_rate",
    "Number of Readmissions": "number_of_readmissions",
    "Start Date": "start_date",
    "End Date": "end_date"
}

DTYPES_PRVSVC = {"Rndrng_Prvdr_CCN": str, "DRG_Cd": str, "Rndrng_Prvdr_Zip5": str}
DTYPES_PRV    = {"Rndrng_Prvdr_CCN": str}
DTYPES_FID    = {"Facility ID": str}

def get_engine():
    load_dotenv()
    user = os.getenv("PGUSER")
    password = os.getenv("PGPASSWORD")
    host = os.getenv("PGHOST")
    port = os.getenv("PGPORT")
    database = os.getenv("PGDATABASE")

    missing = [k for k, v in {
        "PGUSER": user, "PGPASSWORD": password, "PGHOST": host,
        "PGPORT": port, "PGDATABASE": database
    }.items() if not v]
    if missing:
        raise ValueError(f"Missing in .env: {', '.join(missing)}")

    password = urllib.parse.quote_plus(password)
    url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}"

    return create_engine(url)

def truncate(engine, table):
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE staging.{table}"))

def load_service_files(engine):
    frames = []
    for year, path, encoding in SERVICE_FILES:
        print(f"  reading {year}...", end="", flush=True)
        df = pd.read_csv(path, dtype=DTYPES_PRVSVC, encoding=encoding, low_memory=False)
        df = df[list(SERVICE_COLS.keys())].rename(columns=SERVICE_COLS)
        df["data_year"] = year
        frames.append(df)
        print(f" {len(df):,} rows")

    combined = pd.concat(frames, ignore_index=True)
    print(f"  inserting {len(combined):,} rows...", end="", flush=True)
    t0 = time.perf_counter()
    truncate(engine, "inpatient_provider_service")
    combined.to_sql(
        "inpatient_provider_service", engine, schema="staging",
        if_exists="append", index=False, chunksize=10000, method="multi",
    )
    print(f" done in {time.perf_counter() - t0:.1f} secs")

def load_provider_files(engine):
    frames = []
    for year, path, encoding in PROVIDER_FILES:
        print(f"  reading {year}...", end="", flush=True)
        df = pd.read_csv(path, dtype=DTYPES_PRV, encoding=encoding, low_memory=False)
        df = df[list(PROVIDER_COLS.keys())].rename(columns=PROVIDER_COLS)
        df["data_year"] = year
        frames.append(df)
        print(f" {len(df):,} rows")

    combined = pd.concat(frames, ignore_index=True)
    print(f"  inserting {len(combined):,} rows...", end="", flush=True)
    t0 = time.perf_counter()
    truncate(engine, "inpatient_provider")
    combined.to_sql(
        "inpatient_provider", engine, schema="staging",
        if_exists="append", index=False, chunksize=10000, method="multi",
    )
    print(f" done in {time.perf_counter() - t0:.1f} secs")

def load_hgi(engine):
    print(f"  reading...", end="", flush=True)
    df = pd.read_csv(HGI_FILE, dtype=DTYPES_FID, encoding="utf-8", low_memory=False)
    df = df[list(HGI_COLS.keys())].rename(columns=HGI_COLS)
    print(f" {len(df):,} rows")

    df["hospital_overall_rating"] = pd.to_numeric(
        df["hospital_overall_rating"], errors="coerce"
    ).astype("Int64")
    print(f"  ratings coerced to null: {df['hospital_overall_rating'].isna().sum():,}")

    print(f"  inserting {len(df):,} rows...", end="", flush=True)
    t0 = time.perf_counter()
    truncate(engine, "hospital_general_information")
    df.to_sql(
        "hospital_general_information", engine, schema="staging",
        if_exists="append", index=False, chunksize=10000, method="multi",
    )
    print(f" done in {time.perf_counter() - t0:.1f} secs")

def load_hrrp(engine):
    print(f"  reading...", end="", flush=True)
    df = pd.read_csv(HRRP_FILE, dtype=DTYPES_FID, encoding="utf-8", low_memory=False)
    df = df[list(HRRP_COLS.keys())].rename(columns=HRRP_COLS)
    print(f" {len(df):,} rows")

    for col in ["number_of_discharges", "number_of_readmissions", "footnote"]:
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int64")

    for col in ["excess_readmission_ratio", "predicted_readmission_rate", "expected_readmission_rate"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df["start_date"] = pd.to_datetime(df["start_date"])
    df["end_date"] = pd.to_datetime(df["end_date"])
    print(f"  ratios coerced to null: {df['excess_readmission_ratio'].isna().sum():,}")

    print(f"  inserting {len(df):,} rows...", end="", flush=True)
    t0 = time.perf_counter()
    truncate(engine, "hrrp")
    df.to_sql(
        "hrrp", engine, schema="staging",
        if_exists="append", index=False, chunksize=10000, method="multi",
    )
    print(f" done in {time.perf_counter() - t0:.1f} secs")

def main():
    engine = get_engine()
    for name, fn in [
        ("inpatient_provider_service", load_service_files),
        ("inpatient_provider", load_provider_files),
        ("hospital_general_information", load_hgi),
        ("hrrp", load_hrrp),
    ]:
        print(f"\n{name}")
        fn(engine)

if __name__ == "__main__":
    main()