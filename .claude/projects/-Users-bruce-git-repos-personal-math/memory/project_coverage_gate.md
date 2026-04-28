---
name: Coverage gate architecture
description: How ≥90% coverage is enforced in math repo — CI-only via tarpaulin, not pre-push
type: project
originSessionId: 6a19bade-637f-444e-a960-9df032c46c4d
---

≥90% line coverage is enforced in CI for all 7 Rust crates via `cargo tarpaulin --fail-under 90` in the `test` job of each workflow. A PR that drops any crate below 90% fails CI and cannot auto-merge.

**Why:** `cargo tarpaulin` takes ~8s per crate locally; running all 7 in pre-push would add ~60s to every push. CI is the right gate — slower feedback is acceptable for coverage regressions (vs. test failures, which are caught locally).

**How to apply:** Do not add tarpaulin to the pre-push hook. The CI step is the gate. If a crate's coverage drops, the PR test job fails — fix tests before the PR can merge.

**Caveat:** `Swatinem/rust-cache` does not cache `~/.cargo/bin`, so `cargo install cargo-tarpaulin --locked` recompiles tarpaulin on every CI run (~2-3 min per crate). If CI minutes become a concern, switch to `cargo binstall cargo-tarpaulin` (prebuilt binary) or add an explicit `~/.cargo/bin` cache step.
