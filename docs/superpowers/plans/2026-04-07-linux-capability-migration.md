# Linux Capability Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a `wsl2_workstation` profile for `cruncher` (WSL2 Ubuntu) and a `HAS_SNAP` capability for `linux_workstation` (desktop Ubuntu), then replace all `WORKSTATION`/`CRUNCHER` hostname vars in `setup_env.sh` with the appropriate `HAS_*` vars.

**Architecture:** `config/profiles.sh` is the single source of truth for hostname→profile and profile→capability mappings. `lib/detect_env.sh` reads it and sets `HAS_*` vars. Legacy hostname aliases (`WORKSTATION`, `CRUNCHER`) in `detect_env.sh` are kept only as long as call sites reference them — this plan removes all call sites then drops the aliases. The key distinction: `linux_workstation` (desktop) has `HAS_SNAP`, `wsl2_workstation` (WSL2) does not.

**Tech Stack:** bash, BATS

> **Sequencing note:** Execute this plan AFTER the macOS capability migration plan. The macOS plan cleans up the `WORKSTATION`/`CRUNCHER` references in the shared ansible/pip sections (~lines 1225, 1282). This plan then removes the legacy `CRUNCHER` and `WORKSTATION` aliases from `detect_env.sh`, which would break those lines if they still existed.

---

## Files Modified

- `config/profiles.sh` — add `wsl2_workstation` profile; add `snap` to `linux_workstation` caps; remap `cruncher` hostname
- `lib/detect_env.sh` — remove `CRUNCHER` and `WORKSTATION` legacy aliases
- `setup_env.sh` — replace 16 `WORKSTATION`/`CRUNCHER` hostname gates with `HAS_*` vars
- `tests/setup_env/profiles.bats` — add tests for `wsl2_workstation` profile and `HAS_SNAP` capability
- `README.md` — update Machine Profiles table; document `wsl2_workstation` vs `linux_workstation` distinction

---

### Task 1: Add wsl2_workstation profile and HAS_SNAP capability (TDD)

**Files:**
- Test: `tests/setup_env/profiles.bats`
- Modify: `config/profiles.sh`

TDD order: write the failing tests first, then implement the profile changes to make them pass.

- [ ] **Step 1: Write failing tests in profiles.bats**

Append to `tests/setup_env/profiles.bats`:

```bash
@test "detect_env sets PROFILE=linux_workstation for hostname workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "linux_workstation" ]
}

@test "detect_env sets PROFILE=wsl2_workstation for hostname cruncher" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ "${PROFILE}" = "wsl2_workstation" ]
}

@test "HAS_SNAP is set for linux_workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_SNAP}" ]
}

@test "HAS_SNAP is unset for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -z "${HAS_SNAP:-}" ]
}

@test "HAS_DEVTOOLS is set for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_DEVTOOLS}" ]
}

@test "HAS_RUST is set for linux_workstation" {
  export MOCK_HOSTNAME_OUTPUT="workstation"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_RUST}" ]
}

@test "HAS_RUST is set for wsl2_workstation" {
  export MOCK_HOSTNAME_OUTPUT="cruncher"
  export MOCK_UNAME_S="Linux"
  source "${REPO_ROOT}/lib/detect_env.sh"
  detect_env
  [ -n "${HAS_RUST}" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "wsl2_workstation\|HAS_SNAP\|not ok"
```

Expected: the new tests fail (profile `wsl2_workstation` does not exist yet; `HAS_SNAP` is never set)

- [ ] **Step 3: Update config/profiles.sh**

Replace the full content of `config/profiles.sh`:

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
  [cruncher]="wsl2_workstation"
)

