# Silent-False-Success Cluster — Design

Date: 2026-08-13
Status: Draft (pending Multi-Lens Review and user approval)

## Problem

Six functions in this repo return success for work that did not happen. Each is a
trust signal that carries more confidence than its mechanism earned: a caller writes
`install_git || return 1`, the guard cannot fire, and provisioning continues past a
failed install with a log line asserting the install succeeded.

The cluster was assembled from four backlog rows in
`docs/superpowers/README.md`. Re-deriving each row against the code before writing
this spec changed the scope in two directions, and both corrections are load-bearing.

**The backlog understated the defect.** It named `install_zsh_macos` and pointed at
`install_git_macos` as a likely sibling. Both are real. But the Linux twins are worse:
`install_git_linux` runs four unchecked `sudo -H apt` commands before its trailing
`log_info`, and `install_zsh_linux` runs three. macOS swallows one
`brew_install_formula` call; Linux swallows the repository add, the index update, a
full-system `dist-upgrade`, and the install itself. The consequence is that
`lib/workflows.sh:126`'s `install_git || return 1` cannot fire on Linux under any
circumstance.

**One backlog row was already substantially fixed.** `install_bats_macos` carries
`brew_install_formula bats-core || return 1`, and `install_bats_linux` propagates
because its `apt-get install` is the function's last command. bats is the newest code
in this family and the only clean member; git and zsh retain the legacy shape on both
platforms. The `install_bats` dispatcher's missing `else` arm — the third backlog row
— therefore sits above two callees that are themselves broken, which is why it is
folded into this change rather than deferred as an unreachable contract hazard.

