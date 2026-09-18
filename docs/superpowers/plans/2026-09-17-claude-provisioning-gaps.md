# Claude Provisioning Gaps Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four provisioning defects found moving sessions onto `claude`:

- the `pytest` shim is deleted on every login shell on Ubuntu 26.04;
- Linux has no `tflint`, `tfsec`, `zig` or tfenv provisioning;
- the cargo plugins are unprovisioned and unrepaired;
- `pwsh` never installs once its first attempt fails.

**Architecture:** `docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md` (revision 8, approved at `2d296ca3`) is the authority for every part below. When this plan and the spec disagree, the spec wins; stop and report the conflict.

- A tracked pyenv rehash hook, installed as a copy, registers every venv binary without `sort`.
- `doctor` and `-t update` both check the result.
- Cargo plugins are pinned, judged by whether they run, and repaired inside `-t update`.
- `tflint` and `tfsec` come through a checksum-pinned release-binary helper.
- terraform comes through tfenv.
- The `pwsh` guard now asks whether `pwsh` runs, not whether a `.deb` was downloaded.

**Tech Stack:** bash, bats, shellcheck; pyenv 2.8.x hooks; cargo; tfenv; crates.io API.

## Global Constraints

- Work only in `/Users/bruce/git-repos/personal/dotfiles-provisioning`, branch `fix/claude-provisioning-gaps`.
- **Test isolation (tdd.md E2), non-negotiable.** No test may reach the real `~/.pyenv`, `~/.cargo`, `~/.tfenv`, `/usr/local/bin`, crates.io, GitHub or apt.
  - Every new test sets `HOME="${BATS_TEST_TMPDIR}"` and `MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/calls"`.
  - Every new test sets the seams named below.
  - `tests/mocks/sudo` **execs real commands**, so a `sudo install` or `sudo ln` reaching a real path is a real write. Set every directory seam.
- **Seams introduced** (all env-overridable, each with its production default):

  | seam                                                           | default                                             |
  | -------------------------------------------------------------- | --------------------------------------------------- |
  | `_OVERRIDE_PYENV_ROOT`                                         | `${PYENV_ROOT:-${HOME}/.pyenv}`                     |
  | `_CARGO_BIN`                                                   | `${HOME}/.cargo/bin/cargo`, else `command -v cargo` |
  | `_RELEASE_BIN_DIR`                                             | `/usr/local/bin`                                    |
  | `_TFLINT_URL`, `_TFLINT_SHA256`, `_TFSEC_URL`, `_TFSEC_SHA256` | the pins                                            |
  | `_TFENV_ROOT`                                                  | `${HOME}/.tfenv`                                    |
  | `_TFENV_LINK_DIR`                                              | `/usr/local/bin`                                    |
  | `_TFENV_REPO_URL`                                              | `https://github.com/tfutils/tfenv.git`              |
  | `_PWSH_BIN`                                                    | `pwsh`                                              |
  | `_DOCTOR_PROBE_TIMEOUT`                                        | `10`                                                |
  | `_CRATES_API`                                                  | `https://crates.io/api/v1/crates`                   |

- **Pins, copied from the spec.**
  - `CARGO_TOOLS`: `cargo-audit@0.22.1`, `cargo-deny@0.19.4`, `cargo-insta@1.47.2`, `cargo-machete@0.9.2`, `cargo-mutants@27.0.0`, `cargo-semver-checks@0.47.0`, `cargo-tarpaulin@0.35.2`, `cargo-zigbuild@0.22.3`.
  - `TFLINT_VER=0.61.0`, with sha256 amd64 `ca4e4e8cb7cc3436f2b6979e9c4fd4e2623a66fcca1ad1fe12f8669967636ae2` and arm64 `999c25cfdb5208fe1133dec6b219e666a39fc2a7a0786a781dc9924ea5945ebf`.
  - `TFSEC_VER=1.28.14`, with sha256 amd64 `a32d0799bbefababaa4fcd814da9f4d251cd932789590b99d1d5fcb89ace6f68` and arm64 `7b872b0e8f398abebc21ab78f6c0535029ff649f0d18f0f3454a01bece3006a2`.
  - `TERRAFORM_VER=1.15.6` (already present).
