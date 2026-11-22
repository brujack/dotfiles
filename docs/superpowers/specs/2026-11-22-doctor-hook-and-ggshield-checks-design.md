# Doctor checks: installed hooks and ggshield authentication

**Date:** 2026-11-22
**Status:** Draft
**Source:** security audit 2026-11-16, findings F5, F6 and F10 (ai-config
`docs/knowledge/dotfiles-security-audit-2026-11-16.md`).

## Problem

Three findings share one gap: `setup_env.sh -t doctor` says nothing about whether the
local secret-scan and push gates can run.

- **F5.** No doctor check reads the installed hooks. `_git_hooks_check_complete`
  (`lib/git_hooks.sh`) exists, but only the `-t update` and `setup_user` repair sweep calls
  it, and that sweep repairs gaps without reporting them as a health state.
- **F6.** `_git_hooks_check_complete` tests `[[ -x ]]` only. A hook that is present and
  executable but is a stale copy, or another repo's script, passes.
- **F10.** Nothing checks that `ggshield` resolves and holds a working API key. The
  pre-commit hook degrades to a warning when ggshield is missing or unauthenticated
  (ADR-0052), so a machine can commit for weeks with no secret scan and no persistent
  signal.

ai-config ADR-0055 added `make check-hooks` and a SessionStart drift warning, but for
ai-config's own three hooks only. ai-config `ci.md` still records, fleet-wide, "Nothing
reports an uninstalled or stale hook."

## Premise measurements (2026-11-22, `claude`)

- **Hooks.** 27 mandated hooks (`pre-commit`, `pre-push`, `commit-msg` in each of the nine
  `HOOK_EXPECTED_REPOS`) checked with absolute-path `cmp` and `readlink -f`. 26 are a
  symlink to, or a byte-identical copy of, a tracked file in their own repo. One,
  state-ledger's `pre-commit`, is a regular file matching no tracked file: a stale copy.
  It passes `_git_hooks_check_complete` today. This is the live F6 instance. Population:
  one machine (`claude`); the other development boxes were not surveyed.
- **Install styles in use.** `cp`, `install -m`, relative `ln -s`, absolute `ln -s`
  (dotfiles: `ln -sf "$(shell pwd)/scripts/…"`), and terraform_ansible's
  `ansible/scripts/`. No single per-repo name mapping covers them. "Matches some tracked
  file in the same repo" covers all of them.
- **ggshield 1.56.1 exit codes, by command** (measured on `claude` with the real key, with
  `GITGUARDIAN_API_KEY=invalid-fixture-key`, and with `HOME`/`XDG_CONFIG_HOME` pointing at
  an empty directory):

  | command               | good key | bad key | no key |
  | --------------------- | -------- | ------- | ------ |
  | `ggshield api-status` | 0        | **0**   | 3      |
  | `ggshield quota`      | 0        | 128     | 3      |

  `api-status` exits 0 for a rejected key and prints `Status: unhealthy (Invalid API
key.)`. A check built on it passes the case F10 exists to catch. `quota` separates all
  three. A dead proxy (`HTTPS_PROXY=http://127.0.0.1:9`) made `api-status` hit a 15 s
  `timeout` (rc 124).

## Design

Two new doctor arms, run by `run_doctor` in this order, immediately after
`_doctor_check_hooks_path`:

```
_doctor_check_hooks_path
_doctor_check_git_hooks      # new
_doctor_check_ggshield       # new
_doctor_check_versions
```

Neither arm writes anything. Neither changes `-t update`, `setup_user`, or the repair
sweep (operator decision 2026-11-22: doctor only).

### 1. `_doctor_check_git_hooks` (F5, F6)

Prints the heading `Git hooks:`. For each name in `HOOK_EXPECTED_REPOS`, with
`dir=${PERSONAL_GITREPOS}/<name>`:

| state                                                                   | line                                                                                   |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `dir` absent                                                            | `doctor_pass "<name>: not cloned on this host"`                                        |
| `dir/.git` not a directory, or `git rev-parse --git-dir` fails          | nothing (same rule as `_git_hooks_gap_repos`)                                          |
| `_git_hooks_dir` fails                                                  | `doctor_fail "<name>: no hooks directory — remedy: make -C <dir> install-hooks"`       |
| any mandated hook not `-x`                                              | `doctor_fail "<name>: missing <hooks> — remedy: make -C <dir> install-hooks"`          |
| every hook `-x`, any hook's identity is `foreign`                       | `doctor_fail "<name>: <hook> is not this repo's script — remedy: …"`                   |
| every hook `-x`, any hook `stale`, repo on `master` or `main`           | `doctor_fail "<name>: <hook> is stale — remedy: …"`                                    |
| every hook `-x`, any hook `stale`, repo on any other branch or detached | `doctor_warn "<name>: <hook> differs from <branch> (expected off the default branch)"` |
| every hook `-x`, any hook `worktree`                                    | `doctor_warn "<name>: <hook> runs from worktree <path> — remedy: …"`                   |
| identity unreadable (rc 2)                                              | `doctor_fail "<name>: cannot verify hooks (<reason>)"`                                 |
| every hook `-x` and `match`                                             | `doctor_pass "<name>: pre-commit pre-push commit-msg installed"`                       |

