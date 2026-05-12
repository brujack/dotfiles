---
name: Rust clippy manual_is_multiple_of — use n.is_multiple_of(x) not n % x == 0
description: Clippy manual_is_multiple_of lint (Rust 1.86+) requires is_multiple_of() instead of modulo-zero check
type: feedback
---

Use `n.is_multiple_of(x)` instead of `n % x == 0` for integer divisibility checks in Rust. Clippy fires `clippy::manual_is_multiple_of` with `-D warnings` on Rust 1.86+ and the build fails.

**Why:** `is_multiple_of` is more expressive and was stabilized on all integer primitives in Rust 1.86. The repo CI uses `dtolnay/rust-toolchain@stable` which pulls the latest stable, so this lint is always active.

**How to apply:** Any time you write `n % 2 == 0`, `n % 4 == 0`, etc., use the method form instead. Applies to all integer types (u8, u32, u64, i32, etc.).

Example caught in math repo (collatz-rs PR #49, 2026-05-12):

```rust
// Wrong — clippy manual_is_multiple_of fires on Rust 1.86+
fn collatz_next(n: u64) -> u64 {
    if n % 2 == 0 { n / 2 } else { 3 * n + 1 }
}

// Correct
fn collatz_next(n: u64) -> u64 {
    if n.is_multiple_of(2) { n / 2 } else { 3 * n + 1 }
}
```
