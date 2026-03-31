# Phase 3: Profile Abstraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `config/profiles.sh` mapping hostnames to profiles and profiles to capabilities, update `lib/detect_env.sh` to resolve profiles and set `HAS_*` capability vars, add `tests/setup_env/profiles.bats` for coverage. Legacy hostname vars preserved as aliases throughout migration.

**Architecture:** `config/profiles.sh` uses `declare -A` associative arrays (requires bash 5, guaranteed by Phase 0 prerequisite check). `lib/detect_env.sh` sources `config/profiles.sh` then resolves `PROFILE` and iterates capability strings to set `HAS_*` vars via `declare -g`. Legacy `LAPTOP`, `STUDIO`, etc. vars remain so existing tests and call sites are unaffected.

**Tech Stack:** Bash 5, BATS, `tests/mocks/hostname` (MOCK_HOSTNAME_OUTPUT), associative arrays

---

## Files

| File | Action |
|---|---|
| `config/profiles.sh` | Create — associative arrays: hostname→profile, profile→capability string |
| `lib/detect_env.sh` | Modify — source `config/profiles.sh`, resolve `PROFILE`, set `HAS_*` vars, keep legacy aliases |
| `tests/setup_env/profiles.bats` | Create — 11 BATS tests covering profile and capability resolution |
| `Makefile` | Modify — add `tests/setup_env/profiles.bats` to `test-unit` target |

**Key orientation:**
- `lib/detect_env.sh` is sourced early; `detect_env()` is the single call site for all environment detection.
- `tests/mocks/hostname` already handles `MOCK_HOSTNAME_OUTPUT` — no new mock needed.
- `tests/mocks/uname` already handles `MOCK_UNAME_S` — no new mock needed.
- `tests/helpers/common.bash` provides `load_mocks()` and `load_setup_env()`.
- Run tests with `make test` or `make test-unit` from repo root.

---

## Task 1: Write failing tests in `tests/setup_env/profiles.bats`

**Files:**
- Create: `tests/setup_env/profiles.bats`

- [ ] **Step 1: Create `tests/setup_env/profiles.bats` with all 11 tests**

```bash
#!/usr/bin/env bats
# tests/setup_env/profiles.bats — profile and capability resolution tests

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_UNAME_S="Darwin"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── profile resolution ────────────────────────────────────────────────────────

@test "detect_env sets PROFILE=personal_laptop for hostname laptop" {
  export MOCK_HOSTNAME_OUTPUT="laptop"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "personal_laptop" ]
}

@test "detect_env sets PROFILE=mac_workstation for hostname studio" {
  export MOCK_HOSTNAME_OUTPUT="studio"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

@test "detect_env sets PROFILE=mac_workstation for hostname reception" {
  export MOCK_HOSTNAME_OUTPUT="reception"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_workstation" ]
}

@test "detect_env sets PROFILE=mac_mini for hostname office" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "mac_mini" ]
}

@test "detect_env sets PROFILE=unknown for unrecognised hostname" {
  export MOCK_HOSTNAME_OUTPUT="unknownhost"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "unknown" ]
}

# ── capability vars ───────────────────────────────────────────────────────────

@test "HAS_DEVTOOLS is set for personal_laptop" {
  export MOCK_HOSTNAME_OUTPUT="laptop"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_DEVTOOLS is set for mac_workstation" {
  export MOCK_HOSTNAME_OUTPUT="studio"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_DEVTOOLS is unset for mac_mini" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_DEVTOOLS:-}" ]
}

@test "HAS_GUI is set for all Mac profiles" {
  for hn in laptop studio reception office; do
    result=$(bash -c "
      export MOCK_HOSTNAME_OUTPUT='${hn}'
      export MOCK_UNAME_S='Darwin'
      export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
      source '${REPO_ROOT}/lib/detect_env.sh'
      detect_env
      printf '%s' \"\${HAS_GUI:-}\"
    ")
    [ -n "${result}" ] || {
      printf "HAS_GUI not set for hostname: %s\n" "${hn}" >&2
      return 1
    }
  done
}

@test "HAS_DOCKER is unset for mac_mini" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_DOCKER:-}" ]
}

@test "HAS_PRINTING is set for mac_mini" {
  export MOCK_HOSTNAME_OUTPUT="office"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_PRINTING}" ]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test-unit
```

Expected: all 11 tests in `profiles.bats` fail — `lib/detect_env.sh` does not have profile resolution yet.

---

## Task 2: Create `config/profiles.sh`

**Files:**
- Create: `config/profiles.sh`

- [ ] **Step 1: Create the `config/` directory and `config/profiles.sh`**

