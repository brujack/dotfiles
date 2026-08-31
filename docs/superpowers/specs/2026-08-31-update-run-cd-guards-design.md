# The `cd` guards in `run_update`, and the section they hide

**Date:** 2026-08-31
**Status:** Design
**Repo:** dotfiles
**Backlog row:** `run_update`'s five `cd` guards return 1 having recorded nothing

## Problem

ADR-0027 shipped the `-t update` exit contract: `_update_summary` ends on
`return $(( _fail > 0 ))`, so `setup_env.sh -t update` now exits 1 when any section
recorded FAIL. That ADR's Consequences section enumerates three distinct situations in
which `run_update` can now return non-zero, and notes that only the first leaves any
evidence:

1. A section recorded FAIL — summary, `~/.dotfiles-update.log` line, and ledger entry all
   written.
2. The run directory could not be created (`lib/workflows.sh:331`) — nothing recorded.
3. The run aborted mid-way on one of five `cd` guards (`lib/workflows.sh:622`, `:632`,
   `:642`, `:662`, `:664`) — nothing recorded.

Case 3 is this spec. A wrapper or cron job that sees exit 1 and finds no matching log line
is in case 2 or 3, and cannot tell which.

The backlog row proposes the obvious fix: record a FAIL section before returning, at five
call sites. **That fix is wrong for three of the five sites**, for a reason measured below,
and the two it is right for turn out to sit inside a section that reports nothing at all.

## Measurements

All measurements taken 2026-08-31 against `e56d511e`, on the Mac Studio unless the row says
otherwise. Tool versions: bash 5.3.15 (Homebrew, macOS 26.6.2), bash 5.2.21 (Linux 7950X,
matching `ubuntu-latest` per `behavior.md`'s actor table), curl 8.7.1 (`/usr/bin/curl`,
macOS).

### M1 — The left side of a pipeline is already a subshell, so three of the five `cd`-backs are dead

`lib/workflows.sh:620` and its two siblings read:

```bash
{ cd "${HOME}/.tfenv" && git pull; } 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_tfenv"
local _tfenv_rc="${PIPESTATUS[0]}"
cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
```

The brace group is the left element of a pipeline. bash runs every pipeline element in its
own subshell (`lastpipe` is the only exception, and it is off by default and inert in a
non-interactive shell), so the `cd` never reaches the parent and the parent's cwd never
moves. The `cd`-back therefore returns to a directory the shell never left.

Measured on both fleet development machines:

```
bash 5.3.15 (Studio)      after brace-in-pipeline: /tmp (was /tmp)
                          after brace-no-pipe:     /tmp/cdtest
bash 5.2.21 (workstation) after: /tmp (was /tmp)      lastpipe  off
```

The second line of the Studio run is the control: the same brace group _without_ a pipe does
move the parent, so the probe discriminates rather than reporting `/tmp` for an unrelated
reason.

**The probe is a synthetic fixture, not the production lines, and that is deliberate.** What
is under test is a bash language property — pipeline elements execute in subshell
environments — and a fixture isolates it from `git pull`, the `tee`, and the surrounding
function. Reproducing it inside `run_update` would add three confounders and could not
falsify anything the fixture cannot. `shopt lastpipe` is read in the same command as the
result, because `lastpipe` is the single documented way the property can be false; it is off
on both machines and is inert in a non-interactive shell regardless.

**Consequence.** `:622`, `:632` and `:642` cannot usefully fire. They can only _fail_ — when
`${PERSONAL_GITREPOS}/${DOTFILES}` is missing or unreadable — and when they do, they abort a
run mid-way, recording nothing, for a condition that was already harmless. They are not
guards that fail to report; they are an abort path with no corresponding hazard. There is no
failure state to record because there is no failure.

**Scope of this measurement.** The property is a bash pipeline property, not a property of
these three call sites, so it holds for every `fn 2>&1 | tee` invocation in `run_update` —
which is all of them. It follows that `update_aws_cli`'s own `cd`-backs
(`lib/developer.sh:34`, `:43`) are dead for the identical reason, since that function is
invoked as `update_aws_cli 2>&1 | tee`. That is out of scope here; see Deferred.

