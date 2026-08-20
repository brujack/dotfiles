# Add `uv` to the Brewfile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install `uv` on both load-bearing development machines through the repo's own install paths, as step 1 of ai-config's Python dependency management design.

**Architecture:** Two production edits, because the two platforms use different install mechanisms. macOS reads `Brewfile` via `brew bundle` (`lib/macos.sh:193`); Ubuntu reads a hardcoded `brew_install_formula` list in `_install_ubuntu_brew_packages()` (`lib/linux_ubuntu.sh:329`) and never opens the Brewfile. Three tests, then a verification task that actually installs on both machines — because neither edit self-delivers.

**Tech Stack:** Homebrew (`uv` 0.12.5, bottled on both macOS and Linuxbrew), bats.

**Spec:** `docs/superpowers/specs/2026-08-20-brewfile-uv-design.md` (master `61bf75d`, Multi-Lens Review complete, all dispositions Addressed).

## Global Constraints

- `uv` is **unpinned**, deliberately. `-t update` runs `brew upgrade --yes`, so both machines track brew's current `uv`. Recorded as accepted drift; revisit before step 3 of the parent design, per the backlog row.
- The capability tag `[HAS_DEVTOOLS]` does **not** gate installation — `lib/macos.sh:193` bundles the main Brewfile unconditionally. The tag selects `brew-drift` expectations only. `mac_mini` will receive `uv`, exactly as it already receives `pyenv`.
- `lib/linux_ubuntu.sh` is a `.sh` file, so this is **code**: branch + PR + full gate chain, no direct-to-master.
- Do not add `UV_VER` to `lib/constants.sh`. The unpinned decision is deliberate and its revisit is tracked in the backlog, not in a constant.

## Verification Planning

**Command that proves the whole change works:** on each load-bearing machine, run the platform's install path, then `-t update`, and assert `brew-drift` reports clean.

**Expected observable change:** `command -v uv` resolves on both machines; `-t update`'s summary shows `brew-drift` OK rather than `WARN … Missing (in Brewfile, not installed): uv`.

**Edge case that must be exercised:** the Linux machine specifically. A Brewfile-only change would leave `uv` missing there *and* produce a permanent `brew-drift` WARN, because the drift check's formula arm is not macOS-gated and `linux_workstation` carries `HAS_DEVTOOLS`. Verifying only the Studio would pass on a broken change.

---

### Task 1: Brewfile entry + macOS-side tests

```yaml-task
id: 1
description: Add uv to Brewfile with the HAS_DEVTOOLS tag and two bats cases pinning presence and tag identity
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - Brewfile
  - tests/setup_env/brewfile_drift.bats
depends_on: []
```

**Files:** `Brewfile`, `tests/setup_env/brewfile_drift.bats`

**Write both tests first and confirm RED** (both currently exit 1 — measured; the gate runs and finds the defect rather than erroring). Add them next to the existing real-Brewfile case at `:510`:

```bash
@test "_brewfile_parse_section brew: real Brewfile yields uv when HAS_DEVTOOLS is set" {
  unset "${!HAS_@}"
  export HAS_DEVTOOLS=1
  run _brewfile_parse_section brew "${REPO_ROOT}/Brewfile"
  [ "$status" -eq 0 ]
  grep -qx 'uv' <<<"$output"
}

@test "_brewfile_parse_inactive brew: real Brewfile withholds uv without HAS_DEVTOOLS" {
  unset "${!HAS_@}"
  run _brewfile_parse_inactive brew "${REPO_ROOT}/Brewfile"
  [ "$status" -eq 0 ]
  grep -qx 'uv' <<<"$output"
}
```

**The `unset "${!HAS_@}"` in case 1 is load-bearing, not hygiene.** It is what makes the pair pin the tag's *identity*. Measured against the real parse functions: `[HAS_GUI]` → case 1 FAIL, `[HAS_DEVTOOL]` typo → case 1 FAIL, untagged → case 2 FAIL. Only the correct tag passes both. Drop the `unset` and case 1 degrades to presence-only on any machine whose shell exports `HAS_GUI`.

**`grep -qx`, not substring.** `uv` appears nowhere in `Brewfile` as a substring today, so a substring match is unambiguous now and quietly stops being so when someone adds a formula containing those letters.

Then add to `Brewfile`, beside the existing Python tooling (`pyenv` `:91`, `pyenv-virtualenv` `:93`, `python@3.13` `:94`):

```ruby
brew "uv"                                    # [HAS_DEVTOOLS]
```