declare -A PROFILE_CAPS=(
  [personal_laptop]="gui devtools aws k8s docker rust printing"
  [mac_workstation]="gui devtools aws k8s docker rust printing"
  [mac_mini]="gui printing"
  [linux_workstation]="gui devtools aws k8s docker rust snap"
  [wsl2_workstation]="gui devtools aws k8s docker rust"
  [server]="devtools aws"
)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test
```

Expected: exit 0 — all new tests pass, no existing tests broken

- [ ] **Step 5: Commit**

```bash
git add config/profiles.sh tests/setup_env/profiles.bats
git commit -m "$(cat <<'EOF'
feat: add wsl2_workstation profile and HAS_SNAP capability

cruncher (WSL2 Ubuntu) gets its own profile distinct from
linux_workstation (desktop Ubuntu). HAS_SNAP is set only for
linux_workstation where snap is available.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Remove CRUNCHER and WORKSTATION legacy aliases from detect_env.sh

**Files:**
- Modify: `lib/detect_env.sh`

The aliases are safe to remove only after all call sites in `setup_env.sh` are replaced (Task 3 does that). However, the aliases for these two vars are removed here because `config/profiles.sh` changes already make the vars redundant from the profile system's perspective. **Do Task 3 immediately after this task in the same session** — don't commit Task 2 until Task 3 is also done and tests pass.

- [ ] **Step 1: Remove the two alias lines from detect_env.sh**

In `lib/detect_env.sh`, remove these two lines from the legacy alias block:

```bash
  [[ "${hn}" == "workstation" ]] && readonly WORKSTATION=1
  [[ "${hn}" == "cruncher" ]]    && readonly CRUNCHER=1
```

The remaining legacy alias block should look like:

```bash
  # Legacy hostname var aliases (kept until all call sites updated to use HAS_* vars)
  [[ "${hn}" == "laptop" ]]      && readonly LAPTOP=1
  [[ "${hn}" == "studio" ]]      && readonly STUDIO=1
  [[ "${hn}" == "reception" ]]   && readonly RECEPTION=1
  [[ "${hn}" == "office" ]]      && readonly OFFICE=1
  [[ "${hn}" == "home-1" ]]      && readonly HOMES=1
```

Also remove the RATNA reference in the CHRUBY_LOC block (the block currently checks `[[ -n ${RATNA} ]]` as the first condition — remove that branch entirely since RATNA is a deprecated host with no entry in PROFILE_MAP):

```bash
  # setup variables based off of environment
  if [[ -n ${MACOS} ]]; then
    if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
      CHRUBY_LOC="/opt/homebrew/opt/chruby/share"
    fi
  elif [[ -n ${LINUX} ]]; then
    CHRUBY_LOC="/usr/local/share"
  fi
```

(The original had `if [[ -n ${RATNA} ]]; then ... elif [[ -n ${LAPTOP} ]] || ...` — drop the RATNA branch and promote the elif to if.)

- [ ] **Step 2: Verify shell syntax**

```bash
bash -n lib/detect_env.sh && echo "syntax OK"
```

Expected: `syntax OK`

**Do not commit yet — proceed immediately to Task 3.**

---

### Task 3: Replace all WORKSTATION/CRUNCHER gates in setup_env.sh

**Files:**
- Modify: `setup_env.sh`

There are 16 sites to update. They are listed below in line-number order (approximate — adjust if prior edits shifted lines). Make all changes then verify syntax and tests together.

- [ ] **Step 1: Line ~186 — snap package install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]]; then
      printf "Installing workstation packages\\n"
      xargs -a ./ubuntu_workstation_packages.txt sudo apt install -y
```

With:
```bash
    if [[ -n ${HAS_SNAP} ]]; then
      printf "Installing workstation packages\\n"
      xargs -a ./ubuntu_workstation_packages.txt sudo apt install -y
```

- [ ] **Step 2: Line ~439 — Rust install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing Rust Ubuntu\\n"
```

With:
```bash
    if [[ -n ${HAS_RUST} ]]; then
      printf "Installing Rust Ubuntu\\n"
```

- [ ] **Step 3: Line ~453 — Docker install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing docker\\n"
```

With:
```bash
    if [[ -n ${HAS_DOCKER} ]]; then
      printf "Installing docker\\n"
