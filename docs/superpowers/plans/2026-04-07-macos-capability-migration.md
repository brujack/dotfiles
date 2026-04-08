# macOS Capability Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all inline `brew_install_*` calls out of `setup_env.sh` into the appropriate Brewfiles and replace the four remaining deprecated hostname-var gates with `HAS_*` capability vars.

**Architecture:** Brewfiles are the canonical source for Homebrew installs — `install_macos_casks()` already calls `brew bundle` for Brewfile, Brewfile.gui, and Brewfile.devtools based on capabilities. The macOS brew block in `setup_env.sh` should contain only the orchestration calls (`brew_update`, `brew bundle`, `brew cleanup`). Hostname var gates in the shared developer/update section are replaced with `HAS_AWS` and `HAS_DEVTOOLS`.

**Tech Stack:** bash, Homebrew Brewfile DSL, BATS

> **Sequencing note:** Execute this plan BEFORE the Linux capability migration plan. Both plans remove `WORKSTATION`/`CRUNCHER` references from shared sections (ansible virtualenv line ~1225, pip update line ~1282). Running this plan first ensures those references are cleaned up before the Linux plan removes the legacy aliases from `detect_env.sh`.

---

## Files Modified

- `Brewfile` — add `tap "teamookla/speedtest"` + `brew "teamookla/speedtest/speedtest"`
- `Brewfile.gui` — add `cask "miro"`
- `Brewfile.devtools` — add 5 taps + 3 formulae + 2 casks
- `setup_env.sh` — remove inline brew block (lines 138–151); replace hostname gates at lines ~1019, ~1225, ~1282

---

### Task 1: Add entries to Brewfile, Brewfile.gui, and Brewfile.devtools

**Files:**
- Modify: `Brewfile`
- Modify: `Brewfile.gui`
- Modify: `Brewfile.devtools`

There are no logic tests for Brewfile content — the validation is a syntax parse by `brew bundle check`. These changes have no corresponding BATS tests.

- [ ] **Step 1: Add tap + formula to Brewfile**

In `Brewfile`, insert after line `brew "sops"` (alphabetically, `speedtest` sorts between `sops` and `sqlite`):

```
tap "teamookla/speedtest"
```

Add this tap at the very top of `Brewfile`, before the first `brew` line (the file currently has no `tap` lines):

```
tap "teamookla/speedtest"
brew "argocd"
...
```

Then insert the formula between `brew "sops"` and `brew "sqlite"`:

```
brew "sops"
brew "teamookla/speedtest/speedtest"
brew "sqlite"
```

- [ ] **Step 2: Add cask to Brewfile.gui**

In `Brewfile.gui`, insert `cask "miro"` in alphabetical order. It sorts between `microsoft-office` and `obs`:

```
cask "microsoft-office"
cask "miro"
cask "obs"
```

- [ ] **Step 3: Add taps, formulae, and casks to Brewfile.devtools**

`Brewfile.devtools` currently has no `tap` or `brew` lines — only `cask` and `mas`. Add taps at the top, brews after taps, and insert the two new casks in alphabetical order among the existing casks.

The full updated `Brewfile.devtools`:

```
# Brewfile.devtools — installed on HAS_DEVTOOLS machines
tap "chef/chef"
tap "datawire/blackbird"
tap "go-task/tap"
tap "redpanda-data/tap"
tap "snyk/tap"
brew "datawire/blackbird/telepresence-arm64"
brew "go-task/tap/go-task"
brew "redpanda-data/tap/redpanda"
brew "snyk/tap/snyk"
cask "carbon-copy-cloner"
cask "chef/chef/inspec"
cask "cursor"
cask "dbeaver-community"
cask "docker-desktop"
cask "dotnet"
cask "fork"
cask "funter"
cask "gcloud-cli"
cask "lens"
cask "mysqlworkbench"
cask "oracle-jdk"
cask "postman"
cask "session-manager-plugin"
cask "sourcetree"
cask "steam"
cask "vagrant"
cask "virtualbox"
mas "iMovie", id: 408981434
mas "Keynote", id: 409183694
mas "Numbers", id: 409203825
mas "Pages", id: 409201541
mas "Pixelmator Pro", id: 1289583905
mas "Read CHM", id: 594432954
mas "SQLPro for Postgres", id: 1025345625
mas "Telegram", id: 747648890
mas "Valentina Studio", id: 604825918
mas "Xcode", id: 497799835
```

- [ ] **Step 4: Verify Brewfile syntax**

```bash
brew bundle check --file Brewfile --no-upgrade 2>&1 | head -5
brew bundle check --file Brewfile.gui --no-upgrade 2>&1 | head -5
brew bundle check --file Brewfile.devtools --no-upgrade 2>&1 | head -5
```

Expected: no parse errors (missing packages are fine — this is a syntax check only). If brew is not available in the test environment, run:

```bash
bash -c 'grep -n "^tap\|^brew\|^cask\|^mas" Brewfile | head -5' && echo "Brewfile OK"
bash -c 'grep -n "^tap\|^brew\|^cask\|^mas" Brewfile.gui | head -5' && echo "Brewfile.gui OK"
bash -c 'grep -n "^tap\|^brew\|^cask\|^mas" Brewfile.devtools | head -5' && echo "Brewfile.devtools OK"
```

- [ ] **Step 5: Commit**

