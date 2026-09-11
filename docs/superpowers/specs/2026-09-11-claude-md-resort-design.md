# dotfiles CLAUDE.md re-sort — design

**Date:** 2026-09-11 (revised after round-1 multi-lens review)
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
| `### Test Seams` | 41,427 | reference: one paragraph per override variable across 25 distinct paths, plus a 10,031-unit cadence table |
| `### Coverage` | 20,042 | 8 dated "Overall: 91%" bullets (~9,900) and 5 "the rule held again" bullets (~3,900); the rest is method |
| `## Key Conventions` | 19,550 | short conventions (~2,100) plus update-section, git-hooks and make-actor internals |
| `## Testing` | 14,220 | commands and hook behaviour plus requirements-ci rendering narrative |
| `## Entry Points` | 11,173 | a 9-row table; every row is exactly 1,002 units because the formatter pads cells to the widest one |
| `## Dependency Automation` | 6,500 | Renovate and Dependabot history and decisions |
| `### ShellCheck`, `### CI / GitHub Actions`, `### MAKEFLAGS…`, `### Mock Pattern`, `### Testing Rules` | ~18,600 | reference, history, and test-writing rules |

Three measurements bound the design:

- **Nothing is duplicated verbatim.** Zero paragraphs of 200+ characters appear, by two-window
  normalized substring match, in `~/.claude/standards/*.md`, `~/.claude/CLAUDE.md` or any
  `ai-config/docs/knowledge/dotfiles-*.md`; reproduced by the goal-fit lens by sentence (0 of
  473). Two near-duplicates exist: the "Pass-through mocks" paragraph is 82% present in
  `dotfiles-bats-test-infrastructure.md` by 8-word shingles, and the zsh `$0` / worktree
  `zsh -i -c exit` rules are already in `shell.md`, which loads in every session.
- **Knowledge files are rarely opened today.** Over 30 days of top-level dotfiles transcripts,
  1 of 28 sessions used `Read` on a `dotfiles-*.md` knowledge file, despite 9 existing pointers.
  Those pointers are `github.com/brujack/ai-config` links to a PRIVATE repo, so a session cannot
  fetch them, and the content they cover is still inline. Population: Mac Studio transcripts.
- **A local, file-specific pointer is followed.** Probe, 2026-09-11: a scratch copy of dotfiles
  with the five awscli seam paragraphs (4,787 units) moved into a knowledge file and replaced by
  one pointer — `Before editing lib/developer.sh (update_aws_cli, _aws_verify_zip, …) or their
  tests in tests/setup_env/developer.bats, read <absolute path>` — and `claude -p` asked five
  times to plan a test for `update_aws_cli`'s missing-gpg branch. **5 of 5** runs `Read` the
  knowledge file before any other file and named `_AWS_GPG_BIN`. Two control runs with the text
  inline named it too, because the seam is also visible in `lib/developer.sh`. Population:
  non-interactive `claude -p --setting-sources project,local`, read-only tools
  (`Read,Grep,Glob`), one subsystem, a prompt naming the function, Claude Code 2.1.267. It does
  not cover interactive sessions, `Write`-first work, or a prompt that does not name the
  pointer's files.

## Design

### 1. Homes

The five homes of ADR-0077, applied block by block. Every block of 200+ characters is listed in
the plan's **block manifest** with exactly one disposition: `stay`, `compress`, `move:<file>`,
`dedupe:<file>` or `delete`, and a `rule5` flag.

**Rule-5 criterion.** A block keeps a one-line copy in `CLAUDE.md` when any of these hold:
it states a gate or safety rule; it is a deliberate deviation no test pins; or the moment it
matters is not an edit of a nameable file (a tool rewriting a tracked file, creating a new test
with `Write`, choosing where a new test goes). Everything else is reference.

