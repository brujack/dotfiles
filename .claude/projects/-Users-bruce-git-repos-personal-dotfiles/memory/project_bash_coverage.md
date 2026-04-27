---
name: Bash coverage gate status
description: kcov does not work in GitHub Actions; bash-coverage CI job is non-blocking; coverage is local-only for now
type: project
originSessionId: 46dccef5-7a5a-4ab9-902a-756ffcf58677
---

Bash coverage gate infrastructure is in place (PR #49 merged, master 03f8c26).

**Why:** Plan to add per-file coverage floors (90% for core libs, 75% for macos.sh/linux.sh) to match the PowerShell coverage gate.

**Current state (measurement mode, gate not enabled):**

- `make coverage` works locally (macOS/Linux VMs with kcov installed)
- `scripts/run-coverage.sh` runs kcov, checks per-file floors, reports table
- CI job (`bash-coverage` in `.github/workflows/ci.yml`) runs kcov but exits 0 with a warning when no data produced

**kcov incompatibility with GitHub Actions:**

- kcov uses ptrace to trace bash child processes
- GitHub Actions blocks kcov's tracing regardless of security settings tested:
  - ptrace_scope=0 (no effect)
  - Docker container + seccomp=unconfined (no effect)
  - Docker container + CAP_SYS_PTRACE (no effect)
  - Docker container + --privileged (no effect)
- Root cause: kcov's ptrace-based IPC cannot trace bats' test subshells in the GH Actions environment
- bashcov also tried — incompatible with bats-core due to UUID in temp file paths

**How to apply:** When revisiting coverage gating, don't retry kcov or bashcov — need a different approach (e.g., BASH_ENV + DEBUG trap custom tracer, or bats --tap post-processing). Gate enablement requires a tool that works in CI.

**Per-file coverage floors defined (not yet enforced):**

- setup_env.sh, constants.sh, detect_env.sh, helpers.sh, workflows.sh, update_summary.sh, developer.sh: 90%
- linux.sh, macos.sh: 75%