- `shell.md` binds: `[[ ]]`, `${VAR}`, `printf`, `|| return 1` in functions, no `set -e`, no `local x="$(cmd)"`, and a numeric semver comparison (never `[[ a < b ]]`).
- A new function in `lib/*.sh` gets tests in the same commit, covering both branches of each guard plus the error paths.
- **Gates.** The full suite exceeds the 600 s Bash cap, so task gates are `make lint` plus the task's own bats files. The orchestrator runs `make test` and `make bash-coverage` once after Task 13.
- Capture commit and lint output to a file (`git commit ... > log 2>&1`, then read the log), never through a pipe to `tail`. Generate each commit message with `caveman:caveman-commit`.

## Verification (session level)

1. `make test` exits 0 on the branch. The CI test count stays ≥ 840. `make bash-coverage` stays ≥ 91%.
2. Post-merge on the real hosts, spec Verification cases 1–8, run in this order:
   - Cases 1, 2, 4 and 6 use scratch roots on `claude`.
   - Cases 3 and 5: `claude`, `-t setup_user`, then `-t developer`, then doctor.
   - Cases 7 and 8: `workstation`, `-t developer`, then `-t update --brew-only`.
     Each case's negative control must be observed, not assumed.
3. Edge cases that must be exercised:
   - the hook under `set -e` with `nullglob` off on entry;
   - a dangling or absent hook;
   - `--brew-only` reaching the `cargo-tools` section;
   - a crates.io request without a User-Agent (which the test must reject);
   - an existing `workstation` tfenv symlink and version file left untouched;
   - a `PATH` `tflint` not causing a skip in a scratch `_RELEASE_BIN_DIR`.

---

### Task 1: Pins and constants

```yaml-task
id: 1
description: Add CARGO_TOOLS, TFLINT/TFSEC pins and fix TERRAFORM_VER/header annotations (data only, consumers tested in later tasks; tdd not-applicable)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: bash -c 'source lib/constants.sh && [[ ${#CARGO_TOOLS[@]} -eq 8 && ${TFLINT_VER} == 0.61.0 && ${TFSEC_VER} == 1.28.14 ]]'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh]
depends_on: []
```

**Files:** `lib/constants.sh`.

- Add `CARGO_TOOLS=(...)`: the eight `crate@version` entries, alphabetical. Give each entry a `# consumer:` comment copied from the spec's Part 3 table.
- Add `TFLINT_VER`, `TFLINT_SHA256_AMD64`, `TFLINT_SHA256_ARM64`, `TFSEC_VER`, `TFSEC_SHA256_AMD64` and `TFSEC_SHA256_ARM64`, each with a `# read by lib/linux_ubuntu.sh:<fn>` line.
- Change `TERRAFORM_VER`'s annotation to `# read by lib/linux_ubuntu.sh:_install_ubuntu_tfenv`.
- Remove `TFLINT_VER`, `TFLINT_URL`, `TFSEC_VER` and `TFSEC_URL` from the header's "deleted dead pins" list. Keep the other names.

**Interfaces:** Produces `CARGO_TOOLS` (a bash array of `name@version`) and `TFLINT_VER`/`TFSEC_VER` plus their `*_SHA256_{AMD64,ARM64}`.

---

### Task 2: Rehash hook file and `install_pyenv_rehash_hook`

```yaml-task
id: 2
description: Add the tracked pyenv rehash hook and install_pyenv_rehash_hook (copy, gated on versions/), with hook and installer tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/pyenv_rehash_hook.bats
    exit_code: 0
  - cmd: 'grep -q "set -e" tests/setup_env/pyenv_rehash_hook.bats'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [pyenv.d/rehash/dotfiles-register-all-executables.bash, lib/helpers.sh, tests/setup_env/pyenv_rehash_hook.bats]
depends_on: [1]
```

**Hook file.** Copy the spec's Part 1 hook text verbatim, including `|| true` on the `shopt -p` capture. Prepend `#!/usr/bin/env bash` as line 1, so `scripts/list-shell-files.sh` lints it.

**`install_pyenv_rehash_hook`** in `lib/helpers.sh`:

- `root="${_OVERRIDE_PYENV_ROOT:-${PYENV_ROOT:-${HOME}/.pyenv}}"`.
- `[[ -d ${root}/versions ]] || return 0`.
- `mkdir -p "${root}/pyenv.d/rehash" || return 1`.
- If `cmp -s` finds the copy identical to the source, return 0.
- Otherwise `install -m 0644 <src> <dst> || return 1`.
- The source path comes from `DOTFILES_REPO_ROOT`.

**Tests** (a new file):

