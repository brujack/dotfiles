# Bound and make atomic the cheat.sh fetches

- **Date:** 2026-10-09
- **Backlog rows:** "cheat.sh curls in `-t update` have no `--max-time`" and "`_fetch_github_latest passes max-time 10` test matches a substring" (both P2)

## Problem

Four curl calls fetch cheat.sh artifacts with no total-time bound:

| call site               | function         | artifact                     | runs when        |
| ----------------------- | ---------------- | ---------------------------- | ---------------- |
| `lib/workflows.sh:435`  | `run_setup_user` | `~/bin/cht.sh` (binary)      | `~/bin` exists   |
| `lib/workflows.sh:445`  | `run_setup_user` | `~/.zsh.d/_cht` (completion) | `_cht` absent    |
| `lib/workflows.sh:1156` | `run_update`     | `~/bin/cht.sh`               | `cht.sh` present |
| `lib/workflows.sh:1166` | `run_update`     | `~/.zsh.d/_cht`              | `_cht` present   |

The backlog row places all four in `-t update`; two are in `run_setup_user`. curl has no
default total-transfer timeout, so a stalled connection hangs either workflow.

### Adding `--max-time` alone trades a hang for a corrupt file

Measured 2026-10-09 on `claude` (curl 8.22.0) against a local server that sends a 5-byte
body and then stalls: `curl -fsS --max-time 2 -o out` exited 28 and left `out` holding
`hello`, overwriting the pre-existing content `PRE-EXISTING`. curl `-o` truncates the
destination when the body starts, not when the transfer succeeds.

So with a bound and nothing else, a timeout mid-body replaces a working `~/bin/cht.sh` with
a truncated one. `run_update` reports FAIL, but the working copy is already gone and the
truncated file keeps its executable mode. The existing tests promise the opposite —
"leaves a pre-seeded binary unchanged" — and hold only because an HTTP error (`-f`, exit 22)
refuses before any body is written. A mid-body connection reset already had this problem;
a timeout makes it reachable on every slow link.

The `run_setup_user` completion fetch is the worse case: it runs only when `_cht` is
absent, so a truncated `_cht` it writes is never re-fetched by `setup_user`; it survives
until the next `-t update`, which re-fetches `_cht` whenever it exists.

### Bound size

Measured 2026-10-09 on `claude` only, three runs each: `cht.sh/:cht.sh` is 22,888 bytes in
0.47–0.59 s; `cheat.sh/:zsh` is 517 bytes in 0.36–0.43 s. curl 8.22.0 lists `AsynchDNS`,
so `--max-time` also bounds name resolution. `--max-time 10` is roughly 20× the measured
time on this one host and link, and matches the bound #322 chose for the check-versions
calls. The other development machines were not measured.

### The substring test

