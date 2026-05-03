---
name: cargo fmt + tarpaulin compatibility patterns
description: Three patterns for keeping fib-rs and sq-rs above 90% Linux tarpaulin coverage when cargo fmt is enforced
type: project
originSessionId: 6a19bade-637f-444e-a960-9df032c46c4d
---

cargo fmt and Linux ptrace tarpaulin have three specific conflicts in this repo. All three are documented in CLAUDE.md Testing Policy.

**Why:** PR #40 added cargo fmt enforcement; PR #41 applied it; PRs #41/#42 fixed the resulting coverage failures.

**Pattern 1 — fn_call_width is 60%, not 100%.**
cargo fmt expands write!/writeln! macros when their _arguments_ (not the full line) exceed `fn_call_width` (default = 60% of `max_width` = 60 chars). A 92-char total line still gets expanded if the args alone exceed 60 chars.
Fix: add `rustfmt.toml` with `use_small_heuristics = "Max"` to raise fn_call_width to 100%.
Applied to: `fib/fib-rs/rustfmt.toml`

**Pattern 2 — Captured-variable format syntax keeps macros single-line.**
`{c}`, `{m}`, `{exponent}` reduce 4-arg macros to 2-arg form so they fit under the fn_call_width threshold.
Applied to: run() in `fib/fib-rs/src/main.rs`

**Pattern 3 — `break;` in `while let` is an uncoverable Linux ptrace probe.**
Even when executed, the probe doesn't fire. Use `Option::filter` to fold the exit condition into the `while let` and eliminate the explicit `break;`.
Applied to: generate_squares() in `sq/sq-rs/src/main.rs`

**How to apply:** When a new Rust crate's CI coverage drops after cargo fmt changes, check whether multi-line macros or explicit break; statements are in the denominator. Apply the patterns above before adding tests.