**Placement note:** `CLAUDE.md` states alphabetical order; the brew section is not strictly sorted in practice (`cargo-nextest`, `git-lfs`, `mongosh` are all out of order) and the python cluster is itself scrambled. Placing with the Python tooling is deliberate — it groups `uv` with the toolchain it belongs to, and the tests assert membership, not position.

**Interfaces:**
- Consumes: nothing.
- Produces: `uv` in `Brewfile`'s active set when `HAS_DEVTOOLS` is set. Task 2 is independent of this; Task 3 consumes it.

---

### Task 2: Linux install-list entry + Linux-side test

```yaml-task
id: 2
description: Add brew_install_formula uv to _install_ubuntu_brew_packages with a bats case that executes the function
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: [1]
```

**Files:** `lib/linux_ubuntu.sh`, `tests/setup_env/linux_ubuntu.bats`

**Why this task exists at all:** Linux never reads the Brewfile. `brew bundle` appears only at `lib/macos.sh:193/195/198`, reached via `install_macos_casks` (`lib/workflows.sh:301`) inside `if [[ -n ${MACOS} ]]` at `:300`. Without this edit, Task 1 alone installs `uv` on macOS and produces a **permanent** `brew-drift WARN` on `linux_workstation` and `wsl2_workstation` — the drift check is called unconditionally (`lib/workflows.sh:640`) and only its cask arm is macOS-gated (`lib/update_summary.sh:694`, `:717`).

**Write the test first and confirm RED.** Follow the precedent at `tests/setup_env/linux_ubuntu.bats:124`:

```bash
@test "_install_ubuntu_brew_packages: installs uv via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -qx "brew install uv" "${MOCK_CALLS_FILE}"
}
```

**Use `grep -qx`, not the precedent's `grep -q`.** The precedent's `grep -q "brew install pyenv"` also matches the `pyenv-virtualenv` line, so it cannot distinguish the two. `brew_install_formula` runs `NONINTERACTIVE=1 brew install "$formula"` (`lib/helpers.sh`) and the mock records `printf "brew %s\n" "$*"`, so the recorded line is exactly `brew install uv` and an anchored match is precise.

**The test must execute the function, not grep the file.** A `grep 'brew_install_formula uv' lib/linux_ubuntu.sh` gate would pass if the line landed outside `_install_ubuntu_brew_packages()` — in a comment or a neighbouring function. Running the function and asserting against `MOCK_CALLS_FILE` closes that.

Then add to `_install_ubuntu_brew_packages()` in alphabetical position within the existing list — after `brew_install_formula tgenv` (`lib/linux_ubuntu.sh:362`), before `brew_install_formula zoxide` (`:363`). **Corrected 2026-08-20:** this line previously read "after `rustup`, before the `shfmt` comment block", which is the `r`->`s` boundary and is not where `u` sorts; measured, the list runs `ripgrep` `rustup` `shfmt` `starship` `tgenv` `zoxide`, so `uv` belongs between the last two. The trailing tap-qualified entries (`go-task`, `redpanda`) are already out of order and are not the anchor.

```bash
brew_install_formula uv
```

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `uv` installed on Ubuntu via the repo's own install path. Task 3 consumes it.

---

### Task 3: Install on both machines and verify uv leaves the drift Missing list

```yaml-task
id: 3
description: Install uv via each platform's own install path on Studio and workstation, then assert uv is absent from brew-drift's Missing list (verification task, no code change so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'command -v uv >/dev/null'
    exit_code: 0
  - cmd: 'ssh -o ConnectTimeout=10 workstation "PATH=/home/linuxbrew/.linuxbrew/bin:\$PATH command -v uv" >/dev/null'
    exit_code: 0
max_retries: 2
files_touched: []
depends_on: [1, 2]
```

> **Sequencing corrected 2026-08-20 — Tasks 3 and 4 run AFTER the PR merges, not before.** `run_brew_install` (`lib/workflows.sh:290-293`) does `rm -f` then `ln -s` on `${BREWFILE_LOC}/Brewfile` pointing at `${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile` — the **main checkout**, resolved as `/Users/bruce/git-repos/personal/dotfiles/Brewfile`. Measured: that file carries **0** `uv` lines while the feature worktree carries 1, so `brew bundle` cannot see this branch's entry no matter which directory the command is invoked from. The Linux side has the same shape — the workstation has its own clone on master, which is why this task already says `git pull` first. Running either machine pre-merge would therefore install nothing and the only way to make `command -v uv` succeed would be the bare `brew install uv` fallback, which this task explicitly forbids reporting as equivalent. Order is: T1, T2 -> Phase 3 -> PR -> merge -> T3 -> T4. The acceptance gates are unchanged; only their position moves.

