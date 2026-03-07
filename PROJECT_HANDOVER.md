# Project Handover — Anesthesia Emergence Optimizer

## Purpose

This document helps future-you (or collaborators/interviewers) quickly understand the current state of the repository, how to run it, and what to avoid changing unintentionally.

---

## Current Project State

- Repository status: research/portfolio prototype
- Primary runtime: MATLAB (`main.m` orchestration)
- Supporting ETL/runtime: Python (`etl/build_deidentified_cohort.py`)
- Decision-support scope only (not autonomous clinical control)

---

## Fast Re-Run Commands

### MATLAB full run

```matlab
setupProject
main
```

### MATLAB tests

```matlab
tests.runAllTests
```

### Python ETL install

```bash
pip install -r requirements.txt
```

### Build VitalDB de-identified cohort

```bash
python etl/build_deidentified_cohort.py --source vitaldb-lib --output data/vitaldb_cases.csv --detailed-output data/vitaldb_detailed_cases.csv
```

---

## Runtime Controls (Environment Variables)

- `AEP_DATA_SOURCE`: `synthetic | vitaldb | retrospective | mimic-iv`
- `AEP_OPTIMIZER_MODE`: `robust-explainable | legacy-bisection`
- `AEP_PARALLEL_WORKERS`: integer worker count
- `AEP_RUN_EXPENSIVE_TUNING`: `true/false`
- `AEP_USE_TUNING_CACHE`: `true/false`
- `AEP_TUNING_CACHE_REFRESH`: `true/false`
- `AEP_FIXED_BUFFER_MIN`: numeric buffer override

---

## Important Output Locations

- `data/`: train/test cohorts, evaluation outputs, tuning files
- `data/tuning_cache/`: reusable expensive tuning artifacts
- `figures/`: timestamped run outputs and stakeholder graphics
- `explanations/`: technical and presentation documentation

---

## Known Boundaries

- This codebase is built for simulation and communication of decision-support concepts.
- It is not validated for bedside autonomous clinical use.
- Do not claim prospective clinical efficacy without proper study design and governance.

---

## If You Return After Months Away

1. Read `README.md` for overview and links.
2. Read `explanations/PROJECT_EXPLANATION.md` for technical flow.
3. Run `tests.runAllTests` before touching core logic.
4. Run one `main` pass with `AEP_RUN_EXPENSIVE_TUNING=false` for quick sanity.
5. Only then run expensive tuning/sensitivity workflows if needed.

---

## Suggested Next Step (Optional)

If you revisit this for productization, prioritize:

1. Prospective validation design,
2. stronger uncertainty calibration governance,
3. deployment-grade integration and monitoring,
4. explicit regulatory pathway documentation.
