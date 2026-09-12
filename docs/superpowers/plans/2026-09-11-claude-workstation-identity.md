# `claude` Workstation Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the new Linux box `claude` the same identity as `workstation` in dotfiles' hostname table, and correct the documentation this makes false.

**Architecture:** Two data lines in `config/profiles.sh` plus one test-oracle arm and one `wired_only` entry. Tests come first: a pinned assertion for `claude`, and a fix to a swallow that lets a mistyped profile pass. Docs follow in the three files that state facts this change alters.

**Tech Stack:** bash 5, bats, `config/profiles.sh` associative arrays.

**Spec:** `docs/superpowers/specs/2026-09-11-claude-workstation-identity-design.md` at `a63ffa36`.

## Global Constraints

- Work in the worktree `/Users/bruce/git-repos/personal/dotfiles-worktrees/docs-claude-workstation` on branch `docs/claude-workstation`. Never the main checkout.
- **Edit every `.md` file with a python3 script, never Edit/Write** — a PostToolUse prettier hook reflows Markdown tables and will rewrite unrelated rows. `.sh` and `.bats` files may use any tool.
- `make test` is ~11 minutes, over the Bash tool's 600s cap. **No task declares it.** The orchestrator runs it once after Task 2 and again before pushing.
- Stage exact paths (`git add <path>`); never `git add -A` or `.`. No `--no-verify`. No `git stash` of any form.
- Commit trailers: `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_011vMKkiyyQXgXGYwRf64WRm`.
- Subagents never write under `~/.claude/`.
- Measured baseline at `a63ffa36`: the three identity suites are **43 ok / 0 not ok**; `PROFILE_MAP` holds 13 keys.

---

### Task 1: Pin claude's identity and stop the profile swallow (RED)

```yaml-task
id: 1
description: Add a pinned claude assertion and make an unknown profile fail instead of yielding an empty capability set
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/profiles.bats'
    exit_code: 1
    stdout_match: 'not ok .* claude resolves linux_workstation with the full capability set'
  - cmd: 'bats tests/zshrc.d/profiles.bats tests/zshrc.d/cross_shell.bats'
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/profiles.bats
  - tests/zshrc.d/profiles.bats
depends_on: []
```

**Files:**

1. `tests/setup_env/profiles.bats` — append at end of file:

```bash

@test "claude resolves linux_workstation with the full capability set" {
  local snap
  snap=$(_profile_snapshot claude)
  [[ "${snap}" == *"PROFILE=linux_workstation"* ]]
  [ "$(printf '%s\n' "${snap}" | grep -c '^HAS_')" -eq 8 ]
}
```

2. `tests/zshrc.d/profiles.bats:138` — replace `expected_has=""` inside the
   `if [[ -z "${PROFILE_CAPS[${expected_profile}]:-}" ]]; then` branch with a failure that
   names the host, keeping the old assignment unreachable below it:

```bash
      printf 'host %s maps to profile %s absent from PROFILE_CAPS\n' "${hn}" "${expected_profile}" >&2
      return 1
```

**Why RED is the gate:** measured at `a63ffa36` — with these two edits and no table entries,
`bats tests/setup_env/profiles.bats` is rc 1, **34 ok / 1 not ok**, failing only the new
assertion. Exit 1 means it ran and found the defect; a usage error would be 2 or 127.

**Interfaces:**

- Produces: the assertion Task 2 turns green, and a zsh loop that now fails on an unmapped profile.

---

### Task 2: Add the claude identity entries

```yaml-task
id: 2
description: Add claude to PROFILE_MAP and PROFILE_LEGACY with its oracle arm and wired_only exemption
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'bats tests/setup_env/profiles.bats tests/zshrc.d/profiles.bats tests/zshrc.d/cross_shell.bats'
    exit_code: 0
    stdout_match: 'ok 44 '
  - cmd: 'make lint'
    exit_code: 0
max_retries: 3
files_touched:
  - config/profiles.sh
  - tests/helpers/legacy_oracle.bash
  - tests/setup_env/profiles.bats
depends_on: [1]
```

