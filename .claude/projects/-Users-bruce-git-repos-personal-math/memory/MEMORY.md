# Memory Index

## Project

- [project_pi_work.md](project_pi_work.md) — Work done on pi calculator (Python multithreading + Rust implementation) in math/pi via CLI session
- [project_coverage_gate.md](project_coverage_gate.md) — ≥90% coverage enforced via CI tarpaulin (not pre-push); Swatinem cache doesn't cover ~/.cargo/bin
- [project_cargo_fmt_tarpaulin.md](project_cargo_fmt_tarpaulin.md) — Three patterns: fn_call_width=60% threshold, captured-var format syntax, break; dead probe — for keeping Rust crates above 90% after cargo fmt changes

## Feedback

- [feedback_github_actions_patterns.md](feedback_github_actions_patterns.md) — Three required GitHub Actions patterns: env vars for inputs in run: blocks, randomized GITHUB_OUTPUT delimiter, quoted body: in softprops/action-gh-release
- [feedback_pr_review_skill.md](feedback_pr_review_skill.md) — Must invoke `pr-review` skill via Skill tool before pushing any branch; running review inline is not acceptable
- [feedback_task_tracking.md](feedback_task_tracking.md) — Mark each task completed via TaskUpdate immediately after it finishes; never let the task list fall out of sync
- [feedback_rust_io_error_other.md](feedback_rust_io_error_other.md) — Use `io::Error::other()` not `io::Error::new(io::ErrorKind::Other, ...)` — clippy io_other_error lint in Rust 1.74+
- [feedback_injectable_io_pattern.md](feedback_injectable_io_pattern.md) — All CLI Rust crates use run<W,E>(dir) pattern; main() is a thin wrapper; tests inject Vec<u8> + tempdir
- [feedback_verify_hooks_installed.md](feedback_verify_hooks_installed.md) — Verify .git/hooks/pre-push exists at session start; run `make install-hooks` if missing (user requires local test gate)
