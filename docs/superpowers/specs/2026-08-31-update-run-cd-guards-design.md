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
them.** `lib/workflows.sh:650` fetches the cheat.sh binary with `curl … > ~/bin/cht.sh`, no
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

**The class has four sites, and they are not the same construct — an earlier revision said
they were.** The update path is `:650` (binary) and `:658` (completion);
`run_setup_user()` carries `curl … > …` at `:162` and `:172`. But `:172` is guarded:

```bash
update  :650  { curl https://cht.sh/:cht.sh > ~/bin/cht.sh && chmod 754 ...; }   # truncates
update  :658    curl https://cheat.sh/:zsh > "${HOME}"/.zsh.d/_cht              # truncates
install :162    curl https://cht.sh/:cht.sh > ~/bin/cht.sh                      # truncates
install :163    chmod 750 "${HOME}"/bin/cht.sh
install :171  if [[ ! -f ${HOME}/.zsh.d/_cht ]]; then                           # note the `!`
install :172    curl https://cheat.sh/:zsh > "${HOME}"/.zsh.d/_cht              # never-retry
```

`:172` fetches **only when the file is absent**, so it can never truncate an existing one and
the hazard M4 measures is structurally unreachable there. Its hazard is the inverse: a 404
creates a **0-byte `_cht` that then satisfies the `! -f` guard forever**, so the install path
never retries and the completion is permanently empty. `-fsS -o` fixes that too — no file is
created on failure — for a reason worth stating rather than folding into "same class".

Widening from two sites to four on class symmetry and then describing all four identically is
the move this spec criticises the backlog row for, in the other direction. All four are still
in scope; three exhibit truncation and one exhibits never-retry.

**The `chmod 750` at `:163` is left alone.** An earlier revision harmonised it to the update
path's `754`, arguing there was "no argument on record for the group-execute bit differing".
Group-execute does not differ — `750` is `rwxr-x---` and `754` is `rwxr-xr--`, both `r-x` for
group, and the delta is **other-read**. So that sentence described a difference that does not
exist, and the change it justified would have made a network-downloaded `$HOME` executable
world-readable, with no defect behind it and no verification case. Cut. If the split matters
it gets its own row and an actual argument.

**Both artifacts were 0 bytes when measured on 2026-08-31, and the writer is unattributed. They were refetched on 2026-09-01 at 11:36 and are now 22888 and 517 bytes — the state below is a dated observation, not a present-tense claim.**

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

**One discriminator does narrow it, and it was sitting in the `ls` output unused.**
`~/bin/cht.sh` is mode **754**, and only the update path chmods 754 — the install path uses
750. So the file was created by some execution of the update-path block, which is more than
the timestamps alone establish. It does not identify the zeroing event, since `>` preserves
mode, but it rules out the install path as the file's origin.

**Both endpoints are healthy right now** — `curl -w '%{http_code} %{size_download}'` returns
`200 / 22888` for `:cht.sh` and `200 / 517` for `:zsh`, real script bodies. That removes "the
service is currently serving empty 200s" as an explanation and leaves the attribution open.

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

**Keep the conversion with the deletion.** The isolation today is an inherited consequence of
the `| tee`, not a property of the code; `( )` makes it the code's own, so a future edit that
drops the pipe cannot silently reintroduce a parent-scope `cd` with no `cd`-back after it. It
costs two characters. An earlier revision spent a long argument on this — round-2 review
correctly noted that was the spec's longest single defence, for the least severe of its three
groups, against a diff that does not exist. Change kept, argument trimmed to this paragraph.

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
  if [[ -e ${_zsh_autosug}/.git ]]; then
    _update_record_start "zsh-autosuggestions"
    printf "Updating zsh-autosuggestions\\n"
    ( cd "${_zsh_autosug}" && git pull ) \
      2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_zsh-autosuggestions"
    _update_record_end "zsh-autosuggestions" "${PIPESTATUS[0]}"
  else
    _update_skip "zsh-autosuggestions" "not a git checkout — reinstall to enable updates"
  fi
else
  _update_skip "zsh-autosuggestions" "not installed"
