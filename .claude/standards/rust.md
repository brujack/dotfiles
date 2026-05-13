## Rust

### Linting

`cargo clippy -- -D warnings`

### CLI Crate I/O Pattern

All CLI Rust crates must use injectable I/O to keep `fn main()` testable and coverage achievable.

Extract a `run` function with generic writer/reader parameters:

```rust
fn run<W: Write, E: Write>(stdout: &mut W, stderr: &mut E, dir: &Path) -> io::Result<()> {
    // all logic here
}

#[cfg(not(tarpaulin_include))]
fn main() {
    let stdout = io::stdout();
    let stderr = io::stderr();
    if let Err(e) = run(&mut stdout.lock(), &mut stderr.lock(), &Path::new(".")) {
        eprintln!("error: {e}");
        process::exit(1);
    }
}
```

Add `R: BufRead` when stdin is needed. Unit tests inject `Vec<u8>` writers and `io::Cursor` readers. Integration tests in `tests/cli.rs` use `env!("CARGO_BIN_EXE_<name>")` + `tempfile::tempdir()`.

### Error Construction

Use `io::Error::other("msg")` — not `io::Error::new(io::ErrorKind::Other, "msg")`. The `clippy::io_other_error` lint fires on the old form in Rust 1.74+. Applies everywhere, including test `FailWriter` stubs.

### Clippy Lints to Know

These fire with `-D warnings` and are easy to write wrong the first time:

**`clippy::ptr_arg` — prefer `&mut [T]` over `&mut Vec<T>`**

When a function takes a mutable Vec but doesn't push/pop/resize it, use a slice reference instead. It's strictly more general and callers don't need to change — `Vec<T>` auto-derefs to `[T]`.

```rust
// Wrong — clippy::ptr_arg fires
fn process(cache: &mut Vec<u32>) { ... }

// Correct
fn process(cache: &mut [u32]) { ... }
```

**`clippy::manual_is_multiple_of` — use `.is_multiple_of(x)` over `% x == 0`**

Stabilized on all integer primitives in Rust 1.86. CI uses `dtolnay/rust-toolchain@stable` which always pulls the latest stable, so this lint is always active.

```rust
// Wrong — clippy::manual_is_multiple_of fires on Rust 1.86+
if n % 2 == 0 { ... }

// Correct
if n.is_multiple_of(2) { ... }
```

### Tarpaulin Coverage

**Coverage gate is CI-only.** `cargo tarpaulin` takes ~8s per crate locally. Do not add it to the pre-push hook; CI is the gate (`cargo tarpaulin --fail-under 90` in the `test` job).

**Linux ptrace tarpaulin counts more lines as coverable than macOS tarpaulin.** Three patterns produce uncoverable probes on Linux that cannot be fixed by adding tests — apply fixes before concluding coverage is unreachable:

**1. `fn main()` body lines — always exclude**

Linux ptrace counts `fn main()` body lines as coverable even when tests never call `main()`. Exclude it unconditionally:

```rust
#[cfg(not(tarpaulin_include))]
fn main() { ... }
```

Add the companion `Cargo.toml` lint so clippy does not reject the unknown cfg:

```toml
[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(tarpaulin_include)'] }
```

**2. Multi-line `write!/writeln!` arguments — keep macros single-line**

Linux ptrace counts the first and last argument lines of multi-line macros as separate coverable probes that never fire during test runs. Two measures together prevent `cargo fmt` from expanding them:

- Add `rustfmt.toml` with `use_small_heuristics = "Max"` to raise `fn_call_width` from the default 60% to 100% of `max_width`. Without this, `cargo fmt` expands any macro whose arguments alone exceed ~60 chars back to multi-line.
- Use captured-variable format syntax (`{var}` rather than `"{}", var`) to reduce 4-arg macros to 2-arg form so they fit under the threshold.

Format strings that are inherently long (>100 chars total) cannot be made single-line even with these settings; accept 1–2 uncoverable lines per crate from unavoidably long macros.

**3. `break;` inside `while let` — fold into the loop condition**

Linux ptrace counts explicit `break;` statements as coverable probes that never fire even when the break IS executed. Eliminate the break using `Option::filter`:

```rust
// Before (break; uncoverable):
while let Some(val) = next() {
    if val >= limit { break; }
    process(val);
}

// After (no break):
while let Some(val) = next().filter(|&v| v < limit) {
    process(val);
}
```

### Cargo.toml Template

Every Rust crate that uses `#[cfg(not(tarpaulin_include))]` needs:

```toml
[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(tarpaulin_include)'] }
```

### rustfmt.toml

Add to every Rust crate that has `write!/writeln!` macros with arguments that approach the default 60-char threshold:

```toml
use_small_heuristics = "Max"
```

### Tarpaulin Instrumentation Limits

Tarpaulin does not instrument inside macro argument expressions for `error!()`, `trace!()`, `warn!()`, `anyhow!()`, or struct literal fields in `return` statements. Lines inside these constructs show as uncovered even when the branch executes. Accept the coverage ceiling rather than writing complex test infrastructure to reach them — these are genuine instrumentation gaps, not missing tests.
