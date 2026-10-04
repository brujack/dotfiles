# Ubuntu Step Mid-Step Failures Implementation Plan

spec: docs/superpowers/specs/2026-10-04-ubuntu-step-midstep-failures-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every `_install_ubuntu_*` step reports each failed sub-install, never consumes a failed download, never truncates a live keyring, and never ends on a skipped `if`.

**Architecture:** Two new helpers in `lib/linux_ubuntu.sh`, `_install_fetched_binary` (throwaway dir, `sudo install`, URL stamp) and `_install_apt_keyring` (fetch to file, stage, rename), plus a rewritten Go install. Each step then becomes a list of sub-installs with a step-local `_failed` array and an explicit final status. The dispatcher gains base rc 2 and the docker-rc-3-only nvidia skip.

**Tech Stack:** bash, bats, PATH mocks in `tests/mocks/`.

## Global Constraints

- No `set -e`, `set -o pipefail`, or ERR/EXIT/RETURN trap (N2; `scripts/check-lib-exit-traps.sh` enforces EXIT in `lib/`).
- No change to `_install_ubuntu_rust`, `_install_ubuntu_brew_packages`, `_install_ubuntu_albert`; nvidia only its keyring and source-list fetch (N1).
- No change to `run_setup_or_developer`'s handling of `install_ubuntu_packages`' return codes (N3).
- Cleanup commands and "is installed" probes never become failures (N4).
- No sha256 pins for the ten helper tools; nothing under `~/software_downloads` is deleted (N5).
- Failure message shape: `log_warn "<step>: <tool>: <action> failed"`.
- Tests never touch real `/usr/local`, `/etc/apt`, `/usr/share/keyrings`, `~/.local/share`: every new seam is set at `setup()` scope to `BATS_TEST_TMPDIR` (`tdd.md` E2).
- Every absence assertion has a positive control in the same test (`tdd.md` E5).
- Every new check gets a mutation control: delete it, see the named test go red, restore. Report each as `mutation: <check> -> <red test name>` (V1).

## Verification Planning

- **Whole change:** `make test` exits 0 on this box and CI is green (V2).
- **Observable change:** with a failure knob set, `install_ubuntu_packages` returns 2 and prints `ubuntu packages: failed: <steps>`, each failed sub-install named; with none set, it returns 0 and every step's core install call is in `MOCK_CALLS_FILE` (R10).
- **Edge cases:** docker core failure skips nvidia, plugin failure does not; base rc 1 vs 2; apt update failing alone; Go move failing with and without an old tree; leftover `go.old`; telepresence resolution failing with and without a stamp; stamp dir unwritable.
- **Pre-merge measurements (orchestrator, on `claude`):** V3 (apt update / apt install against an unreachable scoped source) and V4 (each exact `snap install` / `snap set` against installed snaps). V5 runs after merge.

---

### Task 1: Scoped failure knobs in mocks

```yaml-task
id: 1
description: Add URL-, subcommand- and argument-scoped failure knobs to the wget, curl, apt, apt-get, nala and mv mocks
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/mocks_fail_knobs.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/mocks/wget, tests/mocks/curl, tests/mocks/apt, tests/mocks/apt-get, tests/mocks/nala, tests/mocks/mv, tests/setup_env/mocks_fail_knobs.bats]
depends_on: []
```

