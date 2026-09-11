# dotfiles CLAUDE.md re-sort — design

**Date:** 2026-09-11
**Parent:** ai-config `docs/superpowers/specs/2026-09-10-claude-md-rearchitecture-design.md`
("dotfiles, sub-project 2") and ai-config ADR-0077 (five content homes, routing sentence),
merged as ai-config#263 and live fleet-wide.
**Prerequisite, met:** dotfiles#261 (`f57c1b36`) — `setup_dotfile_symlinks` never links `rules/`.

## Problem

dotfiles' root `CLAUDE.md` is **156,787 UTF-16 units** and loads in full at the start of every
session in this repo. Measured on `origin/master` at `ce0495f1` with
`len(s.encode("utf-16-le"))//2`. Population: this one file, at that commit.

It only grows. Since 2026-08-11 (`fbf676d6`, 47,565 units), 70 commits on `origin/master`
touched it, 61 of them grew it, and the net change is **+109,222 units**. Population:
`git log --since=2026-08-11 origin/master -- CLAUDE.md`, each commit compared with its parent.

The writers that caused ai-config's growth were routed away by ADR-0077 and are already
live: the `.claude/CLAUDE.md` routing sentence, `tdd.md`, `behavior.md`, and the docs,
learnings, finishing-a-development-branch and worldclass skills. One writer is local to this
file: `CLAUDE.md:402`, "Update this figure whenever tests are added or removed."

Largest blocks (units, same measurement):

| block | units | what it mostly is |
| --- | --- | --- |
| `### Test Seams` | 41,427 | reference: one paragraph per override variable, plus a 10,031-unit cadence table |
| `### Coverage` | 20,042 | 8 dated "Overall: 91%" bullets (~9,900) and 5 "the rule held again" bullets (~3,900); the rest is method |
| `## Key Conventions` | 19,550 | short conventions (~2,100) plus update-section, git-hooks and make-actor internals |
| `## Testing` | 14,220 | commands and hook behaviour plus requirements-ci rendering narrative |
| `## Entry Points` | 11,173 | a 9-row table; every row is exactly 1,002 units because the formatter pads cells to the widest one |
| `## Dependency Automation` | 6,500 | Renovate and Dependabot history and decisions |
| `### ShellCheck`, `### CI / GitHub Actions`, `### MAKEFLAGS…`, `### Mock Pattern` | ~16,300 | reference and history |

Two measurements bound the design:

- **Nothing is duplicated.** Zero paragraphs of 200+ characters appear, by two-window
  normalized substring match, in `~/.claude/standards/*.md`, `~/.claude/CLAUDE.md` or any
  `ai-config/docs/knowledge/dotfiles-*.md`. Every block that leaves must be moved, not
  deduplicated.
- **On-demand homes are read rarely.** The parent spec's transcript census found 4 of 19
  top-level dotfiles sessions (21 days to 2026-09-10) used the `Read` tool on anything under
  `tests/`, `lib/`, `scripts/` or `Makefile`. Population: Mac Studio transcripts, top-level
  sessions only.

## Design

### 1. Homes

The five homes of ADR-0077, applied block by block (approach A). Every moved block is tagged
in the plan as **gate/safety** or **reference**; a gate/safety block keeps a compressed copy
in `CLAUDE.md` (ADR-0077 rule 5), because a knowledge pointer loads only when its trigger
fires and never on a `Write` of a new file.

| block | delete | move to `ai-config/docs/knowledge/` | stays in `CLAUDE.md` |
| --- | --- | --- | --- |
| Coverage | 13 dated bullets; line 402 | method bullets → extend `dotfiles-bash-coverage.md` | floors (bash 91, CI-gated; PowerShell 90) and both measuring commands |
| Test Seams | — | per-variable seams → extend `dotfiles-bats-test-infrastructure.md` (has `## Test Seams`); cadence seams and heartbeat contract → new `dotfiles-cadence-agents.md` | rule-5 lines (below) |
| Mock Pattern, MAKEFLAGS partition | — | extend `dotfiles-bats-test-infrastructure.md` | one line: the guarded/measuring partition is enforced by `tests/scripts/makefile_lint_scope.bats` |
| Testing | dated history | requirements-ci renderings narrative → new `dotfiles-requirements-ci.md` | commands, hook behaviour summary, rule-5 lines |
| ShellCheck, CI | history | CI job and timeout detail → new `dotfiles-ci-jobs.md`; suppression history → `dotfiles-sc2086-site-manifest.md` | suppression rules (compressed); which jobs block auto-merge |
| Key Conventions | dated narrative | update-section coupling, git-hooks sweep, pin probe → extend `dotfiles-update-workflow.md`; make/`PATH` actor matrix → extend `dotfiles-brew-path-presence-guards.md` | short conventions; rule-5 lines |
| Dependency Automation | dated narrative | new `dotfiles-dependency-automation.md` | three one-line decisions: preset inlined, not extended; `pip_requirements` excluded; Dependabot alerts on, auto-PRs off |
| Entry Points | table padding | `update` internals → extend `dotfiles-update-workflow.md` | the nine types as a list, not a table, so the formatter cannot re-pad it |
| Layout, 10-80-10, Symlink Strategy, Profile Model, Adding a New Machine, Local-Only State, GitHub MCP, Code Standards | — | — | stay, lightly compressed |

