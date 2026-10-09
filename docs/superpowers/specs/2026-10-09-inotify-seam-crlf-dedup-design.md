# inotify: unprivileged conf seam, non-text confs refused, one live-value check

Status: Approved (2026-10-09, after Multi-Lens Review round 1)

- **Approved:** 2026-10-09

Date: 2026-10-09
Backlog rows addressed (`docs/superpowers/README.md`):

- `_SYSCTL_CONF` seam writes an env-chosen path as root (`:181`) — fixed
- inotify live-value check copied three times (`:182`) — fixed
- inotify conf parsers reject CRLF lines (`:183`) — closed as won't-fix; see Decision 2

Follows `2026-10-08-inotify-followups-design.md`, whose N4 deferred the first row.

## Problem

Three defects in the inotify step (`_install_ubuntu_inotify`, `lib/linux_ubuntu.sh`) and its
doctor check (`_doctor_check_inotify_limits`, `lib/helpers.sh`), plus a fourth found in
review. Each premise was verified by command on 2026-10-09.

1. **The conf seam writes as root.** `lib/linux_ubuntu.sh:104` pipes into
   `sudo tee "${_conf}"`, and `_conf` is `${_SYSCTL_CONF:-${INOTIFY_SYSCTL_CONF}}`. An
   environment that sets `_SYSCTL_CONF` therefore chooses a path that root overwrites. #324
   fixed the same shape for `_SYSCTL_BIN` (run without sudo when set) and deferred this one
   as its N4. `git grep _SYSCTL_CONF` finds no setter outside the test suite.
2. **CRLF lines are refused.** Both awk parsers use the default `RS="\n"`, so a CRLF line
   keeps its `\r`. On a fixture, `fs.inotify.max_user_instances = 1024\r\n` makes
   `_inotify_conf_value` print nothing, so the step and doctor call the conf unparseable. The
   refusal fails closed and loses no data. Occurrence: 0 CRLF files under `/etc/sysctl.d`,
   `/usr/lib/sysctl.d` and `/run/sysctl.d` on `claude`, and the only writer of this file is
   the step itself, which writes LF.
3. **A NUL byte hides a foreign key (found by the Risk lens).** systemd v259's
   `read_line_full` ends a line at `\r\n`, `\r`, `\n\r` or NUL. awk does not split on NUL or
   bare `\r`. On `printf '# c\0other.key = 5\nfs.inotify.max_user_instances = 512\n'`, mawk
   and gawk both read the first record as a comment: `_inotify_conf_value` prints `512` and
   `_inotify_conf_has_other_keys` returns 1. The step would rewrite the file and delete
   `other.key`, which systemd applies. This exists today; it is not a regression.
4. **The live-value check is copied, and the copies disagree.** The shape check
   `^(0|[1-9][0-9]{0,9})$` plus the `2147483647` cap appears at `lib/helpers.sh:1016` and
   `lib/linux_ubuntu.sh:96`, and the cap a third time in the awk at `lib/helpers.sh:971`. The
   step reads `$(<"${_proc}")` behind a `-r` test and strips all whitespace; doctor reads
   `$(cat "${_proc}" 2>/dev/null)` and strips nothing.

## Decision

### 1. Conf seam: plain `tee` when set, in one write helper

New `_inotify_conf_write <target>` in `lib/linux_ubuntu.sh` performs the step's only write.
When `_SYSCTL_CONF` is non-empty it pipes `fs.inotify.max_user_instances = <target>` into
`tee "${_SYSCTL_CONF}"` without sudo, and its failure message names `_SYSCTL_CONF`. When
`_SYSCTL_CONF` is empty or unset it pipes into `sudo tee "${INOTIFY_SYSCTL_CONF}"`, the
readonly constant. This mirrors `_SYSCTL_BIN`: an inotify seam never runs as root.

The helper exists so the unset branch is testable without reading host state. A test through
the whole step with the seam unset would read the real `/etc/sysctl.d/90-dotfiles-inotify.conf`
first; on `claude` that file holds 1024, so the step never reaches the write and the test's
verdict follows the host (all three lenses). The helper is called with a target and reads no
conf.

Doctor's printed remedy still says `sudo tee '<conf>'` under the seam. That is deliberate: it
is text for an operator, only tests set the seam, and the operator path is the root path.

Rejected: **refuse `_SYSCTL_CONF` outside `/etc/sysctl.d/`** still lets the environment pick a
path root writes, and makes fixture testing impossible. **Remove the seam** leaves nothing
able to test the write without touching the real `/etc`.

### 2. Non-text confs: refuse, do not parse

The step and doctor refuse a conf that contains any byte other than printable ASCII
(0x20-0x7E), tab or newline, with `inotify: <conf> holds non-text bytes (CR, NUL or
non-ASCII); fix by hand` (doctor: same text after `doctor_fail "inotify"`). The check runs
after the readability check and before `_inotify_conf_has_other_keys`. It is a bash pre-check
built on `LC_ALL=C tr -d` piped to `wc -c`, not an awk regex, because awks differ on NUL and
command substitution silently drops NUL bytes.