### M2 — `zsh-autosuggestions` is the one block that does move cwd, and it reports nothing

`lib/workflows.sh:660-665`:

```bash
if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  printf "Updating zsh-autosuggestions\\n"
  cd "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || return 1
  git pull
  cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
fi
```

No pipeline. The `cd` runs in the parent and the `cd`-back is load-bearing today — this is
the only place in `run_update` where cwd actually moves. Sites `:662` and `:664` are genuine.

Three further defects in the same six lines:

- `git pull`'s exit status is discarded outright. No `tee`, no `PIPESTATUS`, no rc check.
- There is no `_update_record_start`/`_update_record_end` pair, so the section is absent from
  the summary whether it succeeds or fails.
- There is no `_update_skip` in either the inner else (plugin absent) or the outer
  `_run_all` else, unlike its four siblings `tfenv`, `oh-my-zsh`, `tpm` and `cheat.sh`.

### M3 — The `record_start`/`record_end` machinery for that section already exists and is already tested

`lib/update_summary.sh:117` carries a `zsh-autosuggestions)` arm in `_update_record_start`
(`git -C .../zsh-autosuggestions rev-parse HEAD > pre_zsh-autosuggestions`), and
`_update_record_end` handles it through the shared git-diff path. Three tests already cover
it:

```
tests/setup_env/update_summary.bats:681  _update_record_start zsh-autosuggestions: creates pre-snapshot file
tests/setup_env/update_summary.bats:736  _update_record_end zsh-autosuggestions: reports no changes when no pre-snapshot
tests/setup_env/update_summary.bats:793  _update_record_end zsh-autosuggestions: reports commit count when pre-snapshot and updates found
```

What is missing is the caller and the `_UPDATE_SECTION_ORDER` entry. `grep -n
zsh-autosuggestions lib/update_summary.sh` shows the name in the `record_start` case arm and
**not** in the order array, and `_update_summary` iterates that array — so even a correctly
written `status_zsh-autosuggestions` file would never be printed. This is tested machinery
with no production caller, which is why wiring it is nearly free.

### M4 — The `_cht` completion block truncates its target on any failure and reports nothing

`lib/workflows.sh:656-659`:

```bash
if [[ -f ${HOME}/.zsh.d/_cht ]]; then
  printf "Updating cheat.sh tab completion\\n"
  curl https://cheat.sh/:zsh > "${HOME}"/.zsh.d/_cht
fi
```

No section, no rc check, no `-f`. The shell's `>` truncates the target when it sets the
redirect up, before curl has produced anything.

Measured against `https://httpbin.org/status/404` with the target pre-seeded to
`ORIGINAL\n` (9 bytes), on **both** platforms this repo provisions — the production paths
differ by OS and the curl builds differ with them:

| invocation              | macOS rc (8.7.1) | Linux rc (8.5.0) | target after |
| ----------------------- | ---------------- | ---------------- | ------------ |
| `curl -sS URL > file`   | 0                | 0                | 0 bytes      |
| `curl -fsS URL > file`  | 56               | 22               | 0 bytes      |
| `curl -fsS -o file URL` | 56               | 22               | **9 bytes**  |

The `target after` column is identical on both. **The exit code is not**, and that is a
constraint on V5 rather than a curiosity: 22 is `CURLE_HTTP_RETURNED_ERROR`, the code `-f` is
documented to return, while macOS's SecureTransport build reports 56 (`CURLE_RECV_ERROR`) for
the same 404. Any test here asserts non-zero, never a specific value.

Two things follow, and they are separate fixes rather than one:

- **`-f` fixes the reporting.** Without it curl exits 0 on a 404 and the section would record
  OK over an emptied file.
- **`-o` fixes the file.** The redirect form destroys the target regardless of `-f`, because
  the shell owns the truncation; `-o` leaves it intact when there is no body to write. This
  is the half a reader would expect `-f` to cover and it does not.

**And one case neither flag reaches.** `cht.sh` answers an unknown topic with **HTTP 200**
and an error body:

```
curl -fsS -o file https://cht.sh/nonexistent-endpoint-xyz-404
rc=0  size=143  content=[Unknown topic.\nDo you mean one of these ]
```

`-f` keys on HTTP status, so an application-level error served at 200 is invisible to it.
This is named rather than fixed: a content sanity check on a completion script is its own
design question, and the failure it would catch (a valid-looking file whose content is an
error message) is materially rarer than the two above. See Deferred.

### M5 — No test asserts a summary section count

`dotfiles/CLAUDE.md` flags hardcoded count assertions (`[[ "$output" == *"9 OK"* ]]`) as the
hazard when a section is added or removed. Measured across `tests/`:

```
grep -rn '"[0-9]* OK\|[0-9]* failed\|[0-9]* skipped\|[0-9]* warnings' tests/   -> 0 matches
grep -rn '[0-9]\+ sections' tests/                                            -> 0 matches
```

The one near-hit is `tests/setup_env/workflows.bats:752`, which asserts the string
`"sections:"` is _absent_ — unaffected by a section count changing.

The three `_UPDATE_SECTION_ORDER` assertions
(`tests/setup_env/update_summary.bats:824,830,836`) are contiguous-substring ordering checks
that all terminate at `rust`:

```bash
[[ "${_joined}" == *"ai-config git-repos legacy-rsync"* ]]
[[ "${_joined}" == *"ai-config git-repos legacy-rsync git-hooks"* ]]
[[ "${_joined}" == *"git-hooks aws rust"* ]]
```

Inserting a name anywhere after `rust` leaves all three green. The CLAUDE.md warning
describes a historical hazard that the current suite does not carry.

### M6 — Nothing downstream of the affected region consumes cwd

After this change no code in `run_update` moves the parent's cwd at all (M1 says the pipeline
sections never did; M2's block is the last one that does, and it stops). The consumers that
run after the affected region were checked for cwd dependence:

| consumer                       | cwd-dependent? | evidence                                                                                                    |
| ------------------------------ | -------------- | ----------------------------------------------------------------------------------------------------------- |
| `update_gems`                  | no             | `lib/developer.sh:210` — builds a `PATH` prefix, runs `gem update`                                          |
| `_update_check_brewfile_drift` | no             | `lib/update_summary.sh` — `${_OVERRIDE_BREWFILE_PATH:-${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile}`, absolute |
| `_update_summary`              | no             | writes to `${_DOTFILES_RUN_TMPDIR}`, reads via `git -C <absolute>`                                          |
| `_ledger_write_dotfiles_entry` | no             | called from `_update_summary`, same absolute paths                                                          |
| `setup_env.sh` after dispatch  | no             | `_run_or_exit run_update` is the last statement on that path                                                |

**A caveat on the `git -C` row**, stated because `shell.md` documents the trap: `git -C` does
not override an exported `GIT_DIR`. That is pre-existing and unchanged by this work, and
`-t update` is not hook-invoked, so no `GIT_DIR` is in the environment on the path that
matters. Named so a reader does not take the table as a claim that these calls are isolated
in general.

## Design

Three groups. They share a region of `lib/workflows.sh` and a defect class — work inside
`run_update` that the summary cannot see — but the fixes differ, and conflating them is what
made the backlog row's proposed remedy wrong.

### Group A — delete the three dead `cd`-backs

At `:622`, `:632`, `:642`: delete the `cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1`
line. Nothing replaces it and no FAIL is recorded, because per M1 there is no failure to
record — the abort path removed is one that could only ever fire spuriously.

In the same edit, convert each `{ ... }` to `( ... )`:

```bash
if [[ -d ${HOME}/.tfenv ]]; then
  _update_record_start "tfenv"
  printf "Updating tfenv\\n"
  ( cd "${HOME}/.tfenv" && git pull ) 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_tfenv"
  _update_record_end "tfenv" "${PIPESTATUS[0]}"
else
  _update_skip "tfenv" "not installed"
fi
```

