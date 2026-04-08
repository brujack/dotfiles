---
name: Pi Calculator Project Work
description: Summary of work done on the pi calculator project (Python + Rust implementations) in the math/pi directory
type: project
---

Work was done in `/Users/bruce/git-repos/personal/math/pi` via CLI (session `8cf1ce1f-990c-4a42-b255-9c81a850673e`, PID 91079).

## What Was Built

**Python (`pi.py`)**: Fully multithreaded Chudnovsky algorithm targeting Apple Silicon and Linux x64.
- Parallel binary splitting via `_bs_chunk_worker()` running in subprocess workers (using `multiprocessing`, not threads, to bypass the GIL)
- Tree-based chunk combination via `_tree_combine()` — pairwise reduction is faster than left-fold for GMP's asymptotically fast multiplication
- Adaptive chunking: splits [0,N) into at most `_CPU_COUNT` chunks, minimum 100 terms each
- Parallel file I/O via `os.pwrite()` with pre-allocated file via `os.ftruncate()`
- Worker functions are at module level (required for macOS spawn mode pickling)
- Module-level `_gmpy2_QT_cache` dict stores plain Python ints (Q, T) — `gmpy2.mpfr` is a C extension type that doesn't support arbitrary attributes

**Rust (`pi-rs/`)**: For >50M digit workloads where Python subprocess IPC overhead becomes significant.
- Uses `rayon::join()` for recursive parallel binary splitting (shared memory, zero IPC cost)
- `rug` crate wrapping GMP + MPFR (same C libs as Python's `gmpy2`)
- Parallel file I/O via `FileExt::write_at`
- Key rug gotcha: operator overloading returns lazy `MulIncomplete` types — must wrap with `Integer::from(...)` before further operations

## Testing
- 20,000 digits in 0.29s (gmpy2 2.3.0, GMP 6.3.0, MPFR 4.2.2)
- Parallel chunks tested on 20-core system

## Final State (commit `f312fd1`)
- `pi.py` — Python multithreaded implementation
- `pi-rs/` — Rust implementation with Cargo.lock
- `README.md` — comparison table, install instructions, CLI docs, algorithm explanation
- `CLAUDE.md` — updated with Rust subdirectory layout, build instructions, rug arithmetic notes
- `.gitignore` — excludes `pi-rs/target/` and `pi_*_digits.txt`

**Why:** Python GIL limits true parallelism; subprocess model overcomes this but adds IPC overhead at very large digit counts, hence the Rust fallback.
**How to apply:** When suggesting changes to pi.py or pi-rs/, be aware of the pickling constraints, the rug lazy-type issue, and the macOS spawn-mode module-level requirement.