**Files:**

1. `config/profiles.sh` — `PROFILE_MAP` gains `[claude]="linux_workstation"` after the
   `[workstation]` line; `PROFILE_LEGACY` gains `[claude]="WORKSTATION"` after its
   `[workstation]` line. No `PROFILE_CAPS` change.
2. `tests/helpers/legacy_oracle.bash:84` — add `  claude) printf 'WORKSTATION' ;;` after the
   `workstation)` arm.
3. `tests/setup_env/profiles.bats:296` — `wired_only=([workstation]=1 [cruncher]=1)` becomes
   `wired_only=([workstation]=1 [cruncher]=1 [claude]=1)`.

**Do not add a `claude-1` twin.** The spec's §2 records why, measured: `claude` connects on
one interface, as `workstation` does.

**Measured gate values** (all at `a63ffa36`, three suites): correct state **44 ok / 0 not ok**.
`[claude]="mac_mini"` → red only on Task 1's assertion. `[claude]="linux_workstatio"` → 3 red.
Exemption omitted → the twin assertion goes red. Oracle arm omitted → 2 red.

**Interfaces:**

- Consumes: Task 1's assertion.
- Produces: `PROFILE_MAP` at 14 keys; `claude` resolving `linux_workstation`/`WORKSTATION`.

---

### Task 3: Correct the two "3 edits across 2 files" claims and the legacy-vars line

```yaml-task
id: 3
description: Fix CLAUDE.md's false legacy-variable claim and the edit-count claims in CLAUDE.md and config/profiles.sh (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "WORKSTATION.*(live|remain|present)" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -c "3 edits across 2 files" CLAUDE.md config/profiles.sh'
    exit_code: 1
  - cmd: 'make lint'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - config/profiles.sh
depends_on: [2]
```

**Files:**

1. `CLAUDE.md:849` — the bullet says `WORKSTATION` and `CRUNCHER` "have been removed; use
   `HAS_*` vars instead". Both are live in `PROFILE_LEGACY` and `.zprofile:10` branches on
   `WORKSTATION`. Rewrite to say all eight legacy variables are derived from `PROFILE_LEGACY`,
   that `WORKSTATION` and `CRUNCHER` remain live, and that new code should still prefer `HAS_*`.
2. `CLAUDE.md:1071` and `config/profiles.sh:6` — both say adding a machine is "3 edits across
   2 files". True for a host with a wireless twin; a wired-only host also needs the
   `wired_only` entry in `tests/setup_env/profiles.bats`, making it **4 edits across 3 files**.
   State both cases.

**Gate note:** the second gate expects exit 1 because `grep -c` returns 1 when every named
file reports 0 — i.e. the stale phrase is gone from both. It returns 0 while either still
carries it.

---

### Task 4: Correct README's profile table and wired-only criterion

```yaml-task
id: 4
description: Drop README's Machines column, name claude in the profile prose, and replace the false wired-only criterion (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "^\| *Profile .*\| *Machines" README.md'
    exit_code: 1
  - cmd: 'grep -qE "^\| *Profile .*\| *Capabilities" README.md'
    exit_code: 0
  - cmd: 'grep -q "no wireless interface" README.md'
    exit_code: 1
  - cmd: 'grep -qE "linux_workstation.*claude" README.md'
    exit_code: 0
max_retries: 3
files_touched:
  - README.md
depends_on: [2]
```

**Files:**

**Gate provenance, measured on the base tree at `c376fbb4`:** the Machines-column gate is
rc 0 now and must become 1; the `linux_workstation.*claude` gate is rc 1 now and must become
0; the Capabilities gate is a positive control so the table cannot be satisfied by deleting
it. An earlier draft gated on `grep -q "claude" README.md`, which passes on the base tree —
README already contains 13 "claude" hits from `.claude/` paths.

