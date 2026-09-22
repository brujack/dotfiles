# CLAUDE.md four-class re-sort — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the DUPLICATE and bare-figure RECORD mass from `dotfiles/CLAUDE.md` — the largest file any session in this fleet launch-loads — without losing a single hazard claim.

**Architecture:** A committed phrase manifest, written before any edit and asserted complete against an independently derived paragraph count, is the ground truth for every later gate. Deletions are then verified per sentence against the surviving copy. A Haiku starting-context probe before and after is the acceptance criterion, replacing a byte or token target.

**Tech Stack:** `python3` for whitespace-normalised matching, `bats`/`make` for the repo gates, a Haiku subagent dispatch for the probe.

**Spec:** `docs/superpowers/specs/2026-09-21-claude-md-four-class-resort-design.md` at `9d7e399a`.
**Parent convention:** `ai-config` `docs/superpowers/specs/2026-09-21-standards-launch-load-reduction-design.md` at `b41bfbcb` (operator-approved).

## Global Constraints

- **Unit of classification is the sub-paragraph, never the heading or the symbol.** A heading routinely mixes classes.
- **Verification is whitespace-normalised substring matching, never `grep -n`.** 46 of 78 `### Test Seams` paragraphs have a first sentence spanning a line wrap; a line-oriented check false-HOLDs on unmodified text.
- **No aggregate gate.** `make test` is `lint check-lock check-requirements-ci test-python` + bats; lint covers only `SHELL_FILES`/`ZSH_FILES`, and no test reads the real `CLAUDE.md`. It cannot fail for this work and can only strand a task. The orchestrator runs it once after Task 10.
- **Never gate on `make check-agent-guidance`.** `.gitignore:47` ignores `.cursor/`, the mirror is untracked, and it fails in any worktree on an unchanged base.
- **DUPLICATE requires both copies to serve the same argument**, not merely the same prose. A citation is not a duplicate of the thing it cites.
- **A rule deleted with its record is the highest-severity failure in this change.** Where a RECORD's rule cannot stand without its narrative, neither moves in this plan.
- File is **179,650 bytes**, **286** blank-line paragraphs at `9d7e399a`. Byte figures use `wc -c`, not python `len()` — the file carries 1,025 multibyte characters.

## Out of scope, deliberately

- **HAZARD compression** (105,799 B, 59%). Pure judgement, no mechanical gate, and the spec names it the worst review-cost ratio in the design. Its own plan.
- **RECORD narrative relocation and REFERENCE moves** (~31,796 B). Both write into `ai-config/docs/knowledge/` and `new-repo-bootstrap`, and the parent spec requires the two repos' merges be sequenced rather than landing in parallel. Second plan, after the parent lands.

This plan ships the classes with mechanical remedies. Expected removal is **DUPLICATE 35,637 B + bare-figure RECORD**, both upper bounds that per-sentence adjudication will reduce.

## Verification Plan (session level)

- **Acceptance is the probe delta, not a byte target.** Baseline at Task 1, re-probe at Task 11, report the difference. A trim that moves the probe materially less than its byte count implies is itself a finding.
- **No hazard claim lost:** every manifest phrase classed HAZARD returns a hit in the post-change file, run by someone who did not perform the edit.
- **Edge cases:** a candidate whose source copy has since been trimmed is not a duplicate and stays; a manifest row whose phrase is not unique is rejected before the manifest locks.

---

### Task 1: Baseline — byte counts and a Haiku starting-context probe

```yaml-task
id: 1
description: Record pre-change byte counts and a measured Haiku starting context in the plan file (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "^BASELINE_BYTES=179[0-9]{3}$" docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md'
    exit_code: 0
  - cmd: 'grep -qE "^BASELINE_CONTEXT=1[0-9]{5}$" docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md'
    exit_code: 0
  - cmd: 'grep -qE "^BASELINE_PARAGRAPHS=286$" docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md]
depends_on: []
```

**Files:** this plan file only.

- [ ] `wc -c CLAUDE.md` → write `BASELINE_BYTES=<n>` into the Baseline Record section below.
- [ ] Paragraph count → `BASELINE_PARAGRAPHS=<n>`:
      `python3 -c "import io;print(len([p for p in io.open('CLAUDE.md',encoding='utf-8').read().split(chr(10)*2) if p.strip()]))"`