| block | delete | move (to `~/git-repos/personal/ai-config/docs/knowledge/`) | stays in `CLAUDE.md` |
| --- | --- | --- | --- |
| Coverage | 13 dated bullets; line 402 | method bullets and the "a lone red on bats test 341 is a re-run candidate" note → extend `dotfiles-bash-coverage.md` | floors (bash 91, CI-gated; PowerShell 90) and both measuring commands |
| Test Seams | — | split by subsystem so each pointer names at most six files: awscli verification → new `dotfiles-seams-awscli.md`; zsh/shell startup (`profiles.zsh`, keychain, gnubin, Homebrew prefix, Docker bin) → new `dotfiles-seams-shell-startup.md`; hooks, coverage tracer and workflows (`GGSHIELD_*`, `_OVERRIDE_LIB_TRAP_SCOPE`, `_OVERRIDE_BATS_BIN`, `_OVERRIDE_RUN_TMPDIR_ROOT`, `_PROFILES_LOADED`) → new `dotfiles-seams-hooks-and-tracer.md`; cadence seams and heartbeat contract → new `dotfiles-cadence-agents.md` | rule-5 lines |
| Mock Pattern | "Pass-through mocks" (dedupe into existing text) | remainder → extend `dotfiles-bats-test-infrastructure.md` | — |
| MAKEFLAGS partition | — | new `dotfiles-makeflags-partition.md` | rule-5 line 10 |
| Testing Rules | — | the two `load_setup_env`/`run_update` explanations → extend `dotfiles-bats-test-infrastructure.md` | rule-5 lines 1, 2, 7, 8 and the rename/grep bullet |
| Testing | dated history | requirements-ci renderings narrative → new `dotfiles-requirements-ci.md` | commands, hook behaviour summary, rule-5 lines 3 and 11 |
| ShellCheck, CI | history → appended to `dotfiles-sc2086-site-manifest.md` with no pointer | CI job and timeout detail → new `dotfiles-ci-jobs.md` | suppression rules (compressed); which jobs block auto-merge |
| Key Conventions | dated narrative | update-section coupling, git-hooks sweep, pin probe → extend `dotfiles-update-workflow.md`; make/`PATH` actor matrix → extend `dotfiles-brew-path-presence-guards.md` | short conventions; rule-5 lines 6, 12 and 13 |
| Dependency Automation | dated narrative | new `dotfiles-dependency-automation.md` | three one-line decisions: preset inlined, not extended; `pip_requirements` excluded; Dependabot alerts on, auto-PRs off |
| Entry Points | table padding | `update` internals → extend `dotfiles-update-workflow.md` (recorded in the manifest as `transform`, since a table cell becomes prose) | the nine types as a list, not a table, so the formatter cannot re-pad it |
| Layout, 10-80-10, Symlink Strategy, Profile Model, Adding a New Machine, Local-Only State, GitHub MCP, Code Standards | — | — | stay, lightly compressed |

**Destinations named by a pointer:** 4 extended (`dotfiles-bash-coverage.md`,
`dotfiles-bats-test-infrastructure.md`, `dotfiles-update-workflow.md`,
`dotfiles-brew-path-presence-guards.md`) and 8 new (`dotfiles-seams-awscli.md`,
`dotfiles-seams-shell-startup.md`, `dotfiles-seams-hooks-and-tracer.md`,
`dotfiles-cadence-agents.md`, `dotfiles-makeflags-partition.md`, `dotfiles-requirements-ci.md`,
`dotfiles-ci-jobs.md`, `dotfiles-dependency-automation.md`). The two existing pointers to
`dotfiles-brewfile-conventions.md` and `dotfiles-ruby-version-manager.md` stay, converted to the
local path. `dotfiles-sc2086-site-manifest.md` (125,240 units) receives history but no pointer.
The plan may regroup the seam files if a pointer would otherwise name more than six files; check 4
uses the plan's final list.

**Rule-5 lines** (a floor; the manifest may add more). Each stays in `CLAUDE.md` as one line:

1. Never modify real system state in tests — use PATH-based mocks from `tests/mocks/`.
2. `make test` must exit 0 before committing.
3. `scripts/pre-push` unsets `GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` below its range-resolution loop, and resolves the repo root with `--show-toplevel` first.
4. Tests drive a binary's absence through its override seam, never by editing `PATH`.
5. Both halves of a seam land in the same commit.
6. Never invoke `scripts/sync_git_repos.sh`, `sync_git_repos` or `sync_legacy_dirs` unmocked outside bats.
7. `load_setup_env()` does not set `MACOS`/`LINUX`/`UBUNTU`/`HAS_*`; a test that depends on OS detection sets them or calls `detect_env`.
8. A new `setup_env.sh` function gets a test in `tests/setup_env/unit.bats` (pure logic) or `install_guards.bats` (side effects); a new script gets its own `tests/` directory.
9. `.warp/settings.toml` keeps `auto_approve_bypasses_command_denylist = false`; a diff flipping it is a sync reversion to re-pin.
10. A test that wants an exact `make` output value must be **guarded** (`--no-print-directory`), not measuring; `makefile_lint_scope.bats` accepts either category, so it does not catch this.
11. Roll the ansible venv back with `pip install --no-deps -r <snapshot>`; `uv sync` cannot reproduce the pre-sync state.
12. If Docker Desktop's installer adds lines to `.zprofile`, delete them rather than committing them.
13. `setup_env.sh` cannot run non-interactively on the Linux workstation; prepend `/home/linuxbrew/.linuxbrew/bin` to `PATH` rather than re-bootstrapping.
14. `config/profiles.zsh` uses `export` and `lib/detect_env.sh` uses `readonly` on purpose, and `tests/helpers/legacy_oracle.bash` is hand-typed on purpose — do not "fix" either.

The previous rule 7 (zsh `$0` and worktree `zsh -i -c exit`) is dropped: `shell.md` already
states both and loads in every session.

**Pointer form**, one per destination, grouped at the end of the section it replaces, naming
at most six files or functions and using the local path, which exists on both development
machines: `- Before editing <files>, read ~/git-repos/personal/ai-config/docs/knowledge/<file>.md.`
The seven existing `github.com/brujack/ai-config` links are replaced with that form.

**Writers.** Line 402 is deleted with the Coverage records. No other in-repo writer exists.

**Size.** Deletions are estimated at ~22,000 units, moves at ~85,000, and what stays at
45,000–50,000 including the five added rule-5 lines. The bar is `CLAUDE.md` ≤ 50,000 UTF-16
units; above it, the plan compresses what stays rather than moving a rule-5 line.

### 2. Delivery

1. **ai-config first, direct docs commits to master from a worktree.** Extend the four existing
   knowledge files, create the eight new ones, append the suppression history to
   `dotfiles-sc2086-site-manifest.md`, and add index rows under `### dotfiles` in
   `docs/knowledge/README.md` — for the eight new files and for the two existing files that
   lack rows (`dotfiles-sc2086-site-manifest.md`, `dotfiles-brew-path-presence-guards.md`).
   Moved text is verbatim except heading level and the manifest's `transform` entries. Message
   the ai-config session before writing.
2. **dotfiles on a branch, with PR and full Phase 3.** Apply the manifest; add pointers; replace
   the seven GitHub links. Retarget the code comments that name moved sections:
   `lib/constants.sh:101`, `scripts/cadence-notify.sh:38`, `tests/scripts/osx.bats:17`,
   `tests/zshrc.d/profiles.bats:64`, `tests/scripts/makefile_lint_scope.bats:5`. These five are
   the full set: `git grep -n 'CLAUDE.md' -- ':!*.md'` also finds
   `tests/setup_env/profiles.bats:465`, which names "Adding a New Machine", a section that stays.
   Those are code files, so the push runs the full suite. **Check 4 runs against ai-config
   `origin/master` before `gh pr create`**, because dotfiles auto-merge waits only on CI.
3. **Close-out.** Widen ai-config's backlog row "Measure the CLAUDE.md writer change" to count
   dotfiles' root `CLAUDE.md` in both step 3 (growth) and step 4 (pointer follow rate); mark this
   spec's plan Done.

### 3. Out of scope

- **A Definition of Done section.** `repo-structure.md` requires one and
  `.github/PULL_REQUEST_TEMPLATE.md` points at it, but dotfiles `CLAUDE.md` has none. New
  content, not a sort; backlogged.
