# ETL Runbook: Build De-identified Case CSV

This script creates a de-identified case-level CSV compatible with `main.m`.

## Install dependencies

```powershell
pip install -r requirements.txt
```

## Option A: VitalDB API -> CSV

```powershell
$env:AEP_DEID_SALT = "replace-with-long-random-secret"
$env:VITALDB_API_TOKEN = "<your-token-if-needed>"
python etl/build_deidentified_cohort.py `
  --source vitaldb-api `
  --api-url "https://<your-vitaldb-endpoint>/cases" `
  --output data/vitaldb_cases.csv
```

If your API field names differ, provide a field-map JSON with aliases:

```powershell
python etl/build_deidentified_cohort.py --source vitaldb-api --api-url "..." --field-map etl/field_map.json --output data/vitaldb_cases.csv
```

## Option B: MIMIC-IV SQL -> CSV

```powershell
$env:AEP_DEID_SALT = "replace-with-long-random-secret"
$env:MIMIC_DB_URI = "postgresql+psycopg2://user:password@host:5432/mimic"
python etl/build_deidentified_cohort.py `
  --source mimiciv-sql `
  --query-file etl/mimiciv_cohort_template.sql `
  --output data/mimiciv_cases.csv
```

## Option C: Existing CSV -> standardized CSV

```powershell
$env:AEP_DEID_SALT = "replace-with-long-random-secret"
python etl/build_deidentified_cohort.py `
  --source csv `
  --input-csv data/raw_export.csv `
  --output data/vitaldb_cases.csv
```

## Run MATLAB pipeline on real data

### VitalDB

```powershell
$env:AEP_DATA_SOURCE = "vitaldb"
matlab -sd "c:\Users\hp\OneDrive - University of Southampton\Year 3\10 Medtech" -batch "setupProject; main"
```

### MIMIC-IV

```powershell
$env:AEP_DATA_SOURCE = "mimic-iv"
matlab -sd "c:\Users\hp\OneDrive - University of Southampton\Year 3\10 Medtech" -batch "setupProject; main"
```

## Data governance notes

- Use de-identified, approved extracts only.
- Keep `AEP_DEID_SALT` secret and do not commit it.
- Never export direct identifiers (names, MRN, exact DOB).
