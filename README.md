# Anesthesia Emergence Optimizer

Portfolio project exploring how to optimize anesthesia stop timing using pharmacokinetic/pharmacodynamic simulation, safety-aware optimization, and clinical-style data pipelines.

## Project Snapshot

- **Domain:** Perioperative decision support (research prototype)
- **Core idea:** Predict when a patient will emerge, then choose a safer/better infusion stop time
- **Optimization goal:** Reduce wake delay while strongly penalizing early-emergence risk
- **Stack:** MATLAB (modeling + evaluation + visualization), Python ETL (VitalDB/MIMIC-style preprocessing)

This is an explainable prototype for research and portfolio demonstration, not a bedside controller.

---

## Why this project matters

Operating room time is expensive, and wake timing is safety-critical. In routine workflows, conservative timing can increase post-op delay. This project demonstrates a structured approach to:

- personalize stop-time recommendations,
- evaluate safety/efficiency trade-offs,
- and communicate potential operational value with transparent metrics and figures.

---

## What I built

### 1) PK/PD simulation engine

- Schnider-style 3-compartment model with effect-site dynamics
- configurable emergence threshold and simulation timestep
- patient-specific covariates (age/weight/BMI/sex/LBM/procedure profile)

### 2) Safety-aware optimization layer

- dual policy modes:
  - `legacy-bisection` (baseline)
  - `robust-explainable` (scenario-based, uncertainty-aware)
- asymmetric objective that heavily penalizes early wake behavior
- safety-buffer tuning on train split, then fixed-policy evaluation on held-out test split

### 3) Data and evaluation pipeline

- synthetic cohort generation + retrospective/VitalDB/MIMIC-style loaders
- standardized schema conversion
- uncertainty model calibration
- subgroup analysis and penalty sensitivity sweeps

### 4) Communication-ready outputs

- stakeholder-oriented figures (`.png` + `.fig`)
- exported CSV metrics for reporting and reproducibility
- one-command hero plot workflow for presentations

---

## Repository structure

```text
.
├─ main.m
├─ setupProject.m
├─ requirements.txt
├─ +emulator/    # data generation/loading + schema normalization
├─ +model/       # PK/PD, optimization, uncertainty, evaluation
├─ +viz/         # plots for technical + stakeholder communication
├─ +utils/       # logging, parallel config, figure persistence
├─ etl/          # Python ETL scripts and SQL templates
├─ data/         # generated datasets + tuning artifacts
├─ figures/      # exported run outputs
└─ tests/        # regression + invariant checks
```

---

## Quick start (MATLAB)

1. Open MATLAB in repo root.
2. (Optional) set runtime options:

```matlab
setenv('AEP_DATA_SOURCE','vitaldb')
setenv('AEP_OPTIMIZER_MODE','robust-explainable')
setenv('AEP_PARALLEL_WORKERS','8')
setenv('AEP_RUN_EXPENSIVE_TUNING','false')
```

3. Run full pipeline:

```matlab
setupProject
main
```

Outputs are written to `data/` and `figures/run_<timestamp>/`.

---

## Quick stakeholder plot (no full rerun)

If `data/testPatients.csv` exists, generate a presentation figure directly:

```matlab
setupProject
makeStakeholderPlot
```

Output: `figures/hero_<timestamp>/stakeholder_hero_plot.png` (+ `.fig`).

---

## Python ETL (VitalDB)

Install dependencies:

```bash
pip install -r requirements.txt
```

Build de-identified cohort files:

```bash
python etl/build_deidentified_cohort.py \
  --source vitaldb-lib \
  --output data/vitaldb_cases.csv \
  --detailed-output data/vitaldb_detailed_cases.csv
```

See `etl/RUN_ETL.md` for full instructions.

---

## Runtime configuration

- `AEP_DATA_SOURCE`: `synthetic | vitaldb | retrospective | mimic-iv`
- `AEP_OPTIMIZER_MODE`: `robust-explainable | legacy-bisection`
- `AEP_PARALLEL_WORKERS`: integer worker count (`1` forces serial)
- `AEP_RUN_EXPENSIVE_TUNING`: `true/false`
- `AEP_USE_TUNING_CACHE`: `true/false`
- `AEP_TUNING_CACHE_REFRESH`: `true/false`
- `AEP_FIXED_BUFFER_MIN`: numeric override for fixed safety buffer

---

## Engineering highlights (portfolio lens)

- **Reproducibility:** deterministic seeding, explicit train/test separation
- **Performance controls:** parallel execution, cache keys for expensive tuning runs
- **Robustness:** uncertainty calibration + seed sweeps + subgroup checks
- **Explainability:** conservative policy design and documented optimization equations
- **Communication:** stakeholder-ready plots and concise result artifacts

---

## Validation

Run test suite:

```matlab
tests.runAllTests
```

Tests include PK invariants and regression-style snapshot checks.

---

## Limitations and responsible use

- Research/prototype software only
- Not validated for direct clinical deployment
- Must not be used as autonomous patient-care control

---

## Author note

This project is part of my portfolio to demonstrate applied optimization in healthcare operations, scientific modeling, and end-to-end technical communication across technical and non-technical audiences.