This is documentary, not behavioural: the brace group already ran in a subshell by virtue of
its position in the pipeline, and `( )` makes the isolation a property of the code rather
than an inherited consequence of the pipe. It is what stops the next reader re-adding a
`cd`-back. The `local _tfenv_rc` temporary is no longer needed once the `cd`-back between the
pipeline and `PIPESTATUS` is gone, so `PIPESTATUS[0]` can be read inline — matching how the
`aws`, `rust` and `cheat.sh` sections already read it.

**Exit-code equivalence.** `{ cd D && git pull; }` and `( cd D && git pull )` return the same
status in every case: `cd` failing yields `cd`'s status from both, and `git pull` failing
yields `git pull`'s status from both. `PIPESTATUS[0]` is unaffected. The only difference
between the two forms is the cwd side effect, which M1 shows does not exist here.

### Group B — subshell `zsh-autosuggestions` and wire it as a section

```bash
if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  _update_record_start "zsh-autosuggestions"
  printf "Updating zsh-autosuggestions\\n"
  ( cd "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" && git pull ) \
    2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_zsh-autosuggestions"
  _update_record_end "zsh-autosuggestions" "${PIPESTATUS[0]}"
else
  _update_skip "zsh-autosuggestions" "not installed"
fi
```

and in the outer `_run_all` else, alongside its four siblings:

```bash
_update_skip "zsh-autosuggestions" "flag not set"
```

The subshell is doing real work here, unlike Group A: it removes both `cd` sites in M2 by
making the `cd` local, so the `cd`-back has nothing to return from. Both `:662` and `:664`
disappear rather than being taught to report.

`_UPDATE_SECTION_ORDER` (`lib/update_summary.sh:5`) gains `zsh-autosuggestions`, placed
immediately after `oh-my-zsh` — it is an oh-my-zsh plugin, and M5 establishes that any
position after `rust` leaves the three ordering assertions green:

```bash
  ai-config git-repos legacy-rsync git-hooks aws rust oh-my-zsh zsh-autosuggestions tpm tfenv cheat.sh brew-drift
```

This is the coupling `dotfiles/CLAUDE.md` names explicitly: a section recorded but absent
from the array is tracked internally and never printed, with no error.

### Group C — fold the `_cht` completion into the `cheat.sh` section

The two fetches become one recorded unit, each keeping its own reachability guard:

```bash
if [[ -f ${HOME}/bin/cht.sh ]] || [[ -f ${HOME}/.zsh.d/_cht ]]; then
  _update_record_start "cheat.sh"
  (
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      printf "Updating cheat.sh\\n"
      curl -fsS -o "${HOME}/bin/cht.sh" https://cht.sh/:cht.sh || exit 1
      chmod 754 "${HOME}/bin/cht.sh" || exit 1
    fi
    if [[ -f ${HOME}/.zsh.d/_cht ]]; then
      printf "Updating cheat.sh tab completion\\n"
      curl -fsS -o "${HOME}/.zsh.d/_cht" https://cheat.sh/:zsh || exit 1
    fi
  ) 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_cheat.sh"
  _update_record_end "cheat.sh" "${PIPESTATUS[0]}"
else
  _update_skip "cheat.sh" "not installed"
fi
```

Three deliberate choices:

- **The outer condition is a disjunction, not a nesting.** Today the two `if`s are siblings,
  so a machine carrying `~/.zsh.d/_cht` but not `~/bin/cht.sh` still updates its completion.
  Nesting the completion fetch inside the binary's guard would silently stop that. The
  disjunction preserves both independent conditions while producing one section row.
- **`-o`, not `>`.** Per M4 this is the half that saves the file; `-f` alone leaves it
  truncated.
- **`exit 1` inside the subshell, not `return`.** The subshell is not a function, so `return`
  is invalid there. `exit` terminates the subshell only and yields its status to
  `PIPESTATUS[0]`.

The `~/bin/cht.sh` / `"${HOME}/bin/cht.sh"` spelling inconsistency in the current code is
resolved to the braced form throughout, since the lines are being rewritten anyway.

## Verification

