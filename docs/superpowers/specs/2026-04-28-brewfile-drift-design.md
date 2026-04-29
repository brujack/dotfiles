# Brewfile Drift Detection — Design Spec

## Context

Running `setup_env.sh -t update` frequently means ad-hoc `brew install` invocations
accumulate over time without making it back into the Brewfile, and Brewfile entries
for uninstalled packages silently linger. There is currently no automated way to
surface this drift.

## Goal

Detect and report drift between the Brewfile manifest and locally installed Homebrew
packages as part of every update run, alongside the existing per-section summary.

## Decision

Add a `brew-drift` section to the update summary infrastructure. It runs at the end
of `run_update()` (just before `_update_summary`), gated on `command -v brew`. Works
on both macOS and Linux wherever Homebrew is installed.

Introduce a `WARN` status to the summary system — non-blocking, visible, and
reusable by future advisory checks.

---

## Scope

| Category | Platforms     | Source             | Actual state          |
| -------- | ------------- | ------------------ | --------------------- |
| Formulae | macOS + Linux | `brew "..."` lines | `brew list --formula` |
| Casks    | macOS only    | `cask "..."` lines | `brew list --cask`    |
| Taps     | macOS + Linux | `tap "..."` lines  | `brew tap`            |
| MAS      | —             | out of scope       | —                     |

Two drift directions:

- **Untracked** — installed locally but absent from Brewfile (ad-hoc installs to commit)
- **Missing** — listed in Brewfile but not installed locally (manifest ahead of reality)

---

## Output Format

When drift exists:

```
[WARN] brew-drift      2 untracked formulae, 1 missing tap

brew-drift details:
  Untracked (installed, not in Brewfile):
    bat
    jq
  Missing (in Brewfile, not installed):
    tap: teamookla/speedtest
```

When clean:

```
[OK]   brew-drift      formulae clean, casks clean, taps clean
```

On Linux (no cask support), the clean message omits casks:

```
[OK]   brew-drift      formulae clean, taps clean
```

When brew or Brewfile unavailable:

```
[SKIP] brew-drift      brew not available
[SKIP] brew-drift      Brewfile not found at /path/to/Brewfile
```

---

## Architecture

### `lib/update_summary.sh`

**`_UPDATE_SECTION_ORDER`** — append `brew-drift` after `cheat.sh`.

**`_update_summary` — WARN status support:**

- Add `WARN` branch to the case statement: `[WARN] %-16s %s`
- WARN items increment a new `_warn` counter (not `_fail`)
- Summary footer changes from `N OK, N failed, N skipped` to
  `N sections: N OK, N failed, N warnings, N skipped`
- After printing the table, iterate `_UPDATE_SECTION_ORDER`; for each section whose
  `detail_<section>` file exists in `_UPDATE_TMPDIR`, print its contents to terminal
  and to the log (preserves deterministic section order)

**`_update_check_brewfile_drift`** — new function:

```
_update_check_brewfile_drift() {
  1. Gate: command -v brew || _update_skip "brew-drift" "brew not available"; return 0
  2. Resolve Brewfile path via seam:
       local _brewfile="${_OVERRIDE_BREWFILE_PATH:-${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile}"
  3. Gate: [[ -f "${_brewfile}" ]] || _update_skip "brew-drift" "Brewfile not found at ${_brewfile}"; return 0
  4. Parse Brewfile:
       _bf_formulae — sorted list from `brew "..."` lines
       _bf_casks    — sorted list from `cask "..."` lines
       _bf_taps     — sorted list from `tap "..."` lines
  5. Get actual state:
       _installed_formulae — brew list --formula | sort
       _installed_casks    — brew list --cask | sort  (macOS only)
       _installed_taps     — brew tap | sort
  6. Compute diff (comm -23 / comm -13):
       untracked_formulae, missing_formulae
       untracked_casks, missing_casks     (macOS only)
       untracked_taps, missing_taps
  7. Build summary string and optional detail file
  8. If any drift: _update_warn "brew-drift" "<summary>"; write detail_brew-drift
     If clean:     _update_ok   "brew-drift" "formulae clean[, casks clean], taps clean"
}
```

Add `_update_warn` as a new helper alongside `_update_ok` and `_update_skip`:

```bash
_update_warn() {
  local _section="$1" _msg="$2"
  printf "WARN\n"  > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_UPDATE_TMPDIR}/result_${_section}"
}
```

### `lib/workflows.sh`

In `run_update()`, call `_update_check_brewfile_drift` immediately before `_update_summary`:

```bash
  # ── drift check ───────────────────────────────────────────────────────────
  _update_check_brewfile_drift

  # ── summary ───────────────────────────────────────────────────────────────
  _update_summary
```

---

## Test Seam

```bash
local _brewfile="${_OVERRIDE_BREWFILE_PATH:-${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile}"
```

Tests write a temp Brewfile to `BATS_TEST_TMPDIR` and export `_OVERRIDE_BREWFILE_PATH`
pointing to it. Add to CLAUDE.md seam table.

---

## Testing

New file: `tests/setup_env/brewfile_drift.bats`

Each test sets up `_UPDATE_TMPDIR` (to `BATS_TEST_TMPDIR`) and a temp Brewfile, then
sources the lib via the standard `load_setup_env` helper.

| Test | Scenario                                            | Expected                                              |
| ---- | --------------------------------------------------- | ----------------------------------------------------- |
| 1    | No drift (formulae/casks/taps all match)            | status=OK, result contains "clean"                    |
| 2    | Untracked formula                                   | status=WARN, detail lists untracked formula           |
| 3    | Missing formula                                     | status=WARN, detail lists missing formula             |
| 4    | Untracked tap                                       | status=WARN, detail lists untracked tap               |
| 5    | Missing tap                                         | status=WARN, detail lists missing tap                 |
| 6    | Missing cask (macOS)                                | status=WARN, detail lists missing cask                |
| 7    | Untracked cask (macOS)                              | status=WARN, detail lists untracked cask              |
| 8    | Mixed drift (untracked + missing across categories) | status=WARN, all items in one detail block            |
| 9    | Brew not available                                  | status=SKIP, result "brew not available"              |
| 10   | Brewfile not found                                  | status=SKIP, result includes path                     |
| 11   | Linux (MACOS unset)                                 | status=OK, casks not checked, no cask lines in result |
| 12   | `_update_summary` WARN branch                       | `[WARN]` prefix printed; WARN counted in footer       |
| 13   | `_update_summary` detail block                      | detail file contents printed after table              |

---

## Constraints

- No logic changes to existing update sections
- `WARN` status is non-blocking — `run_update` exits 0 regardless of drift
- Cask check guarded by `[[ -n ${MACOS:-} ]]`
- Brewfile parsing uses `grep` + `sed`; no external tools beyond standard POSIX utils and brew itself
- Drift check is read-only — it never modifies the Brewfile or installs/removes packages