- **Hook**, sourced from a caller that defines a `make_shims` stub appending its args to a file, over a fixture root that has `versions/v/bin/{pytest,py.test,.dot}`, `versions/v/envs/e/bin/x` and an empty `versions/w/bin/`:
  - (a) `pytest`, `py.test` and `.dot` are registered, and no literal `*` is.
  - (b) Under `set -e` with `nullglob` and `dotglob` off on entry, the caller survives and both options are off afterwards. **This is the red case without `|| true`**: verify it goes red by removing `|| true` locally, then restore it.
  - (c) With both options on at entry, both are on afterwards.
  - (d) With `make_shims` undefined, the hook returns 0 and registers nothing.
- **Installer:**
  - with no `versions/`, it creates nothing;
  - it copies the hook, and the result is a regular file, not a symlink;
  - a second run with an identical copy does not rewrite it (compare mtimes, or use a spy);
  - a changed source is re-copied.

**Interfaces:** Produces `install_pyenv_rehash_hook` (returns 0 or 1) and the seam `_OVERRIDE_PYENV_ROOT`.

---

### Task 3: `_pyenv_missing_shims` and doctor shim arm

```yaml-task
id: 3
description: Add _pyenv_missing_shims predicate and _doctor_check_pyenv_shims wired into run_doctor after _doctor_check_gnu_coreutils
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/doctor_pyenv_shims.bats
    exit_code: 0
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/doctor_pyenv_shims.bats, tests/setup_env/unit.bats]
depends_on: [2]
```

**`_pyenv_missing_shims`**:

- Prints, one per line, every entry name in `${root}/versions/ansible/bin` that has no `${root}/shims/<name>`.
- Returns 0 when it ran, and 2 when `versions/ansible/bin` is absent.

**`_doctor_check_pyenv_shims`**, per spec Part 2:

- Silent when the venv is absent.
- An empty `bin/` gives `doctor_warn`, never a PASS of `0 of 0`.
- Missing shims give `doctor_fail`, naming them, with the remedy `pyenv rehash`.
- Otherwise `doctor_pass "pyenv shims: N of N ansible venv entries shimmed"`.

Call it from `run_doctor` directly after `_doctor_check_gnu_coreutils`. The end-to-end `run_doctor` tests in `unit.bats` stub every sub-check by name (see `CLAUDE.md`), so add a stub for the new arm there.

**Tests:**

- PASS with the count present in the output;
- FAIL naming `pytest`;
- empty-`bin` WARN;
- silence without a venv.

**Interfaces:** Produces `_pyenv_missing_shims` (stdout: names; rc: 0 when it ran, 2 when there is no venv) and `_doctor_check_pyenv_shims`.

---

### Task 4: Hook install call sites before each rehash

```yaml-task
id: 4
description: Call install_pyenv_rehash_hook from run_setup_user and directly before pyenv rehash in setup_ansible and recreate_python_venv, warn-and-continue, with call-order tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/developer.bats
    exit_code: 0
  - cmd: bats tests/setup_env/install_functions.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/developer.sh, lib/workflows.sh, tests/setup_env/developer.bats, tests/setup_env/install_functions.bats, tests/setup_env/workflows.bats]
depends_on: [2]
```

**Call sites.**

- In `setup_ansible`, insert `install_pyenv_rehash_hook || log_warn "pyenv rehash hook not installed — see above"` on the line directly before `pyenv rehash` (currently `lib/developer.sh:537`).
- Do the same in `recreate_python_venv`, before `:566`.
- The rehash stays the last command in each block.
- In `run_setup_user`, add the same warn-and-continue call.

**Tests:**

- A spy `install_pyenv_rehash_hook` that appends `hook-install` to `MOCK_CALLS_FILE`. The pyenv mock appends `pyenv rehash`. Assert the line number of `hook-install` is less than that of `pyenv rehash`, in both functions. A presence-only assertion is insufficient, per the spec.
- A spy returning 1: the rehash is still called, and the function's rc equals the pyenv mock's rehash rc. Set `MOCK_PYENV_EXIT` to prove the rc propagates.
- `run_setup_user` calls the installer (spy).

**Interfaces:** Consumes `install_pyenv_rehash_hook`.

---

### Task 5: `pyenv-shims` update section

