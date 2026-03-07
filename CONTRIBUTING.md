# Contributing Guide

Thanks for your interest in improving this project.

## Scope

This repository is a research/portfolio prototype for anesthesia emergence timing optimization.
Contributions should prioritize clarity, reproducibility, and safety-conscious communication.

## Setup

### MATLAB

1. Open the repository root in MATLAB.
2. Run:

```matlab
setupProject
```

### Python ETL

```bash
pip install -r requirements.txt
```

## Typical Development Flow

1. Create a focused branch.
2. Make minimal, targeted changes.
3. Update docs when behavior changes.
4. Run tests:

```matlab
tests.runAllTests
```

5. Open a pull request with rationale and expected impact.

## Coding Expectations

- Keep functions modular and explicit.
- Preserve deterministic behavior where possible.
- Avoid introducing hidden defaults that alter outcomes silently.
- Prefer transparent logic over opaque complexity.

## Safety and Claims

- Do not overstate clinical validity.
- Keep decision-support framing explicit.
- Do not include or expose identifiable patient data.

## Documentation Requirements

If your change affects model behavior, update at least:

- `README.md`
- relevant file(s) under `explanations/`

## Pull Request Checklist

- [ ] Tests pass locally.
- [ ] Documentation updated.
- [ ] No secrets or private data added.
- [ ] Scope is focused and reviewer-friendly.
