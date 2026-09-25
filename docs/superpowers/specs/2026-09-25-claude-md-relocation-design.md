# CLAUDE.md relocation — move narrative out, keep the rules

**Status:** Approved by operator, 2026-09-25.
**Operator directive (2026-09-25):** "you work on dotfiles claude.md and move things around",
given after a fresh-session `/context` still read **178.4k** following #293.
**Supersedes:** the Non-goal in `2026-09-21-claude-md-four-class-resort-design.md` that forbade
"a knowledge-file split of the seam REFERENCE text". That non-goal is withdrawn by operator
direction. The rest of that spec, and its manifest, stand as a record of #293.

## Problem

`CLAUDE.md` is **179,422 bytes** at `2e38f5e4` (`wc -c`). Every session that opens this
repo loads all of it before reading any file. #293 was meant to reduce that and removed a net
**228 bytes**: 1,514 bytes came out in `75e5fb6b`, and `e6167816` put 1,286 back. Its own
plan recorded that deletion "cannot reach the target; compression is the lever". Neither
compression nor relocation was ever started.

`~/.claude/CLAUDE.md` already states the rule this spec applies: `CLAUDE.md` holds only what a
session needs before it reads any file. Incident write-ups and tool reference go to
`ai-config/docs/knowledge/<repo>-<topic>.md` (ADR-0020). Gate and safety rules stay in
`CLAUDE.md` whatever their form (ADR-0077 rule 5). Most of this file breaks that rule. It keeps
the rule and the story of how the rule was learned in the same paragraph.

**What this spec can and cannot move.** The 178.4k is a whole-session figure, and this file is
about a quarter of it. The rest of the instruction preamble is `~/.claude/CLAUDE.md`, `USER.md`
and the 10 imported standards: **418,189 B**, roughly 107k tokens, all owned by ai-config and
out of scope here. So even the best case of this spec lands a fresh session at roughly
**146–150k**, not under 100k. That is the expected result, not a shortfall. The next lever
after this spec is the shared standards, which is ai-config's work.

**Where the bytes are.** Measured with `awk` over headings at `2e38f5e4`. These are
**characters**, not bytes, because the file carries multibyte characters. Every figure covers
this file only.

| Section                                      |   chars | share |
| -------------------------------------------- | ------: | ----: |
| `### Test Seams`                             |  62,057 |   35% |
| `## Key Conventions`                         |  29,052 |   16% |
| `## Testing` (its own body, not subsections) |  22,021 |   12% |
| `#### Bash` (coverage)                       |   7,038 |    4% |
| `## Dependency Automation`                   |   6,437 |    4% |
| `## Entry Points`                            |   6,435 |    4% |
| everything else                              | ~46,000 |   26% |

**Premise checks, run before this design:**

- **One consumer reads this file, and it reads only the `@` import lines.** 15 files under
  `tests/`, `scripts/`, `Makefile` and `.github/` mention `CLAUDE.md`. The only one that reads
  the real file is `scripts/sync-agent-guidance.sh`, and it reads only `@~/.claude/standards/*`
  import lines. There is one such line (`CLAUDE.md:248`, `powershell.md`), and it stays. The bats
  tests for that script build a fixture through `_OVERRIDE_CLAUDE_MD_PATH`. The two `readlink`
  hits in `tests/setup_env/install_guards.bats:818,864` read the symlinked
  `~/.claude/CLAUDE.md`, which is ai-config's global file. So moving text cannot turn a suite
  red, and a green suite is not evidence either way.
- **The destination exists and is already cited.** `ai-config/docs/knowledge/` holds 12
  `dotfiles-*` files. This file already points at 5 of them, including
  `dotfiles-bats-test-infrastructure.md` (45,171 B), which holds the `MOCK_*` table.
- **The #293 manifest anchors into this file.** `docs/superpowers/plans/phrases.md` rows name
  phrases that must be present in `CLAUDE.md`. `scripts/phrase_check.py` is not wired into
  `make test` or CI (see "Its suite runs in `make test`; the tool does not"), so nothing breaks
  when a phrase moves. The manifest will read stale against the new file. That is handled
  below.

## Design

### The unit is a narrative block, moved byte-for-byte