1. `README.md:335-341` — remove the **Machines** column from the profile table, header and
   separator included, leaving Profile and Capabilities. It duplicates `config/profiles.sh`,
   nothing tests it, and neither "Adding a New Machine" section mentions it.
2. `README.md:343` — the `linux_workstation vs wsl2_workstation` prose names
   `(hostname: workstation)`; make it name both `workstation` and `claude`.
3. `README.md:361` — replace "Machines with no wireless interface (`workstation`,
   `cruncher`) take a single key" with the real criterion: a `-1` name is a second DHCP
   registration for a machine that **connects** on both a wired and a wireless interface, so
   a machine that only ever connects on one takes a single key. `workstation`, `cruncher` and
   `claude` all have wireless hardware and none connects on it. Keep the `home-1` exception.

---

### Task 5: Index the spec and plan

```yaml-task
id: 5
description: Add the All Plans row for this spec and plan (docs-only, no behavior change)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "2026-09-11-claude-workstation-identity" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -c "claude-workstation-identity-design" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched:
  - docs/superpowers/README.md
depends_on: [2]
```

**Files:**

`docs/superpowers/README.md` — append to the All Plans table, matching the row format of the
`2026-09-11` CLAUDE.md re-sort row directly above it:

```
| 2026-09-11 | [claude workstation identity](plans/2026-09-11-claude-workstation-identity.md) | [spec](specs/2026-09-11-claude-workstation-identity-design.md) | In Progress |
```

Edit with python3, not Edit/Write — prettier reflows this table.

---

### Task 6: Update the ai-config fleet list

```yaml-task
id: 6
description: Add claude to USER.md's machine list and update the two counts it makes stale (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "Ubuntu 26.04" /Users/bruce/git-repos/personal/ai-config-worktrees/docs-claude-fleet/USER.md'
    exit_code: 0
  - cmd: 'grep -q "seven machines carry repos" /Users/bruce/git-repos/personal/ai-config-worktrees/docs-claude-fleet/USER.md'
    exit_code: 1
max_retries: 3
files_touched:
  - USER.md
depends_on: [2]
```

**Files:**

This task works in a **separate ai-config worktree**, which the orchestrator creates first:
`/Users/bruce/git-repos/personal/ai-config-worktrees/docs-claude-fleet` on branch
`docs/claude-fleet`, from `origin/master`.

**Gate provenance, measured on the base tree:** `Ubuntu 26.04` is absent from `USER.md` now
and must be present after; `seven machines carry repos` is present now and must be gone. An
earlier draft gated on `grep -q "claude"`, which passes already — the file has 3 such hits.

`USER.md`, Environment section:

1. "seven machines carry repos" becomes eight.
2. "harness development happens on exactly two" becomes three, naming the Mac Studio, the
   Linux 7950X and `claude`. That line was narrowed deliberately on 2026-08-11 — this widens
   it knowingly.
3. Add a machine bullet: **Linux `claude`** — Ubuntu 26.04, x86_64, development machine, all
   repos, and an additional GitHub runner alongside `workstation`.
4. "Six of the seven carry every repo" becomes seven of the eight.

**Leave the Session placement paragraph alone.** `claude` is unprovisioned, so a claim that
sessions run there would be false today.

---

## Session-Level Verification

After Task 2, and again before pushing, the orchestrator runs `make test` in the worktree
(~11 minutes, backgrounded — over the Bash tool's cap). Expected: rc 0.

Then, independently of the suite:

```bash
git -C <worktree> show HEAD:config/profiles.sh | grep -c 'claude'     # 2
bash -c 'source config/profiles.sh; echo "${#PROFILE_MAP[@]}"'        # 14
```

On the box itself, after `scripts/bootstrap_linux.sh` and `setup_env.sh -t setup` have run
there: `setup_env.sh -t doctor` prints `[PASS] PROFILE (linux_workstation)`. `-t doctor` is
brew-gate-exempt (`setup_env.sh:13`), so it runs on a bare box; overall rc stays 1 until the
rest of provisioning completes. This is the only check that runs on the machine the change
exists for.
