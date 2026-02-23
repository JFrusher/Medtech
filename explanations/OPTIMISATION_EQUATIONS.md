# Optimization Equations and Algorithm Notes

## Purpose

This document explains the optimization layer used in the Anesthesia Emergence Predictor, with emphasis on:

- the mathematical objective,
- how stop time is chosen,
- how early wake-up is penalized,
- how training and testing are separated.

---

## 1) Decision Variable and Target

For each patient case, define:

- Surgery end time: $T_{end}$ (minutes)
- Decision variable (infusion stop time): $t_{stop}$
- Desired wake delay after surgery: $\Delta_{target}$
- Target absolute wake time: $T_{target} = T_{end} + \Delta_{target}$

Optimization domain:

$$
0 \le t_{stop} \le T_{end}
$$

Interpretation:

- Larger $t_{stop}$ means infusion is stopped later.
- Smaller $t_{stop}$ means infusion is stopped earlier.

---

## 2) PK/PD State Model Used by the Optimizer

The optimizer queries a PK/PD simulator to map stop time to wake time.

State variables:

- central concentration $C_1$,
- peripheral concentrations $C_2, C_3$,
- effect-site concentration $C_e$.

Dynamics:

$$
\frac{dC_1}{dt}=\frac{u(t)}{V_1}-(k_{10}+k_{12}+k_{13})C_1+k_{21}C_2+k_{31}C_3
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

with infusion policy:

$$
u(t)=
\begin{cases}
\nu_{maint}, & t \le t_{stop} \\
0, & t > t_{stop}
\end{cases}
$$

Wake-time proxy:

$$
T_{wake}(t_{stop}) = \min\{t \ge t_{stop} : C_e(t) \le C_{e,thr}\}
$$

TTW metric:

$$
TTW(t_{stop}) = \max(T_{wake}(t_{stop}) - T_{end}, 0)
$$

---

## 3) Safety-Weighted Objective Function

Define wake timing error relative to target:

$$
\epsilon(t_{stop}) = T_{wake}(t_{stop}) - T_{target}
$$

Split into early and late parts:

$$
\epsilon_{early}=\max(-\epsilon,0), \quad \epsilon_{late}=\max(\epsilon,0)
$$

Asymmetric loss:

$$
\mathcal{L}(t_{stop}) = w_{early}\,\epsilon_{early}^2 + \epsilon_{late}^2
$$

where $w_{early} > 1$ (implemented as 12) strongly penalizes early wake-up.

Why this form:

- Squared terms grow quickly for larger timing mistakes.
- Asymmetry encodes clinical preference: early wake-up is more dangerous than mild lateness.

---

## 4) Per-Patient Optimization Problem

For each patient, solve:

$$
t_{stop}^* = \arg\min_{0 \le t_{stop} \le T_{end}} \mathcal{L}(t_{stop})
$$

Then report:

$$
TTW_{opt}=TTW(t_{stop}^*)
$$

and compare with standard-care baseline:

$$
TTW_{std}=TTW(T_{end})
$$

---

## 5) Numerical Search Strategy (Bisection-Style)

The implementation uses a robust interval search over $[0, T_{end}]$:

1. Initialize low and high bounds.
1. Evaluate midpoint candidate.
1. Simulate wake time and compute loss.
1. Shrink interval based on sign of timing error.
1. Keep best-loss candidate over iterations.

Reasoning:

- Wake time is approximately monotonic with stop time in this setup.
- Bisection-style search is stable, deterministic, and fast for repeated case-by-case optimization.

---

## 6) Post-Optimization Safety Correction

After the search, an explicit safety correction is applied:

- If selected candidate wakes earlier than target, move stop time later in small increments.
- Recompute wake time until target is met (or upper bound reached).

Mathematically, if $T_{wake}(t_{stop}^*) < T_{target}$, iterate

$$
t_{stop} \leftarrow \min(t_{stop}+\Delta t, T_{end})
$$

until $T_{wake}(t_{stop}) \ge T_{target}$ or $t_{stop}=T_{end}$.

This is a deliberate conservative policy layer.

---

## 7) Training vs Testing in the Optimization Stack

Two-level optimization logic is used:

### Level A: Train-time policy tuning

Tune an added target buffer $b$ from candidate set $\mathcal{B}$:

$$
\Delta_{target}^{(b)} = \Delta_{base} + b
$$

Evaluate each candidate on training data and choose:

$$
b^* = \arg\min_{b \in \mathcal{B}} \frac{1}{N_{train}}\sum_{i=1}^{N_{train}} \mathcal{L}_i^{(b)}
$$

### Level B: Test-time fixed policy evaluation

Use only selected buffer $b^*$ on held-out test patients.

This prevents leakage and optimistic self-evaluation.

---

## 8) Why Optimized Results Can Look Unrealistically Good (and Fix)

If planning model and evaluation model are identical, optimization may appear nearly perfect.

To mitigate this, evaluation introduces realization mismatch (noise/perturbation):

- covariate perturbation,
- infusion bias,
- emergence-threshold bias,
- residual clinical delay.

Conceptually:

$$
\widetilde{T}_{wake} = T_{wake}^{model} + \eta
$$

where $\eta$ captures unmodeled real-world effects.

This yields more credible test-set spread and safety metrics.

---

## 9) Cohort Metrics from Optimizer Outputs

For test cohort size $N$:

$$
\overline{TTW}_{std}=\frac{1}{N}\sum_{i=1}^{N} TTW_{std,i}, \quad
\overline{TTW}_{opt}=\frac{1}{N}\sum_{i=1}^{N} TTW_{opt,i}
$$

Early wake rate:

$$
\text{EarlyRate}(\%) = 100\cdot\frac{1}{N}\sum_{i=1}^{N}\mathbf{1}\{TTW_{opt,i}<\Delta_{target}\}
$$

Mean penalized loss:

$$
\overline{\mathcal{L}}=\frac{1}{N}\sum_{i=1}^{N}\mathcal{L}_i
$$

---

## 10) Practical Interpretation for Pitch Delivery

- The optimizer is not just minimizing average wake time.
- It minimizes a safety-aware objective that strongly discourages waking too early.
- A policy buffer is tuned on train data, then frozen for test evaluation.
- Results are therefore framed as conservative and operationally safer.

---

## 11) Suggested Future Equation-Level Enhancements

- Add hard chance constraints on early wake-up probability.
- Replace point-estimate objective with distributionally robust optimization.
- Introduce multi-objective optimization: safety, efficiency, and variability.
- Add uncertainty-aware confidence bounds on predicted stop time.
