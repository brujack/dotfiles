---
name: tarpaulin coverage differs between macOS and Linux CI
description: macOS measures ~10pp higher than Linux CI due to cfg(target_os = "macos") test blocks that only run locally
type: project
---

Local tarpaulin (macOS) reports ~75%; Linux CI (ubuntu-latest) reports ~65%. The gap is macOS-specific provider tests gated with `#[cfg(target_os = "macos")]` covering `user/providers/macos.rs` and `group/providers/macos.rs`.

**Why:** Those test modules only compile and run on macOS. On Linux CI they're skipped entirely, so ~96 lines of macOS provider code show 0% on CI.

**How to apply:** When setting the tarpaulin `--fail-under` gate in CI, measure coverage from a Linux run (or the CI run), not from a local macOS run. The CI gate is 65%; local macOS coverage is ~75%. Both figures are legitimate — they measure different things.

To close the gap without platform-splitting CI: add cross-platform mock tests for macOS providers (similar to the PATH injection approach used for Linux providers), or accept the measurement difference.
