# Anesthesia Emergence Predictor — Full Technical Explanation

## Project Overview

This project is a simulation-first prototype for a healthcare pitch.

- Clinical goal: Predict and optimize Time to Wake (TTW) after Propofol anesthesia.
- Operational goal: Reduce OR delay by timing infusion stop more intelligently.
- Financial goal: Translate TTW reduction into annual OR cost savings.

The pipeline now uses separate training and testing datasets, and it applies a strong asymmetric penalty to early wake-up events (safety-first behavior).

Engineering comment:

- This is a decision-support simulation framework for a pitch/demo, not a validated bedside controller.
- The model is intentionally transparent and modular so assumptions can be audited quickly.

---

## Folder Architecture

```text
10 Medtech/
├─ main.m
├─ setupProject.m
├─ +emulator/
│  ├─ generatePatientData.m
│  └─ createTrainTestData.m
├─ +model/
│  ├─ calculateCe.m
│  ├─ predictEmergence.m
│  ├─ evaluateStrategy.m
│  └─ tuneSafetyBuffer.m
├─ +viz/
│  └─ plotComparison.m
├─ +utils/
│  └─ logger.m
├─ data/
│  ├─ trainPatients.csv
│  ├─ testPatients.csv
│  └─ trainingBufferTuning.csv
└─ explanations/
   └─ PROJECT_EXPLANATION.md
```

Architecture intent:

- main orchestrates the full workflow.
- emulator owns synthetic cohort generation and split.
- model owns PK/PD simulation, optimization, evaluation, and training-stage tuning.
- viz owns pitch-deck figure generation.
- utils provides reusable logging.

---

## End-to-End Execution Flow

When `main` runs:

1. Setup and reproducibility.
   - Calls `setupProject`.
   - Sets deterministic random seed.

1. Data generation and split.
   - `emulator.createTrainTestData(300, 0.8)` builds a large synthetic cohort.
   - Produces `trainTable` and `testTable`.

1. Training-only tuning.
   - `model.tuneSafetyBuffer(...)` scans candidate safety buffers.
   - Selects the buffer minimizing asymmetric, safety-weighted wake timing loss.

1. Held-out test evaluation.
   - `model.evaluateStrategy(...)` evaluates final strategy on test patients only.

1. Economics and reporting.
   - Computes assumption-based and cohort-derived annual savings.
   - Exports `trainPatients.csv`, `testPatients.csv`, `trainingBufferTuning.csv` to `data/`.

1. Visualization.
   - `viz.plotComparison(summary)` generates the 2x3 comparison figure.

Implementation comments:

- Why train/test split matters: prevents tuning leakage and optimistic reporting.
- Why asymmetric penalty matters: waking too early is clinically riskier than waking slightly late.
- Why uncertainty injection matters: avoids “planner and reality are identical” artifacts.

---

## File-by-File Technical Details

### 1) setupProject.m

Purpose:

- Adds project root and subfolders to MATLAB path via `genpath`.
- Logs the configured project path.

Why it matters:

- Prevents package resolution issues during live demos.

### 2) main.m

Purpose:

- Coordinates training/testing workflow and pitch outputs.

Current key parameters:

- `totalPatients = 300`
- `trainRatio = 0.8`
- `emergenceThreshold = 1.2`
- `baseTargetWakeDelayMin = 3`
- `simDtMin = 0.1`
- `earlyPenaltyWeight = 12`
- `candidateSafetyBufferMin = 0:0.25:3`
- OR economics: `$50/min`, `3000 cases/year`

What is learned vs tested:

- Learned on train set: extra safety buffer minutes.
- Reported on test set: TTW improvement, early wake rate, and savings.

Code-level comment:

- If results look unrealistically good, first inspect `TestEarlyWakeRatePct`, TTW standard deviation, and IQR logs before changing thresholds.

### 3) +emulator/generatePatientData.m

Purpose:

- Creates synthetic patient features required by Schnider-based PK.

Generated fields:

- `Age`, `Sex`, `WeightKg`, `BMI`, `HeightCm`, `LBM`
- `SurgeryDurationMin`, `InfusionRateMgPerMin`

Clinical modeling note:

- Height and LBM are included because clearance/distribution equations are covariate-sensitive.