```bash
#!/usr/bin/env bash
# config/profiles.sh — requires bash 5+
# Maps hostnames to profiles and profiles to capabilities.
# Edit PROFILE_MAP to add a new machine — no other file needs changing.

declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"
  [studio]="mac_workstation"
  [reception]="mac_workstation"
  [office]="mac_mini"
  [home-1]="mac_mini"
  [workstation]="linux_workstation"
  [cruncher]="linux_workstation"
)

declare -A PROFILE_CAPS=(
  [personal_laptop]="gui devtools aws k8s docker rust printing"
  [mac_workstation]="gui devtools aws k8s docker rust printing"
  [mac_mini]="gui printing"
  [linux_workstation]="gui devtools aws k8s docker rust"
  [server]="devtools aws"
)
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n config/profiles.sh && printf "bash  OK\n"
zsh  -n config/profiles.sh && printf "zsh   OK\n"
```

Both must exit 0.

---

## Task 3: Update `lib/detect_env.sh` — add profile resolution and legacy aliases

**Files:**
- Modify: `lib/detect_env.sh`

- [ ] **Step 1: Add profile resolution block inside `detect_env()`**

Locate the closing `}` of `detect_env()` in `lib/detect_env.sh`. Insert the following block immediately before the closing brace:

```bash
  # Profile resolution
  source "$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh"
  local hn
  hn=$(hostname -s)
  PROFILE="${PROFILE_MAP[${hn}]:-unknown}"
  for cap in ${PROFILE_CAPS[${PROFILE}]:-}; do
    declare -g "HAS_$(printf '%s' "${cap}" | tr '[:lower:]' '[:upper:]')=1"
  done

  # Legacy hostname var aliases (kept until all call sites updated to use HAS_* vars)
  [[ "${hn}" == "laptop" ]]      && readonly LAPTOP=1
  [[ "${hn}" == "studio" ]]      && readonly STUDIO=1
  [[ "${hn}" == "reception" ]]   && readonly RECEPTION=1
  [[ "${hn}" == "office" ]]      && readonly OFFICE=1
  [[ "${hn}" == "home-1" ]]      && readonly HOME_1=1
  [[ "${hn}" == "workstation" ]] && readonly WORKSTATION=1
  [[ "${hn}" == "cruncher" ]]    && readonly CRUNCHER=1
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n lib/detect_env.sh && printf "bash  OK\n"
zsh  -n lib/detect_env.sh && printf "zsh   OK\n"
```

Both must exit 0.

---

## Task 4: Update `Makefile` `test-unit` target

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add `tests/setup_env/profiles.bats` to the `test-unit` recipe**

Current `test-unit` recipe:

```makefile
test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/zshrc.d/unit.bats
```

Updated `test-unit` recipe:

```makefile
test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/setup_env/profiles.bats tests/zshrc.d/unit.bats
```

---

## Task 5: Run all tests and commit

- [ ] **Step 1: Run the full test suite**

```bash
make test
```

Expected: all tests pass, exit 0. All 11 new tests in `profiles.bats` must pass. No regressions in `unit.bats`, `extracted_functions.bats`, `install_guards.bats`, `install_functions.bats`, or `zshrc.d/unit.bats`.

- [ ] **Step 2: Run unit tests in isolation**

```bash
make test-unit
```

Expected: `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats` all pass.

- [ ] **Step 3: Commit**

```bash
git add config/profiles.sh lib/detect_env.sh tests/setup_env/profiles.bats Makefile
git commit -m "feat: add profile abstraction with HAS_* capability vars

Introduces config/profiles.sh (hostname→profile, profile→capability
maps) and wires it into lib/detect_env.sh so that detect_env() sets
HAS_GUI, HAS_DEVTOOLS, HAS_AWS, HAS_K8S, HAS_DOCKER, HAS_RUST, and
HAS_PRINTING based on the resolved profile. Legacy LAPTOP/STUDIO/etc.
vars are preserved as readonly aliases for existing call sites.
Covered by 11 new BATS tests in tests/setup_env/profiles.bats.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Capability Reference

| Capability var | Profiles that set it |
|---|---|
| `HAS_GUI` | personal_laptop, mac_workstation, mac_mini, linux_workstation |
| `HAS_DEVTOOLS` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_AWS` | personal_laptop, mac_workstation, linux_workstation, server |
| `HAS_K8S` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_DOCKER` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_RUST` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_PRINTING` | personal_laptop, mac_workstation, mac_mini |

## Profile-to-hostname Reference

| Hostname | Profile |
|---|---|
| `laptop` | `personal_laptop` |
| `studio` | `mac_workstation` |
| `reception` | `mac_workstation` |
| `office` | `mac_mini` |
| `home-1` | `mac_mini` |
| `workstation` | `linux_workstation` |
| `cruncher` | `linux_workstation` |
| *(any other)* | `unknown` |
