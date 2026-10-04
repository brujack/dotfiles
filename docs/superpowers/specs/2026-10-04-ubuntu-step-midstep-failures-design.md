# Ubuntu install steps report mid-step failures

- **Status:** Draft
- **Backlog row:** "`_install_ubuntu_*` steps swallow mid-step failures" (P2, bugs and security)

## Problem

`install_ubuntu_packages` (`lib/linux_ubuntu.sh:12`) runs thirteen steps after the base
packages, names the failed ones on stderr and returns 2 when any failed (#298). That
contract is only as good as each step's own return status, and most steps do not have one.

The backlog row says a step "reports only its LAST command's status". Reading the code shows
four distinct shapes. The first is worse than the row describes.

1. **Steps that cannot fail at all.** `_install_ubuntu_docker`, `_install_ubuntu_hashicorp`
   and `_install_ubuntu_cloud_tools` end in an `if [[ -x $(command -v X) ]]; then printf …; fi`.
   An `if` with no true branch returns 0. Measured:
   `bash -c 'f(){ if [[ -x /nonexistent ]]; then echo y; fi; }; f; echo $?'` prints `0`.
   So a docker install where every `apt install` failed returns 0. The dispatcher's
   "skip nvidia because docker failed" guard (`:23`) fires only on docker's one checked
   path, a `daemon.json` that fails `dockerd --validate`, and never for a failed install. It exists to
   stop nvidia rewriting `daemon.json` and restarting docker on a box running live CI runners.
   `_install_ubuntu_k8s_tools` without `HAS_SNAP` and `_install_ubuntu_misc` end the same way
   (a skipped `if`, or an unchecked `nala autoremove`).
2. **Unchecked mid-step commands that then act on their output.** `wget -O <file>` truncates
   its target before it fails. Measured: a file holding `old`, then `wget -O` against a closed
   port, gives rc 4 and 0 bytes. The following `sudo cp -a <file> /usr/local/bin/` still runs.
   telepresence is re-downloaded on every run (`:497`, no existence guard), so one failed
   fetch overwrites a working `/usr/local/bin/telepresence` with an empty file and reports success.
   kind, consul, vault, nomad, packer, vagrant, cf-terraforming, docker-compose and yq have the
   same shape. Their existence guard limits it to the first run, or to a run after a version
   bump.
3. **Pipelines judged by their last element.** `curl … | sudo gpg --dearmor -o <keyring>`
   (k8s, cloud_tools ×3, gui_tools, misc) reports gpg's status, never curl's. Measured on gpg
   2.4.8: empty input exits 2, so a fetch that returned nothing is caught by accident. A fetch
   that returned a partial body is not: `CLAUDE.md` (edge-source bullet) records
   gpg 2.5 exiting 0 on a truncated key. The same holds for `wget -O- … | sudo gpg`
   (VirtualBox).
4. **Deliberate success over failure.** `_install_ubuntu_powershell` warns and `return 0`s
   on every failure (`:191-218`). Its comment gives the reason: "the dispatcher calls this
   function with `|| return 1`". That stopped being true in #298, so the reason no longer holds.
   `_install_ubuntu_base_packages` returns 0 after unchecked installs (`:58-62`) for the same
   historical reason.

Steps that already check every command, and are out of scope: `_install_ubuntu_rust`,
`_install_ubuntu_nvidia`, `_install_ubuntu_brew_packages` (tri-state) and
`_install_ubuntu_albert`.

## Design

### Unit of failure: the sub-install

A **sub-install** is one tool inside a step: kind, telepresence and kubectl inside k8s_tools;
each HashiCorp product; teleport, cloudflared, gcloud and cf-terraforming inside cloud_tools.
The full list is in the table below.

- **Inside a sub-install, fail fast.** The first failed command stops that sub-install
  before any later command runs. In particular, a failed download stops before the `cp`,
  `mv`, `install` or `unzip` that would consume it.
- **A failed download or extract removes what it left behind.** `wget -O` leaves a 0-byte
  file on failure, and the go, kind, consul, vault, nomad, packer, vagrant, cf-terraforming,
  docker-compose and yq sub-installs skip the download whenever that file (or the extracted
  directory) exists. Without cleanup, fail-fast turns one network blip into a failure no
  re-run can clear. So the failing branch deletes the partial download and any partial
  extraction directory before returning.
- **Across sub-installs, degrade.** A failed sub-install does not stop its siblings. One dead
  release URL must not cost kubectl, just as one failed step no longer costs the next step.
  This costs a per-URL mock knob and a sibling assertion per test, and it is worth paying: a
  re-run recovers only if the operator notices the failure, and a fail-the-step design would
  re-create inside a step the coupling #298 removed between steps.
- **Name each failure.** A failed sub-install logs
  `log_warn "<step>: <tool>: <action> failed"`. `<action>` is the command that failed, e.g.
  `download`, `extract`, `install`, `apt install docker-ce`.
- **Step status.** A step returns 0 only when every sub-install it attempted succeeded.
  Otherwise it returns 1. The dispatcher already treats any non-zero step status as a failed
  step.

The idiom is a step-local `_failed` array with one function or block per sub-install. Each
sub-install chains its commands with `|| { log_warn …; return 1; }` inside its own function,
or uses a `|| _failed+=(…)` guard. This mirrors `_install_ubuntu_brew_packages`, the only step
that already has the shape. The step ends with an explicit
`(( ${#_failed[@]} == 0 ))`, so no step can end on a skipped `if` again.

Where a sub-install already has a per-tool download/verify/install helper
(`_install_pinned_release_binary`, `_install_go_from_tarball`), the fix lands in the helper.
Where several sub-installs share the identical wget → cp → chmod → chown shape (kind,
telepresence, docker-compose, yq, and the five HashiCorp zips), one local helper replaces the
copies. The second shape is one helper with an unzip stage. This is permitted, not mandatory:
the plan decides whether the duplication justifies it.

### Rules

- **`apt update` failure is a warning, not a sub-install failure.** One unreachable or
  unsigned third-party source makes `apt update` exit non-zero for every caller (asserted from
  apt's documented behaviour, not measured here; V3 measures it). Nine steps call it (base, go,
  docker, k8s_tools, cloud_tools, gui_tools, misc, powershell, nvidia), so checking it as a
  failure would fail most of them for one cause and name the wrong ones. The
  `apt install` that follows is the check for that sub-install's own package: it fails when a
  newly added source left the package unreachable. **Only base warns.** Base's `apt update`
  runs first, and apt's own `E:`/`W:` lines, already on the terminal, name the broken
  source; base adds one `log_warn "base: apt update reported errors (see apt's E:/W: lines
above); continuing"`. Every later `apt update` is `|| :` with a comment pointing at base, so a
  permanently broken source produces one warning per run, not eight. Exception:
  `_install_ubuntu_powershell` keeps checking `apt update` as a failure, because there it
  directly follows adding the Microsoft source, and its existing tests pin that.
- **Every pipeline element is checked.** A pipeline whose producer can fail (`curl`, `wget
-O-`) copies `${PIPESTATUS[@]}` immediately after the pipeline, with no command between,
  not even a `local` declaration (a `local` resets `PIPESTATUS`, measured), or
  is split into a fetch to a temp file followed by the consumer. `printf … | sudo tee` needs
  only the last element checked, since `printf`/`echo` of a literal cannot fail.
- **Advisory commands stay advisory**, unchanged: cleanup (`sudo rm -f … || true`), the
  "X is installed" probes, `brew trust`, the existing warn-and-skip on dotnet, tflint, tfsec
  and tfenv, and `nala autoremove` (cleanup; it gains a `log_warn` on failure, not a failed
  status).
- **`_install_ubuntu_powershell` returns 1 on failure.** Every `log_warn …; return 0` becomes
  `return 1`. The stale dispatcher comment is deleted.
- **Base packages become tri-state.** `_install_ubuntu_base_packages` returns 1 for an
  unsupported release, exactly as today, and that still aborts `install_ubuntu_packages` with
  rc 1. It returns 2 when any install in it failed. The dispatcher records `base` as a failed
  step and runs every later step. This is the brew_packages convention: rc 2 means partial.
  The dispatcher's `_install_ubuntu_base_packages || return 1` changes accordingly.
- **The nvidia skip fires on a docker core failure only.** The skip exists because, if
  `docker-ce` is absent, `nvidia-ctk runtime configure` creates `daemon.json` first and
  docker's `[[ ! -f daemon.json ]]` guard then never writes the cgroup `exec-opts`; and it
  stops a restart of a docker whose config the docker step rejected. A failed buildx or
  compose plugin, keyring refresh with docker already installed, or `usermod` endangers
  neither. So `_install_ubuntu_docker` returns **3** when an `apt install` of `docker-ce`,
  `docker-ce-cli` or `containerd.io` failed, or `daemon.json` failed validation, and **1** for
  any other failed sub-install. The dispatcher records docker as failed for any non-zero
  status, and skips nvidia only on 3. A docker keyring or source failure with `docker-ce`
  already installed is rc 1; with `docker-ce` absent, the core `apt install` that follows
  fails and makes it rc 3.
- **Go's version check compares the series, not the patch.** `GO_VER="1.27"` while the
  installed toolchain reports `go1.27.1`; the current `==` comparison at `:266` has never
  matched on any machine running the pinned tarball. The check becomes
  `[[ ${INSTALLED_GO_VER} == "${GO_VER}" || ${INSTALLED_GO_VER} == "${GO_VER}".* ]]`, so `1.27`
  and `1.27.1` pass and `1.270` does not; a mismatch after install is a go failure.
- **Go replaces `/usr/local/go` by moving, not deleting first.** `_install_go_from_tarball`
  runs `sudo rm -rf /usr/local/go` before an unchecked `sudo mv` (`:241-243`), so a failed
  move leaves no Go at all. It becomes: move the old tree to `/usr/local/go.old`, move the new
  tree in, and on failure move `go.old` back; delete `go.old` only after the new tree is in
  place.

### Sub-install inventory

| step        | sub-installs                                                                                                           |
| ----------- | ---------------------------------------------------------------------------------------------------------------------- |
| base        | hwe kernel, `check_and_install_nala`, common list, release list                                                        |
| workstation | nala list, snap list                                                                                                   |
| powershell  | (one sub-install; return 0 becomes 1)                                                                                  |
| go          | apt update (silent), tarball download, extract, move into `/usr/local/go` (move-aside), version check by series        |
| docker      | keyring, source, core (`docker-ce`, `docker-ce-cli`, `containerd.io`, `daemon.json`) → rc 3; plugins, `usermod` → rc 1 |
| k8s_tools   | kind, telepresence, kubectl (key, source, install), helm snap                                                          |
| hashicorp   | consul, vault, nomad, packer, vagrant                                                                                  |
| cloud_tools | teleport, cloudflared, gcloud, cf-terraforming; azure cleanup stays advisory                                           |
| gui_tools   | virtualbox, edge (source helper, install), snaps (each `snap install`, `snap set`), steam; albert unchanged            |
| misc        | docker-compose, yq, opentofu; dotnet/tflint/tfsec/tfenv unchanged; autoremove advisory                                 |

`_install_ubuntu_edge_source`'s own status is currently ignored by gui_tools. It becomes part
of the edge sub-install.

## Error handling

The changes add failure reporting, stop consuming bad artifacts, and clean up partial
downloads. On a clean run every step still returns 0. The success path gains only the
`PIPESTATUS` reads and, when a new Go tarball is installed, the move-aside of the old tree and
its deletion afterwards.

A run that previously reported success over a broken install now returns rc 2 from
`install_ubuntu_packages` and prints `ubuntu packages: failed: …`. `run_setup_or_developer`
already warns and continues on rc 2 (`lib/workflows.sh:514-518`), so `-t developer` still
exits 0 and still runs pyenv, ansible, cargo and aws. The only rc that aborts is base's rc 1,
unchanged.

## Testing

Tests go in `tests/setup_env/linux_ubuntu.bats`, which already has 204 tests and per-step
fixtures. Existing whole-binary knobs: `MOCK_WGET_EXIT`, `MOCK_CURL_EXIT`, `MOCK_APT_EXIT`,
`MOCK_NALA_EXIT`, `MOCK_UNZIP_EXIT`, `MOCK_TAR_EXIT`, `MOCK_SNAP_EXIT`, `MOCK_CP_EXIT`.
`MOCK_APT_ONLY_EXIT` is **not** subcommand-scoped: `tests/mocks/apt` exits with it for every
call. `tests/mocks/cp` passes through with `|| true`, so a copy-stage failure is driven only
by `MOCK_CP_EXIT`.

Two new mock knobs, each with its own mock test:

- `MOCK_WGET_FAIL_URL` (and `MOCK_CURL_FAIL_URL`): fail only a call whose argv contains the
  substring, like `tests/mocks/claude`'s `MOCK_CLAUDE_FAIL_ARGS`. A shared `MOCK_WGET_EXIT`
  fails every sibling at once and cannot show R3.
- `MOCK_APT_FAIL_SUBCMD` (and the same for `apt-get`, `nala`): fail only when the first
  non-option argument equals the value, e.g. `update` or `install`, so the two branches of
  the `apt update` rule are drivable separately.

For each sub-install, one failure test asserts five things:

1. the step's status is non-zero (3 for docker's core, 1 otherwise);
2. stderr names the step and the tool;
3. **positive control:** `MOCK_CALLS_FILE` holds the failing call for that tool (its URL, or
   its package name), so the sub-install demonstrably started;
