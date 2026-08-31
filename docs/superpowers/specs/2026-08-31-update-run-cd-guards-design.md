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

Case 3 is what this spec was opened for. A wrapper or cron job that sees exit 1 and finds no
matching log line is in case 2 or 3, and cannot tell which.

The backlog row proposes the obvious fix: record a FAIL section before returning, at five
call sites. **That fix is wrong for three of the five sites**, for a reason measured below,
and the two it is right for turn out to sit inside a section that reports nothing at all.

**The most serious defect in this region is none of those, and it is worth stating before
them.** `lib/workflows.sh:658` fetches the cheat.sh binary with `curl … > ~/bin/cht.sh`, no
`-f`. On any HTTP error curl exits **0** and the shell has already truncated the target, so
`chmod 754` runs on an empty file, `PIPESTATUS[0]` is 0, and an **already-wired section
records `[OK] cheat.sh updated` over a zeroed executable**. That is a wrong verdict rather
than a missing row, and the exit contract cannot catch it because nothing failed as far as
the contract can see. The same shape sits at three further sites, one of them on the install
path with a different file mode. M4 has the measurements.

So the region contains three defect classes at descending severity — a wrong verdict
(Group C), an invisible section (Group B), and an abort path with no hazard (Group A) — and
the backlog row names only the third.

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

The brace group is the left element of a pipeline, and bash runs every pipeline element in
its own subshell. The `cd` therefore never reaches the parent, and the `cd`-back is
returning from a directory the shell never left.

Measured on both fleet development machines:

```
bash 5.3.15 (Studio)      after brace-in-pipeline: /tmp (was /tmp)
                          after brace-no-pipe:     /tmp/cdtest
bash 5.2.21 (workstation) after: /tmp (was /tmp)
```

The second line of the Studio run is the control: the same brace group _without_ a pipe does
move the parent, so the probe discriminates rather than reporting `/tmp` for an unrelated
reason.

**`lastpipe` is not an exception to this, and an earlier revision of this spec said it was.**
That was a falsifier which cannot falsify the claim it was attached to — `lastpipe` moves the
**last** element of a pipeline into the parent shell and has no bearing on the first.
Measured, with the option deliberately enabled:

```
shopt -s lastpipe;  { cd /tmp/lp && true; } | cat   ->  $PWD = /tmp      (left:  did NOT move)
shopt -s lastpipe;  cat /dev/null | { cd /tmp/lp; } ->  $PWD = /tmp/lp   (right: moved)
```

The conclusion is therefore **stronger** than the earlier version argued: there is no bash
option under which a non-final pipeline element runs in the parent, so these three `cd`-backs
are unreachable-as-guards under every shell mode rather than merely under the default one.
The correction matters beyond this spec — a reviewer told that `lastpipe` is the falsifier
will enable it, see a confirming result, and have learned nothing about the actual claim.

**The probe is a synthetic fixture, not the production lines, and that is deliberate.** What
is under test is a bash language property — pipeline elements execute in subshell
environments — and a fixture isolates it from `git pull`, the `tee`, and the surrounding
function. Reproducing it inside `run_update` would add three confounders and could not
falsify anything the fixture cannot.

**Consequence, and it is not "the line does nothing".** An earlier revision said these
`cd`-backs "return to a directory the shell never left" and left the reader to conclude they
are inert. The first half is true and the conclusion is wrong. `cd` is unconditional: it goes
to `${PERSONAL_GITREPOS}/${DOTFILES}` whether or not anything left. And `run_update` contains
no other `cd` before `:622` —

```
awk 'NR>=320 && NR<=621 && /(^|[^_a-zA-Z])cd /' lib/workflows.sh
  ->  { cd "${HOME}/.tfenv" && git pull; } 2>&1 | tee ...     (the pipeline one, only hit)
```