fi
```

**The guard is a `.git` existence test, and an earlier revision's `git -C … rev-parse
--git-dir` was fooled in exactly the case the guard exists for.** `rev-parse --git-dir` walks
**upward**, and `~/.oh-my-zsh` is itself a git checkout (`git -C ~/.oh-my-zsh rev-parse
--git-dir` → `.git`, measured). So a tarball or package install of the plugin, nested inside
that working tree, takes the **update** arm:

```
git -C <omz>/custom/plugins/zsh-autosuggestions rev-parse --git-dir   ->  <omz>/.git   rc 0
git -C <omz>/custom/plugins/zsh-autosuggestions rev-parse --show-toplevel  ->  <omz>
```

Downstream the misdirection is consistent, which is what makes it invisible: `_update_record_start`
snapshots the wrong repo's HEAD, `( cd plugin && git pull )` pulls **oh-my-zsh** — which the
`oh-my-zsh` section already pulled forty lines earlier in the same run, so HEAD has not moved
— and `_update_record_end` renders `[OK] zsh-autosuggestions   no changes`, forever,
byte-identical to a healthy up-to-date plugin.

That is strictly worse than the problem the guard was added for. Pre-change the block is a
silent no-op; the broken guard makes it a silent **false OK** that also double-pulls a second
repo under a section named for the first. A false FAIL would at least have been visible. Found
independently by this session and by the round-2 Risk lens, with the same discriminator.

`[[ -e "${dir}/.git" ]]` rejects the nested non-clone, and `-e` rather than `-d` also accepts
the `.git`-as-file form that submodules and linked worktrees use. It touches no git plumbing,
so it is immune to the second way past the old guard: **an exported `GIT_DIR` defeats
`git -C` entirely** —

```
GIT_DIR=/other/.git git -C <unrelated dir> rev-parse --git-dir   ->  /other/.git   rc 0
GIT_DIR=... env -u GIT_DIR git -C <same>   rev-parse --git-dir   ->  <its real answer>
```

— which `shell.md` documents, and which reaches the test harness specifically, since
`scripts/pre-push` runs `make test` from a hook and git exports `GIT_DIR` into hooks. Any
future git-based variant of this guard needs `env -u GIT_DIR -u GIT_WORK_TREE -u
GIT_COMMON_DIR -u GIT_INDEX_FILE`; the `-e` test needs nothing.

**The SKIP reason names a remedy, because this branch never self-heals.**
`5_general.zsh:44` fires on `[[ ! -d … ]]` only, so `"not installed"` is transient — any
interactive zsh re-clones — while a directory present without `.git` (an interrupted clone, a
deleted `.git`) is permanent and would otherwise sit un-updatable in a SKIP column that M5b
measures as already 13 rows deep on a partial run. `"not a git checkout — reinstall to enable
updates"` costs nothing and keeps the guard from converting a defect into the silence Group B
exists to end.

**Verdict choice.** SKIP rather than FAIL, on the grounds that a plugin installed by another
route is not a failure of this run. Recorded as a decision with a known tension: this fleet
has no non-git installer for that path — `5_general.zsh:45`'s `git clone` is the only creator
anywhere in the repo — so the realistic non-git state may be damage rather than an alternative
install, which would argue for FAIL. The remedy in the reason string is what makes SKIP
acceptable either way.

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

**`_update_summary`'s name column widens from `%-16s` to `%-19s` in the same change.**
`zsh-autosuggestions` is 19 characters; the longest current name is `terraform-skill` at 15.
All four render arms (`lib/update_summary.sh:555`, `:559`, `:563`, `:567`) carry the same
format string, and nothing in the suite asserts summary padding — measured. Left alone, every
weekly summary on every machine gains one row whose reason column is three characters out of
line, and it is the newest row, so it reads as the thing that is broken.

### Group C — fold the `_cht` completion into the `cheat.sh` section

The two fetches become one recorded unit, each keeping its own reachability guard:

The two fetches become one recorded unit, each keeping its own reachability guard, its own
failure, and its own name in the detail block:

```bash
if [[ -f ${HOME}/bin/cht.sh ]] || [[ -f ${HOME}/.zsh.d/_cht ]]; then
  _update_record_start "cheat.sh"
  [[ -f ${HOME}/bin/cht.sh ]]  && printf "Updating cheat.sh\\n"
  [[ -f ${HOME}/.zsh.d/_cht ]] && printf "Updating cheat.sh tab completion\\n"
  (
    _rc=0
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      if curl -fsS -o "${HOME}/bin/cht.sh" https://cht.sh/:cht.sh \
         && [[ -s ${HOME}/bin/cht.sh ]]; then
        chmod 754 "${HOME}/bin/cht.sh" || _rc=1
      else
        printf "cheat.sh binary fetch failed\\n" >&2
        _rc=1
      fi
    fi
    if [[ -f ${HOME}/.zsh.d/_cht ]]; then
      if curl -fsS -o "${HOME}/.zsh.d/_cht" https://cheat.sh/:zsh \
         && [[ -s ${HOME}/.zsh.d/_cht ]]; then
        :
      else
        printf "cheat.sh completion fetch failed\\n" >&2
        _rc=1
      fi
    fi
    exit "${_rc}"
  ) 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_cheat.sh"
  _update_record_end "cheat.sh" "${PIPESTATUS[0]}"
else
  _update_skip "cheat.sh" "not installed"
fi
```

Six deliberate choices, four of them corrections to earlier revisions:

- **The outer condition is a disjunction, not a nesting.** Today the two `if`s are siblings,
  so a machine carrying `~/.zsh.d/_cht` but not `~/bin/cht.sh` still updates its completion.
  Nesting the completion fetch inside the binary's guard would silently stop that. The
  disjunction preserves both independent conditions while producing one section row.
- **An `_rc` accumulator, not `|| exit 1`.** A `|| exit 1` revision reintroduced through
  *sequencing* the coupling the disjunction defends against: a failed binary fetch would
  terminate the subshell and the completion would never be attempted, under a row named for
  the binary. With the accumulator both fetches always run and either failure yields non-zero
  to `PIPESTATUS[0]`. Verified in reproduction: failing first fetch gives `PIPESTATUS[0]=1`,
  `_rc` does not leak to the parent, and behaviour is unchanged under `set -e`.
- **Progress banners outside, failure markers inside.** Two rounds pulled in opposite
  directions here and both were right about their own half. Banners inside the subshell land
  in `err_cheat.sh` and consume two of the ten lines `_update_write_detail_from_err` renders
  as operator-facing detail. Banners outside leave the detail block anonymous: `curl -fsS` on
  a 404 emits `curl: (56) The requested URL returned error: 404` and names **neither the URL
  nor the file**, so `[FAIL] cheat.sh` becomes unlocatable between two fetches. Failure-only
  markers on stderr satisfy both — nothing is consumed on the success path, and a failure
  names its half.
- **`[[ -s … ]]` after each fetch.** `-f` keys on HTTP status, and per M4 `cht.sh` answers an
  unknown topic with HTTP 200 and an error body — so `-f` alone cannot distinguish a usable
  file from a degraded 200. The size check costs one line and covers the deferred
  200-with-empty-body case as well as any future 4xx. `chmod` is gated behind it, so a
  re-moded file is now evidence the fetch succeeded rather than incidental.
- **`-o`, not `>`.** Per M4 this is the half that saves the file; `-f` alone leaves it
  truncated, because the shell owns the truncation.
- **`exit "${_rc}"` inside the subshell, not `return`.** The subshell is not a function, so
  `return` is invalid there. `exit` terminates the subshell only and yields its status to
  `PIPESTATUS[0]`.

Both artifacts are treated as one operational unit, so a completion-only failure renders
`[FAIL] cheat.sh` and exits 1. That is a decision rather than a default: `~/.zsh.d` is on
`fpath`, so the completion is live rather than dead weight, and M4 shows both files currently
zeroed by the same event — they already fail together.

**The install path gets the same `-fsS -o` treatment at `:162` and `:172`**, per M4's
four-site count and for the two different hazards recorded there. `chmod 750` at `:163` is
left as it is — see M4 for why the harmonisation an earlier revision proposed was withdrawn.

The `~/bin/cht.sh` / `"${HOME}/bin/cht.sh"` spelling inconsistency in the current code is
resolved to the braced form throughout, since the lines are being rewritten anyway.

## Verification

Each check is a command with an expected observable. Post-implementation cases are marked;
the rest were run while writing this spec and their output appears in Measurements.

**Read the harness section first — three mocks make the obvious version of these cases
vacuous, and round-2 review found all three.**