A **unit** is the smallest thing that moves or stays whole:

- a blank-line paragraph of prose;
- **each top-level item of a bullet list**, because several sections here are one blank-line
  paragraph holding many bullets. `## Key Conventions` paragraph 2 is 26 bullets and 18,532
  characters in one block, mixing bullets that stay with bullets that move;
- a table or fenced code block, taken whole.

A **block** is one or more consecutive units that make one argument: a rule, plus its
mechanism, measurements and incident history. For each block this spec touches:

1. The block moves **verbatim** into a knowledge file. It is not reworded, shortened or merged.
   Relocation is then checkable by machine.
2. `CLAUDE.md` keeps **every rule sentence of the block, verbatim**: every sentence matching
   check 2's regex. It adds **one pointer line**. The pointer is the only new text. Nothing is
   reworded, so no rule can be weakened by a paraphrase.

**A pointer carries its trigger.** The pointer in this file that sessions demonstrably follow is
conditional: "Before recording or publishing a bash coverage figure, or editing
`scripts/run-bash-coverage.sh`… read …". A bare "see X" is not followed. Every pointer this spec
adds takes the form:

> **Before** `<action>` **on** `<paths or symbols>`, read
> `ai-config/docs/knowledge/<file>.md` § `<heading>`.

Where no action is natural, the pointer names the symbol a session would search for.

Rewording the relocated text is out of scope. Compression and relocation are separate
operations with separate failure modes. Doing both at once makes a lost claim impossible to
tell from a moved one.

### What stays in `CLAUDE.md`, unchanged

- Layout, the 10-80-10 pointer, Entry Points command list, Symlink Strategy, Code Standards
  headings, Profile Model table, Adding a New Machine, Local-Only State, Committing Work.
- Every sentence that is a **gate or safety rule** is kept verbatim (check 2). That includes: never invoke `sync_git_repos.sh` unmocked, the
  direct-to-master pre-push guard, the `sudo` mock exec hazard, never mock `sha256sum`, drive
  absence through seams rather than `PATH`, and the hand-typed identity oracle.

### Destinations

New knowledge files hold the relocated blocks. Existing files get additions only where the
relocated block is plainly part of that file's topic, under a heading
`## Relocated from dotfiles CLAUDE.md (2026-09-25)`.

| Source                                                                                                                                                                                               | Destination                            | New or existing    |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- | ------------------ |
| `### Test Seams` per-seam narratives                                                                                                                                                                 | `dotfiles-test-seams.md`               | new                |
| `### Mock Pattern`, `### MAKEFLAGS and Stdout Partition` narratives                                                                                                                                  | `dotfiles-bats-test-infrastructure.md` | existing, appended |
| `#### Bash` coverage narrative                                                                                                                                                                       | `dotfiles-bash-coverage.md`            | existing, appended |
| `## Testing` uv/renderings, requirements groups, hook internals, `phrase_check`                                                                                                                      | `dotfiles-testing-toolchain.md`        | new                |
| `## Key Conventions` narratives (git-hooks sweep, `core.hooksPath`, gnubin/actor table, linuxbrew non-interactive, `zsh-autosuggestions`, summary width, cheat.sh, Warp, tfenv, cargo-tools, NVIDIA) | `dotfiles-conventions.md`              | new                |
| `## Entry Points` long bullets (`update`, `--dry-run`, `setup_user` plugins)                                                                                                                         | `dotfiles-update-workflow.md`          | existing, appended |
| `## Dependency Automation` narrative                                                                                                                                                                 | `dotfiles-dependency-automation.md`    | new                |
| `## Symlink Strategy` `mcp.json` / `projects/` history                                                                                                                                               | `dotfiles-conventions.md`              | new (same file)    |

Each new file carries ADR-0020 frontmatter (`name` equal to stem, quoted `description`,
`metadata.type: knowledge`, `metadata.repos: [dotfiles]`) so `make validate-knowledge` in
ai-config accepts it.

### Test Seams gets an index, not a sentence

A session editing a test needs to know **which seam exists** before it writes a mock. That is
the reason the 2026-09-21 spec kept the seam text inline. The fix is an index, not the full
text. `### Test Seams` shrinks to:

- the seam idiom line (`local _file="${_OVERRIDE_VAR:-...}"`);
- one bullet per seam: the variable, its reader (`file:function`), then that seam's retained
  rule sentences verbatim, per check 2. A seam with no rule sentence gets only its name and
  reader;
- **every Test Seams unit that cites `tdd.md` E2 stays inline, whole.** These are seams whose
  failing path touches live state, and the regex does not reach all of them. Measured:
  `_CARGO_BIN`'s paragraph ("compile all eight `CARGO_TOOLS` pins for real") contains no rule
  keyword. The predicate is the literal token `E2`. At `2e38f5e4` it selects 5 units,
  13,841 B: rustup, `nvidia-ctk`, the cadence seam table, `_CARGO_BIN`, and the plugin cache.
  **The predicate misses members, so it is a floor, not the list.** Round 3 found two units
  that also touch live state but carry neither `E2` nor a rule keyword: `_RELEASE_BIN_DIR` /
  `_TFENV_LINK_DIR` (`tests/mocks/sudo` execs real commands) and `_OVERRIDE_CLAUDE_SETTINGS`
  (a mock that dirties a tracked fixture). Both stay inline, whole, by name. The plan carries
  the full inline-whole list, and check 5's reviewer may add to it but not remove from it;
- the cross-cutting rules listed above;
- a pointer to `dotfiles-test-seams.md`.

The section shrinks from 62,057 characters to its rule sentences plus seam names.

### The #293 manifest is frozen, not updated

`phrases.md` records what #293's reviewers judged against the file as it stood then. Following
`behavior.md`'s "a frozen reference is preventable only by writing it and pinning it", its rows
are not edited to follow moved text. A note at the top pins it to `e6167816` and says the
anchors describe that revision. A later edit that wires `phrase_check.py` into a gate must
re-anchor first. The `CLAUDE.md` bullet about `phrase_check.py` moves with the Testing
narrative. Its one-line rule stays: "the suite is gated, the tool is not; do not read suite
coverage as manifest enforcement".

## Sequencing across two repos

`dotfiles` and `ai-config` are tightly coupled (git-workflow.md tier table). Order:

1. Message the ai-config session before writing into its tree. Work happens in an ai-config
   worktree.
2. **ai-config lands first:** new and appended knowledge files, `make validate-knowledge`
   green, merged.
3. **dotfiles lands second:** the `CLAUDE.md` rewrite, with every pointer resolving on
   ai-config `master`.

Reversed, `CLAUDE.md` would point at files that are not there yet for as long as the two
merges are apart.

No scratch file is written under `~/.claude/projects/`. That path is inside ai-config's working
tree, and a draft left there fails ai-config's `make test` for every session on the machine.

## Verification

> **Amended 2026-09-25 (Task 4 attempt 1):** the bloat bound is `post bytes - pointer-line bytes <= floor + 8,000`. The 50 required pointers cost at least 7,526 B before any trigger words, so charging them to the slack made the bound unsatisfiable. The bound's purpose is unchanged: it catches text beyond retained rules and pointers. A pointer line must carry nothing but the pointer; Task 5's reviewer checks this. A MOVE unit whose every sentence is retained cannot satisfy checks 2 and 4 together, so such units are INLINE.


**One script runs checks 1 to 4**, against the pre-change file at `2e38f5e4` and the
post-change file. Its splitter is pinned, so every count below can be reproduced:

1. strip fenced code;
2. split into units as the Design defines them: blank-line paragraphs, then top-level list
   items;
3. normalise whitespace with `phrase_check.py`'s normaliser, never `grep -n` (#293 found line
   wraps split sentences);