4. the consuming command never ran (no `cp`/`unzip`/`mv` for that tool), and the partial
   download file is gone;
5. a sibling sub-install in the same step still ran.

Item 5 is what separates design B from a bare `|| return 1`. Item 4 is the destructive-path
guard (`tdd.md` E2); item 3 is what keeps item 4 from passing when the sub-install never ran
(`tdd.md` E5).

Additional cases:

- **apt update, both branches.** With `MOCK_APT_FAIL_SUBCMD=update`, base stays 0 and prints
  its one warning, and a later step stays 0 and prints nothing about `apt update`. With
  `MOCK_APT_FAIL_SUBCMD=install`, the step is non-zero.
- **Partial download is retried.** A failed go download leaves no tarball, so a second call
  with the network knob cleared downloads again (`MOCK_CALLS_FILE` holds two `wget`s).
- **Go version, real strings.** With `_GO_BIN` pointing at a stub that prints
  `go version go1.27.1 linux/amd64` and `GO_VER=1.27`, the go step returns 0; with the stub
  printing `go1.26.3`, it returns non-zero. Every go test sets `_GO_BIN`, so none reads the
  machine's real `go` (`tdd.md` pitfall G).
- **Go move-aside.** With the move of the new tree failing, `/usr/local/go`'s old contents
  are restored (the test points the install root at a fixture via a new
  `_GO_INSTALL_ROOT` seam).
