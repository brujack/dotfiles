---
name: coverage-update-summary-casks
description: Raise update_summary.sh from 82% to 90% by fixing coverage tool exclusions and adding tests for uncovered logic paths
metadata:
  type: project
---

# Coverage: update_summary.sh — Cask Drift and Fallback Paths

## Status: Accepted

## Context

`update_summary.sh` sits at 82% (319/386 coverable lines). The 90% floor requires 347+ covered lines — a gap of 28.

Two distinct root causes:

**1. Coverage tool doesn't exclude case labels or `done <…` variants.**  
Bash xtrace never emits these structural lines as trace events, but `run-bash-coverage.sh` counts them as coverable. Affected patterns:

- Case branch labels: `brew)`, `mas)`, `OK)`, etc. — 29 lines across `_update_record_start`, `_update_record_end`, `_update_summary`
- `done <<< "${var}"` — 6 lines in `_update_check_brewfile_drift` detail loops (the "cask drift detail loops" named in the backlog)
- `done < <(cmd)` — 4 lines in `_brewfile_parse_section` / `_brewfile_parse_inactive`
- Multi-line pipeline tail lines (`> outfile || true` ending a split pipeline) — ~8 lines

Total structural non-coverable lines: ~47. Excluding them: 319/(386−47) = 94% with zero new tests.

**2. Actually uncovered code paths (real missing tests).**

| Location                                   | Uncovered line                                          | Missing scenario                                        |
| ------------------------------------------ | ------------------------------------------------------- | ------------------------------------------------------- |
| `_update_record_end "brew"`                | `[[ -n "${_result}" ]] && …` (line 166)                 | Cask changes detected; `_cask_count > 0` never entered  |
| `_update_record_end "brew"`                | `_result=… cask(s) (…)` (line 167)                      | Same                                                    |
| `_update_record_end "gems"`                | `_result="updated"` (line 203)                          | No test when `pre_gems` doesn't exist                   |
| `_update_record_end "pip"`                 | `_result="no changes"` (line 213)                       | No test when `pip_outdated` exists but is empty         |
| `_update_record_end "pip"`                 | `_result="updated"` (line 216)                          | No test when `pip_outdated` absent                      |
| `_update_record_end "zsh-autosuggestions"` | inner case `zsh-autosuggestions) _git_dir=…` (line 227) | Only test has no pre-snapshot; inner case never reached |
| `_update_record_end "softwareupdate"`      | `_result="updated"` (line 252)                          | No test when `pre_softwareupdate` absent                |
| `_update_record_end "claude"`              | `_result="updated"` (line 271)                          | No test when `pre_claude` absent                        |
| `_update_record_end "snap"`                | `_result="updated"` (line 332)                          | No test when `pre_snap` absent                          |

## Decision

**Fix both.**

### Part 1 — Coverage tool exclusion patterns

Extend the exclusion loop in `scripts/run-bash-coverage.sh` to skip:

1. **Case branch labels** — lines matching `WORD)` or `WORD|WORD)` or `*)` patterns (words ending in `)` with no other structure):

   ```bash
   # Case labels: bash xtrace never emits them as separate events
   [[ "${trimmed}" =~ ^\*?\)$ ]] && continue                        # bare *)
   [[ "${trimmed}" =~ ^[a-zA-Z_][a-zA-Z0-9_|/.*:-]*\)$ ]] && continue  # word)
   ```

2. **`done` with redirections** — `done <<< "..."`, `done < <(...)`, `done < "${file}"`:

   ```bash
   # done with any redirect: structurally identical to bare done
   [[ "${trimmed}" =~ ^done[[:space:]] ]] && continue
   ```

3. **Multi-line pipeline tail lines** — lines that are pure redirections (`> file`, `| cmd`), which are continuation lines of a split pipeline that xtrace traces only on its first line. These have no leading command verb:
   ```bash
   # Continuation lines of multi-line pipelines
   [[ "${trimmed}" =~ ^\> ]] && continue
   ```

### Part 2 — New tests in `tests/setup_env/update_summary.bats`

Add 9 new `@test` blocks:

1. `_update_record_end "brew"` casks-only update (formula_count=0, cask_count>0) → result = "N cask(s) (…)"
2. `_update_record_end "brew"` formulae+casks update → result contains both, separated by `\n`
3. `_update_record_end "gems"` no pre-snapshot → result = "updated"
4. `_update_record_end "pip"` empty pip_outdated → result = "no changes"
5. `_update_record_end "pip"` no pip_outdated → result = "updated"
6. `_update_record_end "zsh-autosuggestions"` with pre-snapshot + inline `_update_git_diff` stub → result = "N commit(s)"
7. `_update_record_end "softwareupdate"` no pre-snapshot → result = "updated"
8. `_update_record_end "claude"` no pre-snapshot → result = "updated"
9. `_update_record_end "snap"` no pre-snapshot → result = "updated"

## Consequences

- Coverage tool is more accurate for any shell file using `case` statements
- `update_summary.sh` reported coverage rises from 82% to ~90%+
- Edge-case fallback paths ("updated" result when no pre-snapshot exists) are now tested
- Brew cask tracking in `_update_record_end` is verified to work correctly

## Related

- Backlog item: `coverage-update-summary-casks`
- Coverage measurement: `make bash-coverage`
- Companion backlog: `coverage-helpers-gaps-2` (next target)