- [ ] Dispatch one Haiku subagent, entire prompt: `Reply with exactly the word OK. Do not use any tools. Do not explain.`
- [ ] From the task's `<output-file>` JSONL, turn 1 only:
      `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` → `BASELINE_CONTEXT=<n>`.
      **Do not use the notification's `subagent_tokens`** — cumulative across turns, read 190,214 against a true 185,132 on a prior probe.
- [ ] Record the parent SHA the probe ran at.

**Interfaces — Produces:** `BASELINE_BYTES`, `BASELINE_PARAGRAPHS`, `BASELINE_CONTEXT` consumed by Tasks 6 and 11.

---

### Task 2: Build `phrase_check.py`, the instrument every later gate uses

```yaml-task
id: 2
description: Build the whitespace-normalised manifest checker with completeness, uniqueness and survival modes, test-first
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'python3 -m pytest tests/test_phrase_check.py -q'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --help'
    exit_code: 0
max_retries: 3
files_touched: [scripts/phrase_check.py, tests/test_phrase_check.py]
depends_on: [1]
```

**Files:** `scripts/phrase_check.py`, `tests/test_phrase_check.py`.

**Relocated from `.claude/scripts/` at execution time.** That directory tracks exactly one file
in this repo and its `.gitignore` allow-path is deliberately one file wide — the comment there
calls all three lines load-bearing. Widening it to admit this script would be the loose-escape-
hatch failure `USER.md` names; `scripts/` is where this repo's own 22 tracked scripts live and is
the correct home. The first dispatch reported this as a blocker rather than force-adding, which
is the right call, though its proposed remedy was the widening.

Exists before any manifest row, because every later gate calls it. Write each test first.

- [ ] **RED:** a phrase spanning a line wrap **is found**. This retired `grep -n`: 46 of 78
      `### Test Seams` paragraphs have a first sentence spanning a wrap.
- [ ] **GREEN:** normalise both sides with `re.sub(r"\s+", " ", s)` before matching.
- [ ] **RED:** `--assert-complete N` exits non-zero when the manifest has fewer than N rows.
- [ ] **RED:** `--assert-complete-derived` derives N from `--source` by blank-line split and
      compares, so no caller has to pass a literal count that could itself go stale.
- [ ] **RED:** `--assert-unique` rejects a phrase occurring more than once in the source.
- [ ] **RED:** a sentence-initial phrase is rejected — the HAZARD remedy capitalises its
      leading word and the match is case-sensitive.
- [ ] **RED:** `--survives CLASS` exits non-zero when a row of that class no longer matches.
- [ ] **RED:** `--deleted-have-counterparts` exits non-zero when a row marked deleted has a
      sentence with no counterpart in its named file.

**Interfaces — Produces:** `phrase_check.py` with `--manifest`, `--source`, `--assert-complete N`,
`--assert-complete-derived`, `--assert-unique`, `--survives CLASS`, `--deleted-have-counterparts`. Every later task calls it in
that flag form; there is no positional form.

---

### Task 3: Manifest fragment A — Key Conventions, Symlink Strategy, Layout

```yaml-task
id: 3
description: Write phrase-manifest rows for Key Conventions, Symlink Strategy and Layout (docs-only data file, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'test -s docs/superpowers/plans/phrases-a.md'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases-a.md --source CLAUDE.md --assert-unique'
    exit_code: 0
max_retries: 3
files_touched: [docs/superpowers/plans/phrases-a.md]
depends_on: [2]
parallel_group: manifest
```

**Files:** `docs/superpowers/plans/phrases-a.md` (new).

One row per sub-paragraph, pipe-separated: `class | phrase | counterpart-file | counterpart-symbol | note`.

