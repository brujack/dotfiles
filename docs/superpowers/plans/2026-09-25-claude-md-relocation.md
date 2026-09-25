# CLAUDE.md relocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move narrative text out of `dotfiles/CLAUDE.md` into `ai-config/docs/knowledge/dotfiles-*.md`, byte for byte. Every rule sentence stays verbatim in `CLAUDE.md`, and each moved block leaves a triggered pointer behind.

**Architecture:** `scripts/relocation_check.py` implements spec checks 1–4 against the file at `2e38f5e4`. A committed relocation map lists the moving sections, the units kept whole inline, and the narrative-only waivers. The knowledge files land in ai-config first. The `CLAUDE.md` rewrite follows and must pass the checker. A non-implementer reviews every relocated block.

**Tech Stack:** `python3` stdlib (`unittest`, `re`, `pathlib`), ai-config `make validate-knowledge`.

**Spec:** `docs/superpowers/specs/2026-09-25-claude-md-relocation-design.md` at `b67a08eb` (operator-approved, three review rounds).

## Global Constraints

- **Base revision is `2e38f5e4`.** Read it with `git show 2e38f5e4:CLAUDE.md`, never from the worktree once edits start.
- **No rewording.** Relocated units move verbatim. The only new text in `CLAUDE.md` is pointer lines and seam-name bullets.
- **Rule regex, case-insensitive:** `\b(never|must|do not|don't|required|refuse[sd]?|HOLD|always|prefer|avoid|verify|only)\b`.
- **Splitter:** strip fenced code, then split into units (blank-line paragraphs, then top-level list items), then normalise with `phrase_check.normalize`, then split sentences at each match of `(?<!\be\.g)(?<!\bi\.e)(?<!\bvs)[.!?][*`)"]{0,3}\s+(?=[A-Z*`(\[])`.
- **Waivers are narrative-only.** There is no "restated as" waiver.
- **Inline-whole units:** every Test Seams unit containing the token `E2`, plus `_RELEASE_BIN_DIR`/`_TFENV_LINK_DIR` and `_OVERRIDE_CLAUDE_SETTINGS`. A reviewer may add units to this list but never remove them.
- **Pointer form:** `**Before** <action> **on** <paths or symbols>, read \`ai-config/docs/knowledge/<file>.md\` § \`<heading>\`.`
- **Thresholds:** relocated bytes >= 60,000, and `wc -c CLAUDE.md <= floor + 8,000`.
- **ai-config lands first.** No scratch files under `~/.claude/projects/`: that path is inside ai-config's tree and fails its `make test`.
- **dotfiles `make test` exceeds the 600s Bash cap.** Tasks that cannot change the suite use scoped gates only. The orchestrator runs `make test` once after Task 4.

## Verification Plan (session level)

- **Mechanical:** `python3 scripts/relocation_check.py check` passes all four checks against the rewritten `CLAUDE.md` and the ai-config knowledge files. Its positive and negative controls are recorded in the PR body.
- **Judged:** Task 5's reviewer gives one verdict per relocated block and per waiver, recorded in the PR body.
- **Outcome (operator, blocks the dotfiles merge):** a fresh-session `/context` baseline for `CLAUDE.md` before the merge and a result after it. Pass is a per-file drop of at least 40%.
- **Post-merge advisory:** check 8, tasks A (`nvidia`) and B (`tflint`), each against a `2e38f5e4` worktree baseline.

---

### Task 1: `relocation_check.py` — the checker, test-first

```yaml-task
id: 1
description: Stdlib checker implementing spec checks 1-4 plus a measure subcommand, with unit tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: python3 -m unittest tests.test_relocation_check -v
    exit_code: 0
  - cmd: python3 -m unittest discover -s tests -p 'test_*.py'
    exit_code: 0
  - cmd: 'python3 scripts/relocation_check.py measure --pre-rev 2e38f5e4 --map tests/fixtures/relocation/map.md'
    exit_code: 0
max_retries: 3
files_touched: [scripts/relocation_check.py, tests/test_relocation_check.py, tests/fixtures/relocation/map.md]
depends_on: []
```

**CLI.**
- `measure --pre-rev REV --map MAP` prints `units=N rule_sentences=N rule_bytes=N floor=N`.
- `check --pre-rev REV --post FILE --dest DIR --map MAP` prints one `CHECKn PASS|FAIL <detail>` line per check. It exits 1 if any check fails.
- Import `normalize` from `scripts/phrase_check.py`. Do not copy it.

**Map format.** One fenced block tagged `relocation-map`, one record per line, fields separated by ` | `:
- `SECTION | <literal heading line>`: a moving section.
- `INLINE | <first 60 normalised chars of unit>`: a unit that stays whole.
- `WAIVE | <normalised sentence> | <reason>`: a narrative-only waiver.
- `MOVE | <unit anchor> | <dest file> | <dest heading>`: a planned move. `<dest heading>` is the bare heading text, with no `### ` prefix. It is the same string a pointer cites after `§`.

**The checks:**
1. Every pre-change unit whose normalised text is absent from the post file is present in some `DIR/dotfiles-*.md`.
2. Every rule-regex sentence from a SECTION, outside INLINE units and not WAIVEd, is present normalised in the post file.
3. Relocated units > 0, relocated bytes >= 60,000, and post bytes <= floor + 8,000. Floor is non-moving units, plus INLINE units, plus retained sentences, counted once.
4. Every pointer matching ``read `ai-config/docs/knowledge/(dotfiles-[a-z0-9-]+\.md)` § `([^`]+)` `` names an existing file, whose `### <heading>` occurs exactly once. Every MOVE is absent from post and present under its named heading.

**Tests, one RED to GREEN cycle each, run against tiny fixture strings.**
- The splitter does not split `(e.g. \`x\`)` and does split after `` .` ``.
- Fenced code is excluded.
- A bullet list splits into items.
- Check 1 fails when a moved unit is altered in the destination. This is the positive control.
- Check 2 fails when a rule sentence is deleted from the post file but survives in the destination, while check 1 passes. This is the negative control.
- Check 2 passes with a WAIVE for that sentence.
- Check 3 fails on an empty relocation, on a relocation of one small unit, and on bloat.
- Check 4 fails on a missing file, a missing heading, and a duplicate heading.
- The fixture map parses.

**Interfaces — Produces:** the CLI above and the map format, consumed by Tasks 2 and 4.

---

### Task 2: Relocation map and measured baseline

```yaml-task
id: 2
description: Author the relocation map (sections, inline, waivers, moves with dest headings) and record measured baseline (docs-only data file, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'python3 scripts/relocation_check.py measure --pre-rev 2e38f5e4 --map docs/superpowers/plans/2026-09-25-relocation-map.md'
    exit_code: 0
  - cmd: 'M=docs/superpowers/plans/2026-09-25-relocation-map.md; [ -f "$M" ] && grep -qE "^BASELINE rule_sentences=[0-9]+ floor=[0-9]+$" "$M"'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/plans/2026-09-25-relocation-map.md]
depends_on: [1]
```

- [ ] Add a `SECTION` line for each spec Destinations row, using the literal heading text. The **Entry Points** entries are the `update`, `--dry-run` and `setup_user` bullets only. **Symlink Strategy** entries are the `mcp.json` and `projects/` history units.
- [ ] Add an `INLINE` line for every inline-whole unit named in the Global Constraints.
- [ ] Add a `MOVE` line for each block, with its destination and a `###` heading unique within that destination file. The spec's Destinations table gives the file.
- [ ] Run `measure` and read every rule sentence in the moving sections. Add a `WAIVE` only where the keyword is used in narrative, e.g. "nothing ever ran". **More than 15 waivers is a finding:** stop and report instead of committing.
- [ ] Write a `BASELINE rule_sentences=<n> floor=<n>` line from `measure`'s output.
- [ ] If `floor + 8000` exceeds 110,000, stop and report. The spec expects about 95–105 KB.
- [ ] Commit.

---

### Task 3: ai-config knowledge files

```yaml-task
id: 3
description: In an ai-config worktree, create and append dotfiles knowledge files with the MOVEd units verbatim under their map headings, and index them (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make -C /home/bruce/git-repos/personal/ai-config-wt-dotfiles-knowledge validate-knowledge
    exit_code: 0
  - cmd: 'for f in test-seams testing-toolchain conventions dependency-automation; do test -f /home/bruce/git-repos/personal/ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-$f.md || exit 1; done'
    exit_code: 0
max_retries: 3
files_touched: [../ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-test-seams.md, ../ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-testing-toolchain.md, ../ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-conventions.md, ../ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-dependency-automation.md, ../ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-bats-test-infrastructure.md, ../ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-bash-coverage.md, ../ai-config-wt-dotfiles-knowledge/docs/knowledge/dotfiles-update-workflow.md, ../ai-config-wt-dotfiles-knowledge/docs/knowledge/README.md]
depends_on: [2]
```

