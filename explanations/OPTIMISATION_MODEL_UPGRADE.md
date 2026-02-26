# Robust Optimizer (Native) — Detailed Technical Guide

This project now runs with the **robust explainable optimizer** as the native mode.

Primary implementation paths:
- `+model/optimizeStopTimeRobust.m`
- `+model/evaluateStrategy.m`
- `+model/defaultPolicyConfig.m`
- `main.m`

---

## 1) Clinical Problem Framing

Goal: choose infusion **stop time** so wake-up occurs near a target delay after surgery end, while avoiding clinically risky early emergence.

The model balances:
- accuracy to target wake delay,
- strong risk aversion for early wake,
- robustness to uncertainty in physiology and process variability.

---

## 2) Why Legacy Optimization Was Insufficient

Legacy bisection optimized a deterministic nominal patient, then uncertainty was only applied in evaluation. This created three issues:

1. **Decision mismatch**: optimized for idealized dynamics, deployed in stochastic reality.
2. **Weak tail protection**: no explicit optimization of high-loss scenarios.
3. **Limited explainability**: no explicit tradeoff curve between candidate stop times and risk components.

---

## 3) Native Robust Explainable Optimizer

For each patient, the optimizer evaluates a grid of candidate stop times over many uncertainty scenarios.

### Scenario dimensions

Each scenario perturbs:
- Weight, Height, LBM,
- infusion delivery bias,
- emergence-threshold bias,
- residual clinical wake delay.

### Objective

For candidate stop time \(s\), scenario loss \(L\):

$$
J(s)=\mathbb{E}[L(s)] + \lambda\,\mathrm{CVaR}_{\alpha}(L(s)) + w_p\,P(\text{early} \mid s)^2
$$

Where:
- \(\mathbb{E}[L]\): expected performance,
- \(\mathrm{CVaR}_{\alpha}\): tail-risk term,
- \(P(\text{early})\): early-emergence probability,
- \(\lambda, \alpha, w_p\): policy weights.

### Asymmetric clinical loss used in each scenario

$$
L = w_e\,\text{early}^2 + \text{late}^2 + 4w_e\,\text{below-window}^2 + 1.5\,\text{above-window}^2
$$

This keeps early-wake risk dominant.

---

## 4) Visual Algorithm Map

```mermaid
flowchart LR
    A[Patient + PK/PD parameters] --> B[Candidate stop-time grid]
    B --> C[Scenario sampling\nphysiology + process uncertainty]
    C --> D[Simulate wake outcomes\nfor each stop-time x scenario]
    D --> E[Compute metrics per stop time\nE[L], CVaR, P(early)]
    E --> F[Minimize robust objective J]
    F --> G[Selected stop time + explainability traces]
```

---

## 5) Explainability Outputs (What You Can Show)

For each patient decision, the optimizer can provide:
- candidate stop-time vector,
- expected loss curve,
- CVaR curve,
- early-probability curve,
- selected index,
- scenario TTW distribution (median, P10, P90).

These are exposed in `result.Explainability` from `optimizeStopTimeRobust`.

---

## 6) Figure-Level Explanation Added

When `viz.plotComparison` runs, figures now include:
- optimizer mode in metadata,
- robust objective summary,
- scenario/candidate counts,
- CVaR parameters,
- one-line interpretation cue.

This gives stakeholders an immediate explanation of **how** the final algorithm made its decisions.

---

## 7) Native Runtime Behavior

In `main.m`:
- `AEP_OPTIMIZER_MODE` controls mode.
- If not set, it defaults to `robust-explainable`.

Modes:
- `robust-explainable` (native)
- `legacy-bisection` (baseline/ablation)

---

## 8) Recommended Reporting Language

Use this concise description in slides/dissertation:

> “We use a scenario-based robust optimizer that selects stop times by minimizing expected clinical loss, tail risk (CVaR), and early-emergence probability under physiologic and process uncertainty. This provides both safer decisions and transparent decision traces.”

---

## 9) Practical Tuning Priorities

If you need to tune behavior, adjust in this order:
1. `RobustEarlyProbWeight` (safety aggressiveness),
2. `RobustCVaRWeight` (tail protection),
3. `RobustCVaRAlpha` (how deep into tail),
4. scenario/candidate counts (accuracy vs runtime).

---

## 10) Validation Checklist

- Compare early wake rate robust vs legacy.
- Compare mean TTW and variance.
- Check TTW tail behavior (P10/P90).
- Confirm stable behavior across seed sweeps.
- Confirm economic impact does not come from unsafe early-shift.