- [ ] Class each sub-paragraph HAZARD / DUPLICATE / RECORD / REFERENCE / AMBIGUOUS.
- [ ] Phrase is taken from the **claim sentence**, and must **not** begin at a sentence boundary — the HAZARD remedy capitalises a leading word and the match is case-sensitive.
- [ ] For every DUPLICATE, name the counterpart file and symbol and state what each copy argues. Same argument is the test; a citation is not a duplicate.
- [ ] Known rows for this scope, from the spec's Measurement: the `$0`-in-a-zsh-startup-file bullet duplicates `~/.claude/standards/shell.md`'s zsh entry (same code, same failure mode, and shell.md's worked example names `config/profiles.zsh`); the `list-shell-files.sh` coverage claim duplicates this same file at its Testing section.

**Interfaces — Produces:** `phrases-a.md`, merged by Task 6.

---

### Task 4: Manifest fragment B — Testing, Coverage, ShellCheck, Mock Pattern, Testing Rules

```yaml-task
id: 4
description: Write phrase-manifest rows for the Testing block excluding Test Seams and MAKEFLAGS (docs-only data file, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'test -s docs/superpowers/plans/phrases-b.md'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases-b.md --source CLAUDE.md --assert-unique'
    exit_code: 0
max_retries: 3
files_touched: [docs/superpowers/plans/phrases-b.md]
depends_on: [2]
parallel_group: manifest
```

**Files:** `docs/superpowers/plans/phrases-b.md` (new).

Same row format and phrase rules as Task 3.

- [ ] Scope: `## Testing` intro, `### ShellCheck`, `### Testing Rules`, `### PowerShell Testing`, `### Coverage`, `### Mock Pattern`. **Exclude** `### Test Seams` and `### MAKEFLAGS and Stdout Partition` — Task 5 owns those.
- [ ] Known DUPLICATE counterparts for this scope: `shell.md` (moreutils/`HAVE_PARALLEL` detection, the `SC1091` structurally-unavoidable rationale, file-wide directive scope, `SC1124`, the `git ls-files` pathspec argument), `ci.md` (`$(nproc)` is the worst worker count on a 2-vCPU runner), `git-workflow.md` (`GIT_DIR` strip in `pre-push`), and `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` (pass-through mocks, `env -i` strips PATH).
- [ ] Three paragraphs in this scope were checked and are **not** duplicated — ggshield actor-boundary resolution, `tests/mocks/curl` short-option-cluster parsing, and the `-o` deferred-write semantics. Class them HAZARD.

**Interfaces — Produces:** `phrases-b.md`, merged by Task 6.

---

### Task 5: Manifest fragment C — Test Seams, MAKEFLAGS, and the remaining sections

```yaml-task
id: 5
description: Write phrase-manifest rows for Test Seams, MAKEFLAGS and all sections not covered by fragments A or B (docs-only data file, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'test -s docs/superpowers/plans/phrases-c.md'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases-c.md --source CLAUDE.md --assert-unique'
    exit_code: 0
max_retries: 3
files_touched: [docs/superpowers/plans/phrases-c.md]
depends_on: [2]
parallel_group: manifest
```

**Files:** `docs/superpowers/plans/phrases-c.md` (new).

Same row format and phrase rules as Task 3.

- [ ] Scope: `### Test Seams`, `### MAKEFLAGS and Stdout Partition`, and every section not in Task 2's or Task 3's list — Repository Overview, 10-80-10, Knowledge Directory, Entry Points, GitHub MCP, Code Standards, Shell Scripts, Platform Detection, Homebrew Helpers, Brewfile Capability Tags, PowerShell Scripts, Windows AI Config Setup, Version Pinning, Ruby Version Manager Split, Language Standards, CI/GitHub Actions, Committing Work, Dependency Automation, Local-Only State, Profile Model, Adding a New Machine.
- [ ] `### Test Seams` carries **partial** duplicates: `_OVERRIDE_CURRENT_LOGIN_SHELL` and `_OVERRIDE_LIB_TRAP_SCOPE` each hold one paragraph with a source counterpart and one with none. Row them separately.
- [ ] Known clean DUPLICATE rows: the `Version Pinning` block restates four values byte-identically from `lib/constants.sh`; the Profile Model capability table restates `PROFILE_CAPS`; `actions/checkout@v5` at the CI section and `@v6` at the Dependency Automation section are **both stale** against the workflow's digest pin — class RECORD and flag for deletion, not correction.

**Interfaces — Produces:** `phrases-c.md`, merged by Task 6.

---

### Task 6: Manifest merge and completeness assertion

```yaml-task
id: 6
description: Merge the three fragments into one locked manifest and assert row count and phrase uniqueness against a freshly derived count
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --assert-unique'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --assert-complete-derived'
    exit_code: 0
max_retries: 3
files_touched: [docs/superpowers/plans/phrases.md]
depends_on: [3, 4, 5]
```

**Files:** `docs/superpowers/plans/phrases.md` (new, merged).

- [ ] Concatenate the three fragments.
- [ ] Assert the merged row count equals a **freshly derived** blank-line split of `CLAUDE.md`,
      not `BASELINE_PARAGRAPHS` read back from the plan. A hand-maintained denominator cannot
      report its own incompleteness: an omitted row is absent from numerator and denominator
      alike, so the figure does not move.
- [ ] Commit the manifest **before any edit to `CLAUDE.md`**. It is locked from here.

**Interfaces — Consumes:** `phrases-a.md`, `phrases-b.md`, `phrases-c.md`.
**Produces:** `phrases.md`, locked; read by Tasks 7-13.

---

### Task 7: DUPLICATE deletions — Key Conventions, Symlink Strategy, Layout

```yaml-task
id: 7
description: Delete CLAUDE.md copies whose counterpart is confirmed present, for fragment A's scope only
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives HAZARD'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives AMBIGUOUS'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives REFERENCE'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --deleted-have-counterparts'
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, docs/superpowers/plans/phrases.md]
depends_on: [6]
```

**Files:** `CLAUDE.md`, and `phrases.md` for per-row verdicts only.

- [ ] For each DUPLICATE row in fragment A's scope: confirm **every sentence being removed** has a counterpart in the named file, using `phrase_check.py`'s normalised search. One phrase-match does not authorise removing a block.
- [ ] A sentence with no counterpart is **not** part of a duplicate. It stays, and the row is recorded `partial` with the reason.
- [ ] A counterpart that has since been trimmed means the row is **not** a duplicate. Record `withdrawn`.
- [ ] Where deletion leaves a seam unnamed, keep a one-line entry naming the variable and its file, with no rationale.
- [ ] Record verdict plus one-line reason per row.
- [ ] Commit. Invoke `caveman:caveman-commit` for the message.

**Interfaces — Consumes:** `phrases.md`. **Produces:** per-row verdicts in the same file.

---

### Task 8: DUPLICATE deletions — the verbatim-verified rows, all fragments

```yaml-task
id: 8
description: Delete the 8 DUPLICATE rows whose full phrase is literally present in the named counterpart, sentence-level, across all fragments
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives HAZARD'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives AMBIGUOUS'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives REFERENCE'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --deleted-have-counterparts'
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, docs/superpowers/plans/phrases.md]
depends_on: [7]
```

**Files:** `CLAUDE.md`, `phrases.md`.

Same per-sentence rule as Task 7.

- [ ] Most counterparts here are **fleet-wide standards**, not source comments — so the duplicate is paid twice per session. Confirm against the live `~/.claude/standards/*.md`, which resolve into `ai-config/.claude/standards/`.
- [ ] The pass-through-mocks paragraph sits **one line below its own pointer** to the knowledge doc. Delete the paragraph, keep the pointer.
- [ ] Commit.

---

### Task 9: reclassify the DUPLICATE rows the manifest format cannot express

```yaml-task
id: 9
description: Record a measured verdict for the 11 paraphrase rows and the 1 self-referential row, which the counterpart gate cannot authorise deleting (manifest-only, no CLAUDE.md edit)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives HAZARD'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives AMBIGUOUS'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives REFERENCE'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --deleted-have-counterparts'
    exit_code: 0
max_retries: 3
files_touched: [docs/superpowers/plans/phrases.md]
depends_on: [8]
```

**Files:** `CLAUDE.md`, `phrases.md`.

- [ ] `Version Pinning` and the Profile Model capability table are the two clean whole-block deletions; both restate live source byte-identically. Replace each with a one-line pointer naming the source file.
- [ ] The two partial seams (`_OVERRIDE_CURRENT_LOGIN_SHELL`, `_OVERRIDE_LIB_TRAP_SCOPE`) lose one paragraph each and **keep** the one with no counterpart.
- [ ] Commit.

---

> **Tasks 8 and 9 were restructured after Task 7 measured 0 of 4 deletable.**
> The spec defines DUPLICATE as *same argument, not same prose*, while
> `--deleted-have-counterparts` requires the full phrase to occur literally in the
> counterpart file. Re-run against the full phrase with the tool's own `match_phrase`:
> **9 of 21** rows qualify, one of which is self-referential (`CLAUDE.md` duplicating
> itself, which the format cannot express either). The remaining 11 are genuine
> duplicated arguments in different words. Task 8 now deletes only the verbatim set;
> Task 9 records the rest for the compression plan, where the remedy is to compress
> both copies rather than delete one.
>
> Measured yield, disjoint per paragraph: HAZARD-only paragraphs hold **64.2%** of the
> file's bytes. Pure DUPLICATE+RECORD+REFERENCE is 17,279 B, under 10%. This plan's
> deletion yield is **~1.2%** against a 14,868-token headroom gap. Deletion cannot reach
> the target; compression is the lever that does.

### Task 10: RECORD — delete bare dated figures

```yaml-task
id: 10
description: Delete RECORD rows that are a bare dated figure, leaving incident narratives in place for the follow-on plan
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives HAZARD'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives AMBIGUOUS'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives REFERENCE'
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, docs/superpowers/plans/phrases.md]
depends_on: [9]
```

**Files:** `CLAUDE.md`, `phrases.md`.

Per the parent spec §4.1, RECORD has two destinations and only one is in scope here.

- [ ] **Delete** a RECORD row whose only content is a number and its date. Git history and the PR body hold it.
- [ ] **Leave** any RECORD whose narrative a reader needs to apply the rule. Those move to `docs/knowledge/` in the follow-on plan, which is sequenced against ai-config's merge.
- [ ] The stale `actions/checkout@v5` and `@v6` claims are bare figures **and** wrong — delete both rather than correcting them; the workflow's digest pin is the source of truth.
- [ ] **A rule deleted with its record is the failure this task can cause.** Both `--survives` gates above must pass, and the second one exists because a RECORD sentence and its rule routinely share a paragraph.
- [ ] Commit. Orchestrator runs `make test` once after this task (Task 10).

---

### Task 11: Post-change probe and delta report

```yaml-task
id: 11
description: Re-probe the Haiku starting context and record the delta against Task 1's baseline (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "^RESULT_CONTEXT=1[0-9]{5}$" docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md'
    exit_code: 0
  - cmd: 'grep -qE "^RESULT_BYTES=1[0-9]{5}$" docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md]
depends_on: [10]
```

**Files:** this plan file.

- [ ] Re-run Task 1's probe verbatim, same prompt, same turn-1 extraction.
- [ ] Record `RESULT_BYTES`, `RESULT_CONTEXT`, and the two deltas.
- [ ] **Report the byte delta and the token delta side by side.** A token delta materially smaller than the byte delta implies is a finding about the trim, not a rounding artifact — record it rather than explaining it away.
- [ ] State the new headroom against Haiku 4.5's 200,000.

---

### Task 12: Substance review by a non-implementer

```yaml-task
id: 12
description: A reviewer who performed none of the edits confirms every HAZARD claim still says what it said, with a recorded verdict per paragraph
role: reviewer
tdd: not-applicable
acceptance:
  - cmd: 'grep -cE "^\\| (kept|weakened|lost) \\|" docs/superpowers/plans/phrases.md'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives HAZARD'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives AMBIGUOUS'
    exit_code: 0
  - cmd: 'python3 scripts/phrase_check.py --manifest docs/superpowers/plans/phrases.md --source CLAUDE.md --survives REFERENCE'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/plans/phrases.md]
depends_on: [11]
```

**Files:** `phrases.md` verdict column only.

The phrase gate detects a claim disappearing. It cannot detect one weakened into a vague summary that still contains the phrase — this task is the only check on that.

- [ ] For every paragraph any task touched, read the pre-change text at the parent SHA (`git show <parent>:CLAUDE.md`) against the post-change text.
- [ ] Record `kept` / `weakened` / `lost` plus a one-line reason per paragraph. A verdict with no record is an assertion, not a review.
- [ ] Anything `weakened` or `lost` goes back to the task that produced it.

---

### Task 13: Close out — spec status, backlog rows, index

```yaml-task
id: 13
description: Mark the spec Done, close the two backlog rows this plan resolves, and record what moved to the follow-on plan (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "2026-09-21-claude-md-four-class-resort" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md]
depends_on: [12]
```

**Files:** `docs/superpowers/README.md`.

**Escalated from `haiku` to `sonnet` at dispatch time.** `roleModels.executor-mechanical` is
Haiku 4.5 and this task is mechanical enough for it, but this repo's measured haiku headroom is
**14,868 tokens** and three of three prior haiku dispatches here failed with
`Autocompact is thrashing`. Revert to `haiku` once a post-change probe shows headroom that
supports it — which is what Task 11 measures.

- [ ] Set the All Plans row to `Done` and point it at this plan file.
- [ ] Close backlog row `Move CLAUDE.md reference text to knowledge files` (row 244) and `CLAUDE.md Test Seams duplicates source comments near-verbatim`.
- [ ] Add one backlog row for the deferred work: HAZARD compression, RECORD narrative relocation and REFERENCE moves, noting the ai-config merge-sequencing constraint.

---

## Baseline Record

Filled by Task 1, read by Tasks 6 and 11.

```
BASELINE_BYTES=179650
BASELINE_PARAGRAPHS=286
BASELINE_CONTEXT=185132
BASELINE_SHA=aba0ebec67cd17df8b91555917668767e8d513b3
RESULT_BYTES=
RESULT_CONTEXT=
```