### 4) +emulator/createTrainTestData.m

Purpose:

- Creates a larger cohort and splits it into training and testing subsets.

Why this was added:

- Avoids tuning and evaluating on the same cases, which can overstate performance.

### 5) +model/calculateCe.m

Purpose:

- Simulates Propofol PK/PD with a 3-compartment model and effect-site link.

State variables:

- Central/plasma concentration: $C_1$ (reported as $C_p$)
- Peripheral: $C_2$, $C_3$
- Effect site: $C_e$

Compartment equations:

$$
\frac{dC_1}{dt}=\frac{u}{V_1}-(k_{10}+k_{12}+k_{13})C_1+k_{21}C_2+k_{31}C_3
$$

$$
\frac{dC_2}{dt}=k_{12}C_1-k_{21}C_2
$$

$$
\frac{dC_3}{dt}=k_{13}C_1-k_{31}C_3
$$

$$
\frac{dC_e}{dt}=k_{e0}(C_1-C_e)
$$

Rate constants:

- $k_{10}=Cl_1/V_1$
- $k_{12}=Cl_2/V_1$
- $k_{13}=Cl_3/V_1$
- $k_{21}=Cl_2/V_2$
- $k_{31}=Cl_3/V_3$

Numerics:

- Uses explicit Euler integration over `timeMin`.
- Uses non-negativity clamps for numerical robustness.

Modeling comments:

- Euler is chosen for speed and deterministic behavior during repeated optimization loops.
- If higher numerical fidelity is needed, switch to `ode45` with controlled tolerances and compare runtime impact.

### 6) +model/predictEmergence.m

Purpose:

- Finds stop time so predicted wake aligns to a target delay after surgery end.

Inputs include:

- Patient covariates
- Surgery end time
- Infusion rate
- Target wake delay
- Emergence threshold
- Simulation step
- `earlyPenaltyWeight`

Safety enhancement (new):

- Optimization uses asymmetric loss that heavily penalizes early wake-up.

$$
\text{Loss}=w_{early}\cdot(\max(target-wake,0))^2 + (\max(wake-target,0))^2
$$

- With `w_{early}=12`, early wake errors are far more costly than late wake errors.
- A final safety correction nudges stop time later if the candidate still wakes too early.

Safety comments:

- This “late-biased correction” is deliberate; it encodes clinical conservatism into optimization.
- Penalty weight tuning should be clinically reviewed; it is a policy decision, not purely statistical.

Outputs now include:

- Standard and optimized stop/wake/TTW metrics
- `IsEarlyWake`, `WakeErrorMin`, `PenalizedLoss`

### 7) +model/evaluateStrategy.m

Purpose:

- Evaluates a fixed strategy over a cohort and aggregates performance/safety metrics.

Outputs include:

- Mean standard TTW
- Mean optimized TTW
- Mean lead time (how much earlier infusion is stopped)
- Mean penalized loss
- Early wake rate percentage

Validation comments:

- Planning is done with nominal model; outcomes are evaluated under perturbed realization (covariate, infusion, threshold, and residual delay noise).
- This setup approximates deployment mismatch and reduces false confidence from self-consistent simulation.

### 8) +model/tuneSafetyBuffer.m

Purpose:

- Learns extra target wake delay (`buffer`) on training data only.

Method:

- Sweeps candidate buffers (0 to 3 min by 0.25).
- For each candidate, runs `evaluateStrategy` on train set.
- Selects buffer with minimum mean penalized loss.

This creates a data-driven safety margin before test evaluation.

### 9) +viz/plotComparison.m

Purpose:

- Builds a 2x3 figure for clinical, safety, and financial storytelling.

Panels:

- Box comparison of TTW distributions.
- Shared-bin normalized histogram (standard vs optimized).
- Stacked violin plot (distribution shape + median).
- Mean TTW bar chart with reduction annotation.
- Per-patient sanity scatter (`Optimized` vs `Standard` with identity line).
- Annual savings bar chart (assumption-based vs simulation-derived).

Visualization comments:

- Shared bins and normalized histogram prevent visual distortion from unequal scaling.
- Scatter against identity line is a sanity diagnostic: points above line indicate worse-than-standard outcomes.

### 10) +utils/logger.m

