# inotify: unprivileged conf seam, CRLF lines, one live-value check

Status: Draft (Phase 1)
Date: 2026-10-09
Backlog rows addressed (`docs/superpowers/README.md`):

- `_SYSCTL_CONF` seam writes an env-chosen path as root (`:181`)
- inotify live-value check copied three times (`:182`)
- inotify conf parsers reject CRLF lines (`:183`)

Follows `2026-10-08-inotify-followups-design.md`, whose N4 deferred the first row.

## Problem

Three defects in the inotify step (`_install_ubuntu_inotify`, `lib/linux_ubuntu.sh`) and its
doctor check (`_doctor_check_inotify_limits`, `lib/helpers.sh`). Each premise was verified by
command on 2026-10-09 before design.

1. **The conf seam writes as root.** `lib/linux_ubuntu.sh:104` pipes into
   `sudo tee "${_conf}"`, and `_conf` is `${_SYSCTL_CONF:-${INOTIFY_SYSCTL_CONF}}`. An
   environment that sets `_SYSCTL_CONF` therefore chooses a path that root overwrites. #324
   fixed the same shape for `_SYSCTL_BIN` (run without sudo when set) and deferred this one
   as its N4; nothing rejected the fix.
2. **CRLF lines are refused.** Both awk parsers use the default `RS="\n"`, so a CRLF line
   keeps its `\r`. Measured on a fixture: `fs.inotify.max_user_instances = 1024\r\n` makes
   `_inotify_conf_value` print nothing (`val=[]`), so the step and doctor call the conf
   unparseable; a lone `\r\n` blank line makes `_inotify_conf_has_other_keys` exit 0, so they
   call it foreign. systemd v259 accepts both: `conf_file_read` reads through
   `read_stripped_line` → `read_line_full`, which ends a line at `\r\n`, `\r`, `\n\r` or NUL.
   The refusal fails closed and loses no data. Occurrence: 0 CRLF files under
   `/etc/sysctl.d`, `/usr/lib/sysctl.d` and `/run/sysctl.d` on `claude`. This is a
   correctness fix, not an incident.
3. **The live-value check is copied, and the copies disagree.** The shape check
   `^(0|[1-9][0-9]{0,9})$` plus the `2147483647` cap appears at `lib/helpers.sh:1016` and
   `lib/linux_ubuntu.sh:96`, and the cap a third time in the awk at `lib/helpers.sh:971`. The
   two bash readers differ: the step reads `$(<"${_proc}")` behind a `-r` test and strips all
   whitespace; doctor reads `$(cat "${_proc}" 2>/dev/null)` and strips nothing.

## Decision

### 1. Conf seam: plain `tee` when set

When `_SYSCTL_CONF` is non-empty the step writes with `tee "${_conf}"`, without sudo. When it
is empty or unset the step writes with `sudo tee "${INOTIFY_SYSCTL_CONF}"`, the readonly
constant. This mirrors `_SYSCTL_BIN`, so the rule becomes one sentence: an inotify seam never
runs as root. The write-failure message names `_SYSCTL_CONF` when the seam was set, as the
apply-failure message already names `_SYSCTL_BIN`.

Tests lose nothing: `load_mocks` points `_SYSCTL_CONF` at `BATS_TEST_TMPDIR`, which the test
user owns. Doctor's printed remedy is text, never executed, and is unchanged.

Rejected: **refuse `_SYSCTL_CONF` outside `/etc/sysctl.d/`** still lets the environment pick
a path root writes, and makes fixture testing impossible. **Remove the seam** leaves nothing
able to test the write without touching the real `/etc`.

### 2. CRLF: strip one trailing `\r`, deny any other

Both awk parsers run `sub(/\r$/, "", line)` on each record before any other test. That
matches systemd for `\r\n` files. After that strip, `_inotify_conf_has_other_keys` counts any
record that still contains `\r` as foreign, and checks this before skipping comments, since such a record may open with `#`. Such a record is a bare-CR (or `\n\r`) file that
systemd splits into several lines and awk sees as one, so its tail may hold another key that
the whole-file `tee` would delete. Default-deny keeps that case refused, now with the accurate
"holds other keys" message instead of "unparseable".

### 3. One live-value reader, one cap constant

- `readonly INOTIFY_INT_MAX=2147483647` in `lib/constants.sh`, beside
  `INOTIFY_MAX_USER_INSTANCES`.
- `_inotify_read_live <proc>` in `lib/helpers.sh`: returns 1 when `<proc>` is unreadable;
  otherwise reads it, deletes all whitespace, and prints the value with rc 0 only when it
  matches `^(0|[1-9][0-9]{0,9})$` and is at most `INOTIFY_INT_MAX`, else returns 1. Shape is
  tested before arithmetic, because bash wraps a 20-digit number and reads `08` as invalid
  octal.
- The step and doctor both call it and keep their own failure messages
  (`inotify: cannot read live value <proc>` and `cannot read <proc>`).
- `_inotify_conf_value`'s awk takes the cap through `-v max="${INOTIFY_INT_MAX}"`. Its shape
  and length checks stay in awk, since the conf value is a field, not a whole file.

Known behaviour change: doctor now accepts a live value with surrounding whitespace, as the
step already did. The kernel's `/proc` file prints `<n>\n`, which both forms already accept.