- **Pipeline producer.** curl fails while gpg succeeds, and the sub-install is still reported
  failed. Without the `PIPESTATUS` check this test passes only when gpg happens to reject
  empty input, so the mock gpg must succeed on empty input to make the case discriminate.
- **Dispatcher, both branches.** With `apt install docker-ce` failing for real (not a stubbed
  `_install_ubuntu_docker`), nvidia is skipped and both are named. With only
  `docker-buildx-plugin` failing, docker is named failed and nvidia still runs.
- **Base rc 2.** A failed common-list install records `base` and later steps still run.
  Unsupported release still returns 1 and runs nothing else.
- **Clean run, discriminating.** A new dispatcher-level test runs every step with all mocks
  succeeding and with each step's install probe satisfied (`_GO_BIN` printing the real
  `go1.27.1` string, docker/kind/etc. resolvable), and asserts both rc 0 **and** that
  `MOCK_CALLS_FILE` holds each step's core install call. The second half stops it passing when
  every step does nothing. Existing tests that asserted the old return-0-on-failure behaviour,
  e.g. powershell's, change with this PR.

Every new check gets a mutation control: delete the check and confirm its test goes red.

## Requirements

- **R1.** `[PR1]` Each of `_install_ubuntu_docker`, `_install_ubuntu_k8s_tools`, `_install_ubuntu_hashicorp`, `_install_ubuntu_cloud_tools`, `_install_ubuntu_gui_tools`, `_install_ubuntu_misc`, `_install_ubuntu_workstation` and `_install_ubuntu_go` returns non-zero when any sub-install it attempted failed, and 0 only when all attempted sub-installs succeeded.
- **R2.** `[PR1]` A failed download, extract, key fetch or source write stops its sub-install before any command that consumes the artifact runs, and removes the partial download file and partial extraction directory it left.
- **R3.** `[PR1]` A failed sub-install does not prevent sibling sub-installs in the same step from running.
- **R4.** `[PR1]` Each failed sub-install is named on stderr with its step and tool.
- **R5.** `[PR1]` A pipeline whose producer is `curl` or `wget` reports the producer's failure even when the last element succeeds.
- **R6.** `[PR1]` An `apt update` failure does not by itself fail a step, except in `_install_ubuntu_powershell`; base's logs exactly one warning, and no other step's logs one.
- **R7.** `[PR1]` `_install_ubuntu_powershell` returns 1 on every failure path it currently returns 0 from.
- **R8.** `[PR1]` `_install_ubuntu_base_packages` returns 1 for an unsupported release and 2 when any of its installs failed; `install_ubuntu_packages` returns 1 for the former and records `base` as a failed step and continues for the latter.
- **R9.** `[PR1]` `_install_ubuntu_docker` returns 3 when an `apt install` of `docker-ce`, `docker-ce-cli` or `containerd.io` failed or `daemon.json` failed validation, and 1 for any other failed sub-install; `install_ubuntu_packages` skips nvidia only when docker returned 3.
- **R10.** `[PR1]` A run where every command succeeds returns 0 from every step, and each step's core install call is made.
- **R11.** `[PR1]` The go step accepts an installed version equal to `GO_VER` or beginning with `GO_VER.`, and fails on any other version after install.
- **R12.** `[PR1]` `_install_go_from_tarball` never leaves `/usr/local/go` absent when it was present before: the old tree is moved aside, restored if the new tree's move fails, and deleted only after the new tree is in place.
- **V1.** Every new check has a mutation control: removing it turns its test red. Record each removal and the red test name in the PR body.
- **V2.** `make test` passes on the Linux development box and in CI.
- **V3.** On a Linux box, add a source pointing at an unreachable host to a scratch sources directory and run `apt update` with `-o Dir::Etc::sourcelist` scoped to it; record its exit code. If it exits 0, R6's rationale is moot but the rule stays harmless. Then, with a scoped source for an already-installed package pointing at the unreachable host, run `apt install -y <package>` and record its exit code; an rc 0 ("already the newest version") is correct behaviour under R6, since the package is installed and base's warning reports the dead source.
- **N1.** No change to `_install_ubuntu_rust`, `_install_ubuntu_nvidia`, `_install_ubuntu_brew_packages` or `_install_ubuntu_albert`.
- **N2.** No `set -e`, `set -o pipefail` or ERR/EXIT trap is introduced.
- **N3.** No change to `run_setup_or_developer`'s handling of `install_ubuntu_packages`' return codes.
- **N4.** Cleanup commands and "is installed" probes do not become failures.