Purpose:

- Standardized timestamped console output.

Format:

- `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`

---

## Cost Model

The script reports two financial views.

1. Assumption-based headline:

$$
(12-3)\times 50\times 3000 = 1{,}350{,}000\ \text{USD/year}
$$

1. Cohort-derived estimate:

$$
\text{Per-case savings}=\max(\overline{TTW}_{std}-\overline{TTW}_{opt},0)\times 50
$$

$$
\text{Annual savings}=\text{Per-case savings}\times 3000
$$

---

## How to Run

From MATLAB in the project root:

```matlab
setupProject
main
```

From PowerShell:

```powershell
matlab -sd "c:\Users\hp\OneDrive - University of Southampton\Year 3\10 Medtech" -batch "setupProject; main"
```

Expected outputs:

- Console summary logs.
- One figure titled `Anesthesia Emergence Predictor`.
- CSV artifacts in `data/`.

---

## Tuning Guide

Useful knobs for scenario analysis:

- In `main.m`:
  - `earlyPenaltyWeight`: increase to further discourage early wake.
  - `candidateSafetyBufferMin`: expand search range for conservative practice.
  - `emergenceThreshold`: stricter or looser wake criterion.
  - `totalPatients`: simulation scale.

- In `generatePatientData.m`:
  - Adjust demographic and dosing distributions to mimic your target hospital population.

---

## Assumptions and Limitations

This is a pitch-grade simulation, not a clinical decision-support device.

- Synthetic cohort (not EHR-derived).
- Constant maintenance infusion profile per case.
- Single-threshold emergence proxy.
- No EEG/hemodynamic/co-medication dynamics.

Roadmap to production realism:

- Validate against de-identified retrospective cases.
- Add uncertainty intervals and confidence calibration.
- Add richer infusion trajectories and constraints.

Risk comments:

- A single-threshold emergence proxy can under-represent multimodal clinical emergence criteria.
- Financial outputs are sensitivity-driven; always present assumptions next to headline savings.

---

## TODO Tree (Engineering Roadmap)

Use this as a delivery backlog from demo-grade to translational-grade.

- [x] [Phase 1] Add uncertainty profile presets in `main.m` (`low`, `moderate`, `high`).
- [x] [Phase 1] Add seed sweep (`N` seeds) and report confidence intervals for TTW and savings.
- [x] [Phase 1] Add unit tests for PK invariants (non-negativity, monotonic washout after stop).
- [x] [Phase 1] Add regression snapshot test for key metrics on fixed seed.

- [x] [Phase 2] Add hard safety constraints (minimum acceptable wake delay window).
- [x] [Phase 2] Add penalty sensitivity analysis for `earlyPenaltyWeight`.
- [x] [Phase 2] Add alarm metric: percentage of cases with wake < target by more than 1 min.
- [x] [Phase 2] Add configurable conservative policy mode for high-risk cohorts.

- [x] [Phase 3] Replace synthetic cohort with de-identified retrospective anesthesia records.
- [x] [Phase 3] Calibrate noise terms against empirical residuals from real cases.
- [x] [Phase 3] Compare predicted vs observed emergence with calibration plots.
- [x] [Phase 3] Add subgroup performance checks (age, BMI, case duration strata).

- [ ] [Phase 4] Auto-export figures to PNG/PDF for pitch deck ingestion.
- [ ] [Phase 4] Add one-page executive report generator (`.md` or `.pdf`).
- [ ] [Phase 4] Add uncertainty ribbons/error bars on key bars and savings plots.
- [ ] [Phase 4] Add safety dashboard panel (early/ontime/late stacked rates).

- [ ] [Phase 5] Containerize runtime and lock MATLAB/toolbox versions.
- [ ] [Phase 5] Add structured logging schema for auditability.
- [ ] [Phase 5] Define model card (intended use, limits, known failure modes).
- [ ] [Phase 5] Prepare clinical review packet and validation protocol draft.

---

## Pitch-Ready Narrative

- We model patient-specific Propofol PK/PD using Schnider-style covariates.
- We tune a safety buffer on training data, then evaluate on held-out test data.
- We explicitly penalize early wake-up because it is clinically riskier.
- Reduced TTW translates directly into OR cost savings at scale.