— so on any invocation from outside the dotfiles repo (cron, a wrapper, `$HOME`, an agent
shell), `:622` **succeeds and silently relocates the parent's cwd** for the rest of the run.

So the three lines are worse than dead and better characterised as: a silent cwd relocation
nobody asked for, carrying an abort path for a hazard that does not exist. Deleting them
removes both. There is still no failure state to record, which is what refutes the backlog
row's proposed fix — but the reason to delete them is not that they do nothing.

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

**The class has four sites, not two, and two of them are on the install path.** The update
path is `:658` (binary) and `:661` (completion); `install_developer_tools` carries the same
construct at `:162` and `:172`:

```bash
:162   curl https://cht.sh/:cht.sh > ~/bin/cht.sh
:163   chmod 750 "${HOME}"/bin/cht.sh          # note: 750, where :659 uses 754
:172   curl https://cheat.sh/:zsh > "${HOME}"/.zsh.d/_cht
```

All four are in scope. The install path runs once per machine rather than weekly, so its
exposure is lower — but it is the same characterised class, and leaving half of it unfixed
and unnamed is the criticism this spec levels at the backlog row. The `750`/`754`
inconsistency is resolved to `754` in the same edit: the update path is the one that has been
running, `~/bin/cht.sh` is invoked by the user, and there is no argument on record for the
group-execute bit differing between the two paths.

**Both artifacts are 0 bytes on this machine right now, and the writer is unattributed.**

```
-rwxr--r--  0  Aug 29 20:00  /Users/bruce/bin/cht.sh        <- mode 754, zero-length executable
-rw-r--r--  0  Aug 29 20:00  /Users/bruce/.zsh.d/_cht
```

`~/.zsh.d` is on `fpath` (`.config/.zshrc.d/5_general.zsh:190`), so the empty completion is
live, not dead weight. That is the on-disk state this class produces, and it is present.

**What cannot be concluded from it, and was, in review.** Two lenses independently joined
these files to the `[OK] cheat.sh updated` row in `~/.dotfiles-update.log` and reported that
M4 had already fired in production with a green verdict over it. The timestamps refuse that:
the most recent summary carrying a `cheat.sh` row is `2026-08-29 11:31:24`, the log's own
mtime is `19:03`, and the files are `20:00`. No logged run wrote them. The bats fixtures
cannot have either — `workflows.bats:11` redirects `HOME` to `BATS_TEST_TMPDIR`.

So: one observable, two stories, and the discriminating artifact is the timestamps rather
than anything in the summary. The honest reading is that the mechanism M4 measures produces
exactly this state and this state exists; the specific event that produced it is not in any
record this repo keeps. Recorded that way rather than as the stronger claim, which would have
been the more persuasive sentence and the unsupported one.

### M5 — Ten tests do assert summary counts, and adding a section cannot move any of them

`dotfiles/CLAUDE.md` flags hardcoded count assertions (`[[ "$output" == *"9 OK"* ]]`) as the
hazard when a section is added or removed. **An earlier revision of this section reported
`-> 0 matches` for the grep below. That number was never the command's output.** The command
returns **63**:

```
grep -rn '"[0-9]* OK\|[0-9]* failed\|[0-9]* skipped\|[0-9]* warnings' tests/     -> 63
```

`[0-9]*` matches _zero_ digits, and the leading `"` binds only to the first alternation
branch, so `[0-9]* failed` matches the bare word `failed` anywhere in the tree — mostly
prose in unrelated comments. The grep was run, its 63 lines were read, the hits were judged
irrelevant, and a conclusion was then written into the slot where the output belongs. That
is the failure this repo's standards spend the most words on, committed while writing a spec
about truthful reporting.

Anchored, it finds **10 real count assertions**:

```
grep -rnE '"[0-9]+ (OK|failed|skipped|warnings)"' tests/                          -> 10

tests/setup_env/unit.bats:795            *"1 warnings"*
tests/setup_env/update_summary.bats:407  *"8 OK"*
tests/setup_env/update_summary.bats:408  *"1 failed"*
tests/setup_env/update_summary.bats:409  *"1 skipped"*
tests/setup_env/update_summary.bats:473  *"1 OK"*
tests/setup_env/update_summary.bats:644  *"1 warnings"*
tests/setup_env/update_summary.bats:645  != *"1 failed"*
tests/setup_env/workflows.bats:2243      *"8 skipped"*
tests/setup_env/workflows.bats:2251      *"10 warnings"*
tests/setup_env/workflows.bats:2257      *"8 OK"*
```

`update_summary.bats:407-409` is exactly the shape `CLAUDE.md` warns about.

**The conclusion survives, and the reason is a mechanism the earlier revision never stated.**
Two independent facts, both checked:

- **The `update_summary.bats` cases seed their sections by name, not by iterating the array.**
  `:395-404` writes `status_brew`, `status_claude`, `status_mas`, then loops
  `softwareupdate pip gems oh-my-zsh tpm tfenv cheat.sh`. `_update_summary` `continue`s on any
  section with no `status_` file (`lib/update_summary.sh:546`), so an unseeded array entry is
  invisible to the tally. Adding `zsh-autosuggestions` to `_UPDATE_SECTION_ORDER` leaves
  `8 OK, 1 failed, 1 skipped` unchanged.
- **The `workflows.bats:2243/2251/2257` hits are `run_check_versions`**, a different function
  with its own tally over tools rather than sections. Unaffected by anything here.

The tally line itself is `printf "%d sections: …"` computed from the loop (`:573`), so nothing
hardcodes a total.

The three `_UPDATE_SECTION_ORDER` assertions
(`tests/setup_env/update_summary.bats:824,830,836`) are contiguous-substring ordering checks
that all terminate at `rust`:

```bash
[[ "${_joined}" == *"ai-config git-repos legacy-rsync"* ]]
[[ "${_joined}" == *"ai-config git-repos legacy-rsync git-hooks"* ]]
[[ "${_joined}" == *"git-hooks aws rust"* ]]
```

Inserting a name anywhere after `rust` leaves all three green.

**Read this section as the reason to re-run a grep rather than quote one.** A reader
re-deriving M5 from the original evidence line gets 63 hits including three literal count
assertions, cannot reconcile that with `0 matches`, and has no way to tell whether the design
is safe. The safety is real; it just has nothing to do with the absence the earlier revision
claimed.

### M5b — What a full and a partial run actually render

Adding a section is judged against the summary's current size, not an imagined clean one.
Measured from `~/.dotfiles-update.log`:

```
last full run (2026-08-29 11:31:24)   22 rows   22 sections: 16 OK, 0 failed, 3 warnings, 3 skipped
partial runs                          15 rows   13 of them SKIP
```

Group B takes those to 23 and 16 rows. **SKIP is already the dominant row type on a partial
run**, so the marginal `_update_skip "zsh-autosuggestions" "flag not set"` is one more line in
a column that is already 13 deep — not a new class of noise. It is added because "every
section always appears" is the summary's contract, and four sibling sections already honour
it.

**The `"not installed"` branch is close to unreachable, which is better than the spec's
earlier framing implied.** `.config/.zshrc.d/5_general.zsh:43-45` self-heals:

```zsh
if [[ ! -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-...}/plugins/zsh-autosuggestions
fi
```

Any interactive zsh restores the directory. So on every machine that has ever opened a shell,
the new section is a real OK/FAIL row on every full run rather than a permanent SKIP. V3 has
to construct the absent state artificially, and does.

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

**The conversion is a precondition for the deletion, not a tidy-up beside it. Land them
together or not at all.** An earlier revision called it "documentary, not behavioural", which
inverts which half carries the risk. The deletion is safe _only while the group sits in a
pipeline_: the isolation today is an inherited consequence of the `| tee`, not a property of
the code. `( )` makes it the code's own property, so a future edit that drops the pipe — this
spec's own Deferred list contemplates work in these lines — cannot silently reintroduce a
parent-scope `cd` with no `cd`-back to follow it.