- **The dangling `~/.claude/rules` link** into `dotfiles/.claude/rules` and the symlink loop
  linking gitignored runtime state. Both are existing backlog rows; this design adds no
  `.claude/rules/`, so neither blocks it.
- **Standards moves.** None is planned. The manifest records any generic rule the standards lack
  and the plan adds a task for it.

## Rejected

- **dotfiles `.claude/rules/`.** The Studio's `~/.claude/rules` (2026-03-31) points at
  `dotfiles/.claude/rules`; a tracked directory there would load as user-level rules in every
  repo until that link is removed on every machine.
- **Nested `tests/CLAUDE.md`.** No leak, but it misses a `Write` of a new test file, which is
  exactly when seam and mock rules matter; the rule-5 copies would be needed anyway.
- **One knowledge file for all seams.** Its pointer would name 25 paths or "any code file", and
  the file would reach about 71,000 units with two parallel sections on the same topic.
- **Move whole sections.** Fewer tasks, but the narrative inside Key Conventions and Entry Points
  stays and the 50,000 bar is at risk.
- **Delete first, move later.** Two plan cycles and two review rounds for the same end state.
- **Bars of 40,000 or none.** 40,000 forces compressing the pre-read sections; no bar leaves the
  sort without a done condition.

## Verification

Each check names a specific non-zero expectation or a control that fails on an empty result.

1. **Size:** `CLAUDE.md` ≤ 50,000 UTF-16 units at the PR head, and ≥ 20,000 (a near-empty file fails).
2. **Records gone:** `grep -o 'Overall: 91%' CLAUDE.md | wc -l` is 0 (8 on `ce0495f1`), and
   `Update this figure` is absent (1 on `ce0495f1`).
3. **Rule-5 lines present:** the plan fixes one grep string per rule-5 line, at least 14 strings,
   and each greps at least once in `CLAUDE.md`.
4. **Pointers resolve:** `CLAUDE.md` names exactly the plan's final list of pointer destinations
   (at least 14 distinct `dotfiles-*.md` paths, all under `~/git-repos/personal/ai-config/`), and
   each exists on ai-config `origin/master`, checked by a line-wise loop, not a zsh word-split
   `for`. Controls: one misspelled name reports exactly 1 missing; all misspelled reports the full
   count. No `github.com/brujack/ai-config` link remains.
5. **Moves landed:** for every manifest entry `move:` or `dedupe:`, the block is a substring of its
   named destination on ai-config `origin/master` after allowing only a heading-level change; the
   number found equals the number of such entries, and their total is at least 80,000 units.
   `transform` entries are checked by the reviewer against their source cell instead.
6. **Nothing lost:** every one of the 143 paragraphs of 200+ characters in
   `ce0495f1:CLAUDE.md` appears in the manifest, and each `stay`/`compress` entry's lead sentence
   is in the new `CLAUDE.md`, each `move`/`dedupe` entry is in its destination, and each `delete`
   entry is on the manifest's deletion list. Expect 0 unaccounted and report the count per bucket.
   Control: removing one entry from the manifest reports exactly 1 unaccounted.
7. **Gates:** `make lint`, `make check-agent-guidance` and `make test` pass in dotfiles;
   `make validate-knowledge` passes in ai-config.
8. **Entry Points:** the section lists exactly nine `-t` types.
9. **Comments:** none of the five retargeted code comments names a section absent from
   `CLAUDE.md`, and `git grep -n 'CLAUDE.md' -- ':!*.md'` returns the same six lines, five
   retargeted plus `profiles.bats:465`.

## Multi-Lens Review

Reviewed at commit: `c9ac2808` (Step 7 self-review commit, before Step 8 dispatch). Adversarial
Spec Review: N/A — no comparison, judge or evaluator component, and every acceptance criterion
is a command.

### Goal-Fit

