# dotfiles CLAUDE.md Re-sort (descoped) — Implementation Plan

> **Status: DONE** — merged direct to master (564fd477), 2026-09-11.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut dotfiles `CLAUDE.md` from 156,787 to 135,902 UTF-16 units by deleting measurement records, flattening the padded Entry Points table and replacing unfetchable knowledge links, without losing a rule.

**Architecture:** Two docs-only repos, direct to master through worktrees. ai-config first: append six coverage-reading rules to `docs/knowledge/dotfiles-bash-coverage.md`. Then one scripted edit of dotfiles `CLAUDE.md` (Appendix A), verified by gates plus an orchestrator allow-list and cell check (Appendix B). Close-out widens ai-config's measurement row and marks this plan Done.

**Tech Stack:** Python 3 edit scripts, `grep`, `iconv`, GNU make targets `lint`, `check-agent-guidance` (dotfiles) and `validate-knowledge` (ai-config).

**Spec:** `docs/superpowers/specs/2026-09-11-claude-md-resort-design.md` at `6428e053` (approved; all dispositions recorded).

## Global Constraints

- Line references are to dotfiles `e9ea9515:CLAUDE.md` (byte-identical to `origin/master` at plan time). If `git diff --quiet e9ea9515 origin/master -- CLAUDE.md` fails, stop and report blocker.
- Work only in worktrees: dotfiles `/Users/bruce/git-repos/personal/dotfiles-worktrees/docs-claude-md-resort`, ai-config `/Users/bruce/git-repos/personal/ai-config-worktrees/docs-dotfiles-bash-coverage-rules`. Never edit a main checkout.
- Edit markdown with the given Python scripts, never the Edit/Write tools: a PostToolUse formatter reflows tables and rewrites `*x*` to `_x_`.
- Never write under `~/.claude/`. Never run `setup_env.sh`.
- dotfiles `make test` runs about 11 minutes, above the 600s Bash cap, and no task changes a file the suite reads. No task runs it; gates are scoped.
- Commits: message from `caveman:caveman-commit`; stage exact paths; end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_011vMKkiyyQXgXGYwRf64WRm`. Subagents commit; the orchestrator pushes.

## Session-level verification

1. Tasks 1–4 gates pass as written.
2. After Task 2, the orchestrator runs Appendix B and both controls (below); expect rc 0, then exactly 1 reported for each control.
3. `iconv -f UTF-8 -t UTF-16LE CLAUDE.md | wc -c` / 2 on dotfiles `origin/master` after push reads 135,902.
4. ai-config `origin/master:docs/knowledge/dotfiles-bash-coverage.md` contains all seven Task 1 grep strings.

**Orchestrator before Task 1:** message the ai-config session that `docs/knowledge/dotfiles-bash-coverage.md` and the `docs/superpowers/README.md` measurement row are about to change.

---

### Task 1: Append coverage-reading rules to ai-config knowledge

```yaml-task
id: 1
description: Docs-only — append the six-rule "Reading the bash coverage figure" section to ai-config docs/knowledge/dotfiles-bash-coverage.md; no behaviour change, so TDD does not apply
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'for x in "## Reading the bash coverage figure" "from the same CI run" "can read higher or lower than CI" "exactly at the 91% floor" "91% is the durable claim" "acceptable only because CI gates it" "20KB-truncated subset of current"; do grep -qF -- "$x" docs/knowledge/dotfiles-bash-coverage.md || exit 1; done'
    exit_code: 0
  - cmd: make validate-knowledge
    exit_code: 0