### The harness, before the cases

`tests/setup_env/workflows.bats` and `update_summary.bats` both call `load_mocks` in
`setup()`, which puts `tests/mocks/` on `PATH`. Three consequences, each measured:

- **`tests/mocks/git:8-9` intercepts `rev-parse --git-dir`** and returns
  `${MOCK_GIT_REVPARSE_EXIT:-0}` while printing **nothing**. Any guard reading that command's
  *output* compares an empty string. This is one reason Group B's guard is `[[ -e
  "${dir}/.git" ]]` rather than git plumbing: a filesystem test is not mockable and needs no
  harness cooperation, so V3's middle case is driven by fixture shape — the thing under test —
  rather than by an env var.
- **`tests/mocks/git` prints nothing for `rev-parse HEAD`**, so a real `git init` fixture
  still yields a zero-byte `pre_zsh-autosuggestions`. V1 and V7 must strip the mock directory
  for the calls that need real git, using the `clean_path` idiom already at
  `workflows.bats:1936`.
- **`tests/mocks/curl` implements `-o` as bare `touch "${outfile}"`** and derives its exit
  solely from `${MOCK_CURL_EXIT:-0}`, never reading `-f`. So today a *successful* mocked fetch
  produces exit 0 and a **zero-byte target** — the exact production state M4 opens this spec
  with, reproduced inside the harness with a green verdict.

Two mock changes follow, and both are to a file shared fleet-wide:

1. `-o` writes `MOCK_CURL_STDOUT` to the target rather than touching it, so a success can be
   distinguished from a failure by content.
2. `MOCK_CURL_HTTP_STATUS`, honoured only when a short-option cluster containing `f` is
   present. **The production invocation is `-fsS`, not `-f`** — measured: an exact-token test
   does not fire, and a `*-f*` substring test also fires on `--form`. Iterate `"$@"`, match
   `^-[a-zA-Z]+$`, and test whether that token contains `f`. Precedence with `MOCK_CURL_EXIT`
   must be stated in the mock, not left to discovery.

**Proving the mock change is inert:** run `make test` with both new variables unset and diff
the ok/not-ok set against a pre-change run. Any delta means the shared mock moved under an
existing suite. Separately, assert the mock directly against the exact production argv —
`MOCK_CURL_HTTP_STATUS=404 tests/mocks/curl -fsS -o /tmp/x https://cht.sh/:cht.sh` must exit
non-zero — which is what makes "honoured only when `-f` is in argv" testable rather than
aspirational.

### The cases

**V1 — the summary gains a `zsh-autosuggestions` row on a run where the plugin exists.**
_(post-implementation)_ `run_update` with `_run_all=1` and a fixture plugin directory that is
a real `git init` repo; assert the rendered summary contains the row. Must fail before the
`_UPDATE_SECTION_ORDER` entry is added — the mutation control, since `record_end` alone writes
a status file nothing prints. Must also assert
`[ -s "${_DOTFILES_RUN_TMPDIR}/pre_zsh-autosuggestions" ]`: an absent or zero-byte pre-snapshot
means the case measured nothing, and per the harness section that is the default outcome
unless the mock is stripped.

**V2 — a failing `git pull` produces FAIL, not silence.** _(post-implementation)_ `git` mock
returning 1 for `pull`; assert `status_zsh-autosuggestions` is `FAIL` and `run_update`'s exit
is non-zero. The case ADR-0027's contract exists for.

**V3 — SKIP on all three absent branches.** _(post-implementation)_ No plugin directory
(`"not installed"`); a directory present without `.git` (`"not a git checkout — reinstall…"`);
`_run_all=0` (`"flag not set"`). The middle case must be a bare `mkdir -p` — the fixture shape
*is* the condition, which is why the guard is a filesystem test.

**V3b — the guard is not fooled by a non-clone nested in a git repo.**
_(post-implementation)_ Build the fixture as `git init "${HOME}/.oh-my-zsh"` plus a plain
`mkdir -p` plugin directory inside it, mirroring the real machine. Assert SKIP, and assert
`MOCK_CALLS_FILE` contains **no** `git pull` for that path. This is the case that would have
caught the `rev-parse --git-dir` guard; without it the fixture in V3 is a non-repo in a
non-repo and cannot discriminate.

