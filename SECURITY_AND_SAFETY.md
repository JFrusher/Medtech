# Security and Safety Notes

## Clinical Safety Position

This repository is for research, simulation, and portfolio demonstration.
It is not a validated autonomous clinical control system.

- Recommendations should be treated as decision-support only.
- Human clinical oversight is mandatory.
- No direct bedside deployment claims should be made from this codebase alone.

## Data Handling Expectations

- Use de-identified datasets only.
- Never commit direct patient identifiers.
- Keep salts, tokens, and credentials in environment variables.
- Review outputs before sharing externally.

## Secret Management

Never store secrets in source files, notebooks, or tracked configs.
Examples: API tokens, database credentials, de-identification salts.

Prefer environment variables and local secret stores.

## Responsible Communication

When presenting results:

- Distinguish simulated outcomes from clinical outcomes.
- State assumptions behind ROI and timing estimates.
- Include uncertainty/limitations explicitly.

## Vulnerability and Risk Reporting

If you find a security/privacy issue or a safety-critical logic issue:

1. Document the issue clearly,
2. avoid public disclosure of sensitive details,
3. notify maintainers directly with reproduction steps and impact.