Stated the earlier way, a reviewer applying this repo's Surgical Changes rule ("do not
reformat as a side effect of an unrelated change") would correctly strike the conversion as
churn and land the deletion alone, which is the one combination that is worse than doing
nothing.

**Exit-code equivalence, verified rather than argued.** `{ cd D && git pull; }` and
`( cd D && git pull )` as a pipeline's left element return identical `PIPESTATUS[0]` for both
a failing `cd` and a failing inner command, under `set -eE` with an `ERR` trap installed, with
no trap escape to the parent and the parent surviving in both. The only difference between
the forms is the cwd side effect.

**Removing the `local _*_rc` temporaries is a consistency-versus-safety trade, not pure
subtraction, and it is taken deliberately.** With the `cd`-back gone there is nothing between
the pipeline and `_update_record_end`, so `${PIPESTATUS[0]}` can be read inline — matching how
`aws`, `rust` and `cheat.sh` already read it. But `local` is itself a command and resets
`PIPESTATUS`:

```
false | true; local_test() { local x="${PIPESTATUS[0]}"; echo "$x ${PIPESTATUS[0]}"; }
  ->  captured=1  then PIPESTATUS[0]=0
```

So the temporaries were never a durable capture either — anything read after them was already
stale. The inline form is correct today and fails **silently to 0** — recording OK over a
failure — if someone later inserts a line between the pipeline and the call. Consistency with
the three sections that already do this wins, and V2 is the test that catches a regression.

### Group B — subshell `zsh-autosuggestions` and wire it as a section

```bash
_zsh_autosug="${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
if [[ -d ${_zsh_autosug} ]]; then
  if git -C "${_zsh_autosug}" rev-parse --git-dir >/dev/null 2>&1; then
    _update_record_start "zsh-autosuggestions"
    printf "Updating zsh-autosuggestions\\n"
    ( cd "${_zsh_autosug}" && git pull ) \
      2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_zsh-autosuggestions"
    _update_record_end "zsh-autosuggestions" "${PIPESTATUS[0]}"
  else
    _update_skip "zsh-autosuggestions" "present but not a git checkout"
  fi
else
  _update_skip "zsh-autosuggestions" "not installed"
fi
```

**The git-dir guard is what keeps this change from manufacturing a weekly false alarm on an
unmeasured machine.** Group B converts a silent no-op into a FAIL that sets `_fail` and, via
ADR-0027, exits 1 — read by the weekly cadence agent and by `doctor`. That is correct when the
directory is a clone whose `git pull` genuinely failed, and wrong when the directory arrived
by some other route (a tarball, a package, a copied `$HOME`), where `git pull` has always
failed harmlessly and silently. The plugin has several documented install methods, and this
session measured only 2 of the 7 machines:

```
Mac Studio        rev-parse --git-dir -> .git   remote -> https://github.com/zsh-users/zsh-autosuggestions
Linux 7950X       rev-parse --git-dir -> .git
```

Both hold. The other five are unmeasured, and would stay unmeasured only until someone
reinstalled a plugin by hand — a point-in-time attestation, not a durable one. The guard
removes the question instead of answering it: a non-repo directory records SKIP with its
reason, no machine can produce a FAIL for having installed the plugin differently, and nothing
here depends on a fleet sweep that would need redoing.

and in the outer `_run_all` else, alongside its four siblings:

```bash
_update_skip "zsh-autosuggestions" "flag not set"
```

The subshell is doing real work here, unlike Group A: it removes both `cd` sites in M2 by
making the `cd` local, so the `cd`-back has nothing to return from. Both `:662` and `:664`
disappear rather than being taught to report.