```yaml-task
id: 5
description: Add pyenv-shims section to run_update (own block, gated run_all|BREW|PIP) that installs hook, rehashes with own pyenv resolution, and WARNs on missing shims
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/update_pyenv_shims.bats
    exit_code: 0
  - cmd: bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, lib/update_summary.sh, tests/setup_env/update_pyenv_shims.bats, tests/setup_env/workflows.bats, tests/setup_env/update_summary.bats]
depends_on: [3, 4]
```

**`run_update`.** Add a new block after the `pip` block, gated on `_run_all || UPDATE_BREW || UPDATE_PIP`. Put `pyenv-shims` into `_UPDATE_SECTION_ORDER` after `pip-check`. The block:

1. With no ansible venv: `_update_skip "pyenv-shims" "no ansible venv"`.
2. `install_pyenv_rehash_hook || log_warn …`.
3. Resolve pyenv using the pattern at `lib/workflows.sh:510-515`: export `PYENV_ROOT`, prepend `${PYENV_ROOT}/bin:${PYENV_ROOT}/shims`, then `command -v pyenv`. Do this inside the block, never inherited from `pip`.
4. Run `pyenv rehash` and write its rc to the section detail. It is non-fatal. A comment notes the possible 60 s lock wait.
5. If `_pyenv_missing_shims` prints anything, `_update_warn` the names. Otherwise record OK.
6. When flags exclude it: SKIP with "flag not set".

**Tests** (a new file). Full-run tests use `HOME="${BATS_TEST_TMPDIR}"`, fixture venvs, and stubs for every other section:

- rehash is called before the check;
- a failing rehash still reaches the check and records its rc;
- WARN names a missing shim;
- SKIP with no venv;
- SKIP under `--gems-only`;
- under `--brew-only`, pyenv resolves without the pip block.

Existing `run_update`/`_UPDATE_SECTION_ORDER` tests in `workflows.bats`/`update_summary.bats` must keep passing. Enumerate every full-run test with `grep -n 'run run_update' tests/setup_env/*.bats` and make sure none reaches a real pyenv.

---

### Task 6: `_cargo_tool_state` and `install_cargo_tools`

```yaml-task
id: 6
description: Add numeric semver compare, _cargo_tool_state (ok/newer/older/broken/absent) and install_cargo_tools (tri-state rc, --force on broken, LIBGIT2_NO_PKG_CONFIG=1 for tarpaulin) with a recording cargo mock
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/cargo_tools.bats
    exit_code: 0
  - cmd: bats tests/setup_env/developer.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/developer.sh, tests/setup_env/cargo_tools.bats, tests/mocks/cargo, tests/helpers/common.bash]
depends_on: [1, 4]
```

**The cargo mock.** Create `tests/mocks/cargo`:

- It logs `cargo $*` plus `LIBGIT2_NO_PKG_CONFIG=${LIBGIT2_NO_PKG_CONFIG:-}` to `MOCK_CALLS_FILE`.
- `install --list` prints `MOCK_CARGO_LIST`.
- `<sub> --help` exits with `MOCK_CARGO_HELP_EXIT_<sub with - replaced by _>`, default 0.
- `install` exits `MOCK_CARGO_INSTALL_EXIT`, default 0.

In `load_mocks` (`tests/helpers/common.bash`), export `_CARGO_BIN="${REPO_ROOT}/tests/mocks/cargo"` by default. Then no existing or future test can reach a real `~/.cargo/bin/cargo`.

**Functions** in `lib/developer.sh`:

- `_semver_cmp a b` prints -1, 0 or 1, comparing dot-separated numeric components and treating missing ones as 0. Test `0.9.2` vs `0.10.0` → -1.
- `_cargo_tool_state <cargo> <crate> <ver> <list>` prints one of `ok`, `newer`, `older`, `broken` or `absent`, per spec Part 3. The `--help` probe is `<cargo> <sub> --help`, where `<sub>` is the crate name without its `cargo-` prefix.
- `install_cargo_tools`, per spec Part 3:
  - With `HAS_RUST` unset: print `cargo tools: skipped (HAS_RUST unset)` and return 0.
  - Resolve `_CARGO_BIN`, else `${HOME}/.cargo/bin/cargo`, else `command -v cargo`. Unresolvable: return 1.
  - Read the list once.
  - `ok`/`newer`: print `cargo tools: <crate> <v> ok`.
  - `absent`/`older`: `install --locked <crate>@<v>`.
  - `broken`: add `--force`.
  - `cargo-tarpaulin` installs with `LIBGIT2_NO_PKG_CONFIG=1` in its environment only.
  - Return 0 if all succeeded, 2 if any failed (names on stderr).

