/*
   01_schema.sql
   Staging tables mirroring the four CMS source files.
   No transformation beyond type coercion; star schema is built in 03/04.
   Payment averages use NUMERIC(14,6): these are per-discharge averages that get
   multiplied back by discharge counts, so precision is preserved until presentation.
   hospital_type omitted from HGI: single-valued across all matched hospitals.
   Provider-level payment columns are nullable: two 2022 hospitals at the
   11-discharge suppression threshold have payment amounts withheld.
*/

DROP TABLE IF EXISTS staging.inpatient_provider_service;
DROP TABLE IF EXISTS staging.inpatient_provider;
DROP TABLE IF EXISTS staging.hospital_general_information;
DROP TABLE IF EXISTS staging.hrrp;

CREATE TABLE staging.inpatient_provider_service (
    rndrng_prvdr_ccn TEXT NOT NULL,
    drg_cd TEXT NOT NULL,
    data_year SMALLINT NOT NULL,
    rndrng_prvdr_org_name TEXT NOT NULL,
    rndrng_prvdr_city TEXT NOT NULL,
    rndrng_prvdr_st TEXT NOT NULL,
    rndrng_prvdr_state_fips SMALLINT NOT NULL,
    rndrng_prvdr_zip5 TEXT NOT NULL,
    rndrng_prvdr_state_abrvtn TEXT NOT NULL,
    rndrng_prvdr_ruca NUMERIC(4,1),
    rndrng_prvdr_ruca_desc TEXT,
    drg_desc TEXT NOT NULL,
    tot_dschrgs INT NOT NULL CHECK (tot_dschrgs >= 11),
    avg_submtd_cvrd_chrg NUMERIC(14, 6) NOT NULL,
    avg_tot_pymt_amt NUMERIC(14, 6) NOT NULL,
    avg_mdcr_pymt_amt NUMERIC(14, 6) NOT NULL,
    PRIMARY KEY (rndrng_prvdr_ccn, drg_cd, data_year)
);

CREATE TABLE staging.inpatient_provider (
    rndrng_prvdr_ccn TEXT NOT NULL,
    data_year SMALLINT NOT NULL,
    tot_dschrgs INT NOT NULL,
    tot_pymt_amt NUMERIC(16, 2),
    tot_mdcr_pymt_amt NUMERIC(16, 2),
    PRIMARY KEY (rndrng_prvdr_ccn, data_year)
);

CREATE TABLE staging.hospital_general_information (
    facility_id TEXT PRIMARY KEY,
    facility_name TEXT NOT NULL,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    zip_code TEXT NOT NULL,
    county_name TEXT,
    hospital_ownership TEXT NOT NULL,
    emergency_services TEXT NOT NULL,
    hospital_overall_rating SMALLINT
);

CREATE TABLE staging.hrrp (
    facility_id TEXT NOT NULL,
    measure_name TEXT NOT NULL,
    facility_name TEXT NOT NULL,
    state TEXT NOT NULL,
    number_of_discharges INT,
    footnote SMALLINT,
    excess_readmission_ratio NUMERIC(8, 4),
    predicted_readmission_rate NUMERIC(8, 4),
    expected_readmission_rate NUMERIC(8, 4),
    number_of_readmissions INT,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    PRIMARY KEY (facility_id, measure_name)
);