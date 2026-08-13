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
full-system `dist-upgrade`, and the install itself.

**Only one of those two is reachable, and the spec says so rather than trading on the
stronger-sounding claim.** `install_git || return 1` at `lib/workflows.sh:126` sits
inside `if [[ -n ${MACOS} ]]`, and `install_git_linux` has no other production caller —
so it never runs at all, and neither its swallowed exit code nor its `dist-upgrade`
has any live consequence. `install_zsh || return 1` at `lib/workflows.sh:133` is gated
`[[ ${MACOS} || ${UBUNTU} ]]`, so `install_zsh_linux` **is** live on every Ubuntu
provisioning run, and its unrequested non-interactive `apt dist-upgrade -y` is the
single highest-value change in this document. An earlier draft framed this as
"`install_git || return 1` cannot fire on Linux", which is true and misleading: the
call never happens there, so the guard's inability to fire is not the defect.

`install_git_linux` is still brought onto the same shape, as dead-code hygiene with no
claimed production benefit. It costs three lines, it keeps the two Linux install
functions readable as a pair, and item 4's dispatcher fix makes `install_git` callable
from a future Linux caller that does not exist today.

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

This is the pattern already present twice in the same file — `install_bats_macos`
guards at line 145 and `install_make_macos` at line 184. The trailing
`log_info "Installed <pkg>"` is retained, because once every failable operation is
guarded, a trailing log is the file's established idiom and carries no risk.

### 2. Linux install guards

`lib/linux_shared.sh`. `install_git_linux` (line 4) and `install_zsh_linux` (line 14)
adopt tiered error handling: the step that defines the function's contract fails the
function, and preparatory steps warn and continue.

```bash
install_git_linux() {
  if quiet_which git; then
    log_info "git already installed"
    return 0
  fi
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

Three decisions are embedded here.

**Why the already-installed guard is not optional once the install step is fatal.**
`install_bats_linux:24` already opens with `quiet_which bats && return 0`;
`install_git_linux` and `install_zsh_linux` do not, so today they re-run `apt install`
on every provisioning run and swallow whatever happens. Making the install step fatal
without adding the guard converts that from harmless to breaking: `run_setup_user`
calls `install_zsh || return 1` at `lib/workflows.sh:133`, ahead of
`clone_or_update_dotfiles`, `setup_ai_config`, and `setup_dotfile_symlinks`. A dpkg
lock held by `unattended-upgrades` — the ordinary state of a freshly-booted Ubuntu box,
which is exactly what gets provisioned — would then abort the entire run having done
nothing, over a package that was already present. With the guard, the fatal path fires
only when zsh is genuinely absent, which is when it should be fatal.

This is the same idiom `install_bats_linux` and `install_bats_macos` already use, and
the macOS git and zsh functions have their own equivalent (`brew list | grep` at
`lib/macos.sh:98,117`). The Linux pair is the only place in the family without one.

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

if [[ -n ${HAS_SNAP} ]]; then
  _update_record_start "snap"
  update_snap_packages 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_snap"
  _update_record_end "snap" "${PIPESTATUS[0]}"
else
  _update_skip "snap" "not applicable"
fi
```

**The `HAS_SNAP` gate is load-bearing, not defensive.** `sudo snap refresh` at
`lib/linux_shared.sh:38` is the only ungated snap call in the repo — the six others, all
in `lib/linux_ubuntu.sh` (lines 39, 177, 379, 401, 413, 421), test `HAS_SNAP`.
`PROFILE_CAPS` in `config/profiles.sh` omits snap from two profiles:

```
[wsl2_workstation]="gui devtools aws k8s docker rust"
[server]="devtools aws"
```

Today that omission is harmless _precisely because of the bug this item fixes_: the
trailing `log_info` swallows a failing `snap refresh`. Propagating the exit code without
adding the gate would therefore introduce the very defect this item's rationale argues
against one paragraph above — a row that goes red on every run on a machine where snap
is not installed and cannot be, blaming a subsystem the operator has no action for. A
permanently-red row stops carrying information the first time it is correctly ignored,
which is strictly worse than the always-green row it replaces.

`_update_skip "snap" "not applicable"` reuses the string the non-Linux arm already emits
eleven lines below, so the two skip paths read identically in the summary.

One open question the gate does not depend on: `wsl2_workstation` was declared snap-less
on the reasoning that snap is unavailable under WSL2, which predates WSL2's systemd
support — Ubuntu 24.04 under systemd-enabled WSL2 runs snapd. If the cruncher does have
a working snapd, the gate costs nothing there and `server` still requires it. The gate is
correct whichever way that measurement lands, so it is not blocked on running
`command -v snap && sudo snap refresh; echo rc=$?` on that machine. If the answer turns
out to be "snapd works," the follow-up is a `PROFILE_CAPS` correction, not a change here.

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

### 5. The coverage publisher discards its measurement's exit code

**This item was rescoped after round-1 review. The original version proposed a `bats`
pre-flight check inside `scripts/run-bash-coverage.sh`, on the stated premise that the
Makefile's `$(error $(BATS_MISSING))` guards "do not cover this path, because
`scripts/push-bash-coverage.sh` — documented for cron use — invokes the coverage script
directly." That premise is false, and the real defect is one level up.**

The cron entry does not invoke the script directly:

```
0 2 * * * cd ~/git-repos/personal/dotfiles && make push-bash-coverage >> ~/.dotfiles-coverage.log 2>&1
```

`Makefile:114-118` carries `ifndef BATS / $(error $(BATS_MISSING))`, so that path is
already guarded — and that guard is the only thing that has ever run on it.
`~/.dotfiles-coverage.log` holds 78 lines, every one of them the guard firing, and zero
lines matching `Coverage:`, `Pushed`, or `unchanged`. The job has never succeeded.
`BATS := $(shell command -v bats)` is evaluated in make's own process under cron's PATH,
which lacks `/opt/homebrew/bin`. A pre-flight check inside the script would use the
identical probe and fail identically, on a path cron never reaches.

The badge itself is unaffected: every commit on `origin/coverage-data` since the branch
was created is authored by `github-actions[bot]`, and `.github/workflows/ci.yml:167-178`
pushes it on every PR. The cron entry is dead _and_ redundant. Deleting it is an operator
action on a machine-local crontab, outside this repo's scope, and is recorded in the
follow-ups section rather than fixed here.

**What this item fixes instead.** `scripts/push-bash-coverage.sh:25` invokes the coverage
script **unchecked**, and line 26 then reads `coverage/bash.json`:

```bash
bash "${REPO_ROOT}/scripts/run-bash-coverage.sh" --json "${BADGE_JSON}"
overall_pct=$(python3 -c "...json.load(open('${BADGE_JSON}'))...")
```

`run-bash-coverage.sh` cleans up at lines 707 and 746, clearing `TRACE_FILE` and
`TRACE_FIFO` only — never the badge JSON. So a stale badge survives every failed
measurement: the child prints its error and exits non-zero, and the parent proceeds to
read, commit and push the _previous_ run's figure, exiting 0. Seven `exit 1` sites
already exist in the child (lines 105, 493, 602, 757, 761, 788, 805), including the
red-suite check and two untrustworthy-denominator paths. The caller discards all seven.

Adding an eighth would be `behavior.md`'s guard-whose-verdict-arrives-too-late: the
verdict would be real and correct, and nothing would read it. Worse, it would make the
cron entry look repairable — fixing that entry's PATH without this change would not
restore the badge job, it would publish a badge that lies, on a schedule.

The fix is in the caller:

```bash
rm -f "${BADGE_JSON}"
if ! bash "${REPO_ROOT}/scripts/run-bash-coverage.sh" --json "${BADGE_JSON}"; then
    printf "ERROR: coverage measurement failed — not publishing a badge\n" >&2
    exit 1
fi
```

Both lines are needed and they fail closed independently. `|| exit 1` stops a failed
measurement from reaching the publish step. `rm -f` ahead of the run means that even if
some future path exits 0 without writing a badge, line 28's existing
`if [[ -z "${overall_pct}" ]]` check catches the absent file rather than reading a
month-old one. Removing the file before the run is what makes "no badge" and "stale
badge" distinguishable at all — without it, the freshness of `coverage/bash.json` is
unobservable from the caller.

The original pre-flight is dropped. The only invocation it would have improved is a human
hand-typing `bash scripts/run-bash-coverage.sh` with bats absent, where the existing
`_check_red_suite` message already halts the run, and where the Makefile's message is
strictly better because it names the durable fix (`./setup_env.sh -t setup_user`).

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
- **Boundary** — the dispatchers with neither `MACOS` nor `LINUX` set. Also
  `install_zsh_linux`/`install_git_linux` with the package already present: rc 0, the
  "already installed" log emitted, and `apt install` **not** invoked.
