# Ubuntu install steps report mid-step failures

- **Status:** Approved
- **Approved:** 2026-10-04
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
   telepresence is re-downloaded on every run (`:520-524`, no existence guard), so one failed
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

5. **Guards keyed on the download, not the install.** kind, the five HashiCorp tools,
   cf-terraforming, docker-compose, yq and Go skip their whole sub-install when the downloaded
   file or extracted directory exists in `~/software_downloads` (`:235`, `:506`, `:551-600`,
   `:663`, `:1264`, `:1277`). So any failure after the download (the `cp`, the `mv`, a
   `chmod`) leaves an artifact that makes every later run skip the tool and report success,
   with the tool never installed. cf-terraforming extracts with `-C ~/software_downloads`, into
   the directory every other tool's guard lives in.
6. **Keyrings written in place.** `curl … | sudo gpg --dearmor --yes -o <live keyring>`
   (teleport `:616`, cloudflare `:633`) truncates the live keyring even when curl fails:
   measured on gpg 2.4.8, a keyring holding `old` given empty input through
   `--batch --yes --dearmor -o` exits 2 and leaves 0 bytes. docker's `sudo curl -o` writes its
   key straight onto the live file (`:441`). A failed fetch therefore breaks that source for
   every later `apt update` until the step runs clean again.

Steps out of scope: `_install_ubuntu_rust`, `_install_ubuntu_brew_packages` (tri-state) and
`_install_ubuntu_albert` already check every command. `_install_ubuntu_nvidia` checks every
command but has two producer-blind pipelines (`curl | sudo gpg --dearmor`, and
`curl | sed | sudo tee` for its source list); those two lines come into scope and nothing else
in nvidia changes.

## Design

### Unit of failure: the sub-install

A **sub-install** is one tool inside a step: kind, telepresence and kubectl inside k8s_tools;
each HashiCorp product; teleport, cloudflared, gcloud and cf-terraforming inside cloud_tools.
The full list is in the table below.

- **Inside a sub-install, fail fast.** The first failed command stops that sub-install
  before any later command runs.
- **Across sub-installs, degrade.** A failed sub-install does not stop its siblings. One dead
  release URL must not cost kubectl, just as one failed step no longer costs the next step.
  This costs a per-URL mock knob and a sibling assertion per test, and it is worth paying: a
  re-run recovers only if the operator notices the failure, and a fail-the-step design would
  re-create inside a step the coupling #298 removed between steps.
- **Name each failure.** A failed sub-install logs
  `log_warn "<step>: <tool>: <action> failed"`. `<action>` is the stage that failed, e.g.
  `download`, `extract`, `install`, `apt install docker-ce`.
- **Step status.** A step returns 0 only when every sub-install it attempted succeeded,
  otherwise 1 (docker: 3 or 1, below). The step ends with an explicit status, so no step can
  end on a skipped `if` again.

The idiom is a step-local `_failed` array with one function or block per sub-install,
mirroring `_install_ubuntu_brew_packages`.

### Downloaded binaries: fetch into a throwaway directory, install last, stamp on success