max_retries: 3
files_touched: [docs/knowledge/dotfiles-bash-coverage.md]
depends_on: []
```

**Repo:** ai-config. Create the worktree `ai-config-worktrees/docs-dotfiles-bash-coverage-rules` on a new branch from `origin/master`; `files_touched` is relative to it.

- [ ] Run the first gate; confirm it exits 1 (all seven strings absent).
- [ ] Append Appendix C to the end of `docs/knowledge/dotfiles-bash-coverage.md` with a script (`open(path, "a")`, one leading blank line). If the frontmatter has `last_reviewed`, set it to `2026-09-11` in the same script.
- [ ] Run both gates; commit.

**Interfaces:** Produces the section Task 2's reworded pointer names ("reading the figure").

---

### Task 2: Scripted re-sort of dotfiles CLAUDE.md

```yaml-task
id: 2
description: Docs-only — run Appendix A on dotfiles CLAUDE.md (delete 12 coverage records, PowerShell and CI figures and line 402; add publish bullet; table to list; local links; reword pointer); TDD not applicable
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: '[ "$(grep -o "Overall: 91%" CLAUDE.md | wc -l | tr -d " ")" -eq 0 ] && ! grep -qE "Update this figure|95\.54%|1626 tests|local-reads-one-point-higher rule did NOT hold" CLAUDE.md'
    exit_code: 0
  - cmd: 'u=$(( $(iconv -f UTF-8 -t UTF-16LE CLAUDE.md | wc -c) / 2 )); [ "$u" -ge 135600 ] && [ "$u" -le 136200 ]'
    exit_code: 0
  - cmd: python3 .claude-resort-gates.py
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make check-agent-guidance
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md]
depends_on: [1]
```

**Repo:** dotfiles. Create the worktree `dotfiles-worktrees/docs-claude-md-resort` on a new branch from `origin/master`.

- [ ] Confirm the Global Constraints base check; run the first two gates and confirm both exit 1.
- [ ] Write Appendix D to `.claude-resort-gates.py` in the worktree root (untracked scratch, never committed; delete it after the gates pass) and confirm it exits 1.
- [ ] Save Appendix A as a scratch file outside the repo and run it from the worktree root; it prints `units 135902`. Any assertion error: stop and report blocker with the message — do not edit by hand.
- [ ] Run all five gates, delete `.claude-resort-gates.py`, confirm `git status --porcelain` shows only `CLAUDE.md`, commit.

**Interfaces:** Consumes Task 1's section name. Produces the commit the orchestrator verifies with Appendix B.

**Orchestrator after Task 2:** in the dotfiles worktree,
`git show e9ea9515:CLAUDE.md > /tmp/claude-501/e9ea.md && python3 <Appendix B> /tmp/claude-501/e9ea.md CLAUDE.md` → rc 0 (`removed=51 outside_allow=0 allow_untouched=0`, `cells=9 missing=0`). Controls on scratch copies: delete one line under `## Knowledge Directory` → exactly 1 `outside_allow`; change one Entry Points purpose → exactly 1 `missing`. Then push ai-config Task 1's branch to master, then dotfiles Task 2's branch to master, and verify both by ref.

---

### Task 3: Widen ai-config's writer-change measurement row

```yaml-task
id: 3
description: Docs-only — add dotfiles' root CLAUDE.md to step 3 of ai-config's "Measure the CLAUDE.md writer change" backlog row; TDD not applicable
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep "^| Measure the CLAUDE.md writer change" docs/superpowers/README.md | grep -qE "Step 3 also counts dotfiles. root .CLAUDE\.md."'
    exit_code: 0
max_retries: 3
files_touched: [docs/superpowers/README.md]
depends_on: [2]
```

**Repo:** ai-config, same worktree as Task 1 after `git pull --ff-only origin master`.

- [ ] Confirm the gate exits 1.
- [ ] With a Python script (assert the row occurs once), insert before the row's final ` |`: `` Step 3 also counts dotfiles' root `CLAUDE.md` from its re-sort commit (dotfiles plan 2026-09-11-claude-md-resort). ``
- [ ] Gate; commit. The orchestrator pushes to master.

---

### Task 4: Mark the plan Done in dotfiles

```yaml-task
id: 4
description: Docs-only — set the 2026-09-11 CLAUDE.md re-sort All Plans row to Done and add the Status DONE banner to this plan; TDD not applicable
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -F "[CLAUDE.md re-sort](specs/2026-09-11-claude-md-resort-design.md)" docs/superpowers/README.md | grep -q "| Done |"'
    exit_code: 0
  - cmd: 'sed -n "3p" docs/superpowers/plans/2026-09-11-claude-md-resort.md | grep -qF "> **Status: DONE**"'
    exit_code: 0
max_retries: 3
files_touched: [docs/superpowers/README.md, docs/superpowers/plans/2026-09-11-claude-md-resort.md]
depends_on: [2]
```

