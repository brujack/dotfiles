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
absent, so a truncated `_cht` it writes is never re-fetched by `setup_user`.

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

Add `_cheat_fetch <url> <dest> <mode>` to `lib/workflows.sh`:

1. `mktemp "${dest}.XXXXXX"` — same directory as the destination, so the final `mv` is a
   rename on one filesystem. Same idiom as `setup_claude_mcp` (`lib/workflows.sh:44`).
2. `curl -fsS -o "${tmp}" --max-time 10 "${url}"`. The argument order is fixed: `-o` stays
   the third argument because existing tests override `curl` as a function and write to
   `"$3"`, and the URL stays last because the stubs match on `"${*: -1}"`.
3. Require `[[ -s "${tmp}" ]]`.
4. `chmod "${mode}" "${tmp}"`.
5. `mv -f "${tmp}" "${dest}"`.

Return codes:

| rc  | meaning                                                  |
| --- | -------------------------------------------------------- |
| 0   | destination replaced                                     |
| 1   | fetch failed: curl non-zero (timeout included), or empty |
| 2   | local failure: `mktemp`, `chmod` or `mv`                 |

On rc 1 or 2 the helper removes the temp file (when one was created) and has not modified
`dest`. It prints nothing; callers own the message, so each call site keeps naming its own
artifact. Splitting fetch from local failure keeps a `chmod` or `mv` failure from being
reported as a network failure.

The explicit `chmod` is required for the completion file too: `mktemp` creates mode 0600,
where `curl -o` previously produced a umask-default file (measured on `claude`: `_cht`
is 0664 under umask 002, so 644 narrows it by group write).

`mv` replaces a symlinked destination with a regular file, where `curl -o` wrote through the
link. Neither artifact is a symlink on `claude` (`ls -l` 2026-10-09: both regular files) and
nothing in this repo creates one, so this is accepted rather than guarded.

### Call sites

- `run_setup_user` binary: `_cheat_fetch https://cht.sh/:cht.sh "${HOME}/bin/cht.sh" 750`,
  still inside `if [[ -d ${HOME}/bin ]]`. A non-zero rc prints a warning naming the
  artifact to stderr and `run_setup_user` continues, as today — a broken cheat.sh is not a
  reason to abort setup.
- `run_setup_user` completion: `_cheat_fetch https://cheat.sh/:zsh "${HOME}/.zsh.d/_cht" 644`,
  still only when `_cht` is absent. Same warn-and-continue.
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
  this way, and assert the destination is byte-identical and no `<dest>.??????` file
  remains — for the binary in both functions and for the completion in `run_update`.
- **Bound.** For each of the four call sites, assert
  `grep -E -- '--max-time 10( |$)' "${MOCK_CALLS_FILE}" | grep -qF <url>`.
- **Local failure.** Make the destination directory non-writable so `mktemp` fails; assert
  the destination is unchanged, the section is FAIL with the `install failed` message, and
  no fetch was attempted.
- **Mode.** On success the binary has the function's mode (750 / 754) and `_cht` is 644.
- **Substring test.** Change `workflows.bats:1492` to the whole-token form.
- The existing cheat.sh tests (`workflows.bats:267`–`:327`, `:2252`–`:2430`) pass unchanged.

## Requirements

- **R1.** `[PR1]` `lib/workflows.sh` defines `_cheat_fetch <url> <dest> <mode>`, which creates its temp file with `mktemp "${dest}.XXXXXX"`, fetches with `curl -fsS -o "${tmp}" --max-time 10 "${url}"` in that argument order, requires the temp file non-empty, applies `chmod "${mode}"`, and replaces the destination with `mv -f`.
- **R2.** `[PR1]` `_cheat_fetch` returns 1 when curl exits non-zero or writes nothing, returns 2 when `mktemp`, `chmod` or `mv` fails, removes any temp file it created on both, and leaves `dest` unmodified on both.
- **R3.** `[PR1]` All four cheat.sh fetches in `lib/workflows.sh` go through `_cheat_fetch`; no `curl` call fetching `cht.sh/:cht.sh` or `cheat.sh/:zsh` remains outside it.
- **R4.** `[PR1]` `run_setup_user` installs the binary with mode 750 and the completion with mode 644, prints a stderr warning naming the artifact when `_cheat_fetch` returns non-zero, and does not return non-zero for that reason.
- **R5.** `[PR1]` `run_update` installs the binary with mode 754 and the completion with mode 644, prints `cheat.sh <binary|completion> fetch failed` on rc 1 and `cheat.sh <binary|completion> install failed` on rc 2, and records the section FAIL on either.
- **R6.** `[PR1]` A test fails the binary fetch through `MOCK_CURL_FAIL_URL` with a pre-seeded `PRE-EXISTING` file and asserts the file is byte-identical and no `cht.sh.??????` file remains, once under `run_setup_user` and once under `run_update`; the same is asserted for `_cht` under `run_update`.
- **R7.** `[PR1]` For each of the four call sites a test asserts `grep -E -- '--max-time 10( |$)'` matches a recorded curl call carrying that call site's URL.
- **R8.** `[PR1]` A test makes the destination directory non-writable and asserts the destination is unchanged, the `install failed` message appears, and the cheat.sh section is FAIL.
- **R9.** `[PR1]` `tests/setup_env/workflows.bats`'s `_fetch_github_latest passes max-time 10` test asserts with `grep -E -- '--max-time 10( |$)'`.
- **R10.** `[PR1]` The two backlog rows named above are removed from `docs/superpowers/README.md`, and `CLAUDE.md`'s cheat.sh bullet states that a failed or timed-out fetch never replaces the existing file.
- **V1.** Mutation: change `_cheat_fetch` to `curl -o "${dest}"` directly (no temp file); the R6 tests go red.
- **V2.** Mutation: change `--max-time 10` to `--max-time 100` in `_cheat_fetch`; the R7 tests go red. Change `_fetch_github_latest`'s `--max-time 10` to `--max-time 100`; the R9 test goes red.
- **V3.** Run `_cheat_fetch` with real curl against a local listener that sends part of a body and stalls; it returns 1 within the bound and the pre-seeded destination is unchanged.
- **V4.** `make test` exits 0 locally and every CI job passes on the PR.
- **N1.** No URL or timeout seam is added to `_cheat_fetch`.
- **N2.** No retry logic.
- **N3.** The 750 / 754 binary-mode difference between `run_setup_user` and `run_update` is not changed.
- **N4.** `run_setup_user` gains no new non-zero return for a cheat.sh failure.
- **N5.** No new mode or knob is added to `tests/mocks/curl`.
- **N6.** No signal trap is added to clean up a temp file left by an interrupt.