**Neither edit self-delivers, which is why this is a task and not a footnote.** `run_update()` contains exactly one brew call — `brew_update` (`brew update` / `brew upgrade --yes` / `brew cleanup`) — and every install path sits outside it: `install_macos_packages` (`lib/workflows.sh:221`), `install_ubuntu_packages` (`:225`), `install_macos_casks` (`:301`), all behind `-t setup` / `-t developer` / `--brew-install`. So from merge until someone runs an install workflow, the machines carry the exact WARN Task 2 exists to prevent. **Corrected 2026-08-20 — that is 6 machines, not the 2 this task installs on.** Measured against `PROFILE_MAP`/`PROFILE_CAPS`: every profile carrying `devtools` sees `uv` in the active expected set, which is `laptop`, `ratna`, `reception`, `studio`, `workstation` and `cruncher` (plus their `-1` wireless twins). Task 3 installs on 2 of those; the other 4 carry one advisory `Missing (in Brewfile, not installed): uv` line in `-t update`'s summary until someone runs an install workflow there. That is the designed self-announcing reminder rather than a defect — but the original sentence stated a boundary narrower than the effect, which is the error class this plan has now made three times.

**Mac Studio:**

```bash
./setup_env.sh -t setup --brew-install     # or -t developer
./setup_env.sh -t update                    # assert: brew-drift OK, not WARN … Missing … uv
command -v uv && uv --version
```

**Linux 7950X — the PATH prepend is mandatory.** `brew` is absent from that machine's non-interactive PATH, and `setup_env.sh:30` gates every workflow on `env which brew`, so a bare `ssh workstation './setup_env.sh …'` exits with `[ERROR] Homebrew not found`. Prepend the prefix:

```bash
ssh workstation 'cd ~/git-repos/personal/dotfiles && git pull && \
  PATH=/home/linuxbrew/.linuxbrew/bin:$PATH ./setup_env.sh -t developer'
ssh workstation 'cd ~/git-repos/personal/dotfiles && \
  PATH=/home/linuxbrew/.linuxbrew/bin:$PATH ./setup_env.sh -t update'
```

**If the prepend is not sufficient** — i.e. `setup_env.sh` still refuses for a reason other than the brew gate — fall back to `PATH=/home/linuxbrew/.linuxbrew/bin:$PATH brew install uv` and **say so explicitly in the report**: that installs `uv` and clears the drift WARN, but it does not exercise the repo's own install path on that machine, so the Task 2 edit remains unverified end-to-end there. Do not report the fallback as equivalent.

**Corrected 2026-08-20 — "drift clean" was unreachable on both machines and is not what this task asserts.** Measured before dispatch, against the real installed state:

| machine | active Brewfile formulae | installed | missing (pre-existing) |
| --- | --- | --- | --- |
| Studio | 128 | 230 | **3** — `codeburn`, `go-task/tap/go-task`, `uv` |
| workstation | 127 | 112 | **77** — including `uv` |

So installing `uv` leaves Studio at 2 missing and the workstation at 76. The reachable assertion — and the one the bash comment above already states — is that **`uv` disappears from the Missing list**, not that the list empties. The `acceptance:` block is unaffected: it gates on `command -v uv` on both machines, which was always correct.

The workstation's 77 is not this branch's problem and must not be read as a regression: `_update_check_brewfile_drift` carries no platform guard (`lib/update_summary.sh:644` checks only `quiet_which brew` and the Brewfile's existence), so Linux is measured against a macOS Brewfile it never installs from — Linux installs from `_install_ubuntu_brew_packages()`. Backlogged separately.

**Record for each machine:** `uv --version`, and the `brew-drift` line from `-t update`'s summary. Both versions go in the PR body — they are the baseline the parent design's step-3 rehearsal will be compared against, and the spec requires the version recorded beside each result.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: `uv` present on both machines; two recorded version strings.

---

### Task 4: Notify the ai-config session

```yaml-task
id: 4
description: Message the ai-config session that step 1 is complete, with both machines' uv versions (coordination task, no code change so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'test -f docs/superpowers/specs/2026-08-20-brewfile-uv-design.md'
    exit_code: 0
max_retries: 2
files_touched: []
depends_on: [3]
```

Per the operator. Send via `SendMessage` to the ai-config session, including: the merged PR number, both machines' `uv --version` output from Task 3, and the two findings from this cycle that bear on their remaining steps — that Linux needs a matching `brew_install_formula` line for **every** tool their design adds, and that `uv sync` prunes by default with `--inexact` explicitly not covering conflicting packages.

**Interfaces:**
- Consumes: Task 3's recorded versions.
- Produces: nothing in-repo.