Each check below is a command with an expected observable. Where the check depends on code
that does not exist yet it is marked _(post-implementation)_; the rest were run while writing
this spec and their real output appears in Measurements.

**V1 — the summary gains a `zsh-autosuggestions` row on a run where the plugin exists.**
_(post-implementation)_ A bats case drives `run_update` with `_run_all=1` and a fixture
plugin directory, then asserts the rendered summary contains a `zsh-autosuggestions` row.
Must fail before the `_UPDATE_SECTION_ORDER` entry is added — that is the mutation control,
since the `record_end` call alone writes a status file that nothing prints.

**V2 — a failing `git pull` in that section produces FAIL, not silence.**
_(post-implementation)_ With a `git` mock returning 1 for `pull`, assert
`status_zsh-autosuggestions` is `FAIL` and that `run_update`'s own exit status is non-zero.
This is the case that ADR-0027's contract exists for and the one M2 says is currently
unreachable.

**V3 — the section reports SKIP on both absent branches.** _(post-implementation)_ One case
with no plugin directory (`"not installed"`), one with `_run_all=0` (`"flag not set"`).

**V4 — cwd is unchanged across `run_update`.** _(post-implementation)_ Assert `$PWD` before
and after a full mocked `run_update` are equal, invoked from a directory that is _not_ the
dotfiles repo. Run against the pre-change code this must fail; against the post-change code
it must pass. The from-elsewhere invocation is load-bearing: run from the repo root, both
versions end at the repo root and the case cannot discriminate.

**Note which way it fails pre-change, because there are two and the case must accept
either.** With a fixture `${PERSONAL_GITREPOS}/${DOTFILES}` present, M2's block moves cwd
there and leaves it; without one, `:664` fails and `run_update` aborts. The assertion is on
`$PWD` equality, which is violated in the first case and unreachable in the second — so the
case must also assert `run_update` completed, or a spurious abort reads as a pass.

**V5 — a 404 on either cheat.sh fetch records FAIL and leaves the target intact.**
_(post-implementation)_ Point the URLs at a mock returning 404 with the target pre-seeded;
assert `status_cheat.sh` is `FAIL` and the target's content is unchanged. The
content-unchanged half is the assertion that fails if someone reverts `-o` to `>`, per M4.

**V6 — the three `_UPDATE_SECTION_ORDER` ordering assertions still pass.** `make test`.
Predicted green from M5 rather than assumed; the substring anchors all end before the
insertion point.

**V7 — full suite and coverage.** `make test`, then read the CI `bash-coverage` figure rather
than a local one. Per `dotfiles/CLAUDE.md`, CI has landed at exactly the 91% floor on five
consecutive measurements, so this change must not add instrumented lines without tests. The
net line count in `lib/workflows.sh` falls (three `cd`-backs and three `local _*_rc`
temporaries removed, against the Group B/C additions), and every added line is covered by
V1–V5.

## Deferred

- **`update_aws_cli`'s dead `cd`-backs (`lib/developer.sh:34`, `:43`).** Same defect as M1,
  different file, and the function has an existing backlog row of its own
  (`update_aws_cli` and `update_rust` swallow every failure except `cd`). Folding it in would
  put a second file and a second failure class into a change whose whole argument is that the
  five sites split cleanly.
- **Case 2 of ADR-0027 — the run-directory failure at `lib/workflows.sh:331`.** Structurally
  unrecordable: the tmpdir is where records go, so there is no place to write a status file.
  Any fix is a different mechanism (a distinct exit code, or a stderr line), and ADR-0027
  explicitly chose a plain 0/1 contract citing dotfiles#194 as the cost of widening one.
  Its own row.
- **`cht.sh`'s HTTP 200 error bodies.** Per M4, `-f` cannot see an application-level error
  served at 200, so a "Unknown topic" body would be written to `~/bin/cht.sh` and recorded
  OK. A content sanity check is its own design question and the failure is materially rarer
  than the two this spec fixes. Named in the row that gets filed for it, not silently
  dropped.

## Related

