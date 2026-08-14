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
# New helper in lib/linux_shared.sh. Per-package by construction — see below.
_apt_pkg_installed() {
  dpkg-query -f '${db:Status-Abbrev}' -W "${1}" 2>/dev/null | grep -q '^ii'
}

install_git_linux() {
  if _apt_pkg_installed git; then
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

`install_zsh_linux` takes the same shape, without the PPA step, and its guard must cover
**both** packages, one call each:

```bash
if _apt_pkg_installed zsh && _apt_pkg_installed zsh-doc; then
```

Three decisions are embedded here.

**Why the already-installed guard is not optional once the install step is fatal.**
`install_bats_linux:24` already opens with a guard; `install_git_linux` and
`install_zsh_linux` do not, so today they re-run `apt install` on every provisioning run
and swallow whatever happens. Making the install step fatal without adding a guard
converts that from harmless to breaking: `run_setup_user` calls `install_zsh || return 1`
at `lib/workflows.sh:133`, ahead of `clone_or_update_dotfiles`, `setup_ai_config`, and
`setup_dotfile_symlinks`. A dpkg lock held by `unattended-upgrades` — the ordinary state
of a freshly-booted Ubuntu box, which is exactly what gets provisioned — would then abort
the entire run having done nothing, over a package that was already present. With the
guard, the fatal path fires only when the package is genuinely absent.

**Why the guard queries install state, and why it took three attempts to get there.**
This guard has now been wrong twice, each time as a narrower probe of the wrong thing:
`PATH` presence, then package-database presence, and only now install _state_. The
sequence is recorded because the third answer is not obviously different from the second
by inspection, and a future reader who "simplifies" it back to `dpkg-query -W` will
reintroduce a live defect.

Measured on Ubuntu 24.04, dpkg 1.22.6, against a real `rc`-state package:

```
dpkg-query -W libnvidia-compute-560                          rc=0   <- reports INSTALLED
dpkg-query -f '${db:Status-Abbrev}' -W ... | grep -q '^ii'   rc=1   <- correct
command -v libnvidia-compute-560                             rc=1   <- also correct
dpkg-query -f '${db:Status-Abbrev}\n' -W zsh <rc-pkg> | grep -q '^ii'   rc=0   <- passes wrongly
```

`-W` queries database _presence_, not install state, and both `apt remove` and
`apt autoremove` leave `rc` (config-retained) entries behind by default. So on any box
where `zsh` or `zsh-doc` was ever removed without `--purge`, a `-W` guard logs
"zsh already installed" and returns 0 for a package that is not on the machine — the
exact silent-false-success this spec exists to remove, in the one function it identifies
as live. Note the third line above: that case is one where the rejected `PATH` probe was
_right_ and the replacement was wrong.

The fourth line is why `_apt_pkg_installed` takes one package and is called twice.
`dpkg-query -f ... -W pkg1 pkg2` emits one record per package, so a single `grep -q '^ii'`
succeeds when _either_ is installed — reintroducing the partial-package hole from the
opposite direction. Two calls joined by `&&` is the only form that requires both.

The idiom is not new to this repo: `lib/helpers.sh:195` already uses
`dpkg -l nala 2>/dev/null | grep -q '^ii'` for the same purpose. It was not cited in
either earlier draft, which is the more useful lesson than the dpkg trivia — the correct
form was already in the file being edited.

**The rejected `PATH` probe, kept because its justification was wrong in an instructive
way.** A round-2 draft used `quiet_which zsh`, justified as "the same idiom
`install_bats_linux` and `install_bats_macos` already use." That was wrong in three ways.

- **It probes the wrong number of things.** `install_bats_linux` probes `bats` and
  installs `bats` — one binary, one package, a faithful proxy. `install_zsh_linux`
  installs `zsh` **and** `zsh-doc`. `zsh-doc` ships no binary, so a `PATH` probe cannot
  observe it at all. Since `install_zsh` runs on every Ubuntu `setup_user`, the first
  machine with zsh from any source would never receive `zsh-doc` again, while the
  function logged "zsh already installed" — the precise silent-false-success shape this
  spec exists to remove, reintroduced by its own fix.
- **The macOS functions are not the precedent claimed.** `install_git_macos:98` and
  `install_zsh_macos:117` guard on `brew list | grep '^git$'` / `'^zsh$'` — that is
  package-manager state, not `PATH`. `_apt_pkg_installed` is their actual analogue;
  `brew list` has no `rc`-state equivalent to trip over, which is why the macOS side
  needed no correction.
- **This repo has already paid for the `PATH`-probe mistake once, in a function this
  spec cites twice as a model.** `install_make_macos:158-167` carries a comment
  explaining at length why probing `gmake` on `PATH` was wrong there: a MacPorts or
  hand-built binary satisfies the probe, skips the install, and leaves the real
  requirement unmet — "Reproduced." Proposing a `PATH` probe while citing that function
  as precedent was a self-contradiction inside one document.

The same defect applies on the git side and is worth stating even though the function is
unreachable: `quiet_which git` is true for the distro git, so the `ppa:git-core/ppa`
step — which exists specifically to obtain a _newer_ git than the distro ships — would
never run. `_apt_pkg_installed git` has the same limitation, since it reports whether
git is installed and not _which_ git; that residual is accepted here because the function is dead
code and item 4's dispatcher fix only makes it callable, not called. If a Linux caller is
ever added, the guard needs to become a version comparison, and this paragraph is the
note saying so.

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

if command -v snap > /dev/null 2>&1; then
  _update_record_start "snap"
  update_snap_packages 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_snap"
  _update_record_end "snap" "${PIPESTATUS[0]}"
else
  _update_skip "snap" "snap not installed on this host"
fi
```

**Some gate is required, and it must probe snap itself rather than the profile
declaration.** `sudo snap refresh` at `lib/linux_shared.sh:38` is the only ungated snap
call in the repo — the six others, all in `lib/linux_ubuntu.sh` (lines 39, 177, 379, 401,
413, 421), test `HAS_SNAP`. Today that omission is harmless _precisely because of the bug
this item fixes_: the trailing `log_info` swallows a failing `snap refresh`. Propagating
the exit code with no gate at all would introduce the very defect this item's rationale
argues against one paragraph above — a row going red on every run on a machine where snap
is not installed, blaming a subsystem the operator has no action for. A permanently-red
row stops carrying information the first time it is correctly ignored, which is worse
than the always-green row it replaces.

**Why not `HAS_SNAP`, which a round-2 draft of this spec used.** That gate reads the
manifest rather than the machine, and the manifest does not say what it appears to say:

```bash
PROFILE="${PROFILE_MAP[${hn}]:-unknown}"                     # lib/detect_env.sh:26
for cap in ${PROFILE_CAPS[${PROFILE}]:-}; do ... done        # lib/detect_env.sh:27
```

`PROFILE_CAPS[unknown]` is undefined, so **an unmapped hostname yields zero `HAS_*`
variables**. `PROFILE_MAP` holds seven entries — `laptop studio reception office home-1
workstation cruncher` — so any Ubuntu host not among them gets `HAS_SNAP` unset. Such a
host refreshes snaps today; under a `HAS_SNAP` gate it would silently stop and report
"not applicable", which is a claim the mechanism never measured. `USER.md`'s rule that a
trust signal must carry the confidence its mechanism earned, inverted.

The round-2 draft also justified the gate with "`server` still requires it regardless."
That is false: **no hostname maps to `server`**. It is a profile with no machines, which
is what a profile looks like after its hosts were added and never enrolled.

`command -v snap` measures the machine rather than the manifest. It is correct on an
unmapped host and correct on `server` if one ever appears.

**It does not, however, "settle the `wsl2_workstation` question" — an earlier draft
claimed that and the claim was too strong.** `command -v snap` observes the binary, which
ships with the `snapd` package and can be present while snapd itself is inoperative. On
such a host the gate takes the _present_ branch and the row goes red.

That is accepted rather than fixed, and the distinction is worth stating because it is
the whole basis of the gate: **snap absent is a configuration fact, snap installed but
broken is a fault.** The first should skip silently; the second should be loud. A red row
for a dead snapd is the gate working, not a regression — which is why the probe stays
`command -v snap` rather than becoming a functional check like `snap version`.

The cruncher's actual state remains unmeasured across three review rounds, and is now
recorded as structurally unmeasurable from here rather than as pending: that host is
Windows with WSL2 and accepts no inbound SSH by design. Nothing in this item depends on
the answer. What does depend on it is the follow-up below, since six sites in
`lib/linux_ubuntu.sh` still read `HAS_SNAP` and would be skipping real work if the
profile declaration is stale.

**The skip reason must differ from the non-Linux arm's.** `_update_skip "snap" "not
applicable"` is already emitted for non-Linux hosts eleven lines below. Reusing that
string would collapse two distinct causes — _not a Linux box_ and _Linux without snapd_ —
into one indistinguishable summary line. At 2am on a fresh box over SSH, those need
different answers, so this arm says `"snap not installed on this host"`.

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

**A round-2 draft then proposed hardening that publisher — `rm -f` on the badge plus
`|| exit 1` on the unchecked child. Round-3 review retired that too, on the ground the
evidence above already establishes: the publisher has no live consumer, so a correct
guard inside it changes no outcome.** That draft's diagnosis was accurate —
`scripts/push-bash-coverage.sh:25` does invoke the coverage script unchecked, the cleanup
at lines 707 and 746 clears only `TRACE_FILE`/`TRACE_FIFO`, and a stale
`coverage/bash.json` does survive to be read, committed and pushed at exit 0 while the
child's seven `exit 1` sites (105, 493, 602, 757, 761, 788, 805) are all discarded. The
error was keeping the item's slot and swapping its contents: a correction inherits the
original item's justification, and that justification no longer held once the consumer
was gone.

**What this item does instead: delete the publisher.**

- `scripts/push-bash-coverage.sh` (62 lines)
- `tests/scripts/push_bash_coverage.bats` (256 lines, 11 tests)
- the `push-bash-coverage` Makefile target and its `.PHONY` and `help` entries
- the `CLAUDE.md:332` reference and the ADR-0008 bullet naming it

Measured against the alternative: deletion removes roughly 320 lines and one make target;
hardening adds four lines plus a new bats case to guard a script nothing runs.

The evidence is fleet-wide rather than one-box, because the round-2 disposition wrongly
recorded this assumption as "answered" on a single machine's crontab. Both development
machines have now been checked. The Studio has the entry above and 78 failed runs;
`ssh workstation` reports no coverage cron and no `~/.dotfiles-coverage.log` at all. The
work Macs and the laptop are not development machines and run no provisioning cron. Every
commit on `origin/coverage-data` is `github-actions[bot]`.

Two properties make deletion the safer option rather than merely the smaller one. It
cannot publish a stale badge because it cannot publish. And it removes an existing wart
the current suite already documents — `push_bash_coverage.bats:249`, "does not fail when
the remote push itself fails" — rather than leaving it beside a newly-added guard, which
would read as though the failure modes had been reviewed and that one accepted.

`scripts/run-bash-coverage.sh` is untouched by all of this. `make bash-coverage` still
measures, CI still publishes on every PR, and the README badge is unaffected.

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
- **Partial-package boundary** — `install_zsh_linux` with `zsh` installed but `zsh-doc`
  absent must **still install**. Mock `dpkg-query` to report `ii` for `zsh` and nothing
  for `zsh-doc`; assert `apt install` is invoked.
- **`rc`-state boundary** — `install_zsh_linux` with `zsh` in `rc` (removed, config
  retained) must **still install**. Mock `dpkg-query` to emit `rc` for `zsh`. This is the
  case that discriminates `_apt_pkg_installed` from `dpkg-query -W`, and it is the defect
  that shipped in the round-2 draft, so it needs its own case rather than being folded
  into the one above.

  **`tests/mocks/dpkg-query` cannot express either case as written.** It ignores its
  package arguments entirely and keys off a single global `MOCK_DPKG_QUERY_EXIT`, with
  `-W` printing one static `MOCK_DPKG_OUTPUT`. Both cases require per-package answers, so
  the mock must be extended to dispatch on `${!#}` (the package name) against a
  per-package status map. That extension is part of this work, not a prerequisite
  assumed to exist — no other section lists it.

- **Snap-presence gate** — `-t update` on Linux with `snap` absent from `PATH` produces a
  skipped snap row reading `snap not installed on this host`, does not invoke
  `snap refresh`, and does not record a failure. With `snap` present, the row is recorded
  normally. Both branches are required or the gate is the one-branch guard
  `logic-review.md` item 6 names.

  **The mock must remove `snap` from `PATH` rather than unsetting a variable.** The gate
  probes the machine, so a test that sets a variable is testing a different gate than the
  one shipping — and would pass identically against the `HAS_SNAP` version this spec
  rejected, which is the whole distinction being made.

  Concretely: `tests/mocks/snap` already exists and `load_mocks` prepends `tests/mocks`
  to `PATH`, so `command -v snap` is **true by default** under the harness. The absent
  branch must strip that specific file from `PATH` — the `_clean_path` idiom `shell.md`
  documents for exactly this shadowing problem — not merely decline to set something.

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

`tests/scripts/push_bash_coverage.bats` is **deleted** with the script it covers — 11
cases, none testing behaviour that survives.

**Two further cases live outside that file and must be deleted with it.**
`tests/scripts/unit.bats:665` and `:673` invoke
`bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"` directly to assert its `-h`/`--help`
output. After the deletion they return 127 with no `Usage:` in output — **hard failures,
not a count change**. An earlier draft of this section listed only the dedicated file and
put the arithmetic at 11; it is 13, across two files. Grep for the script name across
`tests/` before deleting, rather than trusting either figure.

## Verification

Baselines, runnable before any implementation:

```bash
make test            # 1294 tests green
make bash-coverage   # 91% against the CI floor
```

Acceptance:

- `make test` green. Test count is **not** required to exceed the baseline: item 5
  deletes 11 cases along with the script they cover, so the net figure could legitimately
  fall. State the arithmetic in the PR — cases added, 13 removed, net — rather than
  asserting a direction. A bare "count went up" would be satisfied by adding twelve
  trivial cases, and a bare "count went down" is not by itself evidence of anything.
- `make lint` exit 0.
- `make bash-coverage` at or above 91 percent. Note the denominator moves in two
  directions here and the net is not predictable from the diff: new error branches add
  coverable lines, while deleting `scripts/push-bash-coverage.sh` removes a file from the
  `git ls-files`-derived instrumented set entirely. Re-derive the figure from a real run
  rather than reasoning about it, and publish it with its denominator per
  `tdd.md`'s Coverage Denominators rule. If the percentage rises, confirm it rose because
  the new branches are covered and not merely because a low-coverage file left the set.
- Each guard's mutation check goes red when the guard is reverted.
- Two named mutation checks for defects that each survived a full review round, listed
  separately from the general one because each shipped in a draft of this document:
  substituting `quiet_which zsh` for `_apt_pkg_installed` must turn the partial-package
  case red, and substituting `dpkg-query -W` must turn the `rc`-state case red.

## Files

Production:

- `lib/macos.sh` — item 1
- `lib/linux_shared.sh` — items 2 and 3
- `lib/helpers.sh` — item 4
- `lib/workflows.sh` — item 3 caller and its `command -v snap` gate

Deleted by item 5:

- `scripts/push-bash-coverage.sh`
- `Makefile` — the `push-bash-coverage` target, its `.PHONY` entry (line 47), and its
  `help` line (line 55)
- `CLAUDE.md:332` — the sentence naming `make push-bash-coverage`
- `docs/adr/0008-bash-coverage-ps4-xtrace.md:31` — the bullet naming the target

`scripts/run-bash-coverage.sh` is **not** touched. It appeared in two earlier drafts of
this file list — first for a pre-flight check, then not at all — and neither belongs. It
keeps working exactly as it does today.

Tests:

- `tests/setup_env/macos.bats`
- `tests/setup_env/linux_shared.bats`
- `tests/setup_env/workflows.bats`
- `tests/setup_env/install_guards.bats`
- `tests/scripts/push_bash_coverage.bats` — **deleted** along with the script it covers.
- `tests/scripts/unit.bats` — two `push-bash-coverage.sh` cases removed (lines 665, 673).
- `tests/mocks/dpkg-query` — extended to answer per-package rather than from one global
  exit variable, so the partial-package and `rc`-state cases can be written at all.

Deleting a script that performs real `git push` also removes the `tdd.md` pitfall E2
hazard an earlier draft had to design around: a test for the hardened publisher would
have needed `HOME` and the repo root redirected at `setup()` scope so its own failing
branch could not push to the live `coverage-data` branch. That hazard disappears with the
script rather than being mitigated.

## Backlog rows closed by this spec

Four rows move out of `docs/superpowers/README.md`'s backlog when this lands:

- `install_zsh_macos` reports a brew failure as success
- `install_bats` dispatcher returns 0 when no platform matches
- `push-bash-coverage.sh` misreports a missing bats as a red suite — closed by item 5,
  but by deleting the script rather than by fixing the misreport. The row's diagnosis was
  correct and its implied remedy was not: the misreport is real, sits on a path the
  Makefile already guards, and belongs to a publisher with no live consumer. Item 5
  records both retired remedies so the reasoning is not lost when someone later asks why
  the script is gone.
- gnubin prefix pair is duplicated across two languages with only a comment binding them

## Follow-ups this spec does not fix

- **The `push-bash-coverage` crontab entry must be removed by the operator.** Item 5
  deletes the Makefile target the entry invokes, so after this lands the nightly job
  fails with `No rule to make target` instead of the bats guard message — a different
  error, equally ignored, in the same unread log. The crontab is machine-local and no
  repo change reaches it. This is the one follow-up with an ordering constraint: it is
  harmless to do at any time, and leaving it undone leaves a nightly job producing noise.
- **`wsl2_workstation` may be wrongly declared snap-less** in `config/profiles.sh`. The
  declaration predates WSL2's systemd support. This no longer affects anything in this
  spec — item 3 gates on `command -v snap`, not on the capability — but the declaration
  is still consulted by six sites in `lib/linux_ubuntu.sh`, so if the cruncher does run
  snapd those are all skipping work they should do.
- **`PROFILE_CAPS[server]` has no hostname mapping.** `PROFILE_MAP` holds seven entries
  and none resolves to `server`. Either hosts using it were never enrolled, or the profile
  is dead. Worth deciding which, because an unmapped host silently receives _zero_
  `HAS_*` capabilities rather than a sensible default — a failure mode that surfaced only
  because a draft of this spec tried to build a gate on top of it.

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

---

## Multi-Lens Review — Round 2

Reviewed at commit: `5bb88a0f842b611838126d4ee36129fb356e138e` (the round-1 revision)

All three lenses re-run, not only the ones whose findings prompted the revision, because
the round-1 corrections changed design substance rather than wording. That was the right
call: **every round-2 finding is a defect the round-1 corrections introduced.** Both new
guards were wrong, and each was wrong in a way the original text was not.

As in round 1, the main session independently re-ran every load-bearing command before
recording a finding.

### Goal-Fit

Finding: Item 5 hardened a script whose own evidence says it should be deleted, and it is
the only item claiming live value it does not have.

The reads-it test on the round-1 `rm -f` + `|| exit 1`: can any outcome differ because
this exists? Only if the dead cron is repaired — which the same document places in
follow-ups-it-does-not-do while calling the entry "dead and redundant." Where is its
output after the session ends? Nowhere. Two no's.

The revision adopted the round-1 patch without re-asking whether the item should exist
once its consumer was shown to be absent. A correction that keeps an item's slot and
swaps its contents inherits the item's original justification, and that justification had
just been invalidated.

Of six items, three change no production outcome. The spec was explicit about two of them
(2-git, 4) and asserting live value for the third.

Assumption: that the Mac Studio's crontab is the only place on the fleet invoking
`push-bash-coverage`. The round-1 disposition recorded this as "answered" on one
machine's evidence while the conclusion covered the fleet.

Disposition: **Addressed.** Item 5 is now a deletion — the script, its 256-line bats
suite, the Makefile target, and two doc references. The boundary error is corrected in
the item itself: `ssh workstation` returns no coverage cron and no log, so both
development machines are now covered rather than one, and the item says which machines
were checked rather than generalising from the Studio.

### Ergonomics

Finding: The round-1 `HAS_SNAP` gate silently disables snap updates on every Ubuntu host
except one, and labels the skip with a string that already means something else.

Simulating `lib/detect_env.sh:26-28` against the real `config/profiles.sh`: `workstation`
is the only hostname resolving to a snap-carrying profile. An unmapped hostname yields
`PROFILE=unknown`, `PROFILE_CAPS[unknown]` is undefined, so it receives **zero**
capabilities — such a host refreshes snaps today and would print `[SKIP] snap not
applicable` after the change. No hostname maps to `server`, so the fallback justification
defended a profile no machine uses. And reusing `"not applicable"` collapses three
distinct causes into one summary line: not Linux, profile declares no snap, host not
enrolled.

Second finding: `quiet_which zsh` is not the predicate for `apt install zsh zsh-doc`. The
guard probes one binary; the contract is two packages, one of which ships no binary.
`zsh-doc` becomes unreachable forever on any box where zsh already exists.

Assumption: that every Ubuntu host which ever runs `-t update` is present in
`PROFILE_MAP`. `USER.md` describes four Raspberry Pi on Ubuntu 24.04 and a Proxmox fleet,
none of them enrolled.

Disposition: **Addressed.** The gate is now `command -v snap`, which probes the machine
instead of the manifest and makes the enrolment assumption moot rather than load-bearing.
The skip reason is distinct: `"snap not installed on this host"`. The guard is now
`dpkg-query -W zsh zsh-doc`, naming both packages.

### Risk

Finding: The `quiet_which` guard silently drops `zsh-doc`, and the precedent cited for it
was wrong in a way the repo has already paid for.

`install_bats_linux` probes one binary and installs one package — a faithful proxy.
`install_zsh_linux` installs two. The macOS guards the spec called equivalent probe
package-manager state (`brew list | grep '^zsh$'` at `lib/macos.sh:98,117`), not `PATH`.
And `install_make_macos:158-167`, cited twice in the same document as a model, carries a
comment explaining precisely why a `PATH` probe was the wrong guard there — "Reproduced."
The spec proposed the shape that function's own comment documents as a defect.

Second finding: the `HAS_SNAP` gate conflates "profile declares snap" with "snap exists",
and the accompanying test case blesses the conflation — it passes identically whether a
host is genuinely snapless or merely unenrolled.

Explicitly not raised, having checked: `rm -f "${BADGE_JSON}"` is recoverable, since
`coverage/` is gitignored and `origin/coverage-data` holds the authoritative badge. The
`dist-upgrade` deletion is sound. The retained `update_system_packages` wrapper keeps an
ungated `update_snap_packages` call alive for tests only.

Assumption: that every Linux host running `-t update` is enrolled in `PROFILE_MAP` **and**
its declared caps match its real snapd state.

Disposition: **Addressed.** Both findings, and the assumption is dissolved rather than
answered — `command -v snap` does not consult `PROFILE_MAP` at all. The guard is
`dpkg-query -W`, and the item now states why the three cited precedents did not support a
`PATH` probe, including the self-contradiction with `install_make_macos`. The Testing
section gains a partial-package case (`zsh` present, `zsh-doc` absent, must still install)
specifically so substituting `quiet_which zsh` back in turns the suite red, and a
snap-presence case whose mock must remove `snap` from `PATH` rather than unset a variable
— a variable-based mock would pass against the rejected gate too.

### Adversarial Spec Review (comparison/judge designs only)

N/A — unchanged from round 1.

### Verdict-count check

All three lenses ran it and reached the same conclusion as round 1: three PASS-shaped
comparisons plus per-guard mutation reverts, which are genuine falsifiers. Two lenses
independently noted that the round-1 `err_snap` case correctly closed one
measurement-versus-comparison gap while the new capability-gate case opened another —
nothing in the suite tied `HAS_SNAP` to `PROFILE_CAPS`, so the one machine that needs a
snap refresh could stop getting one with everything green. Closed by switching the gate to
a machine probe and requiring the test to mock `PATH`.

The acceptance criteria also changed shape here. Item 5's deletion removes 11 cases, so
"test count strictly greater than baseline" is no longer the right assertion and has been
replaced with stated arithmetic. The coverage denominator now moves in both directions —
new branches add coverable lines, a deleted file leaves the instrumented set — so the
criterion requires re-deriving the figure from a real run and confirming any rise is not
merely a low-coverage file exiting the denominator.

---

## Multi-Lens Review — Round 3 (scoped)

Reviewed at commit: `58a5131` (the round-2 revision)

**Scoped deliberately: one lens (Risk), pointed only at the three items the round-2
revision changed** — the install guard, the snap gate, and item 5's conversion to a
deletion. Everything else was independently verified in two prior full rounds and is
unchanged. The lens was told which sections were new and confirmed it re-read the
unchanged items and found nothing further.

Round 3 was run at all because rounds 1 and 2 both found that the previous round's
_corrections_ carried worse defects than the text they replaced. That held a third time.

### Risk (scoped)

Finding 1: `dpkg-query -W` returns 0 for a removed-but-not-purged package, so the round-2
guard was **worse than the `PATH` probe it replaced** on the one live function in the
spec. Measured by the lens on Ubuntu 24.04 / dpkg 1.22.6 and independently re-run by the
main session against a real `rc`-state package (`libnvidia-compute-560`): `dpkg-query -W`
returns 0, `${db:Status-Abbrev}` + `^ii` returns 1, and `command -v` also returns 1 — the
rejected probe was correct for this case. The combined two-package form
`-W pkg1 pkg2 | grep -q '^ii'` also returns 0 with one `ii` and one `rc`, so the guard has
to be per-package.

Finding 2: item 5's deletion breaks `make test` via two cases the Files section did not
list — `tests/scripts/unit.bats:665` and `:673` invoke the script directly. Deletion
arithmetic is 13 across two files, not 11 in one, and those two are hard 127 failures
rather than a count change. The lens enumerated the rest of the blast radius and confirmed
it: `Makefile:47,55,114-118`, `CLAUDE.md:332`, `docs/adr/0008:31`, zero `.github/`
references, and both `SHELL_FILES` and the coverage instrumented set are `git ls-files`-
derived so they self-adjust.

Finding 3: `command -v snap` observes the binary, not snapd, so the item's claim that the
gate "settles the open question about `wsl2_workstation` without needing to answer it" is
stronger than the probe earns.

Two implementation notes: `tests/mocks/dpkg-query` ignores its arguments and keys off one
global exit variable, so neither discriminating case is writable without extending it;
and `tests/mocks/snap` already exists with `tests/mocks` prepended to `PATH`, so
`command -v snap` is true by default under the harness.

Not raised, having checked: the coverage-denominator movement is real but immaterial —
`scripts/push-bash-coverage.sh` is 27 coverable lines of 3415, so full-coverage deletion
moves the overall figure by roughly 0.07 points, well clear of the 91 floor.

Assumption: that no Linux host running `-t update` has the `snap` binary present with
snapd inoperative. Three rounds have now written "settles with `command -v snap && sudo
snap refresh` on the cruncher" and none has run it.

Disposition: **Addressed, findings 1 and 2 as stated; finding 3 narrowly.**

Findings 1 and 2 are accepted in full. The guard becomes a per-package
`_apt_pkg_installed` helper using `${db:Status-Abbrev}` + `^ii`, the three-attempt history
is recorded in item 2 so nobody simplifies it back, the two `unit.bats` cases are added to
the deletion list, the arithmetic is corrected to 13, and both mock limitations are now
listed as work rather than assumed away. Two named mutation checks were added to
Verification, one per shipped-draft defect.

Finding 3 is addressed by **deleting the overreaching claim, not by changing the gate.**
The observation is correct and the implied remedy is not. `command -v snap` distinguishes
the case that should be silent — snap legitimately absent — from the case that should be
loud: snapd installed but broken, which is a genuine fault. A red row there is the gate
working. Switching to a functional probe such as `snap version` would suppress a real
fault to avoid a cosmetic complaint, so the probe stands and the sentence claiming it
settles the WSL2 question is gone.

The assumption is **carried, not answered, and reclassified as unmeasurable from here.**
The cruncher is powered on but runs Windows with WSL2 and accepts no inbound SSH by
design, so `ssh cruncher` is refused as a matter of configuration rather than
availability. Recording it as "pending measurement" a fourth time would be dishonest —
nothing in this session or a future one can reach it without a human at that keyboard.
Nothing in this spec depends on the answer; the follow-up on `PROFILE_CAPS` staleness
does, and says so.

### Stopping here

Round 3's findings sat entirely in text rounds 1 and 2 had not read, so the skill's
stopping signal has still not strictly fired. Stopping anyway, for a reason the signal
does not capture: **the three defect classes this review found are now each pinned by a
named mutation check** rather than by prose. A fourth round would review the round-3
corrections, which are (a) a helper whose failure mode is now covered by two tests that go
red on the exact substitutions that failed before, (b) two lines added to a deletion list
that was verified by enumeration, and (c) a deleted sentence. The residual risk has moved
from the design into the implementation, which is where Phase 2's iterate-until-green loop
and Phase 3's gate chain are the right instruments — not a fourth lens round over the same
883 lines.