**Repo:** dotfiles, same worktree as Task 2 after `git pull --ff-only origin master`.

- [ ] Confirm both gates exit 1.
- [ ] With a Python script: in the row, replace `| In Progress |` with `| Done |`; insert line 3 of the plan file as `` > **Status: DONE** — merged direct to master (<Task 2 commit SHA>), 2026-09-11. `` followed by a blank line.
- [ ] Gates; commit. The orchestrator pushes to master, then removes both worktrees.

---

## Appendix A: `edit_claude_md.py`

Run from the dotfiles worktree root. Proven on 2026-09-11 against a copy of `e9ea9515:CLAUDE.md`: byte-identical to the spec's dry run, 135,902 units.

```python
import re, pathlib
p = pathlib.Path("CLAUDE.md"); s = p.read_text()
PUBLISH = "- Publish CI's bash coverage figure in the PR body once CI has run (`gh pr edit <n>`); a local run is a preview, labelled as one."
POINTER = "- Before recording or publishing a bash coverage figure, or editing `scripts/run-bash-coverage.sh` or `scripts/bash-tracer.sh`, read `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bash-coverage.md` (method, floors and ceilings, reading the figure)."
a = s.index("#### Bash\n"); b = s.index("\n- `make bash-coverage` measures", a)
parts = re.split(r"\n(?=- )", s[a:b])
leads = ("- **Overall: 91%**", "- **The local-reads-one-point-higher rule did NOT hold", "- **91% has now landed exactly at the floor", "- **The preview discipline paid a fourth time", "- **And a fifth time, on #223")
kept = [parts[0]] + [x for x in parts[1:] if not x.startswith(leads)]
assert len(parts) - len(kept) == 12, len(parts) - len(kept)
kept[-1] = re.sub(r"\n\s*\n\s*$", "", kept[-1])
s = s[:a] + "\n".join(kept) + "\n" + PUBLISH + s[b:]
for old in ["- **`setup_windows.ps1`: 95.54%** (line coverage, measured by Pester `-CodeCoverage`)\n", "- Update this figure whenever tests are added or removed.\n"]:
    assert s.count(old) == 1, old
    s = s.replace(old, "")
m = re.search(r"\(regression proxy; [^\n]*?#260\)", s); assert m
s = s[:m.start()] + "(regression proxy)" + s[m.end():]
pl = [l for l in s.split("\n") if l.startswith("- Method detail, per-file floors/ceilings")]
assert len(pl) == 1
s = s.replace(pl[0], POINTER)
s, n = re.subn(r"\[[^\]]*\]\(https://github\.com/brujack/ai-config/blob/[^/]+/(docs/knowledge/[^)]+)\)", r"`~/git-repos/personal/ai-config/\1`", s)
assert n == 6, n
e0 = s.index("## Entry Points"); e1 = s.index("## Symlink Strategy"); ep = s[e0:e1]
t = [l for l in ep.split("\n") if l.startswith("|")]
assert len(t) == 11, len(t)
bullets = []
for r in t[2:]:
    typ, purpose = [c.strip() for c in r.strip().strip("|").split("|")]
    bullets.append(f"- {typ} — {purpose}")
st = ep.index(t[0]); en = ep.index(t[-1]) + len(t[-1])
s = s[:e0] + ep[:st] + "\n".join(bullets) + ep[en:] + s[e1:]
p.write_text(s)
print("units", len(s.encode("utf-16-le")) // 2)
```

## Appendix B: `verify45.py` (orchestrator, spec checks 4 and 5)

Proven 2026-09-11: dry run rc 0; extra removed line reports `outside_allow=1`; altered cell reports `missing=1`; unchanged file rc 1.