`_UPDATE_SECTION_ORDER` (`lib/update_summary.sh:5`) gains `zsh-autosuggestions`, placed
immediately after `oh-my-zsh` — it is an oh-my-zsh plugin, and M5 establishes both that any
position after `rust` leaves the three ordering assertions green and that the ten count
assertions cannot move, because `_update_summary` skips array entries no test seeds:

```bash
  ai-config git-repos legacy-rsync git-hooks aws rust oh-my-zsh zsh-autosuggestions tpm tfenv cheat.sh brew-drift
```

This is the coupling `dotfiles/CLAUDE.md` names explicitly: a section recorded but absent
from the array is tracked internally and never printed, with no error.

### Group C — fold the `_cht` completion into the `cheat.sh` section

The two fetches become one recorded unit, each keeping its own reachability guard:

The two fetches become one recorded unit, each keeping its own reachability guard **and its
own failure**:

```bash
if [[ -f ${HOME}/bin/cht.sh ]] || [[ -f ${HOME}/.zsh.d/_cht ]]; then
  _update_record_start "cheat.sh"
  [[ -f ${HOME}/bin/cht.sh ]]   && printf "Updating cheat.sh\\n"
  [[ -f ${HOME}/.zsh.d/_cht ]]  && printf "Updating cheat.sh tab completion\\n"
  (
    _rc=0
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      curl -fsS -o "${HOME}/bin/cht.sh" https://cht.sh/:cht.sh || _rc=1
      chmod 754 "${HOME}/bin/cht.sh" || _rc=1
    fi
    if [[ -f ${HOME}/.zsh.d/_cht ]]; then
      curl -fsS -o "${HOME}/.zsh.d/_cht" https://cheat.sh/:zsh || _rc=1
    fi
    exit "${_rc}"
  ) 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_cheat.sh"
  _update_record_end "cheat.sh" "${PIPESTATUS[0]}"
else
  _update_skip "cheat.sh" "not installed"
fi
```

Five deliberate choices, two of them corrections to an earlier revision:

- **The outer condition is a disjunction, not a nesting.** Today the two `if`s are siblings,
  so a machine carrying `~/.zsh.d/_cht` but not `~/bin/cht.sh` still updates its completion.
  Nesting the completion fetch inside the binary's guard would silently stop that. The
  disjunction preserves both independent conditions while producing one section row.
- **An `_rc` accumulator, not `|| exit 1`.** An earlier revision used short-circuit `exit`,
  which reintroduced through _sequencing_ exactly the coupling the disjunction was defending
  against: a failed binary fetch would terminate the subshell and the completion would never
  be attempted, under a row named for the binary. Both lenses that read it caught this
  independently. With the accumulator both fetches always run, and either failure still yields
  a non-zero status to `PIPESTATUS[0]`.
- **The `printf` banners stay outside the subshell.** An earlier revision moved them inside,
  where they would land in `err_cheat.sh` — and on FAIL, `_update_write_detail_from_err`
  renders `tail -10` of that file as the operator-facing detail block, so two banner lines
  would displace two lines of the error output the block exists to show. Same class as the
  detector-banner contamination of the cadence `findings` count that `CLAUDE.md` records, at
  lower severity. Emitting them from the parent under the same guards keeps the detail tail
  purely diagnostic. `-s` also removes curl's progress meter from that file.
- **`-o`, not `>`.** Per M4 this is the half that saves the file; `-f` alone leaves it
  truncated.
- **`exit "${_rc}"` inside the subshell, not `return`.** The subshell is not a function, so
  `return` is invalid there. `exit` terminates the subshell only and yields its status to
  `PIPESTATUS[0]`.

Both artifacts are treated as one operational unit, so a completion-only failure renders
`[FAIL] cheat.sh` and exits 1. That is a decision rather than a default: `~/.zsh.d` is on
`fpath`, so the completion is live rather than dead weight, and M4 shows both files currently
zeroed by the same event — they already fail together.

