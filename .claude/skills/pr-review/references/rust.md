# Rust PR Review Reference

## Security
- No `unsafe` blocks without a `// SAFETY:` comment explaining the invariant
- No `unwrap()` or `expect()` on user-facing or production paths — use `?` or proper error handling
- Dependencies: check `Cargo.lock` diff for new crates; flag any with known CVEs or unfamiliar provenance
- No hardcoded secrets in string literals

## TDD / Tests
- Unit tests in `#[cfg(test)]` modules in the same file
- Integration tests under `tests/`
- `cargo test` must pass clean — zero failures, zero ignored without justification
- Property-based tests (`proptest`, `quickcheck`) preferred for algorithmic code

## Code Quality
- `cargo clippy -- -D warnings` should produce no warnings
- `cargo fmt --check` — formatting must be consistent
- No `todo!()` or `unimplemented!()` in production paths
- Lifetimes annotated clearly; avoid unnecessary `'static` bounds
- Prefer `?` over manual `match` for error propagation
- Iterator chains preferred over imperative loops where readable

## Logic
- `Result` and `Option` exhaustively handled
- Panic paths (`unwrap`, `expect`, index out of bounds) justified or eliminated
- Concurrency: check for `Arc<Mutex<>>` contention, `Send`/`Sync` bounds correct

## Commands to run
```bash
cargo build 2>&1
cargo test 2>&1
cargo clippy -- -D warnings 2>&1
cargo fmt --check 2>&1
cargo audit 2>&1   # if cargo-audit installed
```