- [ADR-0027](../../adr/0027-update-run-exit-code-from-section-status.md) — the exit contract
  that makes case 3 externally visible, and which names this work as a separate fix.
- [2026-08-29-update-run-truthfulness-design.md](2026-08-29-update-run-truthfulness-design.md)
  — the spec ADR-0027 came from; its Deferred section is where `package_capture` and the
  durable run root still sit.
- `dotfiles/CLAUDE.md`, `_UPDATE_SECTION_ORDER` coupling — the documented trap this change
  walks into deliberately and pays for in Group B.

## Multi-Lens Review

Reviewed at commit: `39ee4fd2` (Step 7 self-review commit, before Step 8 dispatch)

Round 1. Three lenses, no shared transcript. Every claim below that this session could check
against the repo was checked; where a lens was refuted, the refutation and its discriminating
artifact are recorded beside the finding rather than the finding being dropped.

### Goal-Fit

Finding, five parts:

1. **M1's "returns to a directory the shell never left" is true of what the line returns
   *from* and false of what it does.** `run_update` contains no `cd` before `:622` other than
   the one inside the pipeline (`awk 'NR>=320 && NR<=621 && /(^|[^_a-zA-Z])cd /'` returns only
   the tfenv brace group — confirmed by this session). So on any invocation from outside the
   dotfiles repo — cron, a wrapper, `$HOME` — the `cd`-back *succeeds and relocates the
   parent's cwd*. The deletion is still right and is now better justified: these lines are a
   silent cwd relocation carrying an abort path, not an inert no-op. **V4's note is wrong as
   written** — with `~/.tfenv` present, `:622` violates `$PWD` equality before M2's block is
   reached, so the pre-change failure is attributed to the wrong line.
2. **V5 cannot falsify the `-f` half of Group C.** `tests/mocks/curl` derives its exit solely
   from `${MOCK_CURL_EXIT:-0}` and never reads `-f` (confirmed: `grep -n '\-f\|MOCK_CURL'
   tests/mocks/curl` shows an argument loop inspecting only `-o`, then `exit
   "${MOCK_CURL_EXIT:-0}"`). Reverting `-fsS -o` to `-sS -o` leaves V5 green. M4 establishes
   two independent fixes and V5 pins only `-o`; the `-f` fix ships with no mutation control.
3. **All 7 cases expect PASS and none pins a derived value on the success path.**
   `_update_record_start`'s arm ends `2>/dev/null || true` (`lib/update_summary.sh:117`), and
   `_update_record_end`'s else renders `"no changes"` for a missing pre-snapshot — byte-identical
   to a real no-op pull. Every existing sibling fixture is a bare `mkdir -p` under a redirected
   `HOME` (`workflows.bats:1631`), not a git repo, so `rev-parse` fails and the section would
   render `[OK] … no changes` having measured nothing, with V1/V2/V3 all passing.
4. **Reads-it, per group.** B and C pass both questions — consumer is the rendered row,
   `~/.dotfiles-update.log`, the ledger entry, and via ADR-0027 the process exit code. **Group A
   has no consumer and changes no verdict.** Acceptable as a deletion (net negative lines), not
   as a mechanism.
5. **Proportionality: the spec leads with its weakest third.** The backlog row that spawned it
   is the least valuable part. The highest-severity defect is introduced as a bullet under M4 —
   an *already-wired* section reporting OK over a truncated executable is a wrong verdict, not a
   missing row.

Verified safe, no action: a new `_UPDATE_SECTION_ORDER` entry cannot render a blank row
(`_update_summary` `continue`s on a missing status file, `:546`); the tally is computed
dynamically (`:573`); one `else` covers every non-`_run_all` path so a single
`_update_skip "zsh-autosuggestions" "flag not set"` suffices.

Assumption: **that V1's fixture will actually exercise the pre-snapshot path.** Genuinely
uncertain — the repo has both patterns, and which one V1 inherits is an implementation choice
not yet made. Settled by writing V1 first and asserting
`[ -s "${_DOTFILES_RUN_TMPDIR}/pre_zsh-autosuggestions" ]`; a zero-byte or absent pre-snapshot
means the case is vacuous.