Shapes 2 and 5 share one cause: the download is written somewhere persistent, and the guard
reads that artifact. Cleaning up the artifact on each failure path (round 2's revision) has a
failure path of its own at every stage. This design removes the persistent artifact instead.

One helper, `_install_fetched_binary <name> <url> <kind> <member> [<dest-name>]`, replaces the
copies in kind, telepresence, consul, vault, nomad, packer, vagrant, cf-terraforming,
docker-compose and yq. `<kind>` is `bin`, `zip` or `tar`; `<member>` is the path inside the
archive (ignored for `bin`).

1. **Skip guard.** If `${_DL_STAMP_DIR}/<name>` exists, holds exactly `<url>`, and
   `${_DL_BIN_DIR:-/usr/local/bin}/<dest-name>` is executable, return 0 without fetching. `_DL_STAMP_DIR`
   defaults to `~/.local/share/dotfiles/installed`. On a skip it prints
   `<tool>: up to date (stamp <path>); rm it to force a re-install`, so the skip is visible and
   the recovery is named. The URL carries the pinned version for every tool except
   telepresence, so a version bump changes the URL and re-installs.
   telepresence's `TELEPRESENCE_URL` ends in `latest`, which redirects to a versioned URL
   (measured: `…/tel2/linux/amd64/2.20.2/telepresence`). Its `<url>` is therefore resolved first
   with `curl -fsSIL -o /dev/null -w '%{url_effective}'`, and the stamp and skip use the
   resolved URL, so telepresence skips like the other nine and is fetched only when upstream
   publishes a new version. A resolved URL equal to `TELEPRESENCE_URL` itself counts as a
   failed resolution, so an upstream switch from redirect to a direct 200 cannot freeze the
   stamp. If resolution fails while a stamp exists **and** the destination is executable **and**
   non-empty, the helper warns and returns 0 (a network blip on a provisioned box is not a
   failure). Otherwise a failed resolution is a failure: without a stamp, an executable
   destination may be the 0-byte binary a past failed `wget` left.
2. **Fetch** with `wget -O` (the only fetch tool the helper uses; telepresence's resolution is
   the `curl -I` above and is not a fetch) **and extract** into `mktemp -d "${_DL_TMP_ROOT:-${HOME}/software_downloads}/.dl.XXXXXXXX"`.
   Each stage is checked.
3. **Install** with `sudo install -m 0755 <tmp>/<member> ${_DL_BIN_DIR:-/usr/local/bin}/<dest-name>`,
   checked. `install` unlinks the target before writing, so replacing a running binary does not
   fail with "Text file busy" (measured: `cp -a` onto an executing binary gives ETXTBSY, rc 1),
   and nothing is ever written to `/usr/local/bin` before every earlier stage succeeded. No
   `-o root -g root`: real sudo already makes root the owner, and under the test harness
   (`tests/mocks/sudo` execs the real `install` as the user) `-o`/`-g` fails with "cannot
   change ownership", rc 1 (measured). `_install_pinned_release_binary` (`:1126`) omits them for
   the same reason.
4. **Stamp** `<url>` into `${_DL_STAMP_DIR}/<name>` only after the install succeeded. A failed
   stamp write is a `log_warn` naming the stamp path, not a sub-install failure: the tool is
   installed and working, and the only cost is that the next run installs it again.
5. `rm -rf <tmp>` on every path, success and failure, with one explicit call before each
   `return` (no RETURN/EXIT trap; `scripts/check-lib-exit-traps.sh` ratchets them and a
   RETURN trap is not function-scoped).

A failure at any stage before the stamp leaves no stamp, so the next run retries from the fetch. Existing
artifacts in `~/software_downloads` are left alone: nothing reads them any more, and deleting
them is not this change's job.

**First run after merge re-installs every tool once**, because no stamps exist yet. That is
about 450 MB of downloads plus a Go tree swap on each Linux development box, once (measured
from the artifact sizes in `~/software_downloads` on `claude`). The alternative, back-filling stamps
from the old artifacts, would trust exactly the artifacts this change exists to stop trusting.

This helper does not add checksum verification. These ten tools have no sha256 pins today,
and adding them is a separate change (N5). `_install_pinned_release_binary` stays as it is for
tflint and tfsec.

### Go

Go uses the same throwaway-directory and stamp shape, through its own function because it
installs a directory, not a binary:

1. Skip when the stamp `go` holds `GO_DOWNLOAD_URL` and `/usr/local/go/bin/go` is executable.
2. Fetch and extract into a throwaway directory under `_DL_TMP_ROOT`, which defaults to a path
   on the same filesystem as `/usr/local` on both development boxes (measured by the round-2
   risk lens with `df`), so the moves below are renames.
3. Own: `sudo chown -R root:root <tmp>/go`, checked. `tar` runs as the user and a rename keeps
   ownership, so without this `/usr/local/go` becomes a user-writable toolchain under a root path.
   Today both boxes show it `root:root` (measured), set by `sudo chown -R` at `:245`.
4. Swap:
   - If `/usr/local/go` is missing and `/usr/local/go.old` exists, a previous run's restore
     failed and `go.old` may be the only good copy: move it back to `/usr/local/go` first. If
     that move-back fails, the Go sub-install fails at once and nothing touches `go.old`.
   - Otherwise `sudo rm -rf /usr/local/go.old`.
   - If `/usr/local/go` exists, `sudo mv -T /usr/local/go /usr/local/go.old`, and remember that
     this move happened.
   - `sudo mv -T <tmp>/go /usr/local/go`. If it fails and the earlier move happened,
     `sudo mv -T /usr/local/go.old /usr/local/go` restores the old tree. If no earlier move
     happened there is nothing to restore.
   - `-T` stops `mv` nesting the tree inside an existing directory (measured: without it, a
     leftover `go.old` gets the tree nested as `go.old/go`). Delete `go.old` only after the new
     tree is in place.
5. Stamp (a failed stamp write warns, as above), then remove the throwaway directory with
   `sudo rm -rf`, since after step 3 it may hold a root-owned tree.
6. The version postcondition compares the series: `[[ ${v} == "${GO_VER}" || ${v} == "${GO_VER}".* ]]`.
   `GO_VER="1.27"` while the toolchain reports `go1.27.1`; the current `==` at `:266` has never
   matched on any machine running the pinned tarball. A mismatch is a go failure.

`_GO_INSTALL_ROOT` (default `/usr/local`) is a new seam so tests run the swap against a fixture.
The owner is hardcoded `root:root`, with no seam: `tests/mocks/chown` records the call and exits
0 without changing ownership, so tests already run `sudo chown -R root:root` on a fixture, and an
environment-settable owner would let an inherited variable choose who owns `/usr/local/go`.

CLAUDE.md's Test Seams section gains one entry naming the stamp directory, the skip line, and
the recovery (`rm` the stamp).

### Keyrings: fetch to a file, dearmor to a staging path, rename

Shape 6 and the pipeline half of shape 3 share one fix: never point a consumer at the live
keyring. One helper, `_install_apt_keyring <url> <keyring> <armored|binary>`:

1. Fetch with `curl -fsSL -o <tmp>/key` into a throwaway directory. Checked.
2. `armored`: `sudo gpg --batch --yes --dearmor -o <keyring>.new < <tmp>/key`. `binary` (docker's
   `.asc`, which apt reads directly): `sudo install -m 0644 <tmp>/key <keyring>.new`. Checked,
   and the staged file must be non-empty.
3. `sudo mv -f <keyring>.new <keyring>`. Checked; on any failure `sudo rm -f <keyring>.new`.
4. Remove the throwaway directory.

The live keyring changes only by rename, so a failed fetch leaves a working keyring working.
Call sites: docker, kubernetes, teleport, cloudflare, gcloud, VirtualBox, opentofu, nvidia. This
pins no fingerprints; `_build_pinned_keyring` stays the pinned path for edge and albert.

nvidia's source list (`curl | sed | sudo tee`) is fetched to a file first, then `sed`'d and
written with the existing `tee`, each checked. These are the only nvidia changes.

After this, no pipeline in scope has a producer that can fail, so there are no `PIPESTATUS`
reads.

### Rules

- **`apt update` failure is a warning, not a sub-install failure.** One unreachable or
  unsigned third-party source makes `apt update` exit non-zero for every caller (asserted from
  apt's documented behaviour, not measured here; V3 measures it). Checking it as a failure
  would fail most steps for one cause and name the wrong ones. **Only base warns.** Base's
  `apt update` runs first, and apt's own `E:`/`W:` lines, already on the terminal, name the
  broken source; base adds one `log_warn "base: apt update reported errors (see apt's E:/W:
  lines above); continuing"`. Every later `apt update` is `|| :` with a comment pointing at
  base. Exceptions: `_install_ubuntu_powershell` and `_install_ubuntu_nvidia` keep checking
  `apt update` as a failure, because each runs it directly after adding its own source, and
  their existing tests pin that.
- **Advisory commands stay advisory**, unchanged: cleanup (`sudo rm -f … || true`), the
  "X is installed" probes, `brew trust`, the existing warn-and-skip on dotnet, tflint, tfsec
  and tfenv, and `nala autoremove` (it gains a `log_warn` on failure, not a failed status).
- **`_install_ubuntu_powershell` returns 1 on failure.** Every `log_warn …; return 0` becomes
  `return 1`. The stale dispatcher comment is deleted.
- **Base packages become tri-state.** `_install_ubuntu_base_packages` returns 1 for an
  unsupported release, exactly as today, and that still aborts `install_ubuntu_packages` with
  rc 1. It returns 2 when any install in it failed; the dispatcher records `base` as a failed
  step and runs every later step. The dispatcher's `_install_ubuntu_base_packages || return 1`
  changes accordingly.
- **The nvidia skip fires on a docker core failure only.** The skip exists because, if
  `docker-ce` is absent, `nvidia-ctk runtime configure` creates `daemon.json` first and
  docker's `[[ ! -f daemon.json ]]` guard then never writes the cgroup `exec-opts`; and it
  stops a restart of a docker whose config the docker step rejected. A failed buildx or
  compose plugin, keyring refresh with docker already installed, or `usermod` endangers
  neither. So `_install_ubuntu_docker` returns **3** when an `apt install` of `docker-ce`,
  `docker-ce-cli` or `containerd.io` failed, or `daemon.json` failed validation, and **1** for
  any other failed sub-install. The dispatcher records docker as failed for any non-zero
  status and skips nvidia only on 3.

### Sub-install inventory

| step        | sub-installs                                                                                       |
| ----------- | -------------------------------------------------------------------------------------------------- |
| base        | hwe kernel, `check_and_install_nala`, common list, release list                                    |
| workstation | nala list, snap list                                                                               |
| powershell  | (one sub-install; return 0 becomes 1)                                                              |
| go          | Go (throwaway dir, swap, stamp, series check)                                                      |
| docker      | keyring, source, core (`docker-ce`, `docker-ce-cli`, `containerd.io`, `daemon.json`) → rc 3; plugins, `usermod` → rc 1 |
| k8s_tools   | kind, telepresence (helper), kubectl (keyring helper, source, install), helm snap                  |
| hashicorp   | consul, vault, nomad, packer, vagrant (helper, `zip`)                                               |
| cloud_tools | teleport, cloudflared, gcloud (keyring helper each), cf-terraforming (helper, `tar`); azure cleanup stays advisory |
| gui_tools   | virtualbox (keyring helper), edge (source helper, install), snaps (each `snap install`, `snap set`), steam; albert unchanged |
| misc        | docker-compose, yq (helper, `bin`), opentofu (keyring helper); dotnet/tflint/tfsec/tfenv unchanged; autoremove advisory |
| nvidia      | keyring (helper) and source list (fetch to file) only                                              |

`_install_ubuntu_edge_source`'s own status is currently ignored by gui_tools. It becomes part
of the edge sub-install.

## Error handling

On a clean run every step still returns 0. The success path changes in three ways: downloads
go through a throwaway directory and `install`, keyrings are staged and renamed, and each
helper-installed tool is fetched and installed once more on the first run after merge.

A run that previously reported success over a broken install now returns rc 2 from
`install_ubuntu_packages` and prints `ubuntu packages: failed: …`. `run_setup_or_developer`
already warns and continues on rc 2 (`lib/workflows.sh:514-518`), so `-t developer` still
exits 0 and still runs pyenv, ansible, cargo and aws. The only rc that aborts is base's rc 1,
unchanged.

## Testing

Tests go in `tests/setup_env/linux_ubuntu.bats` (204 tests today) plus one file for each
helper. Existing whole-binary knobs: `MOCK_WGET_EXIT`, `MOCK_CURL_EXIT`, `MOCK_APT_EXIT`,
`MOCK_NALA_EXIT`, `MOCK_UNZIP_EXIT`, `MOCK_TAR_EXIT`, `MOCK_SNAP_EXIT`, `MOCK_CP_EXIT`,
`MOCK_MV_EXIT`. `MOCK_APT_ONLY_EXIT` is **not** subcommand-scoped. `tests/mocks/mv` and
`tests/mocks/cp` pass through with `|| true`, hiding real failures. There is no `install` mock;
`tests/mocks/sudo` execs the real `install`, so every test points `/usr/local/bin` and
`/usr/local/go` at fixtures through new seams (`_DL_BIN_DIR`, `_GO_INSTALL_ROOT`), never the
real paths (`tdd.md` E2).

New mock knobs, each with its own mock test:

- `MOCK_WGET_FAIL_URL` / `MOCK_CURL_FAIL_URL`: fail only a call whose argv contains the
  substring. Like today's whole-binary knob, the failing branch writes a 0-byte `-O`/`-o`
  target first, so it models truncation.
- `MOCK_APT_FAIL_SUBCMD` (and for `apt-get`, `nala`): fail only when the first non-option
  argument equals the value.
- `MOCK_MV_FAIL_ARGS`: fail only an `mv` whose argv contains the substring, so the Go swap's
  third move can fail while the first two succeed.

For each sub-install, one failure test asserts five things:

1. the step's status is non-zero (3 for docker's core, 1 otherwise);
2. stderr names the step and the tool;
3. **positive control:** `MOCK_CALLS_FILE` holds the failing call for that tool;
4. the destination (fixture `/usr/local/bin/<tool>`, or the live keyring path) is byte-for-byte
   what it was before the run, no stamp was written, and no throwaway directory remains;
5. a sibling sub-install in the same step still ran.

Helper tests, with the destination fixture seeded with known bytes, each of fetch, extract and
install failing in turn: the `mktemp`/fetch call is in `MOCK_CALLS_FILE` (positive control), no
stamp, no throwaway directory, destination holds its seeded bytes; then a second call with the
failure cleared fetches again (two fetch calls) and stamps. Stamp-write failing (stamp directory
unwritable): destination replaced, no stamp, status 0, a warning printed. A matching stamp with
an executable destination makes no fetch call **and** prints the skip line; the same fixture
without the stamp makes exactly one fetch call. A matching stamp with the destination missing
does not skip.

Go tests, with a fixture `_GO_INSTALL_ROOT` seeded with `go/bin/v` holding `old`:

- third `mv` failing → `go/bin/v` still holds `old`, and `MOCK_CALLS_FILE` shows the first move
  to `go.old` happened (the restore path ran, not a no-op);
- no `go` and no `go.old` before, new-tree move failing → the failing `<tmp>/go → go` call is in
  `MOCK_CALLS_FILE`, status is non-zero, and no restore `mv` is attempted;
- no `go` but a `go.old` holding `old`, clean run → `MOCK_CALLS_FILE` shows the `mv` calls in
  order `go.old → go`, `go → go.old`, `<tmp>/go → go`; with the last one failing, `go/bin/v`
  holds `old`; with the move-back failing, status is non-zero and `go.old` still holds `old`;
- `MOCK_CALLS_FILE` holds `chown -R root:root <tmp>/go` before the swap's first `mv`;
- a leftover `go.old` holding `stale` → after a clean run `go/bin/v` holds the new content and
  no `go/go` exists;
- version: `_GO_BIN` stub printing `go version go1.27.1 linux/amd64` with `GO_VER=1.27` → 0;
  printing `go1.26.3` → non-zero. Every go test sets `_GO_BIN` (`tdd.md` pitfall G).

Keyring helper tests: fetch failing → the live keyring fixture holds its old bytes and no
`.new` remains; dearmor producing nothing → same; success → keyring replaced.

Additional cases:

- **apt update, both branches.** With `MOCK_APT_FAIL_SUBCMD=update`, base stays 0 and prints its
  one warning, and in the same run a later step stays 0, its `apt update` call is in
  `MOCK_CALLS_FILE` (positive control), and it prints nothing about `apt update`. With
  `MOCK_APT_FAIL_SUBCMD=install`, the step is non-zero.
- **telepresence.** With `MOCK_CURL_STDOUT` giving a resolved URL that matches the stamp and an
  executable destination: the resolution call is present, no fetch, the skip line printed. With
  a different resolved URL: one fetch, one `install`, the new URL stamped. With resolution
  failing and an executable destination: status 0 and a warning; with the destination missing:
  non-zero.
- **Dispatcher, both branches.** With `apt install docker-ce` failing for real, nvidia is skipped
  and both are named. With only `docker-buildx-plugin` failing, docker is named failed and
  nvidia still runs.
- **Base rc 2.** A failed common-list install records `base` and later steps still run.
  Unsupported release still returns 1 and runs nothing else.
- **Clean run, discriminating.** A dispatcher-level test runs every step with all mocks
  succeeding and asserts both rc 0 **and** that `MOCK_CALLS_FILE` holds each step's core install
  call, including every helper's fetch call. A second run in the same test, with stamps now
  present, asserts no helper `wget` calls **and** that every helper's skip line was printed.

Every new check gets a mutation control: delete the check and confirm its test goes red.

## Requirements

- **R1.** `[PR1]` Each of `_install_ubuntu_docker`, `_install_ubuntu_k8s_tools`, `_install_ubuntu_hashicorp`, `_install_ubuntu_cloud_tools`, `_install_ubuntu_gui_tools`, `_install_ubuntu_misc`, `_install_ubuntu_workstation` and `_install_ubuntu_go` returns non-zero when any sub-install it attempted failed, and 0 only when all attempted sub-installs succeeded.
- **R2.** `[PR1]` kind, telepresence, consul, vault, nomad, packer, vagrant, cf-terraforming, docker-compose and yq are installed through `_install_fetched_binary`, which downloads and extracts only inside a throwaway directory, writes the destination only with `sudo install` after every earlier stage succeeded, writes the stamp only after the install succeeded, treats a failed stamp write as a warning, and removes the throwaway directory on every path.
- **R3.** `[PR1]` A failed sub-install does not prevent sibling sub-installs in the same step from running.
- **R4.** `[PR1]` Each failed sub-install is named on stderr with its step and tool.
- **R5.** `[PR1]` Every apt keyring written by the in-scope steps, nvidia's included, is fetched to a file and replaced only by renaming a non-empty staged file; a failed fetch or dearmor leaves the live keyring unchanged.
- **R6.** `[PR1]` An `apt update` failure does not by itself fail a step, except in `_install_ubuntu_powershell` and `_install_ubuntu_nvidia`; base's logs exactly one warning, and no other step's logs one.
- **R7.** `[PR1]` `_install_ubuntu_powershell` returns 1 on every failure path it currently returns 0 from.
- **R8.** `[PR1]` `_install_ubuntu_base_packages` returns 1 for an unsupported release and 2 when any of its installs failed; `install_ubuntu_packages` returns 1 for the former and records `base` as a failed step and continues for the latter.
- **R9.** `[PR1]` `_install_ubuntu_docker` returns 3 when an `apt install` of `docker-ce`, `docker-ce-cli` or `containerd.io` failed or `daemon.json` failed validation, and 1 for any other failed sub-install; `install_ubuntu_packages` skips nvidia only when docker returned 3.
- **R10.** `[PR1]` A run where every command succeeds returns 0 from every step, and each step's core install call is made.
- **R11.** `[PR1]` The go step accepts an installed version equal to `GO_VER` or beginning with `GO_VER.`, and fails on any other version after install.
- **R12.** `[PR1]` Go is extracted in a throwaway directory, chowned to `root:root` before the swap, and swapped in with `mv -T`; a `go.old` is deleted beforehand only when `/usr/local/go` exists, and is moved back instead when it does not, a failed move-back failing the sub-install without touching `go.old`; if the new tree's move fails after the old tree was moved aside, the old tree is restored; `go.old` is deleted only after the new tree is in place; the stamp is written only after the swap succeeded; the throwaway directory is removed with `sudo rm -rf`.
- **R13.** `[PR1]` A helper-installed tool whose stamp matches its URL and whose destination is executable is not fetched, and the skip prints a line naming the stamp path; for telepresence the URL is the one `TELEPRESENCE_URL` resolves to, a resolved URL equal to `TELEPRESENCE_URL` counts as a failed resolution, and a failed resolution is a warning only when a stamp exists and the destination is executable and non-empty, otherwise a failure.
- **V1.** Every new check has a mutation control: removing it turns its test red. Record each removal and the red test name in the PR body.
- **V2.** `make test` passes on the Linux development box and in CI.
- **V3.** On a Linux box, add a source pointing at an unreachable host to a scratch sources directory and run `apt update` with `-o Dir::Etc::sourcelist` scoped to it; record its exit code. If it exits 0, R6's rationale is moot but the rule stays harmless. Then, with a scoped source for an already-installed package pointing at the unreachable host, run `apt install -y <package>` and record its exit code; an rc 0 ("already the newest version") is correct behaviour under R6, since the package is installed and base's warning reports the dead source.
- **V4.** Before merge, on `claude`: for each snap the workstation list and gui_tools install, run the exact `sudo snap install …` invocation the code uses against the already-installed snap, and the exact `sudo snap set certbot trust-plugin-with-root=ok`; record each exit code. Any non-zero result is fixed or exempted in this PR, so a provisioned box reports rc 0.
- **V5.** After merge, run `setup_env.sh -t developer` on `claude` and record `install_ubuntu_packages`' rc and any `failed:` line; a second run prints the skip line for each of the ten helper tools and downloads none.
- **N1.** No change to `_install_ubuntu_rust`, `_install_ubuntu_brew_packages` or `_install_ubuntu_albert`, and none to `_install_ubuntu_nvidia` beyond its keyring and source-list fetch.
- **N2.** No `set -e`, `set -o pipefail` or ERR/EXIT/RETURN trap is introduced.
- **N3.** No change to `run_setup_or_developer`'s handling of `install_ubuntu_packages`' return codes.
- **N4.** Cleanup commands and "is installed" probes do not become failures.
- **N5.** No sha256 pins are added for the helper-installed tools, and no file under `~/software_downloads` is deleted.

## Amendments

- N5 -> No sha256 pins are added for the helper-installed tools, and no file under `~/software_downloads` that existed before the run is deleted; the helpers' own throwaway directories there are created and removed by the run. — plan non-goal check found the throwaway directory literally violated the original wording.
- R12 -> Go is extracted in a throwaway directory, chowned to `root:root` before the swap, and swapped in with plain `mv` after verifying each move's destination is absent; a `go.old` is deleted beforehand only when `/usr/local/go` exists, and is moved back instead when it does not, a failed move-back failing the sub-install without touching `go.old`; if the new tree's move fails after the old tree was moved aside, the old tree is restored; `go.old` is deleted only after the new tree is in place; the stamp is written only after the swap succeeded; the throwaway directory is removed with `sudo rm -rf`. — macOS `mv` has no `-T` and the test-macos job runs this suite; an absence check before each move gives the same no-nesting guarantee.
- finding R1 (2026-10-04, reviewer both): DIFFERS — Seven of the eight steps aggregate every sub-install into rc 1, but _install_ubuntu_misc (lib/linux_ubuntu.sh:~1614 comment, return at :1685) counts only docker-compose, yq and opentofu; its own header says 'dotnet, tflint, tfsec, tfenv and the nala cleanup are advisory', so a failed tflint/tfsec/tfenv/dotnet install, which are attempted sub-installs, still returns 0.
- R1 -> Each of `_install_ubuntu_docker`, `_install_ubuntu_k8s_tools`, `_install_ubuntu_hashicorp`, `_install_ubuntu_cloud_tools`, `_install_ubuntu_gui_tools`, `_install_ubuntu_misc`, `_install_ubuntu_workstation` and `_install_ubuntu_go` returns non-zero when any sub-install it attempted failed, and 0 only when all attempted sub-installs succeeded, except the advisory sub-installs the Rules section names (dotnet, tflint, tfsec, tfenv and nala autoremove), whose failure warns without failing the step. — the approved Rules section and inventory keep those advisory; R1's wording omitted the carve-out the design states.
- finding R4 (2026-10-04, reviewer both): DIFFERS — In _install_ubuntu_misc a failed docker-compose or yq is handled with a bare `|| _misc_rc=1` (lib/linux_ubuntu.sh:1619/:1623), so stderr carries only the helper's `docker-compose: download failed` / `yq: download failed` with no 'misc' step name, unlike every other step's `<step>: <tool>:` warning.
- R4 reviewed: fixed in 11f11d84 — misc now warns `misc: docker-compose: install failed` and `misc: yq: install failed`, with tests asserting both.
- finding R5 (2026-10-04, reviewer A): DIFFERS — Fetched keyrings go through _install_apt_keyring (stage to <ring>.new, -s check, mv; failures leave the live ring), but the edge keyring written in the in-scope gui_tools step is not fetched, and on a failed gpg/dearmor build _install_ubuntu_edge_source still runs `sudo rm -f "${_edge_list}" "${_edge_keyring}"` (lib/linux_ubuntu.sh:~1189), deleting the live keyring.
- R5 -> Every apt keyring the in-scope steps fetch through `_install_apt_keyring` (docker, kubernetes, teleport, cloudflare, gcloud, VirtualBox, opentofu, nvidia) is fetched to a file and replaced only by renaming a non-empty staged file; a failed fetch or dearmor leaves the live keyring unchanged. — the design routes edge and albert through `_build_pinned_keyring`, outside R5's call-site list; edge's pre-existing deletion on a failed build is a backlog row, not this change.

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

## Multi-Lens Review, round 2

Reviewed at commit: `06685c70` (round-1 revisions). All three lenses re-run because the revision changed design substance.

### Goal-Fit (round 2)

Finding: (1) Install-stage failure still becomes silent success: every download guard keys on the artifact, and R2's cleanup covered download/extract only, so a failed `cp`/`mv` leaves the artifact and the next run skips the tool and reports 0; for Go, every later run reports `failed: go` permanently. (2) R6 false for nvidia, which runs `sudo -H apt update || return 1` right after adding its source, while N1 froze nvidia. (3) N1's premise that nvidia checks every command is wrong: `curl | sudo gpg --dearmor -o … || return 1` and `curl | sed | sudo tee || return 1` are producer-blind. Go move-aside test must seed and assert content.
Assumption: A failed install leaves no download artifact behind; true only for download/extract failures. Settled by a bats case with `MOCK_CP_EXIT=1` for kind, re-run cleared, checking for a second `wget`.
Disposition: Addressed — artifact-keyed guards replaced by a throwaway directory plus a stamp written only after install (R2, R13); nvidia named as R6's second exception and its two pipelines brought into scope (R5, N1). Operator, 2026-10-04: chose "round 3" on the combined spec over the author's recommended split.

### Ergonomics (round 2)

Finding: (1) R5's PIPESTATUS option still lets a fetch failure wipe a live keyring: `curl | sudo gpg --dearmor --yes -o <live>` truncates it (measured, 0 bytes); docker's `sudo curl -o` writes in place. Only fetch-to-temp then install is safe. (2) telepresence: `cp -a` onto a running binary fails with ETXTBSY (measured), so a connected telepresence reports rc 2 every run; use `install` or skip on `cmp`. (3) `mv go go.old` with a leftover `go.old` nests the tree (measured); require `rm -rf` first or `mv -T`. Vacuous risks: the URL-scoped wget knob must still create the `-O` target; the "later step prints nothing about apt update" case needs a positive control.
Assumption: telepresence daemons are alive during a typical reprovision; settled by `pgrep -af telepresence` on both boxes at reprovision time.
Disposition: Addressed — keyring helper stages and renames (R5); `install` plus `cmp` skip for telepresence (R2, R13); `rm -rf go.old` then `mv -T` (R12); mock-knob and positive-control requirements added. Operator, 2026-10-04: "round 3".

### Risk (round 2)

Finding: (1) The R12 restore test was vacuous: `tests/mocks/mv` fails every call under `MOCK_MV_EXIT`, so the first move fails and nothing is restored; needs an argument-scoped mv knob and a positive control. (2) Leftover `go.old` nests (measured `go/go/bin/v`). (3) Same install-stage gap as Goal-Fit. (4) cf-terraforming extracts with `-C ~/software_downloads`, so a literal "delete the partial extraction" wipes every tool's artifacts. (5) URL knob must touch the `-O` target; the apt-update absence case needs its base-warning control. R9/R1 and R8/N3 consistent; `/home` and `/usr/local` share a filesystem on both boxes.
Assumption: every newly checked `snap install`/`snap set` exits 0 on a provisioned `claude`; settled by running each exact invocation against the installed snaps.
Disposition: Addressed — `MOCK_MV_FAIL_ARGS` and a content-seeded Go fixture; `mv -T`; throwaway directory removes the cf-terraforming hazard and the cleanup class; assumption made V4, a pre-merge measurement. Operator, 2026-10-04: "round 3".


## Multi-Lens Review, round 3

Reviewed at commit: `5281b018` (round-2 revisions: stamped installs, keyring staging). All three lenses re-run.

### Goal-Fit (round 3)

Finding: Premise re-verified; combined scope now coherent and the stamp passes the reads-it test (every run's skip guard reads it). (1) The clean-run test and V5 asserted "no fetches" on a second run, contradicting R13's always-fetched telepresence, and both were absence assertions. (2) The stamp-write stage's test asserted "destination unchanged" after the install had already replaced it, and a stamp-write failure was undefined. (3) The Go swap drops root ownership: today `:245` runs `sudo chown -R root:root`; extracting as the user then renaming leaves a user-owned `/usr/local/go`, and a root-owned tree then needs `sudo rm -rf` to clean. Telepresence line reference stale.
Assumption: Each zip/tar holds a single executable at `<member>`. Settled by the author: the old extracted `vagrant_2.4.9` and `consul_2.0.0` directories on `claude` each hold the binary plus `LICENSE.txt`, and today's code copies only the binary.
Disposition: Addressed — telepresence stamps its resolved URL (R13) so the second-run checks are uniform and carry positive controls; stamp-write failure is a warning with its own test (R2); Go tree chowned to `_GO_OWNER` before the swap and cleaned with `sudo rm -rf` (R12). Operator, 2026-10-04: "yes".

### Ergonomics (round 3)

Finding: ETXTBSY premise re-measured (`cp` rc 1, `install` rc 0). (1) Same stamp-write contradiction. (2) Stamps invisible: no log line, doctor check or doc names the stamp directory, so a wrong-but-executable binary is skipped forever. (3) telepresence still downloads 114 MB every run and a network blip becomes rc 2; `latest` redirects to a versioned URL. (4) First-run cost understated: ~450 MB plus a Go swap. (5) Four cases would pass on silence (stamp skip, telepresence busy, second clean run, V5).
Assumption: Every exact `snap install`/`snap set` exits 0 against installed snaps (V4).
Disposition: Addressed — skip line naming the stamp path plus a CLAUDE.md Test Seams entry; telepresence stamps the resolved URL and a failed resolution with an executable destination warns; cost stated; positive controls added. Assumption remains V4, pre-merge. Operator, 2026-10-04: "yes".

### Risk (round 3)

Finding: (1) `sudo install -o root -g root` fails under the harness (`tests/mocks/sudo` execs the real `install` as the user: measured rc 1, "cannot change ownership"), so every success-path helper test would fail; real sudo already makes root the owner. (2) Same Go ownership gap as Goal-Fit, plus the cleanup needing `sudo`. (3) Same R13/clean-run/V5 contradiction. (4) Go deletes `go.old` unconditionally, which loses the only good copy after a failed restore, and attempts a restore when no move happened. (5) Helper-stage absence assertions need `mktemp`/fetch positive controls and a seeded destination. Archive members, same-filesystem (`/` on both boxes), keyring dearmor, stamp-dir ownership and the `mv` mock path checked and clean.
Assumption: Same as Ergonomics (V4).
Disposition: Addressed — `-o`/`-g` dropped, matching `:1126`; Go swap moves a lone `go.old` back instead of deleting it and restores only after a move happened; helper tests seeded and positive-controlled. Operator, 2026-10-04: "yes" (approving the fixes and a scoped Risk re-review in place of a full round 4).

### Risk, scoped re-review (round 3 revisions)

Reviewed at commit: `72b17cbc`, scoped to the diff from `5281b018`.

Finding: (1) `_GO_OWNER`'s stated reason was false: `tests/mocks/chown` records and exits 0 (verified by the author), so the seam only widened production, letting an inherited variable choose `/usr/local/go`'s owner. (2) The Go move-back test's "not deleted" contradicts the design by the end of a clean run; assert `mv` order instead, and define a failed move-back. (3) "No restore `mv`" needs positive controls; the spec never named the fetch tool, so "no fetch" was ambiguous against telepresence's `curl -I`. (4) A failed resolution with an executable destination returned 0 even with no stamp, so a 0-byte binary from the old `wget` bug survives; an unwritable stamp dir only warns. Real `curl -fsSIL -w '%{url_effective}'` resolves to the versioned S3 URL; the curl mock drives it.
Assumption: `…/latest/telepresence` keeps redirecting; a direct 200 would make `url_effective` equal the input and freeze the stamp. Guard: treat an unchanged URL as a failed resolution.
Disposition: Addressed — seam dropped and `root:root` hardcoded; `mv`-order assertion and failed move-back defined (R12); `wget` named as the fetch tool; warn-and-skip on failed resolution requires a stamp and a non-empty executable, and an unchanged resolved URL counts as failed (R13); stamp-write warning names the path. Operator, 2026-10-04: "1-5 addressed".