```

- [ ] **Step 4: Line ~477 — VirtualBox install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing Virtualbox\\n"
```

With:
```bash
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      printf "Installing Virtualbox\\n"
```

- [ ] **Step 5: Line ~488 — Teleport install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing teleport\\n"
```

With:
```bash
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      printf "Installing teleport\\n"
```

- [ ] **Step 6: Line ~499 — cloudflared install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing cloudflared\\n"
```

With:
```bash
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      printf "Installing cloudflared\\n"
```

- [ ] **Step 7: Line ~510 — kind install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      if [[ ! -f ${HOME}/software_downloads/kind_${KIND_VER} ]]; then
        printf "Installing kind\\n"
```

With:
```bash
    if [[ -n ${HAS_K8S} ]]; then
      if [[ ! -f ${HOME}/software_downloads/kind_${KIND_VER} ]]; then
        printf "Installing kind\\n"
```

- [ ] **Step 8: Line ~524 — yq install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      if [[ ! -f ${HOME}/software_downloads/yq_${YQ_VER} ]]; then
        printf "Installing yq\\n"
```

With:
```bash
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      if [[ ! -f ${HOME}/software_downloads/yq_${YQ_VER} ]]; then
        printf "Installing yq\\n"
```

- [ ] **Step 9: Line ~538 — Albert launcher gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]]; then
      if [[ ${FOCAL} ]]; then
        printf "Installing Albert Ubuntu Focal\\n"
```

With:
```bash
    if [[ -n ${HAS_SNAP} ]]; then
      if [[ ${FOCAL} ]]; then
        printf "Installing Albert Ubuntu Focal\\n"
```

- [ ] **Step 10: Line ~575 — telepresence install gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing telepresence\\n"
```

With:
```bash
    if [[ -n ${HAS_K8S} ]]; then
      printf "Installing telepresence\\n"
```

- [ ] **Step 11: Line ~729 — claude-code + plugins gate**

Replace:
```bash
      if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
        brew_install_formula claude-code
```

With:
```bash
      if [[ -n ${HAS_DEVTOOLS} ]]; then
        brew_install_formula claude-code
```

- [ ] **Step 12: Line ~737 — ollama gate**

Replace:
```bash
      if [[ -n ${WORKSTATION} ]]; then
        brew_install_formula ollama
      fi
```

With:
```bash
      if [[ -n ${HAS_SNAP} ]]; then
        brew_install_formula ollama
      fi
```

- [ ] **Step 13: Line ~742 — Microsoft Edge gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]]; then
      printf "Installing microsoft edge\\n"
```

With:
```bash
    if [[ -n ${HAS_SNAP} ]]; then
      printf "Installing microsoft edge\\n"
```

- [ ] **Step 14: Line ~749 — dotnet-sdk-8.0 gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "Installing .net8 sdk\\n"
      sudo -H apt install dotnet-sdk-8.0 -y
    fi
```

With:
```bash
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      printf "Installing .net8 sdk\\n"
      sudo -H apt install dotnet-sdk-8.0 -y
    fi
```

- [ ] **Step 15: Line ~765 and ~776 — snap classic installs and WSL2 helm**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]]; then
      printf "snap software with classic option, the other snap packages are installed in ubuntu_workstation_snap_packages.txt\\n"
      sudo snap install atom --classic
      sudo snap install code --classic
      sudo snap install helm --classic
      sudo snap install slack --classic
      sudo snap install certbot --classic
      sudo snap set certbot trust-plugin-with-root=ok
      sudo snap install certbot-dns-route53
    fi
    # can't use snap on wsl2
    if [[ -n ${CRUNCHER} ]]; then
      curl https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /etc/apt/keyrings/helm-signing.gpg
      echo "deb [signed-by=/etc/apt/keyrings/helm-signing.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
      sudo apt-get update
      sudo apt-get install helm
    fi