Disposition:

### Ergonomics

Finding, five parts:

1. **Group C's `|| exit 1` makes the two fetches sequentially dependent, contradicting the
   spec's own rationale.** Raised independently by the Risk lens. The spec argues for preserving
   independence and then preserves it only in the *guard*, not the *failure path*: today a
   failed binary fetch does not stop the completion fetch; under the design it does.
2. **The folding is right for diagnosis and better than two rows.** `_update_write_detail_from_err`
   renders the last 10 non-blank lines of the tee'd err file on FAIL, and each fetch prints its
   own banner immediately before its curl, so the detail names which half failed. `-s` also
   removes the progress meter that currently pollutes that tail.
3. **Both cheat.sh artifacts are 0 bytes on this machine right now** — `~/bin/cht.sh` (mode
   754, a zeroed executable) and `~/.zsh.d/_cht`, both stamped `Aug 29 20:00`. `~/.zsh.d` is on
   `fpath` (`.config/.zshrc.d/5_general.zsh:190`, confirmed), so the empty completion is live.
   **The lens then attributed this to a logged `run_update`, and that attribution does not
   survive checking.** The most recent summary carrying a `cheat.sh` row is `2026-08-29
   11:31:24` → `[OK] cheat.sh updated`; `~/.dotfiles-update.log`'s mtime is `19:03`; the files
   are `20:00`. No logged run wrote them. The bats fixtures cannot have: `workflows.bats:11`
   redirects `HOME` to `BATS_TEST_TMPDIR`. So the artifact is real and its writer is
   **unattributed** — one observable, two stories, and the discriminating artifact is the
   timestamps rather than anything in the summary. Record it as evidence that M4's mechanism
   produces exactly this on-disk state, not as evidence that the section reported OK over it.
4. **SKIP noise is already the dominant output on partial runs.** Measured from
   `~/.dotfiles-update.log`: the last full run rendered **22 rows, `22 sections: 16 OK, 0
   failed, 3 warnings, 3 skipped`** (confirmed by this session); partial runs render 15 rows of
   which 13 are SKIP. Adding the section takes those to 23 and 16. Correct trade — "every
   section always appears" is the summary's contract — but the spec should name the 13 so a
   reader is not judging "+1 SKIP" against an imagined clean summary.
5. **The `"not installed"` branch is near-unreachable, which is good news the spec does not
   claim.** `.config/.zshrc.d/5_general.zsh:43-45` self-heals — any interactive zsh `git
   clone`s the plugin when the directory is missing (confirmed). So the new section is a real
   OK/FAIL row on every full run on every machine that has ever opened a shell, not a permanent
   noise SKIP. V3 must construct the absent state artificially.

Also reported: a real `0 sections: 0 OK, 0 failed, 0 warnings, 0 skipped` render at `2026-08-29
19:03:04`, with two candidate causes and nothing in V1–V7 that would catch either.

Assumption: **that the cheat.sh binary and its zsh completion are one operational unit**, such
that a completion-only failure should render `[FAIL] cheat.sh`. Settled by the operator's answer
to "do you want `-t update` to exit 1 when only the zsh completion 404s?" Partial evidence cuts
toward yes: the completion is on `fpath`, and both artifacts are currently 0 bytes from the same
event, i.e. they already fail together.

Disposition:

### Risk

Finding, seven parts. Exit-status equivalence between `{ }` and `( )` was verified total for
these cases under `set -eE` with an `ERR` trap, both for `cd`-fails and inner-command-fails —
no finding there, and `exit 1` over `return`, and `-o` over `>`, both confirmed correct.

1. **Group A calls the load-bearing half "documentary," and that inversion is the top risk.**
   The deletion is safe *only while the brace group sits in a pipeline*; the `{ } → ( )`
   conversion is what makes it safe unconditionally, i.e. it is the guard against a future edit
   removing the `| tee`. Calling it documentary invites a reviewer to drop it as churn under
   this repo's Surgical Changes rule, landing the risky half alone. Group A must be stated as
   one atomic edit whose conversion is the *precondition* for the deletion.