**Rule-5 lines known before planning** (a floor; the plan's per-block tagging may add more).
Each stays in `CLAUDE.md` as one line:

1. Never modify real system state in tests — use PATH-based mocks from `tests/mocks/`.
2. `make test` must exit 0 before committing.
3. `scripts/pre-push` unsets `GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` below its range-resolution loop, and resolves the repo root with `--show-toplevel` first.
4. Tests drive a binary's absence through its override seam, never by editing `PATH`.
5. Both halves of a seam land in the same commit.
6. Never invoke `scripts/sync_git_repos.sh`, `sync_git_repos` or `sync_legacy_dirs` unmocked outside bats.
7. zsh startup files resolve their own path with `${${(%):-%x}:A:h}`, never `${0:A:h}`; from a worktree, `zsh -i -c exit` checks the main checkout, not the branch.
8. `.warp/settings.toml` keeps `auto_approve_bypasses_command_denylist = false`; a diff flipping it is a sync reversion to re-pin.
9. `config/profiles.zsh` uses `export` and `lib/detect_env.sh` uses `readonly` on purpose, and `tests/helpers/legacy_oracle.bash` is hand-typed on purpose — do not "fix" either.

**Pointer form**, one per destination, grouped at the end of the section it replaces:
`- Before editing <paths>, read ai-config/docs/knowledge/<file>.md.`

**Writers.** Line 402 is deleted with the Coverage records. No other in-repo writer exists.

**Size.** Deletions are estimated at ~22,000 units, moves at ~85,000, and what stays at
45,000–50,000. The bar is `CLAUDE.md` ≤ 50,000 UTF-16 units; above it, the plan compresses
what stays rather than moving a rule-5 line.

### 2. Delivery

1. **ai-config first, direct docs commits to master from a worktree.** Extend the five
   existing knowledge files and create the four new ones with the moved text, verbatim except
   heading level, and append their rows to `docs/knowledge/README.md`. Message the ai-config
   session before writing; its unmerged `feat/memory-digest` touches one file in that area, so
   rows are appended at the end to keep any conflict trivial.
2. **dotfiles on a branch, with PR and full Phase 3.** Delete, move and compress per section 1;
   add pointers. Retarget the code comments that name moved sections:
   `lib/constants.sh:101`, `scripts/cadence-notify.sh:38`, `tests/scripts/osx.bats:17`,
   `tests/zshrc.d/profiles.bats:64`, `tests/scripts/makefile_lint_scope.bats:5`. Those are code
   files, so the push runs the full suite — a `.md`-only push would skip it (ADR-0017). The
   dotfiles PR merges only after step 1's files are on ai-config `origin/master`.
3. **Close-out.** Widen ai-config's backlog row "Measure the CLAUDE.md writer change" to count
   dotfiles' root `CLAUDE.md` too; mark this spec's plan Done.

### 3. Out of scope

- **A Definition of Done section.** `repo-structure.md` requires one and
  `.github/PULL_REQUEST_TEMPLATE.md` points at it, but dotfiles `CLAUDE.md` has none. New
  content, not a sort; backlogged.
- **The dangling `~/.claude/rules` link** into `dotfiles/.claude/rules` and the symlink loop
  linking gitignored runtime state. Both are existing backlog rows; this design adds no
  `.claude/rules/`, so neither blocks it.
- **Standards moves.** None is planned. This spec did not check every block for a generic rule
  the standards lack; the plan's per-block tagging records any it finds and adds a task for it.

## Rejected

- **dotfiles `.claude/rules/`.** The Studio's `~/.claude/rules` (2026-03-31) points at
  `dotfiles/.claude/rules`; a tracked directory there would load as user-level rules in every
  repo until that link is removed on every machine. A code change and a fleet rollout for a home
  read by about one session in five.
- **Nested `tests/CLAUDE.md`.** No leak, but it misses a `Write` of a new test file, which is
  exactly when seam and mock rules matter; the rule-5 copies in `CLAUDE.md` would be needed
  anyway.
- **Move whole sections (B).** Fewer tasks, but the narrative inside Key Conventions and Entry
  Points stays and the 50,000 bar is at risk.
- **Delete first, move later (C).** Two plan cycles and two review rounds for the same end state.
- **Bars of 40,000 or none.** 40,000 forces compressing the pre-read sections; no bar leaves the
  sort without a done condition.

## Verification

Each check states a non-zero expectation, so a check that inspects nothing fails.

1. **Size:** `CLAUDE.md` ≤ 50,000 UTF-16 units at the PR head.
2. **Records gone:** `grep -o 'Overall: 91%' CLAUDE.md | wc -l` is 0 (8 on `ce0495f1`), and `Update this figure` is absent (1 on `ce0495f1`).
3. **Rule-5 lines present:** the plan fixes one grep string per rule-5 line, and each greps at least once in `CLAUDE.md`.
4. **Pointers resolve:** every `dotfiles-*.md` path named in `CLAUDE.md` exists on ai-config
   `origin/master`, checked by a line-wise loop (not a zsh word-split `for`). Controls: one
   misspelled name reports exactly 1 missing; all misspelled reports all of them.
5. **Verbatim moves:** each moved block is a substring of `git show ce0495f1:CLAUDE.md` after
   allowing only a heading-level change.
6. **Gates:** `make lint`, `make check-agent-guidance` and `make test` pass in dotfiles;
   `make validate-knowledge` passes in ai-config.
7. **Entry Points:** the section lists exactly nine `-t` types.
8. **Comments:** none of the five retargeted code comments names a section absent from
   `CLAUDE.md`.
