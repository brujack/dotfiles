# CLAUDE.md relocation — move narrative out, keep the rules

**Status:** Proposed, 2026-09-25.
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

A **block** is one or more consecutive blank-line paragraphs that make one argument: a rule,
plus its mechanism, measurements and incident history. For each block this spec touches:

1. The block moves **verbatim** into a knowledge file. It is not reworded, shortened or merged.
   Relocation is then checkable by machine.
2. `CLAUDE.md` keeps **one bullet**: the rule in the imperative, plus a pointer naming the
   knowledge file and the heading the block now sits under.

Rewording the relocated text is out of scope. Compression and relocation are separate
operations with separate failure modes. Doing both at once makes a lost claim impossible to
tell from a moved one.

### What stays in `CLAUDE.md`, unchanged

- Layout, the 10-80-10 pointer, Entry Points command list, Symlink Strategy, Code Standards
  headings, Profile Model table, Adding a New Machine, Local-Only State, Committing Work.
- Every sentence that is a **gate or safety rule** is kept, either verbatim or as its
  one-bullet rule form. That includes: never invoke `sync_git_repos.sh` unmocked, the
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
- a table with one row per seam: variable, reader (`file:function`), and a rule of 15 words
  or fewer;
- the cross-cutting rules listed above;
- a pointer to `dotfiles-test-seams.md`.

The table replaces 62,057 characters with an estimated 6,000–8,000.

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

## Verification

1. **Nothing lost (mechanical).** Split the pre-change `CLAUDE.md` into blank-line paragraphs.
   Every paragraph absent from the post-change `CLAUDE.md` must appear verbatim in one of the
   destination files after whitespace normalisation. Normalise with the same function as
   `phrase_check.py`'s matcher, never `grep -n`: #293 found line wraps split sentences.
   **Positive control:** change one word in one relocated paragraph in the destination and
   confirm the check fails and names that paragraph. Revert.
2. **Non-zero control.** The check must report the count of relocated paragraphs, and that
   count must be greater than 0. An empty diff passes check 1 trivially.
3. **Every pointer resolves.** Each `dotfiles-*.md` named in `CLAUDE.md` exists on ai-config
   `origin/master`. Each heading a pointer names exists in that file.
4. **Rules survive (review).** A reviewer who did not do the edit reads each removed block
   against its replacement bullet and records one verdict per block: rule preserved, or rule
   weakened, with the sentence. This check has no mechanical form. It exists because the worst
   failure here is a rule that leaves with its record.
5. **Size.** `wc -c CLAUDE.md` before and after, both recorded in the PR body.
6. **Outcome.** Operator runs `/context` in a **fresh** dotfiles session after both merges and
   reports the figure. This is the acceptance check. Probes taken inside a running session are
   not, because that session's preamble was fixed when it started (#293 plan, Task 11).
7. **Knowledge gate.** `make validate-knowledge` in ai-config passes.

**Expected, stated as an estimate:** `CLAUDE.md` from 179 KB to 55–70 KB. At this corpus's
measured ~3.9 bytes per token, that is roughly 28–32k fewer tokens loaded at launch. The real
figure is check 6's output, not this line.

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