## Multi-Lens Review

Reviewed at commit: `4a11dcb3` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building; premise verified (docker ends on a no-true-branch `if`, rc 0; `wget -O` truncates to 0 bytes; telepresence has no existence guard). Reads-it test: R2 changes behaviour (a working binary is no longer clobbered) and is the highest-value part; R4's stderr naming and rc 2 change no decision, since `run_setup_or_developer` warns and `-t developer` exits 0, and nothing persists past scrollback. R9 widens blast radius: under R1 any docker sub-install failure (buildx plugin, `usermod`) skips the NVIDIA driver install on a GPU box, though only `docker-ce`/containerd/`daemon.json` failure endangers what the guard protects. R3 plus a per-URL mock knob plus four assertions per ~30 sub-installs is the expensive part and is assumed, not argued, on a re-runnable installer. Test item 3 ("consumer never ran") is an absence assertion (tdd.md E5) needing a positive control; the clean-run case names no test that discriminates, since existing rc-0 tests predate any step being able to fail.
Assumption: A step-level docker failure is the right trigger for skipping nvidia. Settled by asking the operator whether a failed buildx plugin or `usermod` should withhold the NVIDIA driver, and by tracing whether `daemon.json` is at risk with `docker-ce` installed but a plugin failed.
Disposition: Addressed — R9 narrowed: docker returns 3 for a core failure (`docker-ce`, `docker-ce-cli`, `containerd.io`, `daemon.json`) and 1 otherwise; nvidia is skipped only on 3. R3's cost is now argued in the Design. Test item 3 gained a positive control, and the clean-run test is now a named, discriminating dispatcher test (R10 reworded). Operator, 2026-10-04: "1-6 addresed".