- **Capability gate** — `-t update` on Linux with `HAS_SNAP` unset produces a skipped
  snap row, not a failed one, and does not invoke `snap refresh` at all. With `HAS_SNAP`
  set, the row is recorded normally. Without both cases the gate is a one-branch guard
  of exactly the kind `logic-review.md` item 6 names.

**One case must pin a derived value, not a verdict.** Item 3 claims that deleting
`cp err_apt err_snap` gives the snap section its own captured output. Every acceptance
criterion above still passes if `err_snap` is written empty — the rows go red and green
correctly, the tests are green, the coverage figure holds. Add a case asserting
`err_snap` contains snap output and does **not** contain apt's, so the suite tests the
measurement and not only the comparison built on it.

The same reasoning does not extend to the per-section timing claim, which is left
unpinned deliberately: asserting on wall-clock durations in a mocked suite buys a flaky
test rather than a real check, and the timing improvement follows structurally from
moving `_update_record_start` next to its own call.

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

- `lib/macos.sh` — item 1
- `lib/linux_shared.sh` — items 2 and 3
- `lib/helpers.sh` — item 4
- `lib/workflows.sh` — item 3 caller and its `HAS_SNAP` gate
- `scripts/push-bash-coverage.sh` — item 5

`scripts/run-bash-coverage.sh` is **not** touched. It was in the original file list for
the pre-flight check that round-1 review retired; the fix landed in its caller instead.

Tests:

- `tests/setup_env/macos.bats`
- `tests/setup_env/linux_shared.bats`
- `tests/setup_env/workflows.bats`
- `tests/setup_env/install_guards.bats`
- `tests/scripts/` — a case for `push-bash-coverage.sh` refusing to publish after a
  failed measurement. The mock must not reach the real script: assert that with the
  child mocked to exit non-zero, the parent exits non-zero and performs no `git push`.
  Per `tdd.md` pitfall E2, the failing branch of this test must not be able to touch the
  real `coverage-data` branch — redirect `HOME` and the repo root to fixtures at
  `setup()` scope so a regressed parent dies at an earlier guard rather than pushing.

## Backlog rows closed by this spec

Four rows move out of `docs/superpowers/README.md`'s backlog when this lands:

- `install_zsh_macos` reports a brew failure as success
- `install_bats` dispatcher returns 0 when no platform matches
- `push-bash-coverage.sh` misreports a missing bats as a red suite — closed by item 5,
  though not as the row describes it. The misreport is real but sits on a path the
  Makefile already guards; the live defect on that path is the discarded child exit code.
  The replacement row's reasoning is recorded in item 5 so the correction is not lost.
- gnubin prefix pair is duplicated across two languages with only a comment binding them

## Follow-ups this spec does not fix

- **The `push-bash-coverage` cron entry is dead and redundant.** 78 runs, zero successes,
  all blocked by the Makefile's bats guard under a PATH lacking `/opt/homebrew/bin`. CI
  has been publishing the badge on every PR throughout. Deleting the crontab line is an
  operator action on a machine-local file; no repo change makes it correct.
- **`wsl2_workstation` may be wrongly declared snap-less** in `config/profiles.sh`. The
  declaration predates WSL2's systemd support. Item 3's `HAS_SNAP` gate is correct either
  way; if `command -v snap && sudo snap refresh` succeeds on the cruncher, the follow-up
  is a `PROFILE_CAPS` correction.

Two further rows are stale and were already fixed by earlier work; they should be
deleted from the backlog in the same commit:

- `make lint` cannot see the extensionless hooks — closed by the `git ls-files`-derived
  `SHELL_FILES` at `Makefile:14`, which includes `scripts/pre-push` and
  `scripts/commit-msg`.
- Coverage denominator: heredoc bodies still inflate it — closed by the heredoc
  exclusion at `scripts/run-bash-coverage.sh:212`, which handles `<<` and `<<-` in any
  quoting for any interpreter.

## Multi-Lens Review

Reviewed at commit: `5ff3cdbc328915d275fa5b114b6e50dde869880e` (Step 7 self-review commit,
before Step 8 dispatch)

Round 1. Every command cited by a lens below was independently re-run by the main
session before the finding was recorded; where the main session's re-run went further
than the lens claimed, that extension is marked.

### Goal-Fit

Finding: Two of the six items change no production outcome, and the strongest item is
buried under them.

Item 2's git half is unreachable. `install_git || return 1` sits inside
`if [[ -n ${MACOS} ]]` at `lib/workflows.sh:125`, and `install_git_linux` has no other
production caller. The spec's framing — "cannot fire on Linux" — is true but understates
it: the call never happens on Linux at all, so neither the added guard nor the
`dist-upgrade` deletion changes any decision there. `install_zsh_linux` by contrast is
live (`workflows.sh:133`, gated `[[ ${MACOS} || ${UBUNTU} ]]`), and its unrequested
non-interactive `apt dist-upgrade -y` on every `setup_user` is the highest-value change
in the document — presented as a footnote to an error-handling cluster rather than as
the scope defect it is.

Item 5 targets a path that is already guarded. The spec asserts the Makefile's
`$(error $(BATS_MISSING))` guards do not cover the cron path because
`push-bash-coverage.sh` invokes the coverage script directly. The crontab entry is
`make push-bash-coverage`, and `Makefile:114-118` carries the guard. Verified: 78 lines
in `~/.dotfiles-coverage.log`, all of them that guard firing, zero successful runs ever;
`BATS := $(shell command -v bats)` evaluates under cron's PATH, which lacks
`/opt/homebrew/bin`. The proposed pre-flight uses the identical probe inside the script
and would fail identically, on a path cron never reaches.

Main-session extension: every commit on `origin/coverage-data` since inception is
`github-actions[bot]`, and `ci.yml:167-178` pushes the badge on every PR. The badge is
current. The cron entry is therefore both dead and redundant with CI.

Assumption: that `update_snap_packages` returning non-zero on a snap-less host is
acceptable. `sudo snap refresh` at `lib/linux_shared.sh:38` has no `HAS_SNAP` guard and
the caller gates on `[[ -n ${LINUX} ]]` only, so the split plausibly makes the snap row
permanently red on the WSL2 box. Settles with `command -v snap && sudo snap refresh;
echo rc=$?` run on the cruncher.

Disposition: **Addressed.** The Problem section no longer trades on "cannot fire on
Linux" — it states that `install_git_linux` is unreachable and that `install_zsh_linux`
is the live one, and keeps the git changes as declared dead-code hygiene with no claimed
benefit. Item 5 was rescoped wholesale; see the Risk disposition. The snap assumption was
addressed under Ergonomics.

### Ergonomics

Finding: The update split turns the snap row permanently red on every Linux machine
whose profile lacks `snap`, and the repo's own capability model says two profiles do.

`sudo snap refresh` at `lib/linux_shared.sh:38` is the only ungated snap call in the
repo — the six others in `lib/linux_ubuntu.sh` (39, 177, 379, 401, 413, 421) all test
`HAS_SNAP`. `PROFILE_CAPS` omits snap from both `wsl2_workstation` and `server`. Today
the omission is harmless precisely because of the bug this spec fixes: the trailing
`log_info` swallows the failure. After the split, `-t update` on the cruncher prints
`[FAIL] snap` on every run, forever, over a subsystem that does not exist there — the
same anti-pattern item 3's own rationale argues against, reintroduced through the gate
rather than the exit code. The fix is one conditional using machinery already present:
`_update_skip "snap" "not applicable"` under `[[ -n ${HAS_SNAP} ]]`, matching the
non-Linux arm two lines below.

Second finding: `install_zsh_linux` has no already-installed guard, so the newly-fatal
`apt install` runs on every `setup_user`. `install_bats_linux:24` opens with
`quiet_which bats && return 0`; `install_zsh_linux:14` and `install_git_linux:4` do not.
`run_setup_user` calls `install_zsh || return 1` at `workflows.sh:133`, before
`clone_or_update_dotfiles`, `setup_ai_config`, and `setup_dotfile_symlinks`. A transient
`apt install zsh zsh-doc` failure — a dpkg lock held by `unattended-upgrades`, the normal
state of a freshly-booted Ubuntu box — now aborts the entire run having done nothing,
over a package that was already installed. The spec's tiering weighs this trade for
`apt update` and `add-apt-repository` and gets it right; it never asks whether the
install step needs to run at all.

Assumption: that `sudo snap refresh` actually exits non-zero on the snap-less profiles —
i.e. that `PROFILE_CAPS` reflects a live fact rather than a stale declaration.
`wsl2_workstation` was declared snap-less on the reasoning that snap is unavailable in
WSL2, which was true before WSL2 supported systemd; Ubuntu 24.04 under systemd-enabled
WSL2 runs snapd. Settles with `command -v snap && sudo snap refresh; echo rc=$?` on the
cruncher. `server` stands regardless.

Disposition: **Addressed.** Both findings. Item 3's caller now gates on `[[ -n ${HAS_SNAP} ]]`
with `_update_skip "snap" "not applicable"` on the else arm, and the Testing section gains
a capability-gate case covering both branches. Item 2 gains the `quiet_which` guard on
both Linux install functions, with the rationale stated as a precondition of making the
install step fatal rather than as a separate improvement. The gate does not wait on the
cruncher measurement: it is correct for `server` regardless, and the possible
`PROFILE_CAPS` staleness is recorded as a follow-up.

### Risk

Finding: Item 5 adds a fifth `exit 1` into a caller that discards all of them, while the
real defect on that path — a stale badge republished after a failed measurement — goes
unaddressed.

`scripts/push-bash-coverage.sh:25` invokes the coverage script **unchecked**, then line
26 reads `coverage/bash.json`. `run-bash-coverage.sh`'s cleanup at lines 707 and 746
clears `TRACE_FILE` and `TRACE_FIFO` only, never the badge JSON. So a stale badge
survives every failed run: the script prints its error, exits non-zero, and the caller
proceeds to read, commit and push the previous run's figure at exit 0. Seven `exit 1`
sites already exist in `run-bash-coverage.sh` (105, 493, 602, 757, 761, 788, 805),
including the red-suite check and two untrustworthy-denominator paths; the caller
discards every one. The spec adds an eighth under the claim that it "exits non-zero so a
scheduled run alerts rather than silently doing nothing." That is `behavior.md`'s
guard-whose-verdict-arrives-too-late: the verdict is real, and nothing reads it.

This also inverts the cron finding above. Fixing the cron PATH without fixing the
unchecked child would not restore the badge job — it would ship a badge that lies, on a
schedule. The one-line fix is `|| exit 1` on the child in `push-bash-coverage.sh`, plus
removing the badge before the run so a stale file cannot be mistaken for a fresh one.

Second finding, testing gap: item 3 claims two improvements from deleting
`cp err_apt err_snap` — snap gets its own captured output, and per-section timing
becomes accurate — and the Testing section pins neither. Implement the split with
`err_snap` written empty and every listed acceptance criterion still passes. One case
should assert `err_snap` contains snap output and not apt's.

Explicitly not raised: the `dist-upgrade` deletion (the spec names its own risk, `apt
install` resolves its own deps, and the operation remains available via `-t update` —
recoverable, not one-way); `check_and_install_nala` under `|| return 1`, which returns 0
on the non-Ubuntu fall-through and so introduces no new abort; the dispatcher `else`
arms, unreachable as stated.

Assumption: that a bare `bash scripts/push-bash-coverage.sh` bypassing `make` is an
invocation path that actually runs somewhere on the fleet. Item 5 exists only to cover
it. Settles with `crontab -l` on the Linux 7950X and the three work Macs, plus
`grep -rn 'push-bash-coverage' .github/`.

Disposition: **Addressed.** Both findings, and the assumption is answered rather than
carried: no bare invocation path exists that the pre-flight would have served, so item 5
is rescoped away from `run-bash-coverage.sh` entirely. The fix is now `rm -f` on the badge
plus `|| exit 1` on the child in `push-bash-coverage.sh`, and the false premise is
recorded in the item rather than quietly deleted. The testing gap is closed by the
`err_snap` content case; the sibling timing claim is explicitly left unpinned with its
reason, rather than pinned by a flaky wall-clock assertion.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison design, no judge or evaluator component, and its acceptance
criteria are concrete commands with numeric thresholds.

### Verdict-count check

All three lenses ran it. Acceptance is three PASS-shaped comparisons (`make test` green,
`make lint` exit 0, coverage at or above 91 percent) plus the per-guard mutation-revert
check, which is a genuine falsifier. The gnubin case's two non-empty assertions are
correctly load-bearing. Two lenses judged the suite not PASS-dominated in the
pathological sense; the Risk lens identified the one real gap, recorded above as its
second finding — the `err_snap` content claim that no criterion pins.
