# dotfiles CLAUDE.md re-sort — design

**Date:** 2026-09-11 (descoped after round-2 review and a second probe)
**Parent:** ai-config `docs/superpowers/specs/2026-09-10-claude-md-rearchitecture-design.md`
("dotfiles, sub-project 2") and ai-config ADR-0077 (five content homes, routing sentence),
merged as ai-config#263 and live fleet-wide.
**Scope decision (operator, 2026-09-11):** ship only the subset every review round found clean —
delete measurement records, flatten the padded Entry Points table, and replace unfetchable
GitHub links with local paths. Moving reference text into knowledge files is deferred to its
own spec (see "Deferred").

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

All changes are to dotfiles `CLAUDE.md`, plus one appended paragraph in ai-config
`docs/knowledge/dotfiles-bash-coverage.md`. Line references are to `origin/master` at `e9ea9515`,
whose `CLAUDE.md` is byte-identical to `ce0495f1`'s.

### 1. Delete the bash coverage records, routing the rules they carry

`#### Bash` under `### Coverage` holds 20 bullets before `- make bash-coverage measures`. Twelve
are records (12,043 units): the eight `**Overall: 91%**` bullets and the four "local reads one
point higher" bullets (`The local-reads-one-point-higher rule did NOT hold on #244`,
`91% has now landed exactly at the floor on the fifth consecutive CI measurement`,
`The preview discipline paid a fourth time`, `And a fifth time, on #223`). All twelve are
deleted. The eight method bullets after them stay.

Five rule-bearing sentences inside those twelve are routed before deletion, not lost:

| rule | already stated elsewhere | action |
| --- | --- | --- |
| Publish CI's coverage figure, never a local one | `~/.claude/standards/shell.md:1432-1433` (ADR-0061) | none |
| Read the ratio, the heuristic-disagreement count and the test count from one CI run | no | append to `dotfiles-bash-coverage.md` |
| A local preview can differ from CI in either direction (#244, #250, #252, #257) | no | append to `dotfiles-bash-coverage.md` |
| CI bash coverage sits at the 91% floor, so a change adding untested instrumented lines breaches the gate immediately | no | append to `dotfiles-bash-coverage.md` |
| A lone red on bats test `extract_new_content: no false positives when state is 20KB-truncated subset of current` is a known flake; re-run before treating it as a regression | no | append to `dotfiles-bash-coverage.md` |

The appended text is one `## Reading the bash coverage figure` section, written as a short
reference paragraph; it quotes no per-PR figures.

### 2. Delete the other two recorded figures and the local writer

- PowerShell: delete `- **setup_windows.ps1: 95.54%** (line coverage, …)` and
  `- Update this figure whenever tests are added or removed.` (line 402). The floor, scope and
  re-measure bullets stay.
- CI: in the `test` job bullet, delete the parenthetical figure
  `(regression proxy; 1626 tests, CI-measured 2026-09-10 on 1d309276, …)`, keeping
  `verifies test count >= 840`.

### 3. Entry Points table to a list

The nine-row `| Type | Purpose |` table becomes nine bullets, `- ` + the backticked type +
` — ` + the purpose cell, cell text unchanged. The formatter pads every table cell to the widest
one, so all nine rows are exactly 1,002 units; 6,328 units are padding. A list cannot be re-padded
by a later `Edit`. `**Options:**` and its bullet stay. Edits use a script, not the Edit tool.

### 4. Local paths for knowledge links

The seven `[…](https://github.com/brujack/ai-config/blob/…/docs/knowledge/<file>.md)` links (to five
distinct files) become `` `~/git-repos/personal/ai-config/docs/knowledge/<file>.md` ``.
`brujack/ai-config` is PRIVATE, so a session cannot fetch the GitHub form; the local path exists on
the Mac Studio and the Linux workstation. All five target files exist.

### Size

156,787 → about 138,100 UTF-16 units (12,043 records, 6,328 padding, about 300 for the other
figures and link text). The ≤ 50,000 bar belongs to the deferred move work, not this change.

## Delivery

1. **ai-config first**: append the `## Reading the bash coverage figure` section to
   `docs/knowledge/dotfiles-bash-coverage.md` as a direct docs commit to master from a worktree,
   after messaging the ai-config session.
2. **dotfiles**: one scripted commit to `CLAUDE.md` on a branch from a worktree, pushed direct to
   master. It is docs-only: the pre-push hook skips a `.md`-only push (ADR-0017), and no code
   comment names a changed section.
3. **Close-out**: widen ai-config's backlog row "Measure the CLAUDE.md writer change" to count
   dotfiles' root `CLAUDE.md` in step 3 (growth); mark this spec's plan Done.

## Out of scope

- Moving reference text to knowledge files, rule-5 copies and pointers (see "Deferred").
- A Definition of Done section (backlog row).
- The dangling `~/.claude/rules` link and the symlink loop linking runtime state (backlog rows).

## Deferred: moving reference text to knowledge files

The original design moved about 85,000 units of reference to twelve knowledge files behind
triggered pointers, to reach ≤ 50,000 units. Two review rounds found the design still changing at
the design level — seam grouping that breaks a six-file pointer cap, accounting that cannot see
rules inside multi-bullet paragraphs, three wrong and four missing rule-5 lines — with each
correction adding mechanism. Two probes (recorded in Problem and after round 2) found that
pointers are followed (5 of 5 read-only; 4 of 5 with Edit/Write) and that moving or deleting
source-derivable seam text did not change outcome, only effort. The open work is the
non-derivable hazard text, not the move itself. It gets its own spec, carrying both rounds'
findings and both probes; a dotfiles backlog row tracks it.

## Rejected

- **The full move now.** Not converging after two rounds; see Deferred.
- **Pause the re-sort.** The records, padding and unfetchable links are clean wins independent
  of the move.
- **dotfiles `.claude/rules/` and nested `tests/CLAUDE.md`.** Rejected in round 1 for the move
  work; unchanged.

## Verification

Each check states a non-zero before-value or a control.

1. **Records gone:** `grep -o 'Overall: 91%' CLAUDE.md | wc -l` 8 → 0; `Update this figure` 1 → 0;
   `95.54%` 1 → 0; `local-reads-one-point-higher rule did NOT hold` 1 → 0.
2. **Method kept:** the eight method bullet leads under `#### Bash` (from
   `The instrumented set is` to `covered > coverable`) each grep exactly once, 8 → 8.
3. **Size:** 137,000 ≤ UTF-16 units ≤ 139,500 — a lower bound, so over-deletion fails.
4. **Deletion scope:** every line removed by `git diff -U0 e9ea9515 -- CLAUDE.md` belongs to the
   twelve record bullets, the two PowerShell lines, the CI parenthetical, the nine table rows plus
   header and separator, or the seven link lines rewritten. Expect 0 unexplained removed lines;
   control: an extra removed line in a scratch copy reports exactly 1.
5. **Entry Points:** exactly 9 bullets naming the nine `-t` types, 0 table rows beginning `| \``,
   and each of the nine purpose cells from `e9ea9515` is a substring of the new `CLAUDE.md`;
   control: altering one cell in a scratch copy reports exactly 1 missing.
6. **Links:** `github.com/brujack/ai-config` 7 → 0; exactly 7 `~/git-repos/personal/ai-config/docs/knowledge/`
   paths, each existing locally, checked by a line-wise loop; control: one misspelled name reports
   exactly 1 missing.
7. **Routed rules:** `dotfiles-bash-coverage.md` on ai-config `origin/master` contains all four
   appended rules (four fixed grep strings, each ≥ 1, 0 before), and `make validate-knowledge`
   passes.
8. **Gates:** `make lint` and `make check-agent-guidance` pass in dotfiles.

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

### Round 2

Reviewed at commit: `edf13c20` (revision addressing round 1). All three lenses re-run, told that
the round-1 section is history.

#### Goal-Fit (round 2)

Finding: Worth building, and no simpler path gets under 50,000; the sections that stay measure
about 24,500 units. Load-bearing: nothing tests a `delete` disposition. Check 6's delete clause is
circular, and its control tests only that the manifest is complete. A rule-bearing paragraph not
on the 14-line floor can be labelled `delete` and every check passes — as round 1 already caught
once with the test-341 note. Check 5's ≥80,000-unit floor points the wrong way: a correct extra
deletion fails it. Proposed: every `delete` carries a reason from a closed set
(`dated-record`, checked for a SHA, PR or date; `padding`; `superseded-by:<file>`, checked by grep),
and the 80,000 floor goes. Also: check 9 fails on a correct tree (`git grep -n 'CLAUDE.md' --
':!*.md'` returns 30 lines at `ce0495f1`, verified); the widened step-4 row has no threshold or
consequence, so it cannot fail; the probe proves less than stated — pointer transcripts 1 and 2
were overwritten by the control runs (the per-run results were scored first), the control also
named the seam from source, and no arm deleted the text without a pointer. Minor: the revision
added six rule-5 lines, not five; "9 existing pointers" is 9 mentions of 5 files, 7 of them
GitHub links; `dedupe:` needs the same exemption from check 5 as `transform`.
Assumption: a Phase 2 Sonnet subagent with Edit/Write and a task naming a test file, not the
function, reads the pointed file before its first Edit. Settle with three arms of five runs
(pointer, inline, deleted-no-pointer), `--model sonnet`, tools `Read,Grep,Glob,Edit,Write`, unique
transcript names.
Disposition: Descoped (operator, 2026-09-11) — these findings concern the reference moves, which are deferred to their own spec after a second probe; the shipped subset (records, table padding, local links) is unaffected. Carried forward by the dotfiles backlog row for the deferred move.

#### Ergonomics (round 2)

Finding: The seam split is by variable family, but a pointer fires on a file name. Shell-startup
needs 14 files; hooks-and-tracer is at six source files with no tests; `_PROFILES_LOADED` sits
with hooks while its files are the identity table; shared files (`lib/helpers.sh`,
`lib/workflows.sh`, `6_path.zsh`, `run-bash-coverage.sh`, `lib/macos.sh`) fire several pointers,
so an edit to `lib/helpers.sh` asks for about 25,000 units of reading. Proposed: group by the file
a pointer names (an identity file; gnubin, Docker bin and Homebrew prefix folded into
`dotfiles-brew-path-presence-guards.md`; function-named pointers for `helpers.sh`). Four rule-5
lines are compressed past usefulness: line 4 contradicts line 1 and 292 `PATH=` assignments (the
real rule: never strip a directory to hide one binary — use a seam or a shim dir); line 10 uses
"guarded/measuring" undefined; line 11 drops the snapshot path and interpreter; line 3 drops why
the `unset` sits below the loop. Check 6 collides with compression: a compressed block's lead
sentence is the first thing rewritten; check a key phrase recorded in the manifest. Check 9 fails
on an untouched tree. Minor: pointers are checked against ai-config `origin/master` while sessions
read local checkouts; two destinations are fed by two sections; two moved paragraphs cite sections
that land elsewhere (`:608`, `:872`).
Assumption: a pointer is followed when the prompt names a symptom rather than the pointer's files.
Settle with five runs of a symptom-only prompt ("`setup_env.sh -t update` reports [FAIL] aws on a
mac without gpg — fix it") with Edit/Write enabled, plus one interactive run; 1 or fewer of 5
refutes.
Disposition: Descoped (operator, 2026-09-11) — these findings concern the reference moves, which are deferred to their own spec after a second probe; the shipped subset (records, table padding, local links) is unaffected. Carried forward by the dotfiles backlog row for the deferred move.

#### Risk (round 2)

Finding: Check 6 accounts for whole paragraphs, but the homes table splits many paragraphs, so it
cannot see rule text. Testing Rules (`:367-374`) is one 8-bullet paragraph split three ways, with
`:370` unhomed; Key Conventions `:882` is one 21-bullet paragraph; the cadence table is one
10,031-character paragraph; `compress` passes when a lead sentence survives (`:320` "The pre-push
hook is **permanent**." survives while its fail-closed rule is cut). Proposed: bullet- and
table-row granularity, and `rule5` entries checked by text. Rule-5 lines against code: 3, 10 and
13 correct; 4 stronger than the repo and `shell.md:611-617` (which prescribes `PATH="${shim}"`);
8 wrong — `setup_env.sh` defines one function, functions live in `lib/*.sh` across 21 bats files,
and `tests/scripts/` is one shared directory; 11 weaker than source and code — a bare `pip` is the
pyenv shim and installs into the wrong interpreter; the source uses `"$(pyenv which python)" -m pip`
after `pyenv shell ansible`. Blocks meeting the criterion but not listed: `_RHN_LOCAL_CFG` exported
in `setup()` not per test; detector stderr is POSTed to ntfy and must carry no credentials;
Dependabot call order (`PUT vulnerability-alerts` before `DELETE automated-security-fixes`) and the
latently armed state; every tool `make test` needs installed in both the `test` and
`bash-coverage` jobs. The six-file cap is already broken by three of four seam groups
(hooks-and-tracer 12 files, cadence 7+, shell-startup over six). Minor: the ai-config formatter
rewrites `*x*` to `_x_` in one moved block (`:367`), so check 5 fails there; dropping old rule 7 is
sound but loses the dotfiles-specific falsifiable startup probe.
Assumption: a session writing or extending a seam-touching test reads the pointed file before its
first Edit/Write when the prompt names a behaviour and the edited file is a hub named in several
pointers. Settle with Edit/Write allowed, the full planned pointer set in a scratch `CLAUDE.md`, and
three behaviour-phrased prompts on a hub file.
Disposition: Descoped (operator, 2026-09-11) — these findings concern the reference moves, which are deferred to their own spec after a second probe; the shipped subset (records, table padding, local links) is unaffected. Carried forward by the dotfiles backlog row for the deferred move.

**Convergence note (orchestrator).** Round 2's findings are still design-level, not apparatus,
and its corrections add mechanism (delete reasons, key phrases, a regrouping, four more rule-5
lines, three reworded ones). By the brainstorming stop criteria that is not convergence. One
subset has been clean in both rounds and depends on nothing else: delete the dated measurement
records and line 402 (routing the test-341 note to `dotfiles-bash-coverage.md`), convert Entry
Points from a padded table to a list, and replace the seven GitHub links with local
`~/git-repos/personal/ai-config/...` paths. That subset moves no reference text and needs no rule-5
copies.

**Probe 2 (operator chose "probe first", 2026-09-11).** Three arms of five runs, each on a fresh
scratch copy of dotfiles `origin/master`: `pointer` (awscli, cadence and `_PROFILES_LOADED`
reference moved to scratch knowledge files, three pointers each naming `lib/helpers.sh`),
`inline` (today's text) and `deleted` (same text removed, no pointer). `claude -p --model sonnet
--setting-sources project,local --allowedTools=Read,Grep,Glob,Edit,Write`. Two behaviour-phrased
prompts naming no function: runs 1–3 "a Mac without gpg reports `[FAIL] aws`; add one bats test",
runs 4–5 "doctor should fail when the vendored AWS CLI signing key is missing; add one bats test".
Each run's JSONL transcript has a unique name.

| arm | read knowledge file before first edit | runs that edited | edits using the correct seam | `PATH=` hacks |
| --- | --- | --- | --- | --- |
| pointer | 4 of 5 | 3 | 3 of 3 | 0 |
| inline | — | 4 | 4 of 4 | 0 |
| deleted | — | 3 | 3 of 3 | 0 |

- **Pointers are followed:** 4 of 5 pointer runs `Read` the knowledge file before their first edit.
  The fifth (a runs-4–5 prompt) did not, and its edit was still correct.
- **Outcome did not differ between arms:** all 10 edits used the correct seam (`_AWS_GPG_BIN` or
  `_AWS_KEY_PATH`), none edited `PATH`, none touched a non-test file. The seams are visible in
  `lib/developer.sh` and `lib/helpers.sh`, so this subsystem cannot show whether moved text
  changes an answer — only effort: the one runs-1–3 edit in the deleted arm took 35 tool calls,
  against 11 with a pointer and 18 and 28 inline.
- **The five runs that did not edit were correct refusals, spread across arms (2 pointer, 1
  inline, 2 deleted):** runs 1–3's premise is false — macOS `update_aws_cli` verifies with
  `pkgutil` (`_aws_verify_pkg`), not gpg — and each run said so instead of writing a test.
- **Leak and harness caveats:** the Layout section still names `_AWS_KEY_PATH` once (the `keys/`
  line), so runs 4–5 could find that seam without moved text. One deleted run issued a `Bash`
  `grep` although Bash was not in `--allowedTools`, so that flag does not restrict tools in
  `claude -p`; the command was read-only inside the scratch copy, and the real dotfiles tree
  showed 0 status lines before and after.
- **Population:** Sonnet via `claude -p`, scratch copies, two prompts, one subsystem's seams, 15
  runs. It does not measure non-derivable hazard text (e.g. `_RHN_LOCAL_CFG` exported in
  `setup()`, detector stderr carrying no credentials) — the rule-5 content round 2 found missing
  or wrong.