### Ergonomics

Finding: (1) Blocker: the go version clause fails every run. `GO_VER="1.27"` (`constants.sh:36`), tarball `go1.27.1`, `/usr/local/go/bin/go version` prints `go1.27.1`, compared with `==` at `:266`. Under R1 every setup on claude/workstation reports `failed: go` with Go correctly installed, training the operator to ignore rc 2. (2) Fail-fast without cleanup makes a failure permanent: `wget -O` leaves an empty file and `_install_go_from_tarball`, kind, consul etc. skip the download whenever the file exists, so one blip never clears. R2 must require removing the partial artifact. (3) A permanently broken source yields up to 8 identical `apt update` warnings per run, none naming the source. Checked and not raised: `usermod` (user exists, idempotent), re-install of installed packages exits 0, workstation lists resolve on 26.04.
Assumption: Every newly-checked command exits 0 on a fully provisioned box; the uncertain one is `dnsutils` in `ubuntu_common_packages.txt`, a virtual package on 26.04 (`apt-cache policy dnsutils` → `Candidate: (none)`, verified by the author). apt resolves it; whether nala 0.16.0 does is unknown. If not, base reports rc 2 on every reprovision. Settled by `sudo nala install -y dnsutils; echo $?` on claude.
Disposition: Addressed — go compares the series (R11); R2 now removes the partial download and extraction; only base warns on `apt update` failure, once (R6). Assumption measured by the author on `claude`, 2026-10-04: `sudo nala install -y dnsutils` printed `Selecting bind9-dnsutils Instead of virtual package dnsutils` … `Nothing for Nala to do.`, rc 0, so the common list does not fail on it. Operator: "1-6 addresed", and asked the author to run the nala command.

