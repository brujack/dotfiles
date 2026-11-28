# ADR-0062: CI scans the real root directories for suite writes

**Date:** 2026-11-27
**Status:** Accepted

## Context

The bats suite must never write to the real host. The ledger guard (`assert_no_real_root_paths`)
reads recorded mock calls, which is a proxy for the write, not the write. Its blind spots (private
ledgers under other names, a ledger repointed inside a `zsh -c` string, the bats files that never
call `load_mocks`, a `PATH` assembled across lines, misattribution through the shared suite ledger
under `--jobs`) were measured on 2026-11-27 and hid 0 hits.

The one instrument without those gaps is a listing of the real root directories before and after
the suite. It caught the 2026-11-26 docker keyring and list escape in `/etc/apt` that no ledger
guard reported, and it ran only when someone remembered to do it by hand.

## Decision

Add `scripts/root-writes.sh mark|check`, a filesystem scan, and wrap it around the bats work in the
CI shard jobs (`test-shard` and `test-macos-shard`) only.

- **Scan.** `mark` writes a marker file. `check` runs `find -newer` and `find -cnewer` against it
  over the resolved roots `/etc`, `/usr/local`, `/usr/share/keyrings` and `/opt`, and counts the
  entries visited.
- **Emptiness is cross-checked.** A root that lists as non-empty by an independent `ls -A`, run under
  the same privilege, must show entries visited. A walk that visited nothing is a failure, not a pass.
- **Privilege.** The scan runs under `sudo -n` when passwordless sudo is available.
- **Fail-only.** The step runs after the suite and fails the shard when it finds a change or cannot
  walk a root. It never rewrites or removes anything.
- **No local mode.** On `claude` there were 30 non-suite changes under the roots in 24 hours and 28
  unreadable directories, so a local run would warn on writes the suite never made.
- **Prune lists.** Each OS has a prune list in the script, holding only `/opt/hca` at merge: the
  hosted runner writes its own agent log there (`hosted-compute-agent.log`) on both OSes during a
  job (rollout runs 46103860810 and 46103849102). An entry enters only by spec amendment, with the
  measurement that produced it. No entry may equal or contain a directory `lib/` installs into;
  `tests/scripts/root_writes.bats` enforces that.
- **macOS stdlib precompile.** Homebrew Python writes stdlib bytecode under `/opt/homebrew/Cellar`
  the first time the suite imports a module, and the suite's `python3 -I` callers ignore
  `PYTHONPYCACHEPREFIX`. `test-macos-shard` compiles the stdlib (`python3 -m compileall`) in a step
  before the window opens, so `/opt/homebrew` stays scanned rather than pruned (rollout run
  46107517429; clean afterwards in run 46110149073, attempts 1 and 2).
- **Rollout gate.** The step merges only after a never-merged scratch branch shows 10 null windows
  per OS, 2 suite windows, and a deliberate `/usr/bin/sudo` escape that the scan catches.

## Consequences

- A red shard names paths, not tests. Reproduce by bisecting the shard's file list inside an
  `ubuntu:26.04` container.
- The scan is not tamper-proof: a PR branch runs its own copy of the scan and the workflow.
- Builtin read probes are not covered. The superpowers Backlog carries a row for it.
- The fixture tests for the script cost about 1-2 s each in marker sleep. The suite itself pays
  nothing beyond the two scan steps per shard.
- The ledger guard stays. It reports the offending test at teardown, which the scan cannot.

## Related

- Spec: `docs/superpowers/specs/2026-11-27-root-writes-scan-design.md`
- Plan: `docs/superpowers/plans/2026-11-27-root-writes-scan.md`
- dotfiles#494, dotfiles#495, dotfiles#497
- [ADR-0060](0060-bats-suite-hooks-sentinel-home.md)