```

With:
```bash
    if [[ -n ${HAS_SNAP} ]]; then
      printf "snap software with classic option, the other snap packages are installed in ubuntu_workstation_snap_packages.txt\\n"
      sudo snap install atom --classic
      sudo snap install code --classic
      sudo snap install helm --classic
      sudo snap install slack --classic
      sudo snap install certbot --classic
      sudo snap set certbot trust-plugin-with-root=ok
      sudo snap install certbot-dns-route53
    fi
    # can't use snap on wsl2
    if [[ -z ${HAS_SNAP} ]]; then
      curl https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /etc/apt/keyrings/helm-signing.gpg
      echo "deb [signed-by=/etc/apt/keyrings/helm-signing.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
      sudo apt-get update
      sudo apt-get install helm
    fi
```

Note: the helm-via-apt block was previously gated on `CRUNCHER` (WSL2 only). The replacement uses `[[ -z ${HAS_SNAP} ]]` which is true on any Linux machine without snap — currently only `wsl2_workstation`. This is correct: if snap is unavailable, install helm via apt.

- [ ] **Step 16: Line ~796 — libssl1.1 gate**

Replace:
```bash
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      printf "installing libssl1.1\\n"
```

With:
```bash
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      printf "installing libssl1.1\\n"
```

- [ ] **Step 17: Line ~1033 — Linux aws-cli gate**

Replace:
```bash
  if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on Linux\\n"
```

With:
```bash
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on Linux\\n"
```

- [ ] **Step 18: Verify shell syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 19: Run tests**

```bash
make test
```

Expected: exit 0

- [ ] **Step 20: Commit Tasks 2 + 3 together**

```bash
git add lib/detect_env.sh setup_env.sh
git commit -m "$(cat <<'EOF'
refactor: replace WORKSTATION/CRUNCHER hostname vars with HAS_* caps

16 sites in setup_env.sh updated. Snap-gated blocks use HAS_SNAP,
k8s blocks use HAS_K8S, devtools/docker/rust blocks use their
respective HAS_* vars. Linux aws-cli uses HAS_AWS && LINUX.

Removes WORKSTATION and CRUNCHER legacy aliases from detect_env.sh
now that all call sites are gone.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Find and update the Machine Profiles table**

Locate the Machine Profiles section in `README.md`. Add a row for `wsl2_workstation` and update the `linux_workstation` row to show `snap` in its capabilities. The table should read:

| Profile | Hostname | HAS_GUI | HAS_DEVTOOLS | HAS_AWS | HAS_K8S | HAS_DOCKER | HAS_RUST | HAS_PRINTING | HAS_SNAP |
|---|---|---|---|---|---|---|---|---|---|
| `personal_laptop` | laptop | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | |
| `mac_workstation` | studio, reception | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | |
| `mac_mini` | office, home-1 | ✓ | | | | | | ✓ | |
| `linux_workstation` | workstation | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | | ✓ |
| `wsl2_workstation` | cruncher | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | | |
| `server` | (any server) | | ✓ | ✓ | | | | | |

Add a note below the table:

```
**linux_workstation vs wsl2_workstation:** `linux_workstation` (hostname: `workstation`) is a
desktop Ubuntu machine with full snap support. `wsl2_workstation` (hostname: `cruncher`) is
WSL2 Ubuntu where snap is unavailable — snap-gated installs (Albert, Microsoft Edge, ollama,
snap classic packages) are skipped, and Helm is installed via apt instead of snap.
```

- [ ] **Step 2: Update the Adding a New Machine section**

If `README.md` references `cruncher` as having profile `linux_workstation`, update it to `wsl2_workstation`. Update any WSL2 notes to reference the correct profile name.

- [ ] **Step 3: Run tests**

```bash
make test
```

Expected: exit 0

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: document wsl2_workstation profile and HAS_SNAP capability

Updates Machine Profiles table with the new wsl2_workstation profile
(hostname: cruncher) and explains the linux_workstation vs
wsl2_workstation distinction.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