**The install path is fixed in the same change** (`lib/workflows.sh:162`, `:172`), per M4's
four-site count. Same `-fsS -o` treatment, and `chmod 750` there is brought to `754` to match
the update path — one mode for one file, rather than whichever path last wrote it deciding.

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

**The fixture must be a real `git init` repo, and the case must assert the pre-snapshot
landed.** Every existing sibling fixture is a bare `mkdir -p` under a redirected `HOME`
(`workflows.bats:1631`), which is not a git checkout — so `_update_record_start`'s
`git -C … rev-parse HEAD > pre_… 2>/dev/null || true` writes nothing, the `|| true` swallows
it, and `_update_record_end` falls to its no-pre-snapshot branch rendering `no changes`. Under
the new git-dir guard a bare `mkdir -p` fixture takes the SKIP arm instead, which is a
different vacuity: the case would assert a row exists and never exercise the update path at
all. Add `[ -s "${_DOTFILES_RUN_TMPDIR}/pre_zsh-autosuggestions" ]` to V1 — an absent or
zero-byte pre-snapshot means the case measured nothing.

**V2 — a failing `git pull` in that section produces FAIL, not silence.**
_(post-implementation)_ With a `git` mock returning 1 for `pull`, assert
`status_zsh-autosuggestions` is `FAIL` and that `run_update`'s own exit status is non-zero.
This is the case that ADR-0027's contract exists for and the one M2 says is currently
unreachable.

**V3 — the section reports SKIP on all three absent branches.** _(post-implementation)_ One
case with no plugin directory (`"not installed"`), one with a directory that is not a git
checkout (`"present but not a git checkout"` — the new guard), one with `_run_all=0`
(`"flag not set"`). The middle case is the one that must not be written as a bare `mkdir -p`
by accident, since that is also how V1's fixture goes wrong; here it is the point.

Note that the `"not installed"` state has to be constructed rather than found: per M5b,
`5_general.zsh:43-45` self-heals the directory on any interactive zsh, so the branch is close
to unreachable on a real machine.

**V4 — cwd is unchanged across `run_update`.** _(post-implementation)_ Assert `$PWD` before
and after a full mocked `run_update` are equal, invoked from a directory that is _not_ the
dotfiles repo. Run against the pre-change code this must fail; against the post-change code
it must pass. The from-elsewhere invocation is load-bearing: run from the repo root, both
versions end at the repo root and the case cannot discriminate.

**Which line fails pre-change, and which way.** An earlier revision attributed this to M2's
`zsh-autosuggestions` block. That is wrong: M1 establishes there is no `cd` in `run_update`
before `:622`, so with `~/.tfenv` present the **tfenv** `cd`-back at `:622` relocates cwd to
the dotfiles repo first and violates `$PWD` equality before M2's block is ever reached.

There are then three pre-change failure paths, and the case must accept any of them:
`:622`/`:632`/`:642` relocating cwd (fixture repo present), M2's block relocating it (fixture
repo present, tfenv absent), or a `cd`-back failing outright and aborting the run (no fixture
repo). The third does not violate `$PWD` equality — it never reaches the assertion — so the
case must **also assert `run_update` completed**, or a spurious abort reads as a pass.

**V5 — a 404 on either cheat.sh fetch records FAIL and leaves the target intact.**
_(post-implementation)_ With the target pre-seeded, drive a simulated 404 and assert
`status_cheat.sh` is `FAIL` **and** the target's content is unchanged.

**This needs a change to `tests/mocks/curl`, which today cannot express the case.** The mock
derives its exit solely from `${MOCK_CURL_EXIT:-0}` and its argument loop inspects only `-o`;
`-f` is never read. So a FAIL comes from an env var rather than a simulated HTTP status, and
reverting `-fsS -o` to `-sS -o` leaves V5 green — pinning M4's `-o` half while the `-f` half,
the one that stops the section recording OK over a zeroed executable, ships with no mutation
control at all.