`tests/setup_env/workflows.bats:1492` asserts `grep -q -- '--max-time 10'`, which
`--max-time 100` also satisfies (mutation-confirmed by #322's test-quality gate). #322
fixed its own tests with `grep -E -- '--max-time 10( |$)'`; this one was out of its scope.

## Design

### One helper

Add `_cheat_fetch <url> <dest> <mode> <head>` to `lib/workflows.sh`:

1. `mktemp "${dest%/*}/.${dest##*/}.XXXXXX"` — same directory as the destination, so the final `mv` is a
   rename on one filesystem. Same idiom as `setup_claude_mcp` (`lib/workflows.sh:44`).
2. `curl -fsS -o "${tmp}" --max-time 10 "${url}"`. The argument order is fixed: `-o` stays
   the third argument because existing tests override `curl` as a function and write to
   `"$3"`, and the URL stays last because the stubs match on `"${*: -1}"`.
3. Require `[[ -s "${tmp}" ]]`, and require the temp file's first line to begin with
   `<head>`: `#!` for the binary, `#compdef` for the completion.
4. `chmod "${mode}" "${tmp}"`.
5. `mv -f "${tmp}" "${dest}"`.

Return codes:

| rc  | meaning                                                  |
| --- | -------------------------------------------------------- |
| 0   | destination replaced                                     |
| 1   | fetch failed: curl non-zero (timeout included), empty, or wrong first line |
| 2   | local failure: empty `<head>`, `mktemp`, `chmod` or `mv` |

On rc 1 or 2 the helper removes the temp file (when one was created) and has not modified
`dest`. It prints nothing; callers own the message, so each call site keeps naming its own
artifact. Splitting fetch from local failure keeps a `chmod` or `mv` failure from being
reported as a network failure.

An empty `<head>` returns 2 before anything is created: `[[ ${line} == ""* ]]` is always
true, so an empty or omitted argument would otherwise switch the check off silently.

Read the first line with `IFS= read -r line < "${tmp}"` and do not treat its rc as failure:
it returns 1 on a file with no trailing newline while still setting `line`, and every mock
and fixture body is written with `printf "%s"`. An empty file leaves `line` empty and fails
the match; NUL bytes are dropped by bash and fail it too.

The first-line check exists because cheat.sh answers HTTP 200 with an error page, which `-f`
cannot refuse. Measured 2026-10-09 on `claude`: `https://cht.sh/:nonexistent-topic-xyz`
returned 200, 118 bytes, beginning `error: unexpected argument '-v' found`. Without the
check, the same response for `:cht.sh` would be installed executable over a working binary.
The live artifacts begin `#!/bin/bash` and `#compdef cht.sh`.

The temp name is dot-prefixed (`.cht.sh.XXXXXX`, `._cht.XXXXXX`). `~/.zsh.d` is on `fpath`
(`.config/.zshrc.d/5_general.zsh:195`) and compinit loads any file whose name starts with
`_`, so an undotted `_cht.XXXXXX` left by an interrupted `setup_user` fetch (with `_cht`
absent) would own the `cht.sh` completion while truncated; compinit skips dot files.

The explicit `chmod` is required for the completion file too: `mktemp` creates mode 0600,
where `curl -o` previously produced a umask-default file (measured on `claude`: `_cht`
is 0664 under umask 002, so 644 narrows it by group write).

`mv` replaces a symlinked destination with a regular file, where `curl -o` wrote through the
link. Neither artifact is a symlink on `claude` (`ls -l` 2026-10-09: both regular files) and
nothing in this repo creates one, so this is accepted rather than guarded.

### Call sites

- `run_setup_user` binary: `_cheat_fetch https://cht.sh/:cht.sh "${HOME}/bin/cht.sh" 750 '#!'`,
  still inside `if [[ -d ${HOME}/bin ]]`. rc 1 prints `cheat.sh binary fetch failed` and rc
  2 prints `cheat.sh binary install failed` to stderr — the same strings as `run_update` — and `run_setup_user` continues, as today — a broken cheat.sh is not a
  reason to abort setup.
- `run_setup_user` completion: `_cheat_fetch https://cheat.sh/:zsh "${HOME}/.zsh.d/_cht" 644 '#compdef'`,
  still only when `_cht` is absent. Same warn-and-continue, with `cheat.sh completion fetch
  failed` / `cheat.sh completion install failed`.
- `run_update`: the subshell, `_rc`, `tee` and `PIPESTATUS[0]` structure is unchanged.
  Binary uses mode 754, completion 644. rc 1 prints the existing `cheat.sh binary fetch
failed` / `cheat.sh completion fetch failed`; rc 2 prints `cheat.sh binary install
failed` / `cheat.sh completion install failed`. Either sets `_rc=1`. The old
  `cheat.sh chmod failed` message is replaced by the binary's rc-2 message; no test asserts
  it.

### Testing

TDD, one behaviour at a time. All new tests use the shared `tests/mocks/curl`, not a
function override, so the call is recorded in `MOCK_CALLS_FILE`.

- **Atomicity.** `MOCK_CURL_FAIL_URL` already models a partial download: it truncates the
  `-o` target, then exits 22. Against today's code that destroys a pre-seeded file; through
  the helper it truncates only the temp file. Tests pre-seed `PRE-EXISTING`, fail the fetch
  this way, and assert the destination is byte-identical — for the binary in both functions
  and for the completion in `run_update`.
- **No temp file left.** Each failure test that reaches curl (R6, R11, R15, R18) reads the temp path the helper actually used from
  the recorded `curl ... -o <tmp>` line in `MOCK_CALLS_FILE`, asserts that line exists, and
  asserts that exact path does not exist. Never a quoted glob, `*` or `ls`: a quoted
  `".cht.sh.??????"` does not expand, and `*`/`ls` skip dot files, so each passes with a
  leftover present.
- **Wrong content.** `MOCK_CURL_STDOUT` set to a body that does not begin with `#!` makes
  the binary fetch fail with `cheat.sh binary fetch failed` and leaves the destination
  unchanged.
- **Bound.** For each of the four call sites, assert
  `grep -E -- '--max-time 10( |$)' "${MOCK_CALLS_FILE}" | grep -qF <url>`.
- **Local failure, mv.** Fail the rename with the existing per-argument `MOCK_MV_FAIL_ARGS`
  matching the temp name; assert the `install failed` message, an unchanged destination, a
  FAIL section and no temp file left. `MOCK_CHMOD_EXIT` is not used: it is global and would
  fail every `chmod` in the run.
- **Local failure, mktemp.** Make the destination directory non-writable so `mktemp` fails,
  restoring its mode in teardown; assert
  the destination is unchanged, the section is FAIL with the `install failed` message, and
  no fetch was attempted.
- **Mode.** On success the binary has the function's mode (750 / 754) and `_cht` is 644.
- **Substring test.** Change `workflows.bats:1492` to the whole-token form.
- **setup_user warning.** A failed binary fetch under `run_setup_user` prints the exact
  string `cheat.sh binary fetch failed`. A looser match on `cht.sh` passes with the warning
  deleted: `run_setup_user` also prints `cht.sh is installed` when `command -v cht.sh`
  resolves, and on `claude` the bats `PATH` carries `/home/bruce/bin`, so it does locally
  and does not on CI.
- The existing test `run_setup_user does not attempt chmod when the cht.sh binary fetch fails`
  (`workflows.bats:309`) refutes `chmod 750 ${HOME}/bin/cht.sh`, which can never appear once
  chmod targets the temp file. It is re-pointed at the temp name (`chmod 750 ${HOME}/bin/.cht.sh.`).
- The four existing success fixtures carry bodies with no valid first line
  (`cheat.sh binary body`, `cheat.sh completion body`, `binary-body`, `completion-body`,
  in `workflows.bats:2252`–`:2430`); each is prefixed with `#!` or `#compdef` as appropriate.
  The other existing cheat.sh tests pass unchanged.

## Requirements

- **R1.** `[PR1]` `lib/workflows.sh` defines `_cheat_fetch <url> <dest> <mode> <head>`, which creates its temp file with `mktemp "${dest%/*}/.${dest##*/}.XXXXXX"`, fetches with `curl -fsS -o "${tmp}" --max-time 10 "${url}"` in that argument order, requires the temp file non-empty with a first line beginning `<head>`, applies `chmod "${mode}"`, and replaces the destination with `mv -f`.
- **R2.** `[PR1]` `_cheat_fetch` returns 1 when curl exits non-zero, writes nothing, or writes a first line not beginning `<head>`, returns 2 when `<head>` is empty or when `mktemp`, `chmod` or `mv` fails, removes any temp file it created on both, and leaves `dest` unmodified on both.
- **R3.** `[PR1]` All four cheat.sh fetches in `lib/workflows.sh` go through `_cheat_fetch`; no `curl` call fetching `cht.sh/:cht.sh` or `cheat.sh/:zsh` remains outside it.
- **R4.** `[PR1]` `run_setup_user` installs the binary with mode 750 and the completion with mode 644, prints `cheat.sh <binary|completion> fetch failed` on rc 1 and `cheat.sh <binary|completion> install failed` on rc 2 to stderr, and does not return non-zero for that reason.
- **R5.** `[PR1]` `run_update` installs the binary with mode 754 and the completion with mode 644, prints `cheat.sh <binary|completion> fetch failed` on rc 1 and `cheat.sh <binary|completion> install failed` on rc 2, and records the section FAIL on either.
- **R6.** `[PR1]` A test fails the binary fetch through `MOCK_CURL_FAIL_URL` with a pre-seeded `PRE-EXISTING` file and asserts the file is byte-identical and no temp file remains (R16), once under `run_setup_user` and once under `run_update`; the same is asserted for `_cht` under `run_update`.
- **R7.** `[PR1]` For each of the four call sites a test asserts `grep -E -- '--max-time 10( |$)'` matches a recorded curl call carrying that call site's URL.
- **R8.** `[PR1]` A test makes the destination directory non-writable, restores its mode in teardown, and asserts the destination is unchanged, no curl call was recorded, the `install failed` message appears, and the cheat.sh section is FAIL.
- **R9.** `[PR1]` `tests/setup_env/workflows.bats`'s `_fetch_github_latest passes max-time 10` test asserts with `grep -E -- '--max-time 10( |$)'`.
- **R10.** `[PR1]` The two backlog rows named above are removed from `docs/superpowers/README.md`, and `CLAUDE.md`'s cheat.sh bullet states that a failed or timed-out fetch never replaces the existing file.
- **R11.** `[PR1]` A test fails the binary's rename through `MOCK_MV_FAIL_ARGS` under `run_update` and asserts the `cheat.sh binary install failed` message, the pre-seeded destination unchanged, the cheat.sh section FAIL, and no temp file left (R16).
- **R12.** `[PR1]` A test asserts that a failed binary fetch under `run_setup_user` prints the exact string `cheat.sh binary fetch failed`.
- **R13.** `[PR1]` The test `run_setup_user does not attempt chmod when the cht.sh binary fetch fails` refutes a `chmod 750` of the temp name `${HOME}/bin/.cht.sh.` rather than of `${HOME}/bin/cht.sh`.
- **R14.** `[PR1]` The binary is fetched with `<head>` `#!` and the completion with `#compdef` at all four call sites.
- **R15.** `[PR1]` A test sets `MOCK_CURL_STDOUT` to a body not beginning `#!` under `run_update` and asserts `cheat.sh binary fetch failed`, the pre-seeded destination unchanged, and the section FAIL.
- **R16.** `[PR1]` Every no-temp-file-left assertion (R6, R11, R15, R18) reads the temp path from the recorded `curl ... -o <tmp>` line, asserts that line exists, and asserts the path does not exist.
- **R17.** `[PR1]` The four existing success fixtures in `tests/setup_env/workflows.bats` begin with `#!` (binary) or `#compdef` (completion).
- **R18.** `[PR1]` A test sets the completion fetch's body to one not beginning `#compdef` under `run_update` and asserts `cheat.sh completion fetch failed`, the pre-seeded `_cht` unchanged, and the section FAIL.
- **R19.** `[PR1]` A test calls `_cheat_fetch` with an empty `<head>` and asserts rc 2, no curl call recorded, and the destination unchanged.
- **V1.** Mutation: change `_cheat_fetch` to `curl -o "${dest}"` directly (no temp file); the R6 tests go red.
- **V2.** Mutation: change `--max-time 10` to `--max-time 100` in `_cheat_fetch`; the R7 tests go red. Change `_fetch_github_latest`'s `--max-time 10` to `--max-time 100`; the R9 test goes red.
- **V3.** Run `_cheat_fetch` with real curl against a local listener that sends part of a body and stalls; it returns 1 within the bound and the pre-seeded destination is unchanged.
- **V4.** `make test` exits 0 locally and every CI job passes on the PR.
- **V5.** Mutation: delete the helper's `rm -f` of the temp file; the R16 assertions go red.
- **V6.** Mutation: delete the first-line check; R15 goes red.
- **V7.** Mutation: delete the `run_setup_user` binary warning; R12 goes red, including on `claude`, where `cht.sh` is on the bats `PATH`.
- **V8.** Mutation: pass `""` as `<head>` at the `run_update` completion call site; R18 goes red. A wrong non-empty `<head>` at the two `run_setup_user` sites has no wrong-content test, by decision.
- **N1.** No URL or timeout seam is added to `_cheat_fetch`.
- **N2.** No retry logic.
- **N3.** The 750 / 754 binary-mode difference between `run_setup_user` and `run_update` is not changed.
- **N4.** `run_setup_user` gains no new non-zero return for a cheat.sh failure.
- **N5.** No new mode or knob is added to `tests/mocks/curl`.
- **N6.** No signal trap is added to clean up a temp file left by an interrupt.

## Multi-Lens Review

Reviewed at commit: `b64f0a7` (Step 7 self-review commit, before Step 8 dispatch). Adversarial Spec Review Gate: not triggered — no comparison or evaluator design, and every acceptance criterion is concrete.

### Goal-Fit

Finding: Worth building. The existing test `run_setup_user does not attempt chmod when the cht.sh binary fetch fails` (`tests/setup_env/workflows.bats:309`) goes vacuous: it refutes `chmod 750 ${HOME}/bin/cht.sh`, and under `_cheat_fetch` chmod only ever targets the temp path, so the assertion holds whatever the helper does. Also, "a truncated `_cht` is never re-fetched" is true of `setup_user` only; `run_update` re-fetches it whenever it exists.
Assumption: `--max-time 10` clears every development machine. Measured 2026-10-09, 10 fetches of `cht.sh/:cht.sh` each: `claude` max 0.50 s, `workstation` max 0.61 s, `studio` max 0.90 s. Refuted as a risk on all three.
Disposition: Addressed — operator: "Accepted" (2026-10-09), on the recommendation to re-point the `:309` test at the temp name (R13) and correct the "never re-fetched" wording.

### Ergonomics

Finding: No blocking flaw. `mktemp "${dest}.XXXXXX"` names the completion temp file `_cht.XXXXXX` inside `~/.zsh.d`, which is on `fpath` (`.config/.zshrc.d/5_general.zsh:195`); compinit loads any `_*` file, so an interrupted `setup_user` fetch (`_cht` absent) leaves a truncated file owning the `cht.sh` completion (probed: `_comps[cht.sh]=_cht.Ab12Cd`). A dot-prefixed template `"${dest%/*}/.${dest##*/}.XXXXXX"` is not matched by compinit (probed) and is hidden in `~/bin`. R8's non-writable directory also needs a teardown that restores the mode.
Assumption: same 10 s question as Goal-Fit; settled by the measurement above.
Disposition: Addressed — operator: "Accepted" (2026-10-09), on the recommendation to dot-prefix the temp name (R1, Design) and restore the directory mode in R8's teardown.

### Risk

Finding: Design proportionate. R2's temp-file cleanup on rc 2 is never exercised: R8 fails at `mktemp`, before any temp file exists, so a helper that leaks the temp file after a failed `chmod`/`mv`, or returns 0 after a failed `mv`, passes R6–R8 and V1–V3. `tests/mocks/mv` and `tests/mocks/chmod` swallow real failures (`|| true`), so nothing catches it by accident. The existing per-argument `MOCK_MV_FAIL_ARGS="cht.sh."` drives the `mv` branch without a new knob (N5 holds). Also confirms the `:309` vacuity, and notes R4's stderr warning has no assertion.
Assumption: no uncertain assumption found; symlink acceptance checked by `ls -l` on `claude`, `workstation` and `studio` (all regular files).
Disposition: Addressed — operator: "Accepted" (2026-10-09), on the recommendation to add an `mv`-failure test via `MOCK_MV_FAIL_ARGS` (R11) and a `setup_user` warning assertion (R12).

### Round 2 — reviewed at `fdbbbb5` (all three lenses; round 1's dot-prefix fix was design substance)

#### Goal-Fit

Finding: No blocking issues; the round-1 revisions add no defect found. Advisory: R6 alone is satisfied by a helper that never calls curl (the suite still catches it via the success tests); R8 does not pin which function and artifact it covers.
Assumption: cheat.sh fails only at the transport or HTTP level. Refuted 2026-10-09 on `claude`: `https://cht.sh/:nonexistent-topic-xyz` returned HTTP 200, 118 bytes, `error: unexpected argument '-v' found`; `https://cheat.sh/:nonexistent-zsh-xyz` likewise (200, 122 bytes). An error page under 200 would pass `-s` and be installed executable over a working binary.
Disposition: Addressed — operator: "Accepted" (2026-10-09), on the recommendation to require a first line beginning `#!` (binary) or `#compdef` (completion) before replacing (R1, R2, R14, R15, V6; existing success fixtures updated, R17).

#### Ergonomics

Finding: Defect introduced by round 1: the Testing → Atomicity bullet still asserted no `<dest>.??????` file, a name the dot-prefixed helper never creates, so the check passes whatever is left; R6 left the `_cht` pattern unnamed; no V item leaks a temp file. Probe: with only `.cht.sh.abc123` present, `*` matched nothing and `ls | wc -l` printed 0.
Assumption: no uncertain assumption found; BSD `mktemp` accepting a dot-prefixed path template is settled by the `test-macos` job.
Disposition: Addressed — operator: "Accepted" (2026-10-09), on the recommendation to replace the glob with the recorded temp path (R16) and add a cleanup-deletion mutation (V5).

#### Risk

Finding: Same defect as Ergonomics, plus: a quoted glob `[ ! -e "$H/bin/.cht.sh.??????" ]` passed with a real `.cht.sh.1dB3YS` present, because quoting stops expansion (tdd.md E5). Proposed a positive control — read the temp path from the recorded `curl ... -o <tmp>` line and assert that exact path is gone — and a mutation deleting the `rm`. Minor, not raised for change: `run` merges stderr into stdout so R12 cannot distinguish streams; a `chmod`-failure rc 2 stays untested because the mock hides real failures; a directory at the destination path would swallow the `mv`.
Assumption: no uncertain assumption found; the residual claim that existing tests pass unchanged is settled by running them (now superseded by R17).
Disposition: Addressed — operator: "Accepted" (2026-10-09), folded into the Ergonomics disposition (R16, V5).

### Round 3 — reviewed at `91bd0c8` (all three lenses; round 2's first-line check was design substance)

#### Goal-Fit

Finding: No issues. Re-fetched all four URL forms 2026-10-09: both artifacts begin `#!/bin/bash` and `#compdef cht.sh`; `cht.sh/:nonexistent-topic-xyz` now returns 200 with `Unknown topic.` — error-page text drifts, which favours a positive head check over matching known error text.
Assumption: no uncertain assumption found.
Disposition: N/A — clean, no action needed

#### Ergonomics

Finding: R12 passes with the warning deleted on any machine with cht.sh installed. The spec left the warning's text unfixed, `run` merges stderr into `$output`, and `run_setup_user` prints `cht.sh is installed` when `command -v cht.sh` resolves; on `claude`, `HOME=<fake> bash -c 'command -v cht.sh'` returned `/home/bruce/bin/cht.sh`. Green locally, red on CI (tdd.md pitfall G).
Assumption: no uncertain assumption found; the nearest is that `cheat.sh/:zsh` keeps `#compdef` as its first line, and if it changes the section FAILs loudly.
Disposition: Addressed — operator: "Accept 1 and 2" (2026-10-09): `run_setup_user` prints the `run_update` strings (R4), R12 asserts the exact string, V7 deletes the warning.

#### Risk

Finding: R14 is pinned at one of four call sites. Only R15 is a wrong-content test (binary, `run_update`); the R17 fixtures pass any lax check. Passing `""` or omitting `<head>` at any other site keeps every R and V green, since `[[ $l == ""* ]]` is always true. Minor: the Testing bullet claimed every failure test reads a curl `-o` line, which R8 has none of; R8 omitted the promised "no fetch attempted"; `IFS= read -r` returns 1 on a file with no trailing newline while still setting the line, so `read … || return 1` would reject every fixture.
Assumption: no uncertain assumption found.
Disposition: Addressed — operator: "Accept 1 and 2" (2026-10-09): empty `<head>` returns 2 (R2, R19), `_cht` wrong-content test (R18), V8 mutation; the two `run_setup_user` sites' non-empty wrong head left untested by decision (V8); Testing bullet narrowed, R8 asserts no curl call, `read` rc behaviour stated in Design.