```python
import re, sys, subprocess, pathlib, difflib
# usage: verify45.py <old CLAUDE.md> <new CLAUDE.md>
old = pathlib.Path(sys.argv[1]).read_text(); new = pathlib.Path(sys.argv[2]).read_text()
ALLOW = set(range(80, 91)) | {197, 233, 352, 398, 402, 469, 473, 845, 849} | set(range(406, 437))
removed = set()
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(a=old.split("\n"), b=new.split("\n"), autojunk=False).get_opcodes():
    if tag in ("delete", "replace"): removed.update(range(i1 + 1, i2 + 1))
outside = sorted(removed - ALLOW); untouched = sorted(ALLOW - removed)
link = re.compile(r"\[[^\]]*\]\(https://github\.com/brujack/ai-config/blob/[^/]+/(docs/knowledge/[^)]+)\)")
e = old[old.index("## Entry Points"):old.index("## Symlink Strategy")]
cells = [[c.strip() for c in l.strip().strip("|").split("|")][1] for l in e.split("\n") if l.startswith("| `")]
missing = [c[:40] for c in cells if link.sub(r"`~/git-repos/personal/ai-config/\1`", c) not in new]
print(f"check4 removed={len(removed)} outside_allow={len(outside)} {outside[:5]} allow_untouched={len(untouched)} {untouched[:5]}")
print(f"check5 cells={len(cells)} missing={len(missing)} {missing}")
sys.exit(0 if (not outside and not untouched and len(cells) == 9 and not missing) else 1)
```

## Appendix C: appended knowledge section

Proven 2026-09-11: all seven Task 1 grep strings absent before, present after; 1,642 units.

```markdown
## Reading the bash coverage figure

- **Read the ratio, the heuristic-disagreement count and the test count from the same CI run.** A union-added line moves the numerator and the denominator together, so a disagreement count and a ratio taken from two runs describe a pair that never existed.
- **A local preview can read higher or lower than CI.** Local ran one point higher on most PRs, but #244 and #250 matched CI's numerator over a different denominator, and #252 and #257 read a higher numerator locally than CI. Platform-conditional branches change what each run traces; tool presence (`ledger`, a populated `~/.gnupg`) is a suspected second cause, not a measured one.
- **CI sits exactly at the 91% floor.** A change that adds instrumented lines without tests breaches the gate immediately rather than eroding a margin.
- **91% is the durable claim; the command ratio is one sample.** The union denominator depends on what each run traced, so the fraction differs between runs of the same commit while the percentage holds.
- **Coverage recorded by derivation is acceptable only because CI gates it.** A PR that changes no instrumented file may carry the previous figure forward, because the `bash-coverage` job re-measures and fails below the floor; a derivation nothing can falsify is an assertion.
- **A lone red on `extract_new_content: no false positives when state is 20KB-truncated subset of current` is a known flake.** It passed in isolation on macOS and the Linux workstation with the tracer on and off, in three full-suite runs off CI, and on a CI re-run of the same commit; re-run it before treating it as a regression.
```

## Appendix D: `.claude-resort-gates.py` (Task 2 gate, spec checks 2, 5-part and 6)

Proven 2026-09-11: exits 1 on `e9ea9515:CLAUDE.md`, 0 on the dry run.

```python
import os, re
s = open("CLAUDE.md").read()
e = s[s.index("## Entry Points"):s.index("## Symlink Strategy")].splitlines()
assert not any(l.startswith("|") for l in e), "table stub left in Entry Points"
assert sum(1 for l in e if l.startswith("- `") and not l.startswith("- `--") and " — " in l) == 9, "Entry Points bullets != 9"
leads = ["- **The instrumented set is", "- **`scripts/` was outside the set until", "- **`scripts/bash-tracer.sh` is the sole remaining exclusion", "- **`git ls-files` rather than a filesystem glob", "- **The denominator counts commands, not source lines.**", "- **A function-declaration exclusion was tried", "- **The denominator is the union of", "- **`covered > coverable` is now a hard"]
bad = [l for l in leads if s.count(l) != 1]
assert not bad, bad
assert s.count("regression proxy") == 1
assert s.count("- Publish CI's bash coverage figure in the PR body once CI has run") == 1
assert s.count("- Before recording or publishing a bash coverage figure") == 1
assert "github.com/brujack/ai-config" not in s
ps = re.findall(r"~/git-repos/personal/ai-config/docs/knowledge/[a-z0-9-]+\.md", s)
assert len(ps) == 7 and len(set(ps)) == 5, (len(ps), len(set(ps)))
assert all(os.path.exists(os.path.expanduser(p)) for p in set(ps))
print("gates ok")
```
