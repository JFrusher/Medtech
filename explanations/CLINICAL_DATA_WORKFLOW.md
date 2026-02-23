# Clinical Data Workflow: VitalDB and MIMIC-IV

## What is possible right now

Yes, this is possible with the current codebase, with one practical requirement:

- The project expects a **cohort-level CSV extract** from VitalDB or MIMIC-IV.
- It does **not** directly query remote databases/APIs from MATLAB in this repo.

The ingest path is now implemented in `main.m` via:

- `AEP_DATA_SOURCE=vitaldb`
- `AEP_DATA_SOURCE=mimic-iv`
- fallback: `synthetic`

Loader functions:

- `+emulator/loadVitalDBData.m`
- `+emulator/loadMimicIVData.m`
- `+emulator/standardizeClinicalSchema.m`

---

## Required schema after parsing

The model requires these fields (standardized automatically when possible):

- `PatientID`
- `Age`
- `Sex` (`M`/`F`)
- `WeightKg`
- `BMI`
- `HeightCm`
- `LBM`
- `SurgeryDurationMin`
- `InfusionRateMgPerMin`

Optional (enables calibration plots):

- `ObservedWakeDelayMin`

---

## Accepted source column aliases

`standardizeClinicalSchema` maps common aliases, including:

- Patient ID: `subject_id`, `hadm_id`, `stay_id`, `caseid`
- Age: `age`, `anchor_age`
- Sex: `gender`, `sex`
- Weight: `weight`, `weight_kg`
- Height: `height`, `height_cm`
- Duration: `anesthesia_duration_min`, `case_duration_min`
- Infusion rate: `propofol_infusion_mg_per_min`, `propofol_rate_mg_min`
- Observed wake: `wake_delay_min`, `ttw_observed_min`

Fallback derivations are implemented:

- `BMI` from weight + height
- `LBM` from sex + weight + BMI (Janmahasatian)
- `SurgeryDurationMin` from start/end timestamps when provided
- `InfusionRateMgPerMin` from total propofol dose / duration when rate is absent

---

## VitalDB workflow

## 1) Build cohort extract

Use your approved VitalDB access method to export a cohort-level CSV to:

- `data/vitaldb_cases.csv`

At minimum include columns mappable to required schema above.

## 2) Run model on VitalDB extract

In PowerShell:

- `$env:AEP_DATA_SOURCE = 'vitaldb'`
- `matlab -sd "<project_root>" -batch "setupProject; main"`

In MATLAB (if env var not set):

- edit `main.m` default source or set env before launch.

---

## MIMIC-IV workflow

## 1) Build cohort extract (recommended via SQL)

Create a de-identified anesthesia cohort CSV from your MIMIC-IV environment and save as:

- `data/mimiciv_cases.csv`

Typical source tables (depends on your pipeline):

- demographics (`patients`, admissions-related tables)
- perioperative/anesthesia medication events
- procedure/timing tables for anesthesia start/end
- optional observed wake timing label table

## 2) Include minimum columns

Provide columns mappable to:

- age, sex, weight, height or BMI,
- surgery duration (or start/end times),
- propofol infusion rate (or total dose + duration),
- optional observed wake delay.

## 3) Run model on MIMIC-IV extract

In PowerShell:

- `$env:AEP_DATA_SOURCE = 'mimic-iv'`
- `matlab -sd "<project_root>" -batch "setupProject; main"`

---

## Data governance and compliance

- Use only de-identified or appropriately governed datasets.
- Do not place protected identifiers in project CSVs.
- Respect VitalDB/MIMIC data use agreements and institution IRB/data policy.

---

## Troubleshooting

- If file missing: run falls back to synthetic and logs a warning.
- If mapping fails: loader throws a clear missing-field error after alias/fallback attempts.
- If calibration figure is missing: ensure `ObservedWakeDelayMin` exists and is non-null.

---

## Practical next step to productionize ingest

- Add a separate ETL script/repo that produces exactly one standardized CSV contract per source.
- Version that contract and validate columns before every run.
- Keep this modeling repo focused on simulation/optimization and not raw database joins.