**Tests:**

- all five states;
- the semver case above;
- the tarpaulin env var present only on tarpaulin's install line;
- `--force` only for `broken`;
- `newer` untouched;
- rc 0, rc 2 and rc 1;
- the `HAS_RUST`-unset message.

**Interfaces:** Produces `install_cargo_tools` (rc 0/1/2), `_cargo_tool_state`, `_semver_cmp`, and the seam `_CARGO_BIN`.

---

### Task 7: cargo-tools call sites

```yaml-task
id: 7
description: Call install_cargo_tools from run_setup_or_developer (advisory) and add cargo-tools run_update block after the run_all-only block, gated run_all|BREW, SKIP without HAS_RUST
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/cargo_tools_update.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, lib/update_summary.sh, tests/setup_env/cargo_tools_update.bats, tests/setup_env/workflows.bats, tests/setup_env/update_summary.bats]
depends_on: [5, 6]
```

**Call sites.**

- In `run_setup_or_developer`, after the platform installs: `install_cargo_tools || log_warn "cargo tools incomplete — see above"`.
- In `run_update`, add a **separate block after the `_run_all`-only "git-based tools" block closes** (currently `:711`, before `gems`), gated on `_run_all || UPDATE_BREW`:
  - With `HAS_RUST` unset: `_update_skip "cargo-tools" "HAS_RUST not set"`.
  - Otherwise run it and map the rc as the `git-hooks` block does: 2 → `record_end 0` plus `_update_warn`, and 1 → FAIL.
  - When the flags exclude it: SKIP.
- In `_UPDATE_SECTION_ORDER`, place `cargo-tools` directly after `rust`.

**Tests** (a new file):

- `--brew-only` records a **non-SKIP** status for `cargo-tools`. This is what proves the placement.
- `--pip-only` gives SKIP.
- `HAS_RUST` unset gives SKIP with its reason.
- rc 2 gives WARN, and rc 1 gives FAIL.
- `run_setup_or_developer` calls it (spy), and a failure there does not abort.

The summary's name column is `%-20s`, and `cargo-tools` fits. An existing test enforces the gutter.

---

### Task 8: crates.io staleness in `check-versions`

```yaml-task
id: 8
description: Add _check_one_cargo_version via crates.io with a User-Agent and count its results in run_check_versions totals
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/check_versions_cargo.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/check_versions_cargo.bats, tests/setup_env/workflows.bats, tests/setup_env/unit.bats]
depends_on: [7]
```

**`_check_one_cargo_version <crate> <pinned>`**:

- Runs `curl -sf -A "dotfiles check-versions (bjackson@pobox.com)" "${_CRATES_API:-https://crates.io/api/v1/crates}/<crate>"`.
- Parses `"max_stable_version":"<v>"`.
- Prints, in `_check_one_version`'s format:
  - `[WARN] <crate> could not fetch latest version` on an empty result;
  - `[OK]` when equal, or when pinned is newer (use `_semver_cmp`);
  - `[OUTDATED] ... latest=<v>` otherwise.

In `run_check_versions`, loop over `CARGO_TOOLS` and pass each line through the same counters `_run_cv_check` uses. It is report-only: no `_prompt_version_update`.

**Tests:**

- Use a fixture JSON via `MOCK_CURL_STDOUT` and cover OK, OUTDATED with `latest=`, and WARN on a fetch failure.
- **Assert that the curl line in `MOCK_CALLS_FILE` matches `-A [^ ]`.** The mock logs `$*`, which flattens quoting.
- Existing `run_check_versions` tests whose totals change must be updated. Enumerate them with `grep -n 'run_check_versions' tests/setup_env/*.bats`.

---

### Task 9: Release-binary helper, tflint, tfsec, zig

```yaml-task
id: 9
description: Add _install_pinned_release_binary (zip|raw, anchored whole-line version skip on _RELEASE_BIN_DIR binary, sha256 -c, sudo only when unwritable), _install_ubuntu_tflint/_tfsec, and zig in the linuxbrew loop
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/release_binary.bats
    exit_code: 0
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/release_binary.bats, tests/setup_env/linux_ubuntu.bats, tests/setup_env/workflows.bats]
depends_on: [1]
```

**`_install_pinned_release_binary <name> <version> <url> <sha256> <kind> <line-regex>`**, per spec Part 4b:

- `dir="${_RELEASE_BIN_DIR:-/usr/local/bin}"`.
- Skip when `"${dir}/<name>"` is executable **and** some whole output line matches `^<regex>$`. Never run the `PATH` copy.
- Otherwise, in a `( … )` subshell with an `EXIT` trap removing its `mktemp -d`:
  - `curl -fsSL -o`;
  - `printf '%s  %s\n' sha file | sha256sum -c -`;
  - for `zip`, `unzip -o` and take `<name>`; for `raw`, the file itself;
  - `install -m 0755`, prefixed with `sudo` only when `[[ ! -w ${dir} ]]`.
- Return 1 on any failure.

**Wrappers.** `_install_ubuntu_tflint` and `_install_ubuntu_tfsec` each select the arch sha by `_LINUX_ARCH`, honour the `_TFLINT_*`/`_TFSEC_*` overrides, and are gated on `HAS_DEVTOOLS`. Call them beside the OpenTofu block, with `|| log_warn`.

- tflint regex: `TFLint version 0\.61\.0`.
- tfsec regex: `v1\.28\.14`.

**zig.** Add `zig` to the `_install_ubuntu_brew_packages` formula loop.

**Tests** (a new file). Use real `sha256sum` and write fixture files, with `_RELEASE_BIN_DIR` set to a tmpdir:

- a sha mismatch leaves the dir empty;
- `raw` and `zip` each install;
- skip when the dir binary prints the pinned line;
- **no skip when only an "out of date … latest is 0.61.0" line matches**;
- **no skip when a `PATH` stub prints the pinned line but the dir is empty**;
- the `HAS_DEVTOOLS` gate.

Existing `install_ubuntu_packages`/`_install_ubuntu_misc` tests in `linux_ubuntu.bats`/`workflows.bats` must stub the new functions. Find them with `grep -n '_install_ubuntu_misc\|install_ubuntu_packages' tests/setup_env/*.bats`.

---

### Task 10: `_install_ubuntu_tfenv`

```yaml-task
id: 10
description: Add _install_ubuntu_tfenv (clone if absent, symlink tfenv/terraform only when absent, never overwrite non-tfenv paths, install+use TERRAFORM_VER only without a version file, warn-and-continue)
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/tfenv.bats
    exit_code: 0
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/tfenv.bats, tests/setup_env/linux_ubuntu.bats]
depends_on: [9]
```

**Behaviour**, per spec Part 4c:

- Gate on `HAS_DEVTOOLS`.
- `root="${_TFENV_ROOT:-${HOME}/.tfenv}"` and `links="${_TFENV_LINK_DIR:-/usr/local/bin}"`.
- If `root` is absent: `git clone "${_TFENV_REPO_URL:-…}" "${root}"`.
- For each of `tfenv` and `terraform`:
  - absent: `sudo ln -s "${root}/bin/<n>" "${links}/<n>"`;
  - a symlink whose `readlink` equals `${root}/bin/<n>`: leave it;
  - anything else: `log_warn` naming the path and leave it.
- If `${root}/version` is absent: `"${root}/bin/tfenv" install "${TERRAFORM_VER}"`, then `use`.
- Any failure: `log_warn`, return 0.
- Call it beside the tflint call, with `|| log_warn`.

**Tests** use a fixture root (a pre-created clone dir with a `bin/tfenv` stub logging its args) and a fixture link dir:

- a missing root gets cloned (git mock);
- absent paths get symlinks;
- a correct symlink is left;
- a regular file is left with a WARN;
- a symlink elsewhere is left with a WARN;
- an existing version file means no `install`/`use` calls;
- a missing version file means `install 1.15.6` then `use 1.15.6`;
- a failure returns 0.

**Assert that no path outside `BATS_TEST_TMPDIR` appears in the ln calls.**

---

### Task 11: `pwsh` guard rewrite

```yaml-task
id: 11
description: Rewrite _install_ubuntu_powershell to skip only when pwsh runs, always refresh the MS config deb otherwise, check each step's rc and warn-and-continue
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats, tests/setup_env/workflows.bats]
depends_on: [10]
```

**Behaviour**, per spec Part 5:

1. `"${_PWSH_BIN:-pwsh}" -NoProfile -Command exit` returning rc 0 → print `pwsh is installed`, return 0.
2. Otherwise, independent of any existing `.deb`: `wget -O` the config for the resolved release (`24.04` under `RESOLUTE`, as today), then `dpkg -i`, `apt update` and `apt install powershell -y`.
3. Check each step. On failure, `log_warn "pwsh install failed at <step>"` and return 0.