Add `MOCK_CURL_HTTP_STATUS`, honoured **only when `-f` appears in argv**: with `-f` and a 4xx
value the mock exits non-zero and writes nothing; without `-f` it exits 0 and writes the error
body, mirroring real curl. Unset, it changes nothing, so the shared mock stays
backward-compatible with every existing suite. Assert on **non-zero**, never a specific code —
per M4 the same 404 yields 56 on macOS and 22 on Linux.

**V6 — the three `_UPDATE_SECTION_ORDER` ordering assertions and the ten count assertions
still pass.** `make test`. Predicted green from M5, on two distinct mechanisms: the ordering
anchors all terminate at `rust`, and the count assertions seed their sections by name while
`_update_summary` skips unseeded array entries.

**V7 — a derived value on the success path, not a verdict.** _(post-implementation)_ V1–V6 all
expect PASS, and none of them would fail if the measurement produced nothing: with the
pre-snapshot missing, `_update_record_end` renders `no changes` and V1 (row present), V2
(FAIL), V3 (SKIP), V5 (cheat.sh) all still pass. Pin a value instead — fixture git repo,
advance `HEAD` by two commits between `record_start` and `record_end`, assert
`result_zsh-autosuggestions` reads literally `2 commit(s)`.

The existing `update_summary.bats:793` case looks like this but is not: it hand-seeds the
pre-file and stubs `_update_git_diff`, so it exercises neither `record_start` writing the
snapshot nor the `run_update` path. V7 is the only case in the suite that tests the
measurement rather than the comparison.

**V8 — full suite and coverage.** `make test`, then read the CI `bash-coverage` figure rather
than a local one. Per `dotfiles/CLAUDE.md`, CI has landed at exactly the 91% floor on five
consecutive measurements, so this change must not add instrumented lines without tests. The
net line count in `lib/workflows.sh` is roughly flat (three `cd`-backs and three `local _*_rc`
temporaries removed, against the Group B guard and the Group C accumulator), and every added
line is covered by V1–V7.

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
- **Who zeroed `~/bin/cht.sh` and `~/.zsh.d/_cht` at `2026-08-29 20:00`.** Per M4 the files
  are real and no logged run, and no bats fixture, can account for them. Both are repaired by
  the next successful `-t update` after this change lands, so the artifact is not itself a
  problem to carry — but "a write to a tracked `$HOME` path that no record explains" is worth
  one row, because the answer is either a manual invocation nobody wrote down or a path
  through this code that this spec has not found.

**No longer deferred:** the install-path `>` truncation at `lib/workflows.sh:162` and `:172`.
An earlier revision fixed the update path only and did not mention them, which is the same
half-fixed-and-unnamed shape this spec criticises the backlog row for. They are in Group C.

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
   _from_ and false of what it does.** `run_update` contains no `cd` before `:622` other than
   the one inside the pipeline (`awk 'NR>=320 && NR<=621 && /(^|[^_a-zA-Z])cd /'` returns only
   the tfenv brace group — confirmed by this session). So on any invocation from outside the
   dotfiles repo — cron, a wrapper, `$HOME` — the `cd`-back _succeeds and relocates the
   parent's cwd_. The deletion is still right and is now better justified: these lines are a
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
   an _already-wired_ section reporting OK over a truncated executable is a wrong verdict, not a
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

Disposition: **Addressed** (user, 2026-08-31) — all five parts, plus the assumption.
Findings 1 and 3 are corrections to spec errors: M1 is reframed as a silent cwd relocation
with the `awk` output that establishes no prior `cd` exists, and V4's attribution is corrected
to `:622`. Finding 2 is addressed by adding `MOCK_CURL_HTTP_STATUS` to `tests/mocks/curl`,
honoured only when `-f` is in argv, so V5 falsifies both halves of M4 — the user chose this
over a real local server (heavier, adds a port dependency) and over accepting the gap. Finding
3's derived-value case is now V7, pinning `2 commit(s)`. Finding 4 is accepted as written:
Group A stays, justified as a deletion rather than a mechanism. Finding 5 is addressed —
the Problem section now leads with Group C's wrong verdict and states the three classes in
descending severity. The assumption is addressed in V1, which must now assert a non-empty
pre-snapshot.

