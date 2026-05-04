---
name: Coverage ceiling and gaps
description: Practical coverage limits for etch-cli — what is and isn't testable, macOS vs CI gap
type: project
originSessionId: a4242489-88b7-4c64-a990-e129cc91fc71
---

Coverage is ~79.4% locally (macOS) and ~65% on Linux CI. The CI gate is ≥65%.

**Why the macOS/CI gap:** `#[cfg(target_os = "macos")]` tests don't run on ubuntu-latest. macOS provider tests (dscl, Homebrew, macOS defaults) add ~14pp locally that CI never sees.

**Practical ceiling: ~80-81%.** The remaining uncovered lines are genuinely untestable in unit tests:

- Network operations: GitHub API (`binary/github.rs`), git clone (`manifests/providers/git.rs`, `atoms/git/clone.rs`), DNS (`contexts/variable_include/dns.rs`)
- Package managers: `package/install.rs`, `package/repository.rs`, `package/providers/homebrew.rs`
- Privilege escalation: `exec.rs` `elevate()` method (needs `sudo --validate`)
- macOS-specific tools: `user/providers/macos.rs` "dscl not found" branches
- Macro instrumentation limits: tarpaulin does not instrument inside `error!()`, `trace!()`, `anyhow!()` macro argument expressions, or struct literal fields in `return` statements — these lines show as uncovered even when the branch executes

**Why:** Discovered through systematic coverage analysis across 15 PRs adding ~40 tests.

**How to apply:** When tarpaulin shows specific lines uncovered in error branches and those branches involve macros or struct literals, accept the ceiling rather than writing complex infrastructure to trigger them.