`<hooks>` is the space-joined list `_git_hooks_check_complete` prints. The remedy text is
always `make -C <dir> install-hooks`. For terraform_ansible, whose `install-hooks` target
lives in `ansible/Makefile`, the remedy names the directory `_git_hooks_target_dir`
returns, not the repo root.

The default-branch test reads the branch name with `git symbolic-ref --short -q HEAD`
and treats only the literal names `master` and `main` as default. It does not read
`refs/remotes/origin/HEAD`, which is a clone-time cache (core.md git-workflow-038).

#### `_git_hooks_identity <repo_dir> <hook_path>` (new, `lib/git_hooks.sh`)

Prints one word and returns:

- **`match`, rc 0.** `hook_path` is a symlink whose fully resolved target is a tracked
  file of the repo's main working tree, or a regular file byte-identical (`cmp -s`) to
  the on-disk content of some tracked file of that tree.
- **`worktree`, rc 1.** `hook_path` is a symlink whose resolved target lies inside a
  linked worktree of the same repo (from `git worktree list --porcelain`).
- **`stale`, rc 1.** `hook_path` is a regular file matching no tracked file, or a symlink
  whose target is inside the repo's main working tree but not tracked.
- **`foreign`, rc 1.** `hook_path` is a symlink whose resolved target lies outside the
  repo and all its worktrees.
- **rc 2,** printing a reason. `git ls-files` fails, or `hook_path` cannot be read.

Candidates for the `cmp` are the tracked paths whose on-disk file is a regular file of
the same byte size as the hook. The size filter keeps the comparison count to a handful
without trusting names. Every git call uses the four-variable strip
(`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`). A symlink is resolved through every level, and the result is compared as a physical path
(`pwd -P`), so a symlinked `PERSONAL_GITREPOS` cannot turn a match into `foreign`.

`_git_hooks_check_complete` is not changed: its callers (the repair sweep) keep their
`-x`-only semantics.

### 2. `_doctor_check_ggshield` (F10)

Prints the heading `ggshield:`.

**Resolution.** It uses the order the pre-commit hook uses today: `GGSHIELD_BIN`, then
`command -v ggshield`, then each of `GGSHIELD_FALLBACK_PATHS`. That code moves out of
`scripts/pre-commit-hook.sh` into a new `lib/ggshield.sh` defining
`resolve_ggshield`, which prints the path and returns:

- 0 when resolved;
- 1 when not found;
- 2 when `GGSHIELD_BIN` is set but not executable.

`scripts/pre-commit-hook.sh` sources `lib/ggshield.sh` from the repository top level it
already `cd`s into, and maps rc 2 to its existing message and `exit 1`, and rc 1 to its
existing announce-twice-and-continue path. Its observable behaviour does not change.
`resolve_ggshield` itself prints nothing on stderr; the messages stay in each caller.

**Doctor lines:**

| condition                      | line                                                                                               |
| ------------------------------ | -------------------------------------------------------------------------------------------------- |
| `resolve_ggshield` rc 2        | `doctor_fail "GGSHIELD_BIN=<value> is not executable"`                                             |
| `resolve_ggshield` rc 1        | `doctor_fail "not installed — the pre-commit secret scan cannot run — remedy: <platform install>"` |
| no `timeout` binary resolvable | `doctor_warn "<path>: found; API key not verified (no timeout binary)"`                            |
| `quota` rc 0                   | `doctor_pass "<path>: authenticated"`                                                              |
| `quota` rc 3                   | `doctor_fail "<path>: no API key — remedy: ggshield auth login"`                                   |
| `quota` rc 124                 | `doctor_warn "<path>: could not verify the API key: no answer in <N>s"`                            |
| `quota` any other non-zero rc  | `doctor_fail "<path>: API key rejected or check failed (rc <rc>) — remedy: ggshield auth login"`   |

`<platform install>` is `brew install ggshield` on macOS and on Linux with Homebrew, the
same remedy `_install_ubuntu_brew_packages` implies. The probe runs
`"${_timeout_bin}" "${_DOCTOR_PROBE_TIMEOUT:-10}" "${_ggshield}" quota </dev/null >/dev/null 2>&1`,
with `_timeout_bin` resolved the same way `_doctor_check_dev_tools` resolves it, through
`_TIMEOUT_FALLBACK_PATHS`. Neither stdout nor stderr of `ggshield` reaches doctor's output,
so no key material or account detail can.