**V4 — cwd is unchanged across `run_update`.** _(post-implementation)_ Assert `$PWD` equal
before and after a full mocked run, invoked from a directory that is _not_ the dotfiles repo.
The from-elsewhere invocation is load-bearing: from the repo root both versions end there and
the case cannot discriminate.

Three pre-change failure paths, and the case must accept any: `:622`/`:632`/`:642` relocating
cwd (fixture repo present — this is the first one hit, not M2's block); M2's block relocating
it; or a `cd`-back failing outright and aborting. The third never reaches the assertion, so
the case must **also assert `run_update` completed**, or a spurious abort reads as a pass.

**V5 — a 404 on either cheat.sh fetch records FAIL and leaves the target intact.**
_(post-implementation)_ Target pre-seeded, `MOCK_CURL_HTTP_STATUS=404`; assert
`status_cheat.sh` is `FAIL` and the target's content is unchanged. Assert **non-zero**, never a
specific code — per M4 the same 404 yields 56 on macOS and 22 on Linux.

**Read the "target intact" half honestly: it discriminates `>` from `-o` and nothing more.**
The mock does not write the target on failure in any variant, so that assertion is evidence
about the shell's redirect operator, not about curl. It still catches a revert of `-o` to `>`,
which is what it is for.

**V6 — the FAIL detail names which fetch failed.** _(post-implementation)_ Fail only the
completion fetch; assert `detail_cheat.sh` contains `cheat.sh completion fetch failed` and not
the binary marker. Without this the failure-markers-inside decision has no test, and reverting
to anonymous curl errors leaves every other case green.

**V7 — the cheat.sh success path writes content.** _(post-implementation)_ Successful mocked
fetch with `MOCK_CURL_STDOUT` set; assert `status_cheat.sh` is `OK` **and** `~/bin/cht.sh` is
non-empty. Without it, a green suite leaves both artifacts at zero bytes. Note this is only
possible after the mock's `-o` handling changes; it is the reason that change is in scope.

**V8 — a derived value on the plugin section's success path.** _(post-implementation)_
Fixture git repo, advance `HEAD` by two commits between `record_start` and `record_end`,
assert `result_zsh-autosuggestions` reads literally `2 commit(s)`. Verified the format is
real: `lib/update_summary.sh:273` renders `"${_commit_count} commit(s)"` and `:275`/`:278`
render `"no changes"`, so a missing pre-snapshot goes red rather than passing.

The existing `update_summary.bats:793` looks like this and is not: it hand-seeds the pre-file
and stubs `_update_git_diff`. V8 must drive `_update_record_start` and must not inherit that
stub from a shared `setup()` — a stub there would make it vacuous with no visible symptom.

**Note what V8 does *not* cover.** `lib/update_summary.sh:155` is `# cheat.sh — no
pre-snapshot needed` and its success arm sets a constant `"updated"`, so cheat.sh has no
derived value to pin. V7 pins content on disk instead, which is the closest available
equivalent for the group this spec ranks highest.

**V9 — the ordering and count assertions still pass.** `make test`. Predicted green from M5 on
two distinct mechanisms: the ordering anchors all terminate at `rust`, and the ten count
assertions seed their sections by name while `_update_summary` skips unseeded array entries.
Includes the `%-19s` column change, which nothing asserts.

**V10 — full suite and coverage.** `make test`, then read the CI `bash-coverage` figure rather
than a local one. Per `dotfiles/CLAUDE.md`, CI has landed at exactly the 91% floor on five
consecutive measurements, so this change must not add instrumented lines without tests. Every
added line is covered by V1–V9.

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


---

## Multi-Lens Review — Round 2

Reviewed at commit: `b580bfcf` (the round-1 revision). All three lenses re-run, per the
re-review rule: round 1's dispositions changed design substance — a guard added, Group C's
control flow rewritten, scope widened to the install path — and a correction is new design
carrying its own defects. That prediction held: **round 2 found a defect in round 1's own fix
that was worse than the problem round 1 raised.**

### Goal-Fit

Finding, six parts. (1) Group C's **success path is unverified and unverifiable under the
proposed mock** — `tests/mocks/curl` implements `-o` as bare `touch`, so a green suite leaves
both artifacts at zero bytes, reproducing the production defect inside the harness; the spec
applied its own pin-a-derived-value remedy to Group B and not to the group it calls most
severe. (2) The **750→754 change names the wrong bit** — group-execute is `r-x` in both, the
delta is other-read, and the change makes a `$HOME` executable world-readable with no defect,
no consumer and no test behind it. (3) The git-dir guard **defends a state this repo has no
code path to produce** — the only creator of that directory anywhere in the repo is
`5_general.zsh:45`'s `git clone`. (4) The **"four sites, one class" framing flattens two
failure modes**: `:172` is `! -f`-guarded and cannot truncate; its hazard is a 0-byte file
that satisfies the guard forever. (5) Group A's `( )` conversion **fails the reads-it test** —
no consumer, no record, insurance against a diff that does not exist, and it carries the
spec's longest argument for its least severe group. (6) Minor: M4 leaves the **file mode
unused as a discriminator** — 754 means the update path created the file.

Assumption: **that an HTTP 200 from `cht.sh` implies a usable file** — i.e. that `-f` is
sufficient to make the section's verdict truthful. Both endpoints measured healthy today
(`200/22888`, `200/517`), so it is neither confirmed nor dead; cht.sh already serves 200 with
an error body for unknown topics. Cheapest sufficient hedge named: `[[ -s … ]]` in the
accumulator.

Disposition: **Addressed** (user, 2026-08-31). (1) — mock `-o` now writes the body, plus V7
asserting OK **and** non-empty content; user chose this over a production-only check and over
recording it as a gap. (2) — cut entirely; user chose this over normalising to 750 and over
keeping 754 with corrected reasoning. (3) — recorded as a stated tension in Group B's verdict
paragraph rather than removing the guard; the guard survives because round-2 Risk found it
was also *broken*, which is a separate matter from whether it is needed. (4) — M4 rewritten,
`:172`'s inverse hazard named. (5) — conversion kept, argument trimmed to one paragraph;
resolved by this session rather than by the user, since round-1 Risk called the same change
load-bearing and the two rounds directly conflict. The deciding fact is that it costs two
characters. (6) — added to M4. Assumption addressed by the `[[ -s … ]]` hedge, which covers
the 200-empty case without needing to settle it.

### Ergonomics

Finding, four parts. (1) **Moving the banners outside removed the property that justified the
fold** — `curl -fsS` on a 404 emits `curl: (56) … error: 404`, naming neither URL nor file, so
`[FAIL] cheat.sh` becomes unlocatable between two fetches; round 1 Ergonomics approved the
fold *because* each fetch named itself, and the round-1 disposition kept the fold and deleted
the reason. (2) **`zsh-autosuggestions` is 19 characters against a `%-16s` column** — every
weekly summary on seven machines gains one misaligned row, and it is the newest one, so it
reads as broken. (3) The new SKIP reason is legible but is **the one branch that never
self-heals**, and it lands in a column already 13 rows deep on a partial run; it needs a
remedy in the reason string. (4) 750→754: no finding from this lens.

Also: three harness defects — `tests/mocks/git` answers `rev-parse --git-dir` from an env var,
`load_mocks` shadows a real `git init` fixture so V1's own `[ -s … ]` assertion would fail
against a genuine repo, and both need the `clean_path` idiom at `workflows.bats:1936`.

Assumption: **that a non-git `zsh-autosuggestions` directory is a benign alternative install
rather than a damaged clone.** Genuinely uncertain — no non-git installer exists in this repo,
which leans toward damage, but Homebrew ships a formula and oh-my-zsh documents several
methods. Settled by `ls -a` on any machine where the `.git` test fails: a complete plugin
layout with no `.git` vindicates SKIP, a partial tree confirms damage and argues FAIL.

Disposition: **Addressed** (user, 2026-08-31). (1) — failure-only markers inside the subshell,
banners outside; user chose this over moving both banners back in and over accepting the
ambiguity. It satisfies both rounds, which had pulled in opposite directions and were each
right about their own half. New V6 tests it. (2) — column widened to `%-19s` in the same
change; resolved by this session, since nothing asserts padding and the alternative is a
permanently misaligned row. (3) — remedy added to the reason string. (4) — superseded by
Goal-Fit 2; the mode change is cut. The harness defects are addressed in Verification's new
"The harness, before the cases" section, and are the reason Group B's guard is a filesystem
test rather than git plumbing. Assumption is recorded as an open tension in Group B rather
than settled, since settling it needs the five unmeasured machines.

### Risk

Finding, seven parts. (1) **Group B's guard is fooled in exactly the case it was added for,
and fails toward a silent wrong verdict** — `rev-parse --git-dir` walks upward, `~/.oh-my-zsh`
is itself a checkout, so a nested non-clone takes the update arm; `git pull` then targets
oh-my-zsh, which the `oh-my-zsh` section already pulled in the same run, so HEAD has not moved
and the row renders `[OK] zsh-autosuggestions no changes` forever. Worse than the false FAIL
it prevents, because a FAIL is visible. A second way past it: an exported `GIT_DIR` defeats
`git -C`, which reaches the bats suite specifically, since `scripts/pre-push` runs it from a
hook. (2) The **750→754 justification names the wrong bit** and the change is a loosening —
same finding as Goal-Fit 2, reached independently. (3) **`MOCK_CURL_HTTP_STATUS` "honoured
only when `-f` appears in argv" is unsatisfiable as worded** — production emits `-fsS`, an
exact-token test does not fire, and a substring test also fires on `--form`. (4) **V5's
"target intact" half is structurally unable to fail** — the mock never writes the target, so
the assertion is evidence about the shell's redirect operator, not about curl. (5) The `_rc`
accumulator is **correct — no finding**, verified in reproduction including under `set -e`;
one unremarked side effect, `chmod` was ungated so a re-moded file was not evidence of a
successful fetch. (6) **M6 holds** — tried to break it and could not. (7) Proportionality:
Groups B and C earn their weight; Group A remains a deletion carrying the spec's longest
argument.

Assumption: **that `MOCK_CURL_HTTP_STATUS` can be added to the shared mock without altering
any existing suite's pass/fail set.** Genuinely uncertain — precedence against
`MOCK_CURL_EXIT` is unspecified, the `touch "${outfile}"` path has existing consumers, and the
`-f` detection must match `-fsS` without matching `--form`. Refuted or confirmed by running
`make test` with the new variables unset and diffing the ok/not-ok set, plus asserting the
mock against the exact production argv.

Disposition: **Addressed** (user, 2026-08-31). (1) — guard replaced with `[[ -e "${dir}/.git"
]]`, which rejects the nested non-clone, handles the `.git`-as-file worktree case, and is
immune to the `GIT_DIR` route because it touches no git plumbing; new V3b builds the fixture
as a repo-inside-a-repo and asserts no `git pull` is issued. User chose fix-and-keep-SKIP over
FAIL and over dropping the guard. This session found the same defect independently while the
lenses ran, with the same discriminator. (2) — cut. (3) — Verification now specifies iterating
`"$@"` for `^-[a-zA-Z]+$` containing `f`, with the exact-production-argv assertion the lens
proposed. (4) — V5's scope is now stated honestly in the spec: it discriminates `>` from `-o`
and nothing more. (5) — `chmod` is now gated behind the fetch and the `[[ -s … ]]` check, so a
re-moded file is evidence of success. (6) and (7) — no action; (7)'s proportionality point is
addressed by trimming Group A's argument. Assumption addressed by the two-part inertness proof
now in Verification.

### Adversarial Spec Review (comparison/judge designs only)

N/A — unchanged from round 1. No comparison arms, no judge or evaluator component, and the
verification cases are commands with concrete observables.

### Stopping here

Round 2's findings have moved from the design into the **apparatus** — three mocks, a
`PATH`-strip idiom, and which fixture shape drives which branch. Per this skill's stopping
rule that is prose review's floor: the next instrument is Phase 2's first red test, not a
third round at ~250k tokens per lens.

The qualifier was checked rather than assumed. Risk 1 is *located* in the design and
falsifies a design premise, so it is a design finding and would license another round on its
own — but it is fixed, and its fix is a filesystem test with a dedicated case (V3b) rather
than a new mechanism. Everything else that survived is a harness question a single `bats` run
answers in seconds.

Round-1 and round-2 lens cost: 6 dispatches, 1,472,384 tokens, all logged via `cost_log.py`;
the dispatch count matches the `Agent` calls made.
