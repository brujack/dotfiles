---
name: Rust clippy ptr_arg — prefer &mut [T] over &mut Vec<T> in function parameters
description: Clippy ptr_arg lint fires when a function takes &mut Vec<T>; correct form is &mut [T]
type: feedback
---

Prefer `&mut [T]` (slice reference) over `&mut Vec<T>` when writing Rust function parameters that don't need to grow or shrink the Vec. Clippy fires `clippy::ptr_arg` with `-D warnings` and the build fails.

**Why:** A slice reference is strictly more general — callers can pass `&mut Vec<T>`, `&mut [T]`, array references, etc. It's also the idiomatic Rust form per the clippy lint.

**How to apply:** When writing any function that takes a mutable Vec parameter but only reads or writes elements (not push/pop/resize), write `&mut [T]` instead of `&mut Vec<T>`. Callers don't need to change — `Vec<T>` auto-derefs to `[T]`.

Example caught in math repo (collatz-rs PR #49, 2026-05-12):

```rust
// Wrong — clippy ptr_arg fires
fn chain_length(n: u64, cache: &mut Vec<u32>, limit: u64) -> u32 { ... }

// Correct
fn chain_length(n: u64, cache: &mut [u32], limit: u64) -> u32 { ... }
```