This covers CRLF, bare CR, `\n\r` and NUL alike, closes Problem 3, and keeps every refusal
fail-closed. CRLF backlog row `:183` is closed as won't-fix: parsing CRLF would widen the
whole-file `tee` to rewrite a file only a hand edit could produce, for zero known occurrences.
Cost accepted: a conf with a non-ASCII comment (`# café`) is refused too.

### 3. One live-value reader, one cap constant

- `readonly INOTIFY_INT_MAX=2147483647` in `lib/constants.sh`, beside
  `INOTIFY_MAX_USER_INSTANCES`.
- `_inotify_read_live <proc>` in `lib/helpers.sh`: returns 1 with no output when `<proc>` is
  unreadable; otherwise reads it, deletes all whitespace, and prints the value with rc 0 only
  when it matches `^(0|[1-9][0-9]{0,9})$` and is at most `INOTIFY_INT_MAX`, else returns 1
  with no output. Shape is tested before arithmetic, because bash wraps a 20-digit number and
  reads `08` as invalid octal.
- The step and doctor both call it and keep their own failure messages
  (`inotify: cannot read live value <proc>` and `cannot read <proc>`).
- `_inotify_conf_value`'s awk takes the cap through `-v max="${INOTIFY_INT_MAX}"`. Its shape
  and length checks stay in awk.

Known behaviour change: doctor now accepts a live value with surrounding whitespace, as the
step already did. The kernel's `/proc` file prints `<n>\n`, which both forms already accept.

### Widened write condition (Step 7 check)

Nothing widens. Item 1 changes only the privilege of the write and moves it into a helper.
Item 2 only adds refusals. Item 3 admits whitespace-padded live values in doctor, which writes
nothing.

## Testing

All in `tests/setup_env/linux_ubuntu.bats` (step, write helper) and
`tests/setup_env/unit.bats` (doctor, parsers, reader), TDD, one behaviour at a time.

- **Write helper, seam set:** `_inotify_conf_write 4096` leaves the conf holding exactly
  `fs.inotify.max_user_instances = 4096`, and `MOCK_CALLS_FILE` has no `sudo` line.
- **Write helper, seam unset:** `_SYSCTL_CONF` unset; a `SHIM_DIR` `sudo` shim records its
  argv, drains stdin, and executes nothing. The test asserts `command -v sudo` resolves to the
  shim before calling, then asserts the recorded line is
  `tee /etc/sysctl.d/90-dotfiles-inotify.conf` and rc 0. No test calls the whole step with the
  seam unset.
- **Write failure under the seam:** `MOCK_TEE_EXIT=1` (`tests/mocks/tee` swallows real write
  errors); rc 1 and the message names `_SYSCTL_CONF`.