**Files:** the six mocks; new `tests/setup_env/mocks_fail_knobs.bats` (setup copies `tests/setup_env/mocks_sudo.bats`' `load_mocks` + `MOCK_CALLS_FILE` pattern).

- `MOCK_WGET_FAIL_URL` / `MOCK_CURL_FAIL_URL`: when set and any argv element contains it, write a 0-byte `-O`/`-o` target (same as today's whole-binary failure) and exit 4 (wget) / 22 (curl). Other calls behave as today. Existing knobs keep precedence.
- `MOCK_APT_FAIL_SUBCMD` (apt, apt-get, nala): exit 100 when the first argument not starting with `-` equals the value; otherwise today's behaviour. Recording unchanged.
- `MOCK_MV_FAIL_ARGS`: exit 1 without moving when the joined argv contains the value; otherwise today's pass-through.
- Tests per knob: matching call fails **and** a non-matching call in the same test succeeds (positive control); wget/curl failure leaves a 0-byte target.

**Interfaces:** Produces the four knob names used by Tasks 2–10.

### Task 2: `_install_apt_keyring` helper

```yaml-task
id: 2
description: Add _install_apt_keyring (fetch to file, dearmor or copy to <keyring>.new, rename) with tests
role: executor
model: sonnet
tdd: required
requirements: [R5]
acceptance:
  - cmd: bats tests/setup_env/apt_keyring.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/apt_keyring.bats]
depends_on: [1]
```

**Behaviour (spec "Keyrings"):** `_install_apt_keyring <url> <keyring> <armored|binary>`. Throwaway dir via `mktemp -d "${_APT_KEY_TMP_ROOT:-${TMPDIR:-/tmp}}/apt-key.XXXXXXXX"`. `curl -fsSL -o <tmp>/key <url>`; `armored`: `sudo gpg --batch --yes --dearmor -o <keyring>.new < <tmp>/key`; `binary`: `sudo install -m 0644 <tmp>/key <keyring>.new`. Require rc 0 **and** `[[ -s <keyring>.new ]]`, then `sudo mv -f <keyring>.new <keyring>`. Any failure: `sudo rm -f <keyring>.new`, `rm -rf <tmp>`, return 1. Explicit `rm -rf` before every return.

**Tests** (keyring fixture seeded with `old`; mocks/gpg exits 0 on empty input, so the `-s` check is what catches an empty dearmor): fetch fails via `MOCK_CURL_FAIL_URL` → keyring holds `old`, no `.new`, no tmp dir, curl call recorded; staged file empty → same; `MOCK_MV_FAIL_ARGS=.new` → keyring `old`, no `.new`; success → keyring replaced, rc 0.

**Interfaces:** Produces `_install_apt_keyring <url> <keyring> <armored|binary>` → 0/1.

### Task 3: `_install_fetched_binary` helper

```yaml-task
id: 3
description: Add _install_fetched_binary (throwaway dir, sudo install, URL stamp, skip line, telepresence URL resolution) with tests
role: executor
model: sonnet
tdd: required
requirements: [R2, R4, R13]
acceptance:
  - cmd: bats tests/setup_env/fetched_binary.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/fetched_binary.bats]
depends_on: [2]
```

**Behaviour:** spec "Downloaded binaries" steps 1–5, verbatim. Signature `_install_fetched_binary <name> <url> <bin|zip|tar> <member> [<dest-name>] [--resolve]`; `--resolve` enables the telepresence URL resolution (`curl -fsSIL -o /dev/null -w '%{url_effective}'`; result equal to input counts as failed). Seams: `_DL_STAMP_DIR` (default `${HOME}/.local/share/dotfiles/installed`), `_DL_TMP_ROOT` (default `${HOME}/software_downloads`), `_DL_BIN_DIR` (default `/usr/local/bin`). Fetch is `wget -O` only. Install `sudo install -m 0755` (no `-o`/`-g`). Stamp-write failure: `log_warn` naming the stamp path, rc 0. Skip prints `<name>: up to date (stamp <path>); rm it to force a re-install`. Failure messages carry `<name>: <stage> failed`; the calling step prefixes its own name.

**Tests:** spec Testing "Helper tests" and "telepresence" bullets, all with destination seeded with known bytes and `mktemp`/fetch positive controls. Unwritable stamp dir via `chmod 0500` on a fixture dir.

**Interfaces:** Produces `_install_fetched_binary …` → 0 installed/skipped/warned, 1 failed.

### Task 4: Go install rewrite

```yaml-task
id: 4
description: Rewrite Go install as throwaway dir + root chown + mv -T swap + stamp, compare version by series
role: executor
model: sonnet
tdd: required
requirements: [R1, R11, R12]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats tests/setup_env/install_functions.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats, tests/setup_env/install_functions.bats]
depends_on: [3]
```

**Behaviour:** spec "Go" steps 1–6. New seam `_GO_INSTALL_ROOT` (default `/usr/local`), set at `setup()` scope in both test files. Owner hardcoded `root:root` (mocks/chown records only). `_install_ubuntu_go`'s `apt update` becomes `|| :` (R6). Version check: `[[ ${v} == "${GO_VER}" || ${v} == "${GO_VER}".* ]]`; mismatch → `log_warn "go: version check failed"`, rc 1.

**Existing tests that change:** `linux_ubuntu.bats` "skips wget when tarball already exists" becomes "skips when stamp matches and go executable" (prints skip line). Every go test sets `_GO_BIN`.

**New tests:** spec Testing "Go tests" bullets: restore after third `mv` fails; no-go/no-old with positive control; `go.old` move-back order and move-back failure; leftover `go.old` not nested; `chown -R root:root <tmp>/go` recorded before the first swap `mv`; series match `1.27.1` → 0, `1.26.3` → 1.

### Task 5: Base tri-state and dispatcher

```yaml-task
id: 5
description: Base returns 2 on failed installs with one apt update warning; dispatcher records base and continues
role: executor
model: sonnet
tdd: required
requirements: [R6, R8]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [4]
```

**Behaviour:** `_install_ubuntu_base_packages`: unsupported release → 1 (unchanged). `apt update` failure → `log_warn "base: apt update reported errors (see apt's E:/W: lines above); continuing"` exactly once. Each of hwe kernel, `check_and_install_nala`, common list, release list checked into `_failed`; any → `log_warn` per item and return 2. Delete the stale comment at the old `return 0`. Dispatcher: `_install_ubuntu_base_packages` rc 1 → return 1; rc 2 → `_failed+=(base)` and continue.

**Tests:** `MOCK_NALA_EXIT=1` → base rc 2, dispatcher rc 2 naming `base`, a later step's call recorded (positive control). `MOCK_APT_FAIL_SUBCMD=update` → base rc 0, one warning line (`grep -c` = 1). Unsupported release → rc 1, no later step call.

### Task 6: Docker and nvidia

```yaml-task
id: 6
description: Docker returns 3 on core failure and 1 otherwise, uses the keyring helper; nvidia skip only on 3; nvidia keyring and list fetched safely
role: executor
model: sonnet
tdd: required
requirements: [R1, R3, R4, R5, R9]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [5]
```

**Behaviour:** docker sub-installs per spec inventory. Keyring: `_install_apt_keyring https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.asc binary`. Core (`docker-ce`, `docker-ce-cli`, `containerd.io`, `daemon.json` validation) failure → rc 3; any other → rc 1. `apt update` `|| :` with a comment pointing at base. Dispatcher: track docker's rc; skip nvidia only when it was 3 (message unchanged). nvidia: keyring via `_install_apt_keyring "${NVIDIA_CONTAINER_GPGKEY_URL}" "${_keyring}" armored`; list fetched with `curl -fsSL -o <tmp>` then `sed` to a second tmp file then `sudo -H tee`, each checked, tmp removed. nvidia's `apt update || return 1` stays.

**Tests:** spec "Dispatcher, both branches"; docker keyring failure with docker present → rc 1; nvidia list fetch failing → rc 1 and list fixture unchanged (positive control: curl call recorded).

### Task 7: k8s_tools and hashicorp

```yaml-task
id: 7
description: kind, telepresence and the five HashiCorp tools through _install_fetched_binary; kubectl keyring helper; explicit step status
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [6]
```

**Behaviour:** kind `bin` (dest `kind`); telepresence `bin --resolve`; consul/vault/nomad/packer `zip` member `<tool>`; vagrant `zip` member `vagrant`, amd64 URL unchanged. kubectl: `_install_apt_keyring` armored, source `printf | sudo tee` checked, `apt update || :`, install checked. helm snap checked. Each step: `_failed` array, `log_warn "<step>: <tool>: <action> failed"`, final `(( ${#_failed[@]} == 0 ))`. Stale helm cleanup stays advisory.

**Existing tests that change:** "skips kind wget when already downloaded" and "skips consul wget when dir already exists" become stamp-skip tests. Set `_DL_*` seams at `setup()` scope.

**Tests:** per sub-install, the five assertions in spec Testing, using `MOCK_WGET_FAIL_URL` (kind URL fails, telepresence still fetched; consul fails, vault still installed).

### Task 8: cloud_tools, gui_tools, workstation

```yaml-task
id: 8
description: Per-sub-install status in cloud_tools, gui_tools and workstation; keyrings via helper; cf-terraforming via _install_fetched_binary
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [7]
```

**Behaviour:** teleport, cloudflared, gcloud: `_install_apt_keyring` armored, source write checked, `apt update || :`, install checked. cf-terraforming: `_install_fetched_binary cf-terraforming "${CF_TERRAFORMING_URL}" tar cf-terraforming`. Azure legacy cleanup unchanged. gui_tools: virtualbox keyring helper (armored); edge = `_install_ubuntu_edge_source` status + install; each `snap install`/`snap set` checked; steam checked; albert unchanged; replace the `_tail_rc` capture with the `_failed` array (albert's rc still returned when non-zero, preserving its own tests). workstation: nala list and snap list each checked.

**Tests:** five-assertion tests for teleport keyring fetch failure (cloudflared still runs), cf-terraforming install failure (`MOCK_WGET_FAIL_URL`), a snap failure in gui_tools (steam still runs), workstation snap failure.

### Task 9: misc and powershell

```yaml-task
id: 9
description: "misc sub-installs via helpers with explicit status; powershell returns 1 on failure; remaining apt updates ignore their status"
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [8]
```

**Behaviour:** docker-compose and yq `bin` via `_install_fetched_binary`; opentofu keyring helper (armored), list checked, `apt-get update -qq || :`, install checked. dotnet/tflint/tfsec/tfenv unchanged. `nala autoremove` failure → `log_warn` only. powershell: every `log_warn …; return 0` → `return 1`; delete the stale dispatcher comment; its `apt update` check stays. Then `grep -n 'apt update\|apt-get update' lib/linux_ubuntu.sh`: every hit outside base, powershell, nvidia and `_install_ubuntu_albert` (frozen by N1; it has one) is `|| :` with a comment pointing at base.

**Existing tests that change:** powershell tests asserting rc 0 on failure assert rc 1.

**Tests:** yq fetch failure (docker-compose still installed), opentofu install failure, autoremove failure → step rc 0 and a warning, powershell wget failure → rc 1.

### Task 10: Clean-run test, docs, backlog

```yaml-task
id: 10
description: Discriminating dispatcher clean-run test; CLAUDE.md seam entry; remove the backlog row; plan index row
role: executor
model: sonnet
tdd: required
requirements: [R10]
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
  - cmd: grep -q '_DL_STAMP_DIR' CLAUDE.md
    exit_code: 0
  - cmd: '! grep -qF "steps swallow mid-step failures" docs/superpowers/README.md'
    exit_code: 0
max_retries: 3
files_touched: [tests/setup_env/linux_ubuntu.bats, CLAUDE.md, docs/superpowers/README.md]
depends_on: [9]
```

**Test:** spec "Clean run, discriminating": all mocks succeed, `HAS_*` set, `_GO_BIN` printing `go version go1.27.1 linux/amd64`; assert rc 0, each step's core install call, every helper's `wget` call; second run asserts no helper `wget` call and every helper's skip line.

**Docs:** CLAUDE.md Test Seams: one entry for `_DL_STAMP_DIR`/`_DL_TMP_ROOT`/`_DL_BIN_DIR`/`_GO_INSTALL_ROOT` and the scoped mock knobs (default paths, set at setup scope, skip line, `rm` the stamp to force a re-install). Remove the backlog row. Add an All Plans row (status In Progress) linking this plan and the spec.

## Non-goal check

Run 2026-10-04 by one fresh reviewer subagent (`nongoal-check.md`) against the plan and the effective N list.

- **N1 — UNCLEAR.** Quote: Task 9: "`grep -n 'apt update\|apt-get update' lib/linux_ubuntu.sh`: every hit outside base, powershell and nvidia is `|| :`". Measured: `_install_ubuntu_albert` contains one `apt update` (rust and brew_packages none), so the sweep would have edited a frozen function. Resolution, plan revised. Before: "every hit outside base, powershell and nvidia is `|| :`". After: "every hit outside base, powershell, nvidia and `_install_ubuntu_albert` (frozen by N1; it has one) is `|| :`".
- **N2 — CLEAR.**
- **N3 — CLEAR.**
- **N4 — CLEAR.**
- **N5 — UNCLEAR.** Quote: Task 3: "Seams: ... `_DL_TMP_ROOT` (default `${HOME}/software_downloads`)", with the throwaway dir created and removed there. Resolution, spec amendment: N5 now protects files that existed before the run, which is what it meant; the helper's own throwaway directory is not such a file.

