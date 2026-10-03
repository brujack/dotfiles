# Scoped apt keys for albert; azure-cli to linuxbrew — Implementation Plan

> **Status: DONE** — merged in dotfiles#309 (2e9fc839), 2026-10-03.

spec: docs/superpowers/specs/2026-10-03-scoped-apt-keys-azure-albert-design.md

**Spec:** [2026-10-03-scoped-apt-keys-azure-albert-design.md](../specs/2026-10-03-scoped-apt-keys-azure-albert-design.md)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove machine-wide apt trust for the Microsoft and albert OBS keys: albert gets a pinned, `signed-by` keyring over https; azure-cli moves to linuxbrew.

**Architecture:** One fail-closed builder (`_build_pinned_keyring`) builds and verifies a keyring in a temp dir and installs it only on success. Albert and edge use it. azure-cli's apt block is deleted; `_install_ubuntu_brew_packages` installs it and migrates off the apt package once brew's `az` runs. Legacy global keys and sources are deleted on every run.

**Tech Stack:** bash, bats, real gpg via `_MS_GPG_BIN`, PATH mocks in `tests/mocks/`.

## Global Constraints

- `ALBERT_GPG_FPR="A4B83CD05FDF5C5178482D4A1488EB46E192A257"`; `MS_GPG_FPR` unchanged.
- Builder returns: 0 installed; 1 keys read but not exactly one `pub:` matching the pin; 2 no `pub:` readable (gpg missing/non-zero, non-key body). Never touches the final keyring path on failure.
- No test reaches the network or writes under the real `/etc/apt` or `/usr/share/keyrings`; `tests/mocks/sudo` execs real commands, so every path goes through a seam set at setup scope.
- Every `sudo` dpkg/apt call carries `DEBIAN_FRONTEND=noninteractive` on the sudo command line (`tests/scripts/dpkg_sudo_frontend.bats`).
- Every absence/equality/unchanged assertion has a same-test presence assertion (`tdd.md` E5).
- No key-validity (revoked/expired) check.
- Never let a test run the real `az`: `tests/mocks/brew` prints nothing for `--prefix`, so an unseamed `"$(brew --prefix)/bin/az"` is `/bin/az`, which on `claude` is the real apt `az`. Task 3 adds `_BREW_AZ_BIN` and sets it at setup scope.

## Verification

- Session level: `make test` exits 0 (run by the orchestrator once, after Task 3).
- Post-merge (V1, V2): `./setup_env.sh -t developer` on `claude` and `workstation`; then `ls /etc/apt/trusted.gpg.d/` lists neither `microsoft.asc.gpg` nor `home_manuelschneid3r.gpg`; `sources.list.d` holds `albert.list` (https, signed-by) and no azure-cli file; `sudo apt update` exits 0 with no `NO_PUBKEY`; `dpkg -s azure-cli` not installed; `command -v az` under `/home/linuxbrew`; `az version` and `albert --version` run.
- Edge cases: non-key body keeps the last source; two concatenated keys rejected; first run with a fetch failure leaves no albert source (expected, per spec §5).

Baselines: `bats tests/setup_env/linux_ubuntu.bats` = 155 ok, 0 not ok at `72fae2a9`.

---

### Task 1: Fail-closed keyring builder; edge onto it

```yaml-task
id: 1
description: Add _build_pinned_keyring (temp build, verify, install on success, rc 0/1/2), rename the fpr check, move edge onto it, add the albert fixture
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R12, R13]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -c "_edge_keyring_has_pinned_fpr" lib/linux_ubuntu.sh tests/setup_env/linux_ubuntu.bats | grep -v ":0$"'
    exit_code: 1
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
  - tests/fixtures/albert-obs.asc
depends_on: []
```

**Files:** `lib/linux_ubuntu.sh` (around `_edge_keyring_has_pinned_fpr`, ~line 775, and `_install_ubuntu_edge_source`), `tests/setup_env/linux_ubuntu.bats`, new `tests/fixtures/albert-obs.asc`.

Steps:

- [ ] Create the fixture: `curl -fsSL https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_26.04/Release.key -o tests/fixtures/albert-obs.asc`; confirm `gpg --show-keys --with-colons` shows one `pub:` and `fpr:::::::::A4B83CD05FDF5C5178482D4A1488EB46E192A257:`.
- [ ] Add `export _APT_KEY_TMP_ROOT="${BATS_TEST_TMPDIR}/apt-key-tmp"` (and `mkdir -p`) to `setup()`.
- [ ] RED, one at a time, builder tests (call `_build_pinned_keyring <key> <ring> <fpr>` directly; final ring under `BATS_TEST_TMPDIR`):
  - pinned key (`keys/microsoft.asc`, `MS_GPG_FPR`) → rc 0, ring lists exactly that fpr, `stat` mode 644, `_APT_KEY_TMP_ROOT` empty after.
  - wrong key (albert fixture vs `MS_GPG_FPR`) → rc 1; ring pre-seeded with `printf old`, asserted present before, byte-identical (`cmp`) after.
  - two keys (`cat keys/microsoft.asc tests/fixtures/albert-obs.asc`) vs `MS_GPG_FPR` → rc 1, ring unchanged.
  - truncated (`head -c 200 keys/microsoft.asc`) → rc 2, ring unchanged.
  - non-key body (`printf '<html>x</html>'`) → rc 2, ring unchanged.
  - gpg non-zero (`_MS_GPG_BIN` pointed at a stub `exit 2`) → rc 2, ring unchanged.
- [ ] GREEN: implement. `mktemp -d "${_APT_KEY_TMP_ROOT:-${TMPDIR:-/tmp}}/apt-key.XXXXXXXX"`; `"${_MS_GPG_BIN:-gpg}" --dearmor < key > "${dir}/k.gpg"`; capture rc; count `^pub:` via `--homedir <tmp> --batch --show-keys --with-colons`; 0 pubs or gpg rc≠0 → 2; not exactly one pub or fpr ≠ pin → 1; success → `sudo install -m 0644 "${dir}/k.gpg" "${ring}"`. `rm -rf` the dir on every path without an EXIT trap (`scripts/check-lib-exit-traps.sh`).
- [ ] Rename `_edge_keyring_has_pinned_fpr` → `_keyring_has_pinned_fpr <ring> <fpr>`; make `_install_ubuntu_edge_source` call the builder with its key, keyring and `MS_GPG_FPR`, keeping its own `rm -f` of list+keyring on failure. Do not edit any existing edge test (R2).
- [ ] Update the comment at ~line 789 ("unseamed albert writes") to describe what is still unseamed.
- [ ] Run gates; commit (`caveman:caveman-commit`).

**Interfaces:** Produces `_build_pinned_keyring <key_file> <keyring> <fpr>` → 0/1/2; `_keyring_has_pinned_fpr <ring> <fpr>`; seam `_APT_KEY_TMP_ROOT`.

### Task 2: Albert: pinned keyring over https, keep-last-good, legacy cleanup

```yaml-task
id: 2
description: Extract _install_ubuntu_albert with ALBERT_GPG_FPR, https source, fetch/key failure paths, legacy cleanup, and gui_tools rc propagation
role: executor
model: sonnet
tdd: required
requirements: [R5, R6, R7, R8, R9, R10, R11, R12, R13]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -nE "trusted.gpg.d/home_manuelschneid3r|deb http://download.opensuse" lib/linux_ubuntu.sh | grep -v "rm -f"'
    exit_code: 1
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - lib/constants.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: [1]
```

**Files:** `lib/linux_ubuntu.sh` (`_install_ubuntu_gui_tools`, the `HAS_SNAP` albert block ~line 838), `lib/constants.sh` (next to `MS_GPG_FPR`, line 158), tests.

Steps:

- [ ] `setup()`: export `_APT_SOURCES_DIR`, `_APT_TRUSTED_DIR`, `_APT_KEYRINGS_DIR` under `BATS_TEST_TMPDIR` and `mkdir -p` them. Never set `MOCK_CURL_STDOUT` at setup scope.
- [ ] RED/GREEN one at a time (feed `MOCK_CURL_STDOUT="$(cat tests/fixtures/albert-obs.asc)"` per test):
  - good key → `albert.list` contains `https://download.opensuse.org/` and `signed-by=${_APT_KEYRINGS_DIR}/albert-obs.gpg`; `apt install albert` in mock log; rc 0.
  - curl fails (`MOCK_CURL_EXIT=22`) → pre-seeded `albert.list` + keyring asserted present, then `cmp`-identical; WARN contains the URL; no `apt install albert`; rc 2.
  - non-key body (`MOCK_CURL_STDOUT='<html>'`) → same as curl fails.
  - wrong fingerprint (`MOCK_CURL_STDOUT="$(cat keys/microsoft.asc)"`) → pre-seeded list + keyring present, then both absent; WARN contains `BC528686B50D79E339D3721CEB3E94ADBE1229CF` and `A4B83CD05FDF5C5178482D4A1488EB46E192A257`; no install; rc 2.
  - temp dir → mock log's curl line has `-o ${_APT_KEY_TMP_ROOT}/albert-key.`; `_APT_KEY_TMP_ROOT` empty after, on success and on curl fail.
  - legacy cleanup → seed `${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg` and `${_APT_SOURCES_DIR}/home:manuelschneid3r.list`, assert present, run, assert gone; also on the wrong-fingerprint path.
  - second run → `albert.list` present, `cmp` identical after a second call.
  - gui_tools propagation → albert rc 2 (curl fails) makes `_install_ubuntu_gui_tools` return non-zero; `install_ubuntu_packages` stderr names `gui_tools`.
  - gui_tools success path → albert good key, `MOCK_SNAP_EXIT=1`, `HAS_FLATPAK` unset: `_install_ubuntu_gui_tools` still returns non-zero.
- [ ] Implement: `ALBERT_GPG_FPR` in `constants.sh`; `_install_ubuntu_albert` per spec §3 (legacy `rm -f` first; `curl -fsSL -o <tmpdir>/albert-key.asc "${_ALBERT_KEY_URL:-...}"`; builder; branch on 0/1/2; WARN text per R7/R8; print fetched fpr(s) via `--show-keys`); `gui_tools` calls it under `HAS_SNAP`, captures rc, runs the rest, and returns non-zero at the end only if it failed, preserving the last command's status otherwise.
- [ ] Fix `:1568` ("HAS_SNAP installs albert"): set `MOCK_CURL_STDOUT` to the fixture.
- [ ] Gates; commit.

**Interfaces:** Consumes `_build_pinned_keyring`. Produces `_install_ubuntu_albert` → 0/2; seams `_APT_SOURCES_DIR`, `_APT_TRUSTED_DIR`, `_APT_KEYRINGS_DIR`, `_ALBERT_KEY_URL`.

### Task 3: azure-cli to linuxbrew; apt migration; azure legacy cleanup

```yaml-task
id: 3
description: Delete the azure apt block, clean its legacy key and sources, install azure-cli via brew, and remove the apt package once brew az runs
role: executor
model: sonnet
tdd: required
requirements: [R3, R4, R11, R12, R13]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats tests/scripts/dpkg_sudo_frontend.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -nE "packages.microsoft.com/repos/azure-cli|add-apt-repository|apt install azure-cli" lib/linux_ubuntu.sh'
    exit_code: 1
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
  - tests/mocks/dpkg
depends_on: [2]
```

**Files:** `lib/linux_ubuntu.sh` (`_install_ubuntu_cloud_tools` azure block ~lines 636-656; `_install_ubuntu_brew_packages` ~line 696), tests, `tests/mocks/dpkg`.

Steps:

- [ ] `tests/mocks/dpkg`: when `$1 == -s` and `MOCK_DPKG_S_STATUS` is set, print `Status: ${MOCK_DPKG_S_STATUS}`.
- [ ] `setup()`: `export _BREW_AZ_BIN="${BATS_TEST_TMPDIR}/brew-az"` with a stub that logs `brew-az $*` to `MOCK_CALLS_FILE` and exits `${MOCK_BREW_AZ_EXIT:-0}`.
- [ ] RED/GREEN one at a time:
  - brew install → `brew install azure-cli` (or the `brew_install_formula` call) in mock log.
  - migration → `MOCK_DPKG_S_STATUS='install ok installed'`: `brew-az version` and `apt-get remove -y azure-cli` with `DEBIAN_FRONTEND=noninteractive` on the sudo line both in the log.
  - brew az broken (`MOCK_BREW_AZ_EXIT=1`) → `brew-az version` in log; no `apt-get remove`.
  - not apt-installed (`MOCK_DPKG_S_STATUS='deinstall ok config-files'`, and unset) → `brew-az version` in log; no `apt-get remove`.
  - remove fails (apt-get mock non-zero via its existing exit var) → stderr names `azure-cli-apt-remove`; rc 2.
  - no azure apt path → `_install_ubuntu_cloud_tools`: gcloud install in log; no `add-apt-repository`, no `apt install azure-cli`.
  - azure legacy cleanup → seed `${_APT_TRUSTED_DIR}/microsoft.asc.gpg`, `${_APT_SOURCES_DIR}/archive_uri-http_packages_microsoft_com_repos_azure-cli_-resolute.list`, `packages.microsoft.com_repos_azure-cli.list`, `azure-cli.list`; assert present; run `_install_ubuntu_cloud_tools`; all gone.