4. split sentences at each match of
   `(?<!\be\.g)(?<!\bi\.e)(?<!\bvs)[.!?][*`)"]{0,3}\s+(?=[A-Z*`(\[])`. The sentence ends after
   the punctuation and any closing markup. Python rejects a variable-width lookbehind, so this
   is a boundary match, not a `re.split` lookbehind; the first draft of this line would not
   compile. Tested on
   `Use it (e.g. \`ledger init\`) must still read. **Both** call sites must branch. Done \`x\`.`,
   which gives 3 sentences, with no split inside `e.g.` and a split after `` .` ``. The plan's
   first task measures the splitter against the file and pins the count. The figures below are
   from a simpler splitter and are indicative only.

The **moving sections** are exactly the headings in the Destinations table. The plan lists
them by literal heading text, and the script reads that list. It does not infer it.

The **rule regex** is `\b(never|must|do not|don't|required|refuse[sd]?|HOLD|always|prefer|avoid|verify|only)\b`,
case-insensitive. **Measured at `2e38f5e4` with this splitter:** 187 matching sentences, 47,010
bytes, inside the sections that move.

1. **Nothing lost from the destination (mechanical).** Every unit absent from the post-change
   `CLAUDE.md` must appear verbatim in one of the destination files.
   **Positive control:** change one word in one relocated unit in the destination. Confirm the
   check fails and names that unit, then revert.
2. **Rules retained in `CLAUDE.md` (mechanical).** Check 1 cannot catch the worst case: it
   certifies the destination, so a rule that leaves with its narrative passes there by
   construction.
   - Every pre-change sentence matching the rule regex must appear, normalised, in the
     post-change `CLAUDE.md`.
   - The **only** exemption is a waiver row naming a sentence that uses a keyword in narrative,
     not as a rule. For example, "nothing ever ran", or "only surfaced because…".
   - A waiver row is the sentence plus a one-line reason. There is no "restated as" waiver:
     nothing is reworded.
   - **Negative control:** delete one retained rule sentence from the post-change `CLAUDE.md`
     while it survives verbatim in the destination. Confirm check 2 goes red while check 1
     stays green, then revert.
3. **Non-zero and size (mechanical).**
   - The count of relocated units must be greater than 0.
   - **Relocated bytes >= 60,000.** This fails an empty or token relocation. The floor
     threshold below cannot, because the floor grows with every unit kept.
   - **Hard threshold:** `wc -c CLAUDE.md <= floor + 8,000`.
     - The script computes the **floor**: unmoved sections, plus retained rule sentences, plus
       inline E2 units, with overlap counted once.
     - The 8,000 B allows for pointers and seam-name bullets.
     - The threshold is derived from the floor on purpose. It catches bloat, meaning text
       added beyond retained rules and pointers. It is not a size target.
   - An empty or token relocation fails on relocated bytes.
   - If check 2 cannot be met under the threshold, **stop and report**. Do not drop rules or
     add waivers to reach the number.
4. **Every pointer resolves.**
   - Each `dotfiles-*.md` named in `CLAUDE.md` exists on ai-config `origin/master`.
   - Each heading a pointer names exists in that file **exactly once**.
   - Headings: the implementer writes one `###` heading per relocated block in the destination,
     named for its subject. Pointers cite those headings. No two pointers may share a heading
     unless they cite the same block.
5. **Review (judgement).** A reviewer who did not do the edit judges two things:
   - **Each relocated block:** did any rule in it that the regex cannot see leave `CLAUDE.md`?
     Keyword-less rules like "Always remove…" are now caught by `always`, but others may not
     be. Verdict per block: complete, or rule missing plus the sentence.
   - **Each waiver row:** narrative, or actually a rule.
   - **Each retained sentence whose meaning depends on a moved antecedent** ("**Both** call
     sites must…"): retain its whole unit instead. The reviewer flags these, and a flagged
     sentence's unit moves back inline.

   Both sets of verdicts go in the dotfiles PR body, the only record that outlives the session.
   Expected volume: one verdict per block (about 40) plus the waiver rows. Waivers are
   narrative-only, so a double-digit count is itself a finding worth stating.
6. **Knowledge gate.** `make validate-knowledge` in ai-config passes.
7. **Outcome (operator).** Baseline and result both come from `/context` in a **fresh** dotfiles
   session, with the per-file `CLAUDE.md` line and the total recorded.
   - **The baseline is taken before the dotfiles merge.** It is the first line of the dotfiles
     PR body, and the PR does not merge without it, because it cannot be recovered afterwards.
   - Probes inside a running session do not count, because a session's preamble is fixed at
     start (#293 plan, Task 11).
   - **Pass:** the per-file `CLAUDE.md` figure falls by at least 40%.
   - The total is recorded, not gated.
8. **Behaviour (post-merge, advisory).** In a fresh dotfiles session, run two tasks.
   - **Task A:** "add a test for `_install_ubuntu_nvidia`'s restart branch". This seam stays
     inline. **Pass:** the test sets `_OVERRIDE_DOCKER_DAEMON_JSON` and runs under the
     `nvidia-ctk` mock.
   - **Task B:** "add a test for `_install_ubuntu_tflint`'s checksum-mismatch branch". This seam
     moves to index-only. **Pass:** the test sets `_RELEASE_BIN_DIR`, `_RELEASE_TMP_ROOT` and
     `_TFLINT_SHA256`, and does not mock `sha256sum`.
   - **Baseline:** the same task in a session started in a worktree at `2e38f5e4`, the
     pre-change file.
   - n=1 per arm, so a single fail does not prove the index insufficient. It triggers a second
     run. Two fails move that seam's narrative back inline.
   - Result recorded as a comment on the merged dotfiles PR.

**Expected, stated as an estimate:** `CLAUDE.md` from 179 KB to about 95–105 KB, roughly 19–21k
fewer tokens at this corpus's average of ~3.9 B/token. This file is dense with paths and
tables, so its real ratio may differ. Check 7's per-file line settles it.

## Non-goals

- **No rewording of relocated text.** HAZARD compression stays a separate piece of work.
- **No edits to `~/.claude/standards/*.md`** or to ai-config's own `CLAUDE.md`.
- **No `.claude/rules/` path-scoped loading.** It would bring Test Seams back automatically when
  a session touches `tests/**`. That behaviour is unmeasured for this repo, and ai-config uses
  it for two small files only. Recorded as a follow-on to measure, not adopted here.
- **No change to the #293 manifest rows** beyond the freezing note.

## Alternatives considered

- **Compress in place.** Higher yield per paragraph, but it is pure judgement with no
  mechanical check, and #293's spec named it the worst review-cost ratio. Rejected for this
  change.
- **Path-scoped rules file.** See Non-goals.
- **Delete the narratives instead of moving them.** `behavior.md`: "a move with no citation is
  a deletion". The pointers are the citation. Deleting would remove incident evidence the
  rules cite as their reason.

## Multi-Lens Review

Reviewed at commit: `8d67be06` (Step 7 self-review commit, before Step 8 dispatch)

Every reference in round 1 (check numbers, section names) describes the spec at `8d67be06`. The Verification section has since been renumbered, and these references are not updated to follow it.

### Goal-Fit

Finding: Worth building, but it moves about 17% of the 178.4k and the spec never says so. The global preamble (`~/.claude/CLAUDE.md`, `USER.md` and the 10 imported standards) is 418,189 B, about 107k tokens, and is out of scope. Best case lands a fresh session around 146–150k. Check 6 has no threshold, so success is undefined. Only check 2 fails when the relocation does nothing, and moving one paragraph satisfies it. Proposed: a hard `wc -c CLAUDE.md <= 70,000` check. Check 4's verdicts have no durable home; the PR body should hold them.
Assumption: The 3.9 B/token ratio holds for this file, which is dense with paths, code and tables. Settle it with the per-file "Memory files" line of `/context` in a fresh dotfiles session, taken before the dotfiles merge. The baseline cannot be recovered afterwards.
Disposition: Addressed (operator, 2026-09-25). Added a Problem paragraph stating the ~17% ceiling and the 418,189 B out of scope. Check 3 now carries a hard `wc -c CLAUDE.md <= 70,000`. Check 5's verdicts go in the PR body. Check 7 takes the per-file `/context` baseline before the dotfiles merge and passes at a 60% per-file drop.

### Ergonomics

Finding: Check 1's unit, the blank-line paragraph, is wrong for this file. Key Conventions paragraph 2 is 26 bullets and 18,532 chars in one block. Moving one bullet forces all 18.5k into a destination or tempts loosening the checker. The unit must also be the top-level list item. Pointers need a trigger condition ("before editing X, read Y"), following the working bash-coverage pointer. The 15-word seam-row cap is too tight where the hazard is a destructive failing path (`nvidia-ctk`, `_CARGO_BIN`).
Assumption: A fresh session doing a seam task acts on the index row or follows the pointer, rather than copying what `tests/` looks like. Check after merge: give a fresh session "add a test for `_install_ubuntu_nvidia`'s restart branch", then look for a Read of `dotfiles-test-seams.md` and for `_OVERRIDE_DOCKER_DAEMON_JSON` plus the `nvidia-ctk` mock. Run the same task on today's file as the baseline.
Disposition: Addressed (operator, 2026-09-25). The unit is now a paragraph, a top-level list item, or a whole table or code block. Pointers carry a "Before <action> on <paths>, read …" trigger. Seam rows may run to 30 words where the failing path is destructive. The assumption is Accepted, reason: tested after merge as check 8.

### Risk

Finding: The verification plan cannot catch the spec's own worst case. Check 1 certifies the destination, and nothing mechanical checks what stays in `CLAUDE.md`. A gate rule that leaves with its narrative is green on check 1 by construction. The only "Never invoke" in the file (`sync_git_repos.sh`) sits inside the 18.5k Key Conventions block. Proposed: a retention check. Every pre-change sentence matching `never|must|do not|required|refuse|HOLD` must appear, normalised, in the post-change `CLAUDE.md` or in a waiver list the reviewer signs. Add a negative control: delete one rule from `CLAUDE.md` while it survives in the destination, and confirm red. Scratch drafts under `~/.claude/projects/` block ai-config `make test`.
Assumption: A pointer plus a bullet of 15 words or fewer is enough for correct behaviour without the narrative. This is argued, not measured. Test it the same way as the Ergonomics assumption.
Disposition: Addressed (operator, 2026-09-25). New check 2 is a retention check: 134 rule-shaped sentences, each either kept or waived to a replacement phrase that is verified present. It has a negative control. Check 3 says stop rather than drop rules if it conflicts with the size threshold. A no-scratch-under-`~/.claude/projects/` rule is added to Sequencing. The assumption is Accepted, reason: tested after merge as check 8.

### Round 2 (all three lenses, reviewed at `3191d194`)

Round-1 fixes changed design substance, so all three lenses re-ran. **Every round-2 finding is a defect the round-1 fixes introduced.**

**Goal-fit.** Finding: the size budget does not close. Unmoved sections hold 38,418 B. Rule sentences inside the moving sections, kept verbatim, add about 28 KB. With the seam index, `CLAUDE.md` reaches about 74 KB before any pointer, so `<= 70,000` needs about 100 reworded "restated as" waivers. That is the compress-in-place work the spec rejects. Suggested: derive the threshold from the measured floor. Assumption: a large share of the 104 moving rule sentences are narrative uses that can be waived without loss. Refuted if more than 16 of a random 20 are real rules. Disposition: Addressed (operator, 2026-09-25: "Verbatim, extended").

**Ergonomics.** Finding:
- The check-2 population cannot be reproduced: the splitter is undefined, and other splitters give 124 or 130, not 134.
- About 100–150 waiver verdicts in one PR is a review nobody reads.
- Pointers must name `file § heading`, but nothing creates per-block headings in the destinations.
- Check 7's baseline is easy to miss. Check 8 needs a `2e38f5e4` worktree for its baseline and has no pass criterion.

Assumption: about 130 rule sentences can be cut under 70 KB by accepted one-line restatements. Disposition: Addressed (operator, 2026-09-25: "Verbatim, extended").

**Risk.** Finding: checks 2 and 3 conflict structurally. The waiver check only tests that a string is present, so "`sync_git_repos.sh`" alone would satisfy a "restated as" row. All of check 2's guarantee therefore falls onto check 5's human judgement again. Rules without the keywords are missed ("Always remove the old file before symlinking", "Prefer deleting to suppressing", "Verify the directive is live"). Check 1 remains sound. Assumption: restated bullets for Key Conventions are well under half the verbatim size. Disposition: Addressed (operator, 2026-09-25: "Verbatim, extended").

**Resolution.** Operator chose to keep rules verbatim with the extended regex. "Restated as" waivers are removed. Waivers are narrative-only. The splitter is pinned in Verification. The threshold is 100,000 B, derived from the floor. Pointer headings are written per block and must be unique. Check 7 passes at 40%, and its baseline blocks the merge. Check 8 is advisory, with a baseline worktree, a pass criterion, and a second run on fail.

**Author's measurement at `2e38f5e4`, for the disposition.** The splitter is: strip fences; split on blank lines and at list-item starts; normalise whitespace; split at `(?<=[.!?])\s+`. That gives:

| regex | sentences in moved sections | bytes |
| --- | ---: | ---: |
| base (`never|must|do not|...|HOLD`) | 104 | 25,625 |
| extended (adds `always|prefer|avoid|verify|only`) | 187 | 47,010 |

The floor if all are kept verbatim is **38,418 + 25,625 + ~7,000 index ≈ 71 KB** for the base regex, and **≈ 92 KB** for the extended one, before pointers.

### Round 3 (scoped Risk, reviewed at `17f3b891`)

Finding:
1. The `sudo` mock exec hazard (`_RELEASE_BIN_DIR`/`_TFENV_LINK_DIR`) has 0 regex hits and no `E2`, so it would relocate whole, and `_OVERRIDE_CLAUDE_SETTINGS` likewise.
2. "A token relocation fails here" was false: the floor includes unmoved text, so moving one unit passes. Retention bloat is absorbed one-for-one.
3. The splitter mis-splits. It does not split after `.**` or `` .` `` (35 of 192 matches glue two or more sentences). It does split inside `e.g.`, producing fragments. 1 of 6 sampled retained sentences depends on a moved antecedent. The set of moving sections was not pinned (192 / 47,999 B against the spec's 187 / 47,010).

Assumption: a name-and-reader index is enough for a seam that moves to index-only. Refute by running check 8's task against `_RELEASE_BIN_DIR`, not `nvidia-ctk`, which stays inline.

Disposition: Addressed (operator, 2026-09-25), per the resolution below. Assumption Accepted, reason: tested after merge by check 8 task B.

**Author's proposed resolution, already applied at the next commit, pending operator disposition:**
1. Both units are named inline-whole. The E2 predicate is declared a floor, and the reviewer may only add to the list.
2. New check: relocated bytes >= 60,000. The floor threshold is re-described as a bloat check.
3. The splitter is revised and its count is pinned by the plan's first task. The moving sections are listed by literal heading. A retained sentence that depends on a moved antecedent keeps its whole unit.
4. The assumption becomes check 8's second task, against `_RELEASE_BIN_DIR`.

**Stopping note.** Round 3's findings sit in the apparatus: splitter regex, threshold arithmetic, predicate membership. The rule-loss finding (1) is closed by naming the units and by check 5, which no mechanical predicate replaces. Per the brainstorming stop rule, the next instrument is the plan's first measured task, not a fourth lens.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Amendment 2026-09-25: rule bullets replace verbatim sentence retention

**Operator decision, after Task 5's block review.** The verbatim design failed check 5: 58 of 85 MOVE groups had a finding.
- The keyword regex misses rules phrased as plain imperatives, and prohibitions phrased as "not optional" or "deliberately".
- Sentences kept on their own lose their antecedents ("**Both** call sites must…").

Verbatim retention guarded against paraphrase weakening a rule. The fragments it produced weaken rules more, and more often. Findings are recorded in the map under `## Block review verdicts` (f9733db3).

**New representation.** For each MOVE group, `CLAUDE.md` carries 1–3 imperative lines, written by hand, stating every rule in the group, followed by the group's pointer. INLINE units are unchanged.

**Coverage contract.** A group's rule lines must cover:
(a) every sentence the verbatim design retained for that group;
(b) every "rule missing" sentence the Task 5 review listed for it.

**Changed checks:**
- **Check 2 (mechanical, bullets mode):** every MOVE (dest, heading) has exactly one pointer in `CLAUDE.md`.
- **Check 3:** relocated bytes >= 60,000, and `wc -c CLAUDE.md <= 90,000`.
- **Check 5:** the independent reviewer judges each group's rule lines against the coverage contract. Verdicts: `covered`, `weakened: <rule>` or `missing: <rule>`. Any non-`covered` verdict blocks.

Checks 1 and 4 are unchanged. **Test Seams:** one bullet per seam. The lead is `` `VAR` (`file:function`) ``, with the reader taken from the code, followed by its rule lines and pointer. INLINE units carry no added lead.