### Risk

Finding: (1) Same go blocker as Ergonomics, measured independently; tests not setting `_GO_BIN` (set at only two sites) read the real binary and become machine-dependent (pitfall G). (2) Same R9 over-breadth as Goal-Fit; the one real case the skip protects: if `docker-ce` failed, `nvidia-ctk runtime configure` creates `daemon.json` first and docker's `[[ ! -f daemon.json ]]` (`:455`) never writes the cgroup `exec-opts`. Narrow the predicate to docker-ce/containerd or `daemon.json` failure. (3) Mock gaps: `tests/mocks/apt` uses one exit code for every subcommand (`MOCK_APT_ONLY_EXIT` is not subcommand-scoped, verified by the author), so R6's both-branches case needs a new knob; `tests/mocks/cp` passes through with `|| true`, so install-stage failure needs `MOCK_CP_EXIT`. Mock wget models truncation; mock gpg exits 0 on empty input, so the pipeline case discriminates. (4) Positive control needed for test item 3 (same as Goal-Fit); clean run passes if every step does nothing. (5) Destructive path left armed: `_install_go_from_tarball` runs `sudo rm -rf /usr/local/go` before an unchecked `sudo mv` (`:241-243`); move the old tree aside instead. (6) The dispatcher's `|| return 1` at `:13` must change for R8 (wording); PIPESTATUS must be read with no command between, not even `local` (measured). Not over-engineered.
Assumption: `apt install` of an already-installed package exits non-zero when its source is unreachable, making it "the authoritative check". If it exits 0 ("already the newest version"), a dead source on a provisioned box is reported only by the `apt update` warning. Settled by extending V3: with docker-ce installed, point `docker.list` at an unreachable host, run `apt update` then `apt install docker-ce -y`, record both rcs.
Disposition: Addressed — go blocker (R11; every go test sets `_GO_BIN`), R9 narrowed, new subcommand- and URL-scoped mock knobs, positive control, go move-aside instead of `rm -rf` first (R12), dispatcher wording for R8, PIPESTATUS read with nothing between. Assumption folded into V3 as a measurement; either result is consistent with R6. Operator, 2026-10-04: "1-6 addresed".

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