A scan of all 36 tracked shell files for the shape (a function whose last command is a
`log_*` or `printf` call, so its return code is the log's) returned 27 hits. Twenty-two
are legitimate: value-returning helpers such as `_git_hooks_join` and `_git_repo_status`,
the `doctor_pass`/`doctor_fail`/`doctor_warn` reporters, and three functions
(`safe_link`, `setup_claude_mcp`, `install_make_macos`) that guard every failable
operation before their trailing log. The real defect set is five functions plus one
dispatcher family.

## Non-goals

**No mechanical scanner for this shape.** A head-only check keyed on "last command is a
log call" is 81 percent false-positive against this repo as measured above. A precise
check would need to identify an unchecked failable call preceding the trailing log,
which is real static analysis rather than a grep. `shell.md` records that the last
head-only shell scanner in this fleet — the function-length check — was deleted under
ADR-0056 for the same reason. This spec fixes the instances and does not add a gate.

**No change to the macOS `brew_install_formula` contract.** The two macOS install
guards are brought onto the pattern their own file already uses in two other functions;
nothing about `brew_install_formula` itself changes.

## Design

### 1. macOS install guards

`lib/macos.sh`. In `install_git_macos` (line 96) and `install_zsh_macos` (line 115),
the `brew_install_formula` call gains `|| return 1`.

This is the pattern already present twice in the same file — `install_bats_macos:134`
and `install_make_macos:184` both guard their brew call this way. The trailing
`log_info "Installed <pkg>"` is retained, because once every failable operation is
guarded, a trailing log is the file's established idiom and carries no risk.

### 2. Linux install guards

`lib/linux_shared.sh`. `install_git_linux` (line 4) and `install_zsh_linux` (line 14)
adopt tiered error handling: the step that defines the function's contract fails the
function, and preparatory steps warn and continue.

```bash
install_git_linux() {
  log_info "Installing git via apt"
  sudo -H add-apt-repository ppa:git-core/ppa -y \
    || log_warn "PPA add failed — continuing with distro git"
  sudo -H apt update \
    || log_warn "apt update failed — package index may be stale"
  sudo -H apt install git -y \
    || { log_error "Failed to install git"; return 1; }
  log_info "Installed git"
}
```

`install_zsh_linux` takes the same shape, without the PPA step, installing
`zsh zsh-doc`.

Two decisions are embedded here.

**Why the install step alone fails the function.** `apt install <pkg>` is what the
function promises. A failed PPA add means the distro package is used instead, which is
a degradation rather than a failure. A failed `apt update` leaves a stale index, which
usually still resolves. Making all four steps fatal would mean a transient mirror
timeout aborts `run_setup_user` at its first step; the operator then re-runs the entire
provisioning flow to recover from something that was never going to prevent the install.
Where a prep failure genuinely does prevent the install, the install step catches it —
so nothing is lost by warning rather than returning.

**Why `dist-upgrade` is deleted.** `sudo -H apt dist-upgrade -y` currently runs inside
both install functions, so `setup_env.sh -t setup_user` performs an unrequested
full-system upgrade, non-interactively, on every Linux run. That is a scope defect
independent of error handling: a function named "install git" should not upgrade the
system. The operation already exists in `update_system_packages`, where `-t update`
invokes it deliberately. Removing it removes a failure mode rather than adding a check
for one. `apt update` is retained — a fresh index is what the install itself needs.

The known risk: if any package on the Ubuntu boxes depends on having been
dist-upgraded before installation, that surfaces as a new failure. `apt install`
resolves its own dependencies, so this is unlikely, but it is the one behaviour change
in this spec that could break something the current code does not.

### 3. Update path — split apt from snap

`lib/linux_shared.sh:33` and `lib/workflows.sh:448`.

`update_system_packages` currently performs both apt and snap work and returns a single
code, which `run_update` records into two separate summary sections:

```bash
update_system_packages 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_apt"
local _pkg_ec="${PIPESTATUS[0]}"
cp "${_DOTFILES_RUN_TMPDIR}/err_apt" "${_DOTFILES_RUN_TMPDIR}/err_snap" 2>/dev/null || true
_update_record_end "apt"  "${_pkg_ec}"
_update_record_end "snap" "${_pkg_ec}"
```

Because the function ends in `log_info`, `_pkg_ec` is always zero, so both rows always
report OK. Fixing propagation alone would expose a second defect: a `snap refresh`
failure would mark the apt row red, and an apt failure would mark the snap row red.
That is the same trust-signal defect one level down — a row asserting more than its
mechanism measured — and it is worse than the current state, because an always-OK row
teaches nobody to trust it while a sometimes-red row that blames the wrong subsystem
does.

The function splits:

```bash
update_apt_packages() {
  sudo -H apt update           || { log_error "apt update failed"; return 1; }
  check_and_install_nala       || { log_error "nala install failed"; return 1; }
  sudo -H nala full-upgrade -y || { log_error "nala full-upgrade failed"; return 1; }
  sudo -H nala autoremove -y   || { log_error "nala autoremove failed"; return 1; }
  log_info "Updated apt packages"
}

update_snap_packages() {
  sudo snap refresh || { log_error "snap refresh failed"; return 1; }
  log_info "Updated snap packages"
}

update_system_packages() {
  local _rc=0
  update_apt_packages  || _rc=1
  update_snap_packages || _rc=1
  return "${_rc}"
}
```

`check_and_install_nala` belongs to the apt half because the upgrade cannot proceed
without it.

The wrapper runs both halves unconditionally rather than short-circuiting: snap should
still refresh when apt fails. `update_system_packages` is retained rather than removed
so that existing tests and any other reference keep working.

The caller becomes:

```bash
_update_record_start "apt"
update_apt_packages 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_apt"
_update_record_end "apt" "${PIPESTATUS[0]}"

_update_record_start "snap"
update_snap_packages 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_snap"
_update_record_end "snap" "${PIPESTATUS[0]}"
```

`PIPESTATUS[0]` read as the next command after the pipeline is the idiom already used
at `lib/workflows.sh:330`.

Two consequences of the split, both improvements:

- The `cp err_apt err_snap` line is deleted. Each section now has its own captured
  output; today the snap row's detail shows apt's output.
- Per-section timing becomes accurate. Today both `_update_record_start` calls fire
  before the combined operation, so both rows report the combined duration.

### 4. Dispatcher contracts

`lib/helpers.sh`. `install_git` (246), `install_zsh` (254), and `install_bats` (262)
each test `MACOS` then `LINUX` with no `else` arm, so with neither set the `if` compound
falls through and the function returns zero. A caller writing `install_bats || return 1`
cannot distinguish "an arm ran and installed bats" from "no arm ran".

Each gains:

```bash
  else
    log_error "Unsupported platform — cannot install <pkg>"
    return 1
  fi
```

The existing fall-through test pins rc 0. It encodes the bug and is updated in the same
change.

This is not reachable from production today: the only call sites, at
`lib/workflows.sh:126,133,137`, are guarded by the exact complement of the dispatchers'
own conditions. It is included because the two callees below `install_git` and
`install_zsh` are being fixed in this same change, and leaving the dispatcher above them
returning a false zero would mean the propagation added in items 1 and 2 stops one level
short of the caller.

### 5. bats pre-flight in the coverage runner

`scripts/run-bash-coverage.sh`. Line 738 invokes `bats` and line 739 captures its
status; `_check_red_suite` at line 757 then prints, for any non-zero status:

```
ERROR: bats suite failed (exit 127, 0 test(s) not ok) — refusing to compute coverage over a red run
```

With bats absent, exit 127 is "command not found" and no suite ran at all. The message
asserts a suite failure that never happened. The Makefile's four `$(error $(BATS_MISSING))`
guards do not cover this path, because `scripts/push-bash-coverage.sh` — documented for
cron use — invokes the coverage script directly. The `127` is the only clue, on the one
path nobody is watching.

A pre-flight check is added before the bats invocation:

```bash
if ! command -v bats > /dev/null 2>&1; then
    printf "ERROR: bats not installed — cannot measure coverage (install: brew install bats-core, or apt-get install bats)\n" >&2
    exit 1
fi
```

The guard goes in `run-bash-coverage.sh` rather than `push-bash-coverage.sh` because
that is the script that actually invokes bats, so one guard covers both the Makefile
path and the cron path. It exits non-zero so a scheduled run alerts rather than
silently doing nothing, with a message distinct from the red-suite message so the cause
is unambiguous.

Pre-flight is chosen over special-casing 127 inside `_check_red_suite`, because 127 can
also arise from bats itself invoking something missing — the two cases warrant different
messages and only a pre-flight check can tell them apart.

### 6. gnubin prefix parity test

`lib/macos.sh:171-172` (bash) and `.config/.zshrc.d/6_path.zsh:41-42` (zsh) both
hardcode `/opt/homebrew/opt/make/libexec/gnubin` and
`/usr/local/opt/make/libexec/gnubin`. A shared constant is unavailable: one is a bash
library, the other is sourced by every interactive zsh at shell start. Today the only
thing keeping them in step is a comment in each file saying so.

If they drift, the install guard and the `PATH` consumer disagree — the guard reports
"GNU make already installed" while plain `make` stays at 3.81. That is precisely the
defect fixed one level up in commit `91769f3`.

A bats case extracts the prefix literals from each file and asserts the two sets are
equal:

```bash
@test "gnubin prefixes match between lib/macos.sh and 6_path.zsh" {
  local _bash_prefixes _zsh_prefixes
  _bash_prefixes="$(grep -oE '/(opt/homebrew|usr/local)/opt/make/libexec/gnubin' \
    "${REPO_ROOT}/lib/macos.sh" | sort -u)"
  _zsh_prefixes="$(grep -oE '/(opt/homebrew|usr/local)/opt/make/libexec/gnubin' \
    "${REPO_ROOT}/.config/.zshrc.d/6_path.zsh" | sort -u)"

  [ -n "${_bash_prefixes}" ]
  [ -n "${_zsh_prefixes}" ]
  [ "${_bash_prefixes}" = "${_zsh_prefixes}" ]
}
```

The two non-empty assertions are load-bearing, not defensive padding. A grep that
matches nothing in both files makes the equality comparison vacuously true, so the test
would pass over a file that no longer contains either prefix — the empty-set trap that
`shell.md` records for derived-list assertions.

**What this test does not catch**, stated so nobody reads it as stronger than it is: it
verifies the two sets agree, not that they are correct. Both files being wrong in the
same way passes. That residual is acceptable because a wrong-together pair is caught by
`install_make_macos`'s own tests and, on a real mac, by `make --version` reporting 3.81
— whereas drift between the two files is silent on both sides and has no other detector.

An alternative was considered and rejected: running `6_path.zsh` against a fixture
directory at each prefix and asserting `PATH`, which would test the actual coupling
rather than the literals. The `_OVERRIDE_GNUBIN_*` seam exists on the bash side only,
so the zsh half would need a new seam, and the test would need a zsh subshell inside
bats. That is disproportionate to a two-line duplication.

## Testing

Every change is an error path that currently cannot be reached, so each needs a test
that reaches it.

**Every error-path test asserts two things: the return code is 1, and the trailing
success log is absent.** Asserting the return code alone would pass against a function
that returns 1 while still claiming `Installed git` in its output, which is half the
defect being fixed.

Per `tdd.md`'s mandatory categories:

- **Error path** — for each guarded call, a test with the underlying command mocked to
  fail, asserting rc 1 and no success log.
- **Both branches** — each guard also needs its success case, asserting rc 0 and the
  success log present. For the Linux tiered handling this means a third case: a prep
  step failing while the install succeeds must return 0 and emit the warning.
- **State transition** — for the update split, the summary rows must be asserted
  independently: apt failing with snap succeeding produces one red row and one green
  row, and the reverse.
- **Boundary** — the dispatchers with neither `MACOS` nor `LINUX` set.

**Mutation check on every guard.** Revert each `|| return 1` and confirm the
corresponding test goes red. This is not optional here: all six items are checks that
currently cannot fail, and a test written for one that also cannot fail reproduces the
exact defect being fixed. Per `behavior.md`, a check derived from the same decision as
the thing it checks cannot falsify it.

Existing test files needing new cases: `tests/setup_env/macos.bats`,
`tests/setup_env/linux_shared.bats`, `tests/setup_env/workflows.bats`,
`tests/setup_env/install_guards.bats`. The gnubin case is new and belongs with the
existing make-install cases in `install_guards.bats`.

## Verification

Baselines, runnable before any implementation:

```bash
make test            # 1294 tests green
make bash-coverage   # 91% against the CI floor
```

Acceptance:

- `make test` green, test count strictly greater than the baseline.
- `make lint` exit 0.
- `make bash-coverage` at or above 91 percent. All five production files touched are in
  the instrumented set, and the new error branches add coverable lines, so the tests
  must cover them or the gate drops.
- Each guard's mutation check goes red when the guard is reverted.

## Files

Production:

- `lib/macos.sh` — items 1
- `lib/linux_shared.sh` — items 2, 3
- `lib/helpers.sh` — item 4
- `lib/workflows.sh` — item 3 caller
- `scripts/run-bash-coverage.sh` — item 5

Tests:

- `tests/setup_env/macos.bats`
- `tests/setup_env/linux_shared.bats`
- `tests/setup_env/workflows.bats`
- `tests/setup_env/install_guards.bats`

## Backlog rows closed by this spec

Four rows move out of `docs/superpowers/README.md`'s backlog when this lands:

- `install_zsh_macos` reports a brew failure as success
- `install_bats` dispatcher returns 0 when no platform matches
- `push-bash-coverage.sh` misreports a missing bats as a red suite
- gnubin prefix pair is duplicated across two languages with only a comment binding them

Two further rows are stale and were already fixed by earlier work; they should be
deleted from the backlog in the same commit:

- `make lint` cannot see the extensionless hooks — closed by the `git ls-files`-derived
  `SHELL_FILES` at `Makefile:14`, which includes `scripts/pre-push` and
  `scripts/commit-msg`.
- Coverage denominator: heredoc bodies still inflate it — closed by the heredoc
  exclusion at `scripts/run-bash-coverage.sh:212`, which handles `<<` and `<<-` in any
  quoting for any interpreter.