- [ ] Create the worktree: `git -C ~/git-repos/personal/ai-config fetch origin && git -C ~/git-repos/personal/ai-config worktree add -b docs/dotfiles-knowledge-relocation ../ai-config-wt-dotfiles-knowledge origin/master`.
- [ ] Give each new file ADR-0020 frontmatter: `name` equal to its stem, a quoted `description`, `metadata.type: knowledge`, `metadata.repos: [dotfiles]`, and `source: relocated from dotfiles CLAUDE.md at 2e38f5e4`.
- [ ] Append to each existing file a `## Relocated from dotfiles CLAUDE.md (2026-09-25)` section.
- [ ] Write every MOVE unit **verbatim** (the bytes from `git show 2e38f5e4:CLAUDE.md`) under its `### <heading>`. Write them with a Python script that reads the map. Do not retype them.
- [ ] Add four index rows to `docs/knowledge/README.md`, next to the existing `dotfiles-*` rows.
- [ ] Commit in the ai-config worktree. Do not push. Phase 3 lands this PR first.

---

### Task 4: Rewrite `CLAUDE.md`

```yaml-task
id: 4
description: Replace moved units in CLAUDE.md with their retained rule sentences verbatim plus one triggered pointer per block; Test Seams becomes a per-seam index
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'python3 scripts/relocation_check.py check --pre-rev 2e38f5e4 --post CLAUDE.md --dest /home/bruce/git-repos/personal/ai-config-wt-dotfiles-knowledge/docs/knowledge --map docs/superpowers/plans/2026-09-25-relocation-map.md'
    exit_code: 0
  - cmd: 'grep -c "^@~/.claude/standards/powershell.md$" CLAUDE.md'
    exit_code: 0
    stdout_match: '^1$'
max_retries: 3
files_touched: [CLAUDE.md]
depends_on: [3]
```

`tdd` is not applicable: this is docs-only and no test reads `CLAUDE.md` content (spec premise). Task 1's checker is the gate.

- [ ] Replace each MOVE block with its retained rule sentences, verbatim and in their original order, followed by one pointer line in the Global Constraints form. The trigger names the paths or symbols a session would touch.
- [ ] Test Seams becomes the seam idiom line, then one bullet per seam: `` `VAR` (`file:function`) `` followed by that seam's retained sentences. INLINE units stay whole. Close with a pointer to `dotfiles-test-seams.md`.
- [ ] Leave non-moving sections byte-identical.
- [ ] Run `check` and fix until all four checks PASS. **Never add a WAIVE, remove an INLINE, or shorten a retained sentence to pass.** If check 3's bloat bound fails with retained rules alone, stop and report.
- [ ] Commit. Paste the `check` output and `wc -c` before and after into the commit body.

---

### Task 5: Independent block review (spec check 5)

```yaml-task
id: 5
description: A non-implementer judges each MOVE block for keyword-less rules that left CLAUDE.md, each WAIVE, and each retained sentence with a moved antecedent; verdicts recorded (review, no code)
role: reviewer
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "^## Block review verdicts" docs/superpowers/plans/2026-09-25-relocation-map.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/plans/2026-09-25-relocation-map.md]
depends_on: [4]
```

- [ ] For each MOVE, read the pre-change block against what now stays. Verdict: `complete`, or `rule missing: <sentence>`.
- [ ] For each WAIVE, the verdict is `narrative` or `rule`.
- [ ] For each retained sentence whose meaning depends on text that moved, the verdict is `needs unit`.
- [ ] Record all verdicts under `## Block review verdicts`.
- [ ] Any `rule missing`, `rule` or `needs unit` verdict sends the task back to Task 4. There the unit moves back inline, or the sentence gets its whole unit. Then this review re-runs.

---

### Task 6: Freeze the #293 manifest and update indexes

```yaml-task
id: 6
description: Pin phrases.md to e6167816 with a freezing note, mark plan In Progress in docs/superpowers/README.md (docs-only, no behavior change, so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "e6167816" docs/superpowers/plans/phrases.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/plans/phrases.md]
depends_on: [4]
```

- [ ] Add at the top of `phrases.md`: "**Frozen at `e6167816`.** These anchors describe `CLAUDE.md` as #293's reviewers judged it. The 2026-09-25 relocation moved many of them to `ai-config/docs/knowledge/dotfiles-*.md`, and they are deliberately not updated. Any change that wires `phrase_check.py` into a gate must re-anchor first."
- [ ] Commit.

The `docs/superpowers/README.md` index row, marked In Progress, is added by the orchestrator in the plan commit.

---

## Post-merge (operator and orchestrator, not dispatched)

1. **Before the dotfiles merge:** the operator runs `/context` in a fresh dotfiles session and records the total and the `CLAUDE.md` line as the first line of the dotfiles PR body.
2. **Merge order:** the ai-config PR (Task 3), then re-run `check` with `--dest` pointing at ai-config `origin/master`, then the dotfiles PR.
3. **After both merges:**
   - The operator runs `/context` in a fresh session. Pass is a per-file drop of at least 40%.
   - Check 8, tasks A and B, each against a session started in a `2e38f5e4` worktree. Results go in a comment on the dotfiles PR.
