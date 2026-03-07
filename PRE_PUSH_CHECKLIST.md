# Final Push Checklist

Use this checklist before your final push to keep the repository clean, understandable, and reproducible.

## 1) Repository Hygiene

- [ ] `git status` shows only intentional changes.
- [ ] No secrets/API tokens are hardcoded.
- [ ] `.gitignore` excludes local/editor/cache artifacts only.
- [ ] Large generated artifacts are intentional and useful.

## 2) Documentation Completeness

- [ ] `README.md` reflects actual project behavior.
- [ ] Pricing and stakeholder docs are up to date.
- [ ] Handover docs exist (`PROJECT_HANDOVER.md`, this checklist).
- [ ] Claims are conservative and aligned to prototype scope.

## 3) Reproducibility

- [ ] Main run command still works: `setupProject; main`.
- [ ] Test command still works: `tests.runAllTests`.
- [ ] ETL instructions in `etl/RUN_ETL.md` are still accurate.
- [ ] Required environment variables are documented.

## 4) Portfolio Readiness

- [ ] README includes architecture and visual outputs.
- [ ] Results gallery links resolve to existing images.
- [ ] Safety and limitations are clearly stated.
- [ ] Interview talking points remain consistent with the code.

## 5) Suggested Local Commands

```bash
git status
git add -A
git diff --staged
```

If everything looks correct:

```bash
git commit -m "docs: finalize repository handover and client-facing materials"
git push
```

## 6) Optional Final Tag

```bash
git tag -a v1.0-portfolio-freeze -m "Portfolio freeze after pitch"
git push origin v1.0-portfolio-freeze
```