### Widened write condition (Step 7 check)

Item 2 widens when the step's whole-file `tee` runs: a CRLF conf holding only our key,
comments and blank lines, with a value below `max(live, 1024)`, was refused and is now
rewritten. On that input the rewrite deletes the comments and converts the file to LF. That
is exactly what the step already does to the same file with LF endings, which #324 accepted:
comments are not keys and systemd ignores them. No other line can be lost, because
`_inotify_conf_has_other_keys` still refuses any record that is not blank, a comment or our
key. Items 1 and 3 widen nothing: item 1 changes only the privilege of the write, and item 3
admits only whitespace-padded live values, which do not change what is written.

## Testing

All in `tests/setup_env/linux_ubuntu.bats` (step) and `tests/setup_env/unit.bats` (doctor and
parsers), TDD, one behaviour at a time.

- **Seam set:** a step run that writes the conf records no `sudo` call naming `tee`, and the
  conf holds the written value.
- **Seam unset:** with `_SYSCTL_CONF` unset, a `SHIM_DIR` `sudo` shim that records its argv and
  does not exec anything sits first on `PATH`. The step records
  `sudo tee /etc/sysctl.d/90-dotfiles-inotify.conf` and then returns 1 at read-back, having
  written nothing. Before running, the test asserts `command -v sudo` resolves to the shim, so
  a PATH regression cannot reach `tests/mocks/sudo`, which execs real commands (`tdd.md` E2).
- **Write failure under the seam:** the message names `_SYSCTL_CONF`.
- **CRLF:** a CRLF key line parses to its value; a CRLF blank line and a CRLF comment are not
  foreign; a step run over a CRLF conf below target rewrites it and reads it back. A bare-CR
  file holding our key and another key is refused as holding other keys, by both the step and
  doctor.
- **Dedup:** `_inotify_read_live` boundary table: unreadable, empty, `0`, `1024`, `08`,
  ` 1024\n`, `2147483647`, `2147483648`, 11 digits, 20 digits, `abc`. Each value runs through
  the step and doctor, which must agree on readable versus not.
- **Mutations**, each turning at least one test red: `sudo` restored on the seam branch;
  the `\r` strip removed from either parser; the embedded-`\r` deny removed; the step or doctor
  reverted to an inline check that drops whitespace stripping; the awk `-v` cap replaced by a
  smaller literal.

Real-tool check (pitfall F): one CRLF fixture is produced with `printf '...\r\n'` and parsed
by the real awk, not a mock.

## Requirements

- **R1.** `[PR1]` When `_SYSCTL_CONF` is non-empty, `_install_ubuntu_inotify` writes the conf with `tee` and no sudo, and its write-failure message names `_SYSCTL_CONF`; when `_SYSCTL_CONF` is empty or unset, it writes with `sudo tee "${INOTIFY_SYSCTL_CONF}"`.
- **R2.** `[PR1]` `_inotify_conf_value` and `_inotify_conf_has_other_keys` remove one trailing `\r` from each line before any other test, so a CRLF assignment of the key parses to its value and a CRLF blank or comment line is not foreign.
- **R3.** `[PR1]` `_inotify_conf_has_other_keys` exits 0 for any line that still contains `\r` after that removal, checked before the blank and comment skips, so a line starting with `#` or `;` that contains `\r` is foreign too.
- **R4.** `[PR1]` `lib/constants.sh` defines `readonly INOTIFY_INT_MAX=2147483647`, and the literal `2147483647` appears nowhere in `lib/helpers.sh` or `lib/linux_ubuntu.sh` outside comments.
- **R5.** `[PR1]` `_inotify_read_live <proc>` prints the whitespace-stripped value and returns 0 only when `<proc>` is readable and the value matches `^(0|[1-9][0-9]{0,9})$` and is at most `INOTIFY_INT_MAX`; otherwise it prints nothing and returns 1.
- **R6.** `[PR1]` `_install_ubuntu_inotify` and `_doctor_check_inotify_limits` obtain the live value only through `_inotify_read_live`, and keep their existing failure messages.
- **R7.** `[PR1]` CLAUDE.md's Test Seams bullet states that `_SYSCTL_CONF` is written without sudo when set; ADR-0044 carries a dated Consequences note; the three Backlog rows at `docs/superpowers/README.md:181-183` are deleted.
- **V1.** `make test` passes; each mutation listed in Testing turns at least one test red.
- **V2.** After merge, on `claude`: `-t doctor` passes the inotify check, and `-t developer` prints `inotify: already 1024 or higher` with `/etc/sysctl.d/90-dotfiles-inotify.conf` byte-identical before and after.
- **N1.** No test runs the step with `_SYSCTL_CONF` unset unless a recording `sudo` shim that executes nothing resolves first on `PATH`.
- **N2.** No change to which conf values the step writes or which live values it applies, beyond accepting CRLF confs (R2) and whitespace-padded live values in doctor (R5, R6).
- **N3.** No change to doctor's printed remedy text or to `_SYSCTL_BIN` handling.
- **N4.** Bare-CR and `\n\r` confs are not parsed; they stay refused.
- **N5.** No shared `_inotify_conf_state` helper (Backlog `:325` stays open).