Finding: Worth building, and there is no simpler path. Deleting records, line 402 and table
padding alone reaches only about 135,000 units. Premises reproduced independently: 156,787 units,
the 1,002-unit Entry Points rows, and "nothing is duplicated" (0 of 473 sentences of 120+
characters matched elsewhere). Load-bearing defect: a pure-deletion implementation passes all
eight checks. Check 4 has no minimum count, and check 5 iterates "each moved block" with no count
and compares against the old file, never the destination. Proposed: a moved-block manifest
naming each destination file; each block present in its named file on ai-config `origin/master`,
with the count equal to the manifest length and at least ~80,000 units found; exactly 9 distinct
destination names in `CLAUDE.md`. Reads-it test: the knowledge moves only change a decision if a
pointer is followed. Over 30 days of top-level dotfiles transcripts (28 sessions), 1 used `Read`
on any `dotfiles-*.md` knowledge file, despite 9 existing pointers to 5 of them. Nothing will
measure follow-through afterward either: the close-out widens the parent's step 3 (growth) to
dotfiles but not step 4 (pointer follow rate). The other candidates for rule 5: the venv-snapshot
rollback's `--no-deps` and `setup_env.sh`'s non-interactive refusal on the Linux workstation.
Assumption: a session about to edit a path named in a `Before editing <paths>, read …` pointer
opens that knowledge file. If false, the ~85,000 moved units are archived rather than consulted,
and verbatim moves across two repos buy nothing over deletion plus rule-5 lines. Settle after
landing with a widened step 4; ai-config's own step-4 reading for the same pointer style is an
earlier proxy.
Disposition: Addressed (operator, 2026-09-11) — block manifest with checks 5 and 6 (moves landed, nothing lost, counts and a control); check 4 fixes the destination count; step 4 widened to dotfiles; `--no-deps` rollback and the workstation non-interactive refusal added to rule 5. The pointer-follow assumption was probed before revising: 5 of 5 runs read a local, file-specific pointer's target (see Problem).

### Ergonomics

Finding: Five findings, two load-bearing.
- **One pointer cannot cover the per-variable seams.** They name 25 distinct paths across
  `lib/`, `scripts/`, `tests/`, `config/` and `.config/` (23,109 units). One pointer either lists
  all 25 paths or globs "any code file". The destination would also grow from 40,775 to about
  71,357 units, with two parallel `## Test Seams` and `## Mock Pattern` sections. Split the
  destination by subsystem so each pointer names a few files: awscli verification, zsh startup,
  hooks and coverage tracer, test mocks. Cadence is already split this way.
- **The pointer path does not resolve.** `ai-config/docs/knowledge/<file>.md` is relative, and
  dotfiles has no `ai-config/` directory. The 7 existing GitHub links cannot be fetched either:
  `brujack/ai-config` is PRIVATE. Use `~/git-repos/personal/ai-config/docs/knowledge/…`, which
  exists on both development machines (verified by the orchestrator), and have the plan replace
  the existing links.
- **The rule-5 criterion misses notes whose trigger is not an edit.** The Docker Desktop line
  ("If the installer's `.zprofile` lines reappear, delete them rather than committing them") has
  the same shape as rule 8, no test pins it, and no "Before editing" pointer can fire for it.
  Name the criterion: a deliberate deviation not pinned by a test, or one whose trigger is not an
  edit, is rule 5.
- **The checks pass when nothing is done.** Only check 7 and check 4's misspelling control carry
  specific non-zero expectations. Needed: check 4 expects exactly 9 paths, check 3 expects at
  least 9 strings, and a reverse check shows every non-deleted block of `ce0495f1` is a substring
  of the new `CLAUDE.md` or one of the 9 files.
- **Minor:** `dotfiles-sc2086-site-manifest.md` is 125,240 units; give it no pointer.