- [ ] The acceptance grep matches `add-apt-repository` anywhere in `lib/linux_ubuntu.sh`, comments included: describe the legacy filename without naming that tool. It currently matches only lines 644, 650, 651, 653.
- [ ] Delete tests `:1416`, `:1454`, `:1487`, `:1497` (azure apt assertions), replaced by the rows above.
- [ ] Implement per spec §1 and §5. Add `azure-cli` alphabetically-adjacent to the formula list; migration after the loop using `"${_BREW_AZ_BIN:-$(brew --prefix)/bin/az}" version >/dev/null 2>&1` and `dpkg -s azure-cli 2>/dev/null | grep -qx 'Status: install ok installed'`; failure → `_failed+=(azure-cli-apt-remove)`.
- [ ] Gates; commit.

**Interfaces:** Consumes seams from Task 2. Produces seam `_BREW_AZ_BIN`.

### Task 4: Document seams; close the backlog row

```yaml-task
id: 4
description: Docs-only — CLAUDE.md Test Seams entries for the new seams and builder, remove the backlog row; no behaviour change so tdd not applicable
role: executor
model: sonnet
tdd: not-applicable
requirements: []
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -q "_APT_KEY_TMP_ROOT" CLAUDE.md && grep -q "_BREW_AZ_BIN" CLAUDE.md && grep -q "_build_pinned_keyring" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "Unscoped Microsoft apt key" docs/superpowers/README.md'
    exit_code: 1
max_retries: 2
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [3]
```

Steps:

- [ ] In `CLAUDE.md` Test Seams, add one bullet group for `_APT_SOURCES_DIR`/`_APT_TRUSTED_DIR`/`_APT_KEYRINGS_DIR`/`_APT_KEY_TMP_ROOT`/`_ALBERT_KEY_URL`/`_BREW_AZ_BIN`: why each exists (mock sudo execs real commands; BSD mktemp; brew mock's empty `--prefix` resolves to the real `/bin/az`), and the builder's 0/1/2 contract and build-then-install rule.
- [ ] Remove the "Unscoped Microsoft apt key and http azure-cli source" Backlog row.
- [ ] Gates; commit. The orchestrator then runs `make test` once (this task cannot move the suite).

Orchestrator after Task 4: `make test` (redirect to a file, capture `$?`), then `finishing-a-development-branch`.

## Non-goal check

Reviewer run 2026-10-03 against `nongoal-check.md`. Counts: 3 CLEAR, 0 CONFLICT, 1 UNCLEAR.

- N1 CLEAR, N2 CLEAR, N4 CLEAR.
- N3 UNCLEAR. Quote: Task 3 "no azure apt path → `_install_ubuntu_cloud_tools`: gcloud install in log …" and Task 2 "`install_ubuntu_packages` stderr names `gui_tools`". Why: those tests run whole steps whose sibling blocks (gcloud) write under real `/etc/apt` without a seam.
  Resolution: spec amendment to N3 (see the spec's `## Amendments`). Checked: the gcloud block writes `/usr/share/keyrings/cloud.google.gpg` and `/etc/apt/sources.list.d/google-cloud-sdk.list` unseamed, nine existing tests already run `_install_ubuntu_cloud_tools`, and N1 forbids changing the gcloud block. Seaming it belongs to the existing Backlog row "`_install_ubuntu_*` tests reach real `/etc/apt/sources.list.d` paths". The plan's new code paths are all seamed, so the amended N3 holds. Plan text unchanged.

