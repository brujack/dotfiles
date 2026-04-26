---
name: rust-io-error-other
description: Use io::Error::other() not io::Error::new(io::ErrorKind::Other, ...) — clippy io_other_error lint
type: feedback
originSessionId: 6a19bade-637f-444e-a960-9df032c46c4d
---

Use `io::Error::other("msg")` instead of `io::Error::new(io::ErrorKind::Other, "msg")`.

**Why:** The `clippy::io_other_error` lint fires on the old form in Rust 1.74+. Encountered in FailWriter test helpers across prime-rs and twin-primes-rs.

**How to apply:** Any time you write a `FailWriter` or similar test stub that returns an `io::Error`, always use `io::Error::other(...)`.