Also found, harmless: `tests/setup_env/profiles.bats:465` names "Adding a New Machine", which
stays.
Assumption: a pointer in dotfiles `CLAUDE.md` is followed by the session or subagent that edits
the named file. 5 of the last 21 days' dotfiles sessions that edited `tests/`, `lib/` or
`scripts/` (7 in 60 days, subagents included) opened 0 `dotfiles-*` knowledge files. That proves
little while the content is still inline and the links cannot be fetched. Settle with a probe
after the files land: one local-path pointer, `claude -p "add a test for update_aws_cli's
missing-gpg branch"` several times including via a subagent, counting runs that `Read` the file
before the first `Edit`/`Write`.
Disposition: Addressed (operator, 2026-09-11) — seams split into subsystem files with pointers naming at most six files; local `~/git-repos/personal/ai-config/...` path and replacement of the seven GitHub links; rule-5 criterion stated, Docker `.zprofile` line added; fixed counts on checks 3 and 4 and a reverse (nothing lost) check; the sc2086 manifest gets no pointer; `profiles.bats:465` named as intentionally unchanged.

### Risk

Finding: Nothing proves that every removed paragraph landed somewhere, and `### Testing Rules`
demonstrates it. That section (master `CLAUDE.md:365-375`) has no row in the homes table. Two
rule-5 lines come from it, and its other six bullets have no stated home. Five of the eight checks
pass on an empty result, so the spec's "each check states a non-zero expectation" is false.
Proposed accounting check: each of the 143 paragraphs of 200+ characters in `ce0495f1:CLAUDE.md`
lands in the new `CLAUDE.md`, a knowledge file or a named deletion list. Expect 0 unaccounted,
report every bucket's count, and use one dropped paragraph as a control that reports 1.

**Rule-5 content outside the nine:**
- `:367`: `load_setup_env()` does not set OS vars, so a test must set them or call `detect_env`.
- `:369`, `:371`: where a new function's test and a new script's test directory go.
- `:613`: the Docker `.zprofile` line.
- `:866`: a case that merely wants an exact value must be *guarded*. The compressed "enforced by
  `makefile_lint_scope.bats`" claims more than the test enforces: `:678` accepts either category,
  so the mistake that shipped passes it.

**Cross-repo ordering is not enforced.** dotfiles `auto-merge` waits only on CI, so check 4 must
run before `gh pr create`, or the PR must open without auto-merge.

**Knowledge README.** It is grouped by repo (`### dotfiles` at :50, `### terraform-ansible`
last), so rows appended at the end are misfiled. The feared conflict does not exist either:
`feat/memory-digest` adds lines inside `### ai-config`. `validate_knowledge.py` skips the README,
which already lacks rows for `dotfiles-sc2086-site-manifest.md` and
`dotfiles-brew-path-presence-guards.md`.

**Check 5 cannot pass as written for the `update` internals.** A padded table cell turned into
prose is not a substring, and the ai-config PostToolUse formatter may re-pad moved table fragments.

**Deletions that carry a rule:** `:411`, "treat a lone red there [bats test 341] as a re-run
candidate", appears nowhere else. Route it to `dotfiles-bash-coverage.md`.

**Premise holds, with exceptions:**
- 0 paragraph and 0 sentence matches, but an 8-word shingle comparison shows `:847`
  ("Pass-through mocks") is 82% present in `dotfiles-bats-test-infrastructure.md`. Dedupe rather
  than duplicate it.
- Rule 7 is already loaded from `shell.md` (zsh `$0`, and worktree `zsh -i -c exit`).

Assumption: pointer follow-through, as the other two lenses found. ADR-0077's one-in-five figure
counts `Read`s under code paths, not pointer following; if follow-through is near zero every move
is a deletion and each misclassified paragraph is a silent loss. Measurable now against today's
pointers: over 21 days of Studio top-level dotfiles transcripts, count sessions that edited a path
those pointers cover and how many `Read` the pointed-to file.
Disposition: Addressed (operator, 2026-09-11) — accounting check 6 over every 200+ character paragraph with a control; Testing Rules row and rule-5 lines 7, 8, 10 and 12 added, with the MAKEFLAGS qualifier kept; check 4 runs before `gh pr create`; README rows go under `### dotfiles` plus the two missing rows; `transform` entries for the table-cell move; the test-341 note routed to `dotfiles-bash-coverage.md`; Pass-through mocks deduped; rule 7 dropped as already in `shell.md`.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