- **Non-text refusal:** fixtures built with `printf` for a CRLF key line, a lone bare `\r`, a
  NUL-hidden foreign key (Problem 3's exact bytes) and a non-ASCII comment. Each is refused by
  the step (rc 1, conf byte-identical afterwards, no write recorded) and by doctor (FAIL with
  the non-text message). Controls: a plain LF conf at 512 is still rewritten, and a conf with
  tab separators is not refused.
- **Reader boundary table**, each with a fixed expected result: `0` prints `0`; `1024` prints
  `1024`; ` 1024\n` prints `1024`; `2147483647` prints `2147483647`; unreadable, empty, `08`,
  `2147483648`, 11 digits, 20 digits and `abc` each return 1 with empty output. The step and
  doctor are each run on one accepted and one rejected value.
- **Mutations**, each turning at least one test red: `sudo` restored on the seam branch;
  the constant path replaced by `${_conf}` on the unset branch; the non-text check removed
  from the step or from doctor; `tr`'s keep-set widened to pass `\r`; the reader's regex
  loosened to accept `08`; the reader made to always return 1; the awk `-v` cap replaced by
  a smaller literal.

## Requirements

- **R1.** `[PR1]` `_inotify_conf_write <target>` writes `fs.inotify.max_user_instances = <target>` with `tee "${_SYSCTL_CONF}"` and no sudo when `_SYSCTL_CONF` is non-empty, naming `_SYSCTL_CONF` in its failure message, and with `sudo tee "${INOTIFY_SYSCTL_CONF}"` otherwise; `_install_ubuntu_inotify` writes the conf only through it.
- **R2.** `[PR1]` `_install_ubuntu_inotify` and `_doctor_check_inotify_limits` refuse, with a message containing `non-text bytes` and `fix by hand`, an existing readable conf that contains any byte other than 0x20-0x7E, tab or newline, before checking for other keys.
- **R3.** `[PR1]` `lib/constants.sh` defines `readonly INOTIFY_INT_MAX=2147483647`, and the literal `2147483647` appears nowhere in `lib/helpers.sh` or `lib/linux_ubuntu.sh` outside comments.
- **R4.** `[PR1]` `_inotify_read_live <proc>` prints the whitespace-stripped value and returns 0 only when `<proc>` is readable and the value matches `^(0|[1-9][0-9]{0,9})$` and is at most `INOTIFY_INT_MAX`; otherwise it prints nothing and returns 1.
- **R5.** `[PR1]` `_install_ubuntu_inotify` and `_doctor_check_inotify_limits` obtain the live value only through `_inotify_read_live`, and keep their existing failure messages.
- **R6.** `[PR1]` CLAUDE.md's Test Seams bullet states that `_SYSCTL_CONF` is written without sudo when set and that non-text confs are refused; ADR-0044 carries a dated Consequences note; the three Backlog rows at `docs/superpowers/README.md:181-183` are deleted.
- **V1.** `make test` passes; each mutation listed in Testing turns at least one test red.
- **V2.** After merge, on `claude`: `-t doctor` passes the inotify check, and `-t developer` prints `inotify: already 1024 or higher` with `/etc/sysctl.d/90-dotfiles-inotify.conf` byte-identical before and after.
- **N1.** No test runs `_install_ubuntu_inotify` with `_SYSCTL_CONF` unset, and no test calls `_inotify_conf_write` with it unset unless a recording `sudo` shim that executes nothing resolves first on `PATH`.
- **N2.** The awk parsers are not taught to read CRLF or any other line ending.
- **N3.** No change to which conf values the step writes or which live values it applies; no change to doctor's printed remedy text or to `_SYSCTL_BIN` handling.
- **N4.** No shared `_inotify_conf_state` helper (Backlog `:325` stays open).

## Multi-Lens Review

Round 1 reviewed at commit: `95dabcd2` (spec as first written, with the Step 7 R3-ordering fix). Adversarial Spec Review Gate: skipped — no comparison design, no judge, concrete acceptance criteria. History below refers to that version's numbering.

### Goal-Fit

Finding: (1) The seam-unset test reads the real `/etc/sysctl.d/90-dotfiles-inotify.conf`
before writing; on `claude` it holds 1024, so no `sudo tee` is recorded and the test is red,
while CI (file absent) is green. (2) The CRLF fix does not earn its cost: zero occurrences, a
dotfiles-owned file only the step writes (LF), a fail-closed refusal today, versus two parser
edits, a deny rule and a widened overwrite. Close the row as won't-fix. (3) The dedup changes
no decision on real input; the constant and `-v` cap are cheap, the reader function mildly
over-engineered but defensible. (4) "Step and doctor agree" passes if the reader always
returns 1; pin printed values.
Assumption: that `_SYSCTL_CONF` has no non-test users. Settle with `git grep` across repos
and a grep of shell rc files on each machine.
Disposition: Addressed (operator, 2026-10-09) — (1) write moved into `_inotify_conf_write`, tested directly; (2) option A: refuse non-text confs, row closed won't-fix; (3) reader kept, the row asked for one predicate; (4) fixed-value boundary table.

### Ergonomics

Finding: (1) Same host-dependent seam-unset test as Goal-Fit (1). (2) The seam write-failure
test cannot reach its message: `tests/mocks/tee` ends in `|| true`, so it needs
`MOCK_TEE_EXIT=1`. (3) Same always-reject reader gap. (4) Doctor's remedy still prints
`sudo tee` under the seam; name it as deliberate.
Assumption: no operator exports `_SYSCTL_CONF` relying on the root write; checked on `claude`
(tracked repo, `~/.zshrc*`, `config/local.sh`), unverified on the 7950X and the Studio.
Disposition: Addressed (operator, 2026-10-09) — (1) as Goal-Fit; (2) `MOCK_TEE_EXIT=1` named in Testing; (3) fixed-value table; (4) stated in Decision 1. The assumption is accepted: the variable is a leading-underscore test seam documented under Test Seams.

### Risk

Finding: (1) Same host-dependent test; forcing a write with a high live value only moves the
dependency to read-back. (2) "No other line can be lost" is false for NUL: systemd ends a
line at NUL, awk does not, so `# c\0other.key = 5\n...= 512` reads as a comment plus our key
under mawk and gawk, and the step deletes `other.key`. Pre-existing. (3) Same always-reject
reader gap; also name the CRLF parse value.
Checked, not raised: `\r` regex under mawk/gawk, numeric `-v` comparison, unset
`INOTIFY_INT_MAX` failing closed, `readonly` double-sourcing.
Assumption: systemd v259 ends a sysctl.d line at NUL and bare CR; settled by reading
`read_line_full` in `src/basic/fileio.c` at v259 (done in Phase 1 premise check).
Disposition: Addressed (operator, 2026-10-09) — (1) as Goal-Fit; (2) non-text refusal covers NUL, added as Problem 3; (3) fixed-value table.