```bash
git add Brewfile Brewfile.gui Brewfile.devtools
git commit -m "$(cat <<'EOF'
feat: move inline brew installs to Brewfiles

speedtest → Brewfile (universal), miro → Brewfile.gui, chef/inspec +
dotnet + go-task + redpanda + snyk + telepresence → Brewfile.devtools

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Remove inline brew installs from setup_env.sh macOS block

**Files:**
- Modify: `setup_env.sh` (lines 138–151)

The target block is inside `elif [ -x "$(command -v brew)" ]` (line 132). After the change the block ends immediately after `install_macos_casks` and `brew cleanup`.

- [ ] **Step 1: Remove the inline install lines**

Replace this block in `setup_env.sh` (lines 132–155, the `elif` branch):

```bash
    elif [ -x "$(command -v brew)" ]; then
      brew_update
      printf "Installing other brew stuff...\\n"
      #https://github.com/Homebrew/homebrew-bundle
      brew_tap_if_missing homebrew/bundle
      install_macos_casks
      brew_install_cask chef/chef/inspec
      brew_tap_if_missing cloudflare/cloudflare
      brew_install_cask dotnet
      brew_install_formula go-task/tap/go-task
      brew_install_cask miro
      brew_tap_if_missing snyk/tap
      brew_install_formula snyk
      brew_tap_if_missing teamookla/speedtest
      brew_install_formula speedtest
      brew_install_formula redpanda-data/tap/redpanda
      if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
        brew_install_formula datawire/blackbird/telepresence-arm64
        brew_install_formula cloudflared
      fi

      printf "Cleaning Homebrew up...\\n"
      brew cleanup
    fi
```

With:

```bash
    elif [ -x "$(command -v brew)" ]; then
      brew_update
      printf "Installing other brew stuff...\\n"
      #https://github.com/Homebrew/homebrew-bundle
      brew_tap_if_missing homebrew/bundle
      install_macos_casks

      printf "Cleaning Homebrew up...\\n"
      brew cleanup
    fi
```

- [ ] **Step 2: Verify shell syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 3: Run tests**

```bash
make test
```

Expected: exit 0

- [ ] **Step 4: Commit**

```bash
git add setup_env.sh
git commit -m "$(cat <<'EOF'
refactor: remove inline brew installs from macOS setup block

All installs now delegated to Brewfile/Brewfile.gui/Brewfile.devtools
via install_macos_casks(). Inline calls were redundant and bypassed
the capability model.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Migrate macOS aws-cli hostname gate to HAS_AWS

**Files:**
- Modify: `setup_env.sh` (lines ~1019–1032)

The current block wraps the macOS aws-cli install in `LAPTOP || STUDIO || RECEPTION || OFFICE || HOMES || RATNA`, then has an inner `if [[ -n ${MACOS} ]]`. The spec collapses both into one `HAS_AWS && MACOS` check and removes one level of nesting.

- [ ] **Step 1: Replace the aws-cli gate**

Replace this block (lines ~1019–1032):

```bash
  if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    if [[ -n ${MACOS} ]]; then
      printf "Installing aws-cli on MacOS\\n"
      if [[ ! -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg ]]; then
        wget -O ${HOME}/software_downloads/awscli/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
        sudo installer -pkg ${HOME}/software_downloads/awscli/AWSCLIV2.pkg -target /
        rm -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg
        if [[ -x $(command -v aws) ]]; then
          printf "aws-cli is installed MacOS\\n"
        fi
      fi
    fi
  fi
```

With:

```bash
  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on MacOS\\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg ]]; then
      wget -O ${HOME}/software_downloads/awscli/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
      sudo installer -pkg ${HOME}/software_downloads/awscli/AWSCLIV2.pkg -target /
      rm -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed MacOS\\n"
      fi
    fi
  fi
```

- [ ] **Step 2: Verify shell syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 3: Run tests**

```bash
make test
```

Expected: exit 0

- [ ] **Step 4: Commit**

```bash
git add setup_env.sh
git commit -m "$(cat <<'EOF'
refactor: replace macOS aws-cli hostname gate with HAS_AWS

Collapses outer LAPTOP||STUDIO||...||RATNA + inner MACOS check into
a single HAS_AWS && MACOS condition. Removes RATNA which was a
deprecated host.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Migrate Ansible virtualenv and pip update hostname gates to HAS_DEVTOOLS

**Files:**
- Modify: `setup_env.sh` (lines ~1225 and ~1282)

Two separate lines, same replacement pattern. Both currently enumerate all Mac + Linux hostnames including the deprecated `RATNA`.

- [ ] **Step 1: Replace the Ansible virtualenv gate (line ~1225)**

Replace:

```bash
    if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]] || [[ -n ${RATNA} ]]; then
```

With:

```bash
    if [[ -n ${HAS_DEVTOOLS} ]]; then
```

- [ ] **Step 2: Replace the pip update gate (line ~1282)**

Replace:

```bash
  if [[ -n ${STUDIO-} || -n ${LAPTOP-} || -n ${RECEPTION-} || -n ${OFFICE-} || -n ${HOMES-} || -n ${WORKSTATION-} || -n ${CRUNCHER-} || -n ${RATNA-} ]]; then
```

With:

```bash
  if [[ -n ${HAS_DEVTOOLS} ]]; then
```

- [ ] **Step 3: Verify shell syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 4: Run tests**

```bash
make test
```

Expected: exit 0

- [ ] **Step 5: Commit**

```bash
git add setup_env.sh
git commit -m "$(cat <<'EOF'
refactor: replace ansible/pip hostname gates with HAS_DEVTOOLS

Replaces the eight-way STUDIO||LAPTOP||...||RATNA hostname guards for
Ansible virtualenv setup and pip update with HAS_DEVTOOLS. Covers the
same machines (personal_laptop, mac_workstation, linux_workstation,
server) without RATNA which is a deprecated host.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
