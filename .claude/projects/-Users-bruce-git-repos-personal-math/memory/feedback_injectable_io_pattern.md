---
name: injectable-io-pattern
description: Established pattern for testable CLI Rust crates in this repo — extract run<W,E> or run<R,W,E> from main()
type: feedback
originSessionId: 6a19bade-637f-444e-a960-9df032c46c4d
---

All CLI Rust crates use injectable I/O to reach ≥90% coverage: extract a `run` function that takes generic `W: Write`, `E: Write` (and `R: BufRead` when stdin is needed), plus a `dir: &Path` for file output. `main()` becomes a thin wrapper that locks stdio and calls `run`.

**Why:** `main()` and interactive stdin functions are untestable without this pattern. All 7 crates (sq-rs, fib-rs, e-rs, pi-rs, prime-rs, factorial-rs, twin-primes-rs) now use it.

**How to apply:** When adding a new Rust CLI crate or raising coverage on an existing one, apply this pattern. Unit tests inject `Vec<u8>` writers and `io::Cursor` readers. Integration tests in `tests/cli.rs` use `env!("CARGO_BIN_EXE_<name>")` + `tempfile::tempdir()`.
