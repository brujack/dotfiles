---
name: Next steps plans created
description: April batch (PRs 5-9) all merged; 5 new specs + plans written 2026-04-08, awaiting implementation
type: project
---

**April batch — all done:**
- PR A: lib/workflows.sh extraction — DONE, merged as PR #7
- PR B: doctor + dry-run support — DONE, merged as PR #9
- PR C: secrets guardrails — DONE, merged as PR #5
- PR D: CI safety pass — DONE, merged as PR #8
- PR E: plan hygiene — DONE, merged as PR #6 (adds docs/superpowers/README.md master status index)

**Next round — specs AND plans written 2026-04-08, ready to implement:**
- local-overrides: config/local.sh sourced after detect_env, git-ignored
- granular-update-flags: --brew-only, --pip-only, --gems-only, --mas-only, --claude-only
- doctor-enhanced: active health checks with pass/fail, non-zero exit on failure
- workflow-test-coverage: coarse + conditional branching tests for lib/workflows.sh in tests/setup_env/workflows.bats
- check-versions: -t check-versions compares constants against GitHub latest releases

**Why:** User asked for next improvement recommendations; brainstormed and approved all 5 designs. Specs written 2026-04-08, plans written same session.

**How to apply:** Recommended implementation order: local-overrides (simplest) → granular-update-flags → doctor-enhanced → workflow-test-coverage → check-versions. Plans are in docs/superpowers/plans/2026-04-08-*.md.