### Ergonomics

Finding, five parts:

1. **Group C's `|| exit 1` makes the two fetches sequentially dependent, contradicting the
   spec's own rationale.** Raised independently by the Risk lens. The spec argues for preserving
   independence and then preserves it only in the _guard_, not the _failure path_: today a
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

Disposition: **Addressed** (user, 2026-08-31), with finding 3 partly refuted rather
than adopted. Finding 1 is fixed with an `_rc` accumulator — the user confirmed the two
artifacts are one operational unit, so both fetches always attempt and either failure yields
FAIL and exit 1. Finding 2 needed no change. Finding 3's artifact is recorded in M4; its
attribution to a logged run is refuted there with the discriminating timestamps, and the
non-attribution is deferred as its own row. Findings 4 and 5 are recorded as M5b. The
assumption is settled by the user in favour of one unit.

### Risk

Finding, seven parts. Exit-status equivalence between `{ }` and `( )` was verified total for
these cases under `set -eE` with an `ERR` trap, both for `cd`-fails and inner-command-fails —
no finding there, and `exit 1` over `return`, and `-o` over `>`, both confirmed correct.

1. **Group A calls the load-bearing half "documentary," and that inversion is the top risk.**
   The deletion is safe _only while the brace group sits in a pipeline_; the `{ } → ( )`
   conversion is what makes it safe unconditionally, i.e. it is the guard against a future edit
   removing the `| tee`. Calling it documentary invites a reviewer to drop it as churn under
   this repo's Surgical Changes rule, landing the risky half alone. Group A must be stated as
   one atomic edit whose conversion is the _precondition_ for the deletion.
2. **The falsifier this spec named for M1 is the wrong end of the pipeline.** `lastpipe`
   governs the **last** element and can never make the left side run in the parent. Confirmed
   by this session: `shopt -s lastpipe` then a left-element `cd` leaves `$PWD` at `/tmp`, while
   the same `cd` as the _right_ element moves it to `/tmp/lp`. Two consequences — M1's
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
~/.zsh.d/_cht`), both on the _install_ path. Confirmed by this session, including the
   750/754 inconsistency.
7. **Removing the `local _*_rc` temporaries is a small robustness regression.** Confirmed:
   `local x="${PIPESTATUS[0]}"` is itself a command and resets `PIPESTATUS` to `(0)` — measured
   `captured=1 then PIPESTATUS[0]=0`. So inline reading is correct _today_ and fails silently to
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

Disposition: **Addressed** (user, 2026-08-31) — all seven parts and the assumption.
Findings 1, 2, 3 and 7 are corrections to spec errors and are made in M1, M5 and Group A;
finding 2's `lastpipe` correction is written up as a falsifier that could not falsify, since
that is the transferable half. Finding 4 shares its fix with Ergonomics 1. Finding 5 moves the
banners out of the subshell. Finding 6 is fixed rather than deferred — the user chose to fix
both install-path sites and resolve `750` to `754` in the same change, over deferring either.
The assumption is addressed by construction rather than by measurement: a `git -C … rev-parse
--git-dir` guard yields SKIP for a non-checkout, so the five unmeasured machines cannot
produce a false FAIL and no fleet sweep is needed. The user chose this over measuring the
other five, on the grounds that a sweep is a point-in-time attestation that a hand
reinstallation invalidates.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. There are no arms to compare,
no judge or evaluator component, and V1–V7 are commands with concrete observables rather than
acceptance criteria open to two readings. Not borderline, so not run.
