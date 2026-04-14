---
name: math repo ADR and CI hardening
description: ADRs, CI lint enforcement, and secrets guardrail added to math repo 2026-04-09
type: project
---

**Completed 2026-04-09:**

- Added `docs/adr/` with six seed ADRs (0001 Chudnovsky, 0002 Python+Rust dual impl, 0003 segmented sieve, 0004 GMP/rug, 0005 rayon, 0006 per-project CI)
- Fixed CI lint gaps: `pi-py.yml` now uses `make test` (was calling unittest directly, skipping ruff); all Rust workflows now use `make test` (was using `cargo test`, skipping clippy)
- Added secrets guardrail: `.gitleaks.toml`, credential paths in `.gitignore`, `secret-scan.yml` workflow

**Why:** ADR practice rolled out across personal repos; CI lint was not enforced for pi.py and all Rust projects; math had no secrets scanning per ADR-0005 cross-cutting requirement.

**How to apply:** math repo is now fully compliant with cross-cutting standards (ADRs, lint in CI, secrets guardrail).