**Tests.** Update the existing pwsh tests: enumerate them first with `grep -n powershell tests/setup_env/*.bats`. Then cover:

- a runnable `pwsh` stub means no wget;
- **a pre-existing `.deb` plus an absent `pwsh` still downloads and installs**, the stale-box case;
- a RESOLUTE URL of `24.04`;
- each failing step gives a WARN naming it and rc 0.

---

### Task 12: doctor Linux dev-tools arm

```yaml-task
id: 12
description: Add _doctor_check_dev_tools (LINUX and HAS_DEVTOOLS only; pwsh/tflint/zig/terraform/tfsec must resolve and run under timeout from HOME; WARN never FAIL) wired after _doctor_check_tools
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/doctor_dev_tools.bats
    exit_code: 0
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/doctor_dev_tools.bats, tests/setup_env/unit.bats]
depends_on: [3]
```

**Behaviour**, per spec Part 6:

- Gate on `LINUX` and `HAS_DEVTOOLS`; otherwise print nothing.
- For each tool, run its probe inside `( cd "${HOME}" && timeout "${_DOCTOR_PROBE_TIMEOUT:-10}" <probe> )`. The probes are:
  - `pwsh -NoProfile -Command exit`
  - `tflint --version`
  - `zig version`
  - `terraform version`
  - `tfsec --version`
- rc 0 → `doctor_pass`.
- Unresolvable → `doctor_warn "<t>" "not found — setup_env.sh -t developer"`.
- Non-zero or timeout → `doctor_warn "<t>" "does not run (rc N) — setup_env.sh -t developer"`.
- Add a stub for the new arm in `unit.bats`'s end-to-end `run_doctor` tests.

**Tests** use PATH stubs in a tmpdir:

- PASS;
- WARN when absent;
- **WARN when it resolves but exits 1**;
- WARN on timeout (a stub sleeping 3 s with `_DOCTOR_PROBE_TIMEOUT=1`);
- silence without `LINUX`, and without `HAS_DEVTOOLS`.

---

### Task 13: ADR, CLAUDE.md, index

```yaml-task
id: 13
description: Write ADR-0032 (pyenv rehash hook amends ADR-0031), update CLAUDE.md layout/entry points/test seams, and mark spec/plan index In Progress (docs-only; tdd not-applicable)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0032-pyenv-rehash-hook.md
    exit_code: 0
  - cmd: 'grep -q "0032" docs/adr/README.md'
    exit_code: 0
  - cmd: 'grep -q "pyenv.d/" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "_CARGO_BIN" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [docs/adr/0032-pyenv-rehash-hook.md, docs/adr/README.md, docs/adr/0031-gnu-coreutils-precedence-on-resolute.md, CLAUDE.md, docs/superpowers/README.md]
depends_on: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
```

**ADR-0032** (Nygard format; copy the header shape from ADR-0031).

- **Context:** ADR-0031's `PATH` fix covers interactive shells only, and D1 was measured across login, ssh and `setup_env` actors.
- **Decision:** a copied rehash hook that registers without `sort`.
- **Consequences:**
  - pyenv hook-contract churn (8 `pyenv-rehash` commits since 2025-12);
  - the doctor and `-t update` detectors;
  - a copy, not a link (silent dangle measured);
  - untracked file inside `workstation`'s pyenv clone.

**ADR-0031.** Add a one-line "Amended by ADR-0032" status note; the status stays Accepted. Add an index row.

**`CLAUDE.md`:**

- the Layout tree gains `pyenv.d/`;
- the `update` entry point gains the new sections `pyenv-shims` and `cargo-tools`;
- Test Seams gains one paragraph per seam from Global Constraints, with the E2 reason each exists (sudo mock execs real commands; real `~/.cargo`, `~/.tfenv`, `/usr/local/bin`);
- Key Conventions gains the tfenv-on-Linux line and the cargo pins/`check-versions` line.

Keep each addition tight: a measured claim or a pointer to the spec, no restated figures.

**`docs/superpowers/README.md`:** set the spec row to link this plan, with status In Progress.

**After Task 13, the orchestrator runs `make test` (backgrounded, polled) and `make bash-coverage`, and fixes regressions before Phase 3.**