`quota` is a read-only endpoint. Not running a scan keeps the probe from consuming scan
quota.

## Testing

- **Hook fixtures.** Built under `BATS_TEST_TMPDIR` with `PERSONAL_GITREPOS` and
  `HOOK_EXPECTED_REPOS` pointed at them: one real `git init` repo per state, with
  tracked `scripts/hook.sh`. States: absent, linked worktree only, no hooks dir, missing
  hook, non-executable hook, symlink match, absolute and relative symlink, copy match,
  stale copy on `master`, stale copy on a branch, symlink into a linked worktree,
  symlink to another fixture repo, symlink to an untracked file, an empty hook file, and
  an unreadable hook.
- **Positive control** for identity. A copy that passes turns into a `stale` FAIL after a
  one-byte edit to the installed hook, in the same test.
- **ggshield.** A stub at `tests/stubs/ggshield-stub`, reached only through `GGSHIELD_BIN`
  and `GGSHIELD_FALLBACK_PATHS`, with exit code and sleep read from `STUB_GGSHIELD_*`.
  Cases: rc 0, 3, 128, 1, timeout (`_DOCTOR_PROBE_TIMEOUT=1`, stub sleeps 5), not found,
  non-executable override, and no `timeout` binary. The no-`timeout` case uses
  `_TIMEOUT_FALLBACK_PATHS` at a missing path and a scoped `PATH` of stubs.
- **Leak check.** The stub prints a fixed fake key on stdout and stderr. A test asserts
  doctor's output does not contain it, after asserting the stub was actually called
  (absence needs a positive control).
- **Hook behaviour.** The existing `tests/scripts/pre_commit_hook.bats` ggshield resolution
  tests pass unchanged after the move to `lib/ggshield.sh`. `resolve_ggshield` gets unit
  tests for its three return codes.
- **Wiring.** A `run_doctor` test with both arms stubbed asserts their headings appear
  between `Git hooks path` and the versions section.

## Rejected alternatives

- **`ggshield api-status`** as the auth probe. Measured above: it exits 0 for a rejected
  key.