2. **The falsifier this spec named for M1 is the wrong end of the pipeline.** `lastpipe`
   governs the **last** element and can never make the left side run in the parent. Confirmed
   by this session: `shopt -s lastpipe` then a left-element `cd` leaves `$PWD` at `/tmp`, while
   the same `cd` as the *right* element moves it to `/tmp/lp`. Two consequences — M1's
   conclusion is **stronger** than argued (no bash option runs a non-final pipeline element in
   the parent, so the three `cd`-backs are unreachable-as-guards under every shell mode), and a
   reviewer who tries to break M1 with `lastpipe` gets a confirming result for an unrelated
   reason. That is `behavior.md`'s "a check that cannot falsify the thing it checks," arriving
   inside an otherwise-correct measurement.
3. **M5's published evidence line is false.** It reads `-> 0 matches`; the command returns
   **63**. `[0-9]*` matches zero digits and the leading `"` binds only to the first branch, so
   `[0-9]* failed` matches bare prose. Anchored (`grep -rnE '"[0-9]+ (OK|failed|skipped|warnings)"'`)
   returns **10**, including `update_summary.bats:407-409` (`"8 OK"`, `"1 failed"`, `"1 skipped"`)
   — exactly the shape `CLAUDE.md` warns about. **The conclusion survives, for a reason M5 never
   states:** that test seeds its sections explicitly by name (`brew`, `claude`, `mas`, plus a
   7-element loop) and `_update_summary` `continue`s on a missing status file, so an unseeded
   array entry is uncounted; and the `workflows.bats:2243/2251/2257` hits are `run_check_versions`,
   a different function with its own tally. All confirmed by this session.
4. **Group C silently couples two executions the spec is at pains to keep independent** — same
   finding as Ergonomics 1, reached independently.
5. **Group C moves the `printf` banners inside the tee'd subshell.** They then land in
   `err_cheat.sh`, and on FAIL `_update_write_detail_from_err` renders `tail -10` of that file
   as operator-facing detail, so banners consume detail lines error output needs. Same class as
   the findings-count contamination in `CLAUDE.md`'s cadence section, lower severity.
6. **The `>`-truncation class exists at two further sites the spec neither fixes nor defers:**
   `lib/workflows.sh:162` (`curl https://cht.sh/:cht.sh > ~/bin/cht.sh`, followed by `chmod
   750` where the update path uses `754`) and `:172` (`curl https://cheat.sh/:zsh >
   ~/.zsh.d/_cht`), both on the *install* path. Confirmed by this session, including the
   750/754 inconsistency.
7. **Removing the `local _*_rc` temporaries is a small robustness regression.** Confirmed:
   `local x="${PIPESTATUS[0]}"` is itself a command and resets `PIPESTATUS` to `(0)` — measured
   `captured=1 then PIPESTATUS[0]=0`. So inline reading is correct *today* and fails silently to
   `0` — recording OK over a failure — if anyone later inserts a line between the pipeline and
   the call. It matches the existing `aws`/`rust` style; state the consistency-vs-safety trade
   rather than presenting it as pure subtraction.

Verdict count: 7 of 7 expect PASS; V1 and V4 carry pre-change mutation controls; no case pins a
non-zero derived value on the success path.

Assumption: **that the `zsh-autosuggestions` plugin directory is a git clone on every machine
that has it.** If any machine has it from a tarball or a copied `$HOME`, today's silent no-op
becomes a weekly FAIL row and a non-zero exit — converting benign silence into a recurring false
alarm on the one channel this repo keeps quiet. Settled by
`git -C ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions rev-parse --git-dir` on each of the seven
machines. **This session checked two of seven:** Mac Studio `.git`, remote
`https://github.com/zsh-users/zsh-autosuggestions`; Linux workstation `.git`. Both hold. The
remaining five are unmeasured, so the assumption is supported on the development set and open on
the fleet.

Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. There are no arms to compare,
no judge or evaluator component, and V1–V7 are commands with concrete observables rather than
acceptance criteria open to two readings. Not borderline, so not run.