- **A per-repo `installed-name:source` map** (ADR-0055's `MANAGED_HOOKS`). That needs a
  map for each of nine repos, maintained in dotfiles for repos dotfiles does not own.
  "Byte-identical to some tracked file" needs no map and caught the one live instance.
- **Comparing against `HEAD`'s blob** instead of the working tree. ADR-0055 compares
  against the working tree, because that is what `install-hooks` copies. A blob compare
  would call a freshly installed hook stale whenever the source has uncommitted edits.
- **Extending `_git_hooks_check_complete` to check identity.** It changes what the repair
  sweep repairs, which the operator ruled out of scope.

## Requirements

- **R1.** `run_doctor` calls `_doctor_check_git_hooks` and then `_doctor_check_ggshield`, both immediately after `_doctor_check_hooks_path` and before `_doctor_check_versions`.
- **R2.** `_doctor_check_git_hooks` prints the heading `Git hooks:` and, for each `HOOK_EXPECTED_REPOS` name whose directory under `PERSONAL_GITREPOS` is absent, calls `doctor_pass "<name>: not cloned on this host"`.
- **R3.** `_doctor_check_git_hooks` prints nothing for a listed name whose `.git` is not a directory or whose `git rev-parse --git-dir` fails.
- **R4.** When `_git_hooks_dir` fails for a repo, `_doctor_check_git_hooks` calls `doctor_fail "<name>: no hooks directory — remedy: make -C <dir> install-hooks"`, where `<dir>` is the directory `_git_hooks_target_dir` prints for that repo, or the repo directory itself when it prints nothing.
- **R5.** When any of `pre-commit`, `pre-push`, `commit-msg` is not executable in a repo's hooks directory, `_doctor_check_git_hooks` calls `doctor_fail "<name>: missing <hooks> — remedy: make -C <dir> install-hooks"`, `<hooks>` being the space-joined names `_git_hooks_check_complete` prints.
- **R6.** `_git_hooks_identity <repo_dir> <hook_path>` prints `match` and returns 0 when `hook_path` is a symlink resolving to a tracked file of the repo's main working tree, or a regular file `cmp -s`-identical to the on-disk content of a tracked file of that tree.
- **R7.** `_git_hooks_identity` prints `worktree` and returns 1 for a symlink resolving inside a linked worktree of the same repo; prints `foreign` and returns 1 for a symlink resolving outside the repo and all its worktrees; prints `stale` and returns 1 for a regular file matching no tracked file, or a symlink to an untracked file inside the main working tree.
- **R8.** `_git_hooks_identity` returns 2 and prints a reason when `git ls-files` fails or `hook_path` is unreadable.
- **R9.** With every mandated hook executable: a `foreign` hook gives `doctor_fail "<name>: <hook> is not this repo's script — remedy: make -C <dir> install-hooks"`; a `stale` hook gives `doctor_fail "<name>: <hook> is stale — remedy: make -C <dir> install-hooks"` when `git symbolic-ref --short -q HEAD` prints `master` or `main`, and `doctor_warn "<name>: <hook> differs from <branch> (expected off the default branch)"` otherwise, `<branch>` being `detached HEAD` when detached.
- **R10.** With every mandated hook executable: a `worktree` hook gives `doctor_warn "<name>: <hook> runs from worktree <path> — remedy: make -C <dir> install-hooks"`; an identity rc 2 gives `doctor_fail "<name>: cannot verify hooks (<reason>)"`; all three `match` gives `doctor_pass "<name>: pre-commit pre-push commit-msg installed"`.
- **R11.** `_git_hooks_check_complete` is unchanged.
- **R12.** `lib/ggshield.sh` defines `resolve_ggshield`, which prints the resolved path and returns 0, returns 1 when nothing resolves, and returns 2 when `GGSHIELD_BIN` is set but not executable, resolving in the order `GGSHIELD_BIN`, `command -v ggshield`, then each word of `GGSHIELD_FALLBACK_PATHS` (default `/opt/homebrew/bin/ggshield /usr/local/bin/ggshield /home/linuxbrew/.linuxbrew/bin/ggshield`), and writes nothing to stderr.
- **R13.** `scripts/pre-commit-hook.sh` resolves ggshield only through `resolve_ggshield`, sourced from `lib/ggshield.sh` under the repository top level, and its stderr messages and exit codes for each resolution outcome are unchanged.
- **R14.** `_doctor_check_ggshield` prints the heading `ggshield:`; on `resolve_ggshield` rc 2 calls `doctor_fail "GGSHIELD_BIN=<value> is not executable"`; on rc 1 calls `doctor_fail "not installed — the pre-commit secret scan cannot run — remedy: brew install ggshield"`.
- **R15.** When ggshield resolves and no `timeout` binary resolves through `_TIMEOUT_FALLBACK_PATHS` or `PATH`, `_doctor_check_ggshield` calls `doctor_warn "<path>: found; API key not verified (no timeout binary)"` and runs no ggshield command.
- **R16.** Otherwise `_doctor_check_ggshield` runs `<timeout> "${_DOCTOR_PROBE_TIMEOUT:-10}" <path> quota` with stdin from `/dev/null` and stdout and stderr discarded, and maps rc 0 to `doctor_pass "<path>: authenticated"`, rc 3 to `doctor_fail "<path>: no API key — remedy: ggshield auth login"`, rc 124 to `doctor_warn "<path>: could not verify the API key: no answer in <N>s"`, and any other non-zero rc to `doctor_fail "<path>: API key rejected or check failed (rc <rc>) — remedy: ggshield auth login"`.
- **R17.** No test reaches the real `ggshield` binary or the network: every `_doctor_check_ggshield` test sets `GGSHIELD_BIN` or `GGSHIELD_FALLBACK_PATHS` to `tests/stubs/ggshield-stub` or a missing path.
- **R18.** A test asserts that a fake key printed by the stub on stdout and stderr does not appear in `_doctor_check_ggshield`'s output, in a test that also asserts the stub was invoked.
- **R19.** A test installs a byte-identical copy that `_doctor_check_git_hooks` reports as PASS, edits one byte of the installed copy, and asserts the repo then reports `is stale` as a FAIL.
- **V1.** On `claude`, `./setup_env.sh -t doctor` on the finished branch reports state-ledger's `pre-commit` as stale (unless it has been reinstalled meanwhile, in which case reinstall a stale copy in a throwaway clone listed via `HOOK_EXPECTED_REPOS` and run the arm there), and reports `ggshield: … authenticated`.
- **V2.** On `claude`, `GITGUARDIAN_API_KEY=invalid-fixture-key ./setup_env.sh -t doctor` reports the ggshield arm as FAIL with `rc 128`, against the real binary and service.
- **V3.** On the Studio, the hook arm runs on BSD userland and gives the same verdicts as on `claude` for the repos it has cloned; any difference is explained before merge.
- **V4.** CI is green on the PR, including all three `test-macos-shard` legs.
- **N1.** No change to `-t update`, `setup_user`, `install_git_hooks_all_repos` or any repair path.
- **N2.** No doctor arm writes, removes or reinstalls any file in any repo or under `HOME`.
- **N3.** `_doctor_check_ggshield` never runs `ggshield secret scan` or any other command that consumes scan quota.
- **N4.** No per-repo hook-name map is added.
