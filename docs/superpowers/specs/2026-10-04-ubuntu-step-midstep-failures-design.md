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
- **Across sub-installs, degrade.** A failed sub-install does not stop its siblings. One dead
  release URL must not cost kubectl, just as one failed step no longer costs the next step.
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
  `apt install` that follows is the authoritative check: it fails when the package is
  unreachable. `apt update` keeps its call and gains `|| log_warn "<step>: apt update reported
errors; continuing"`. Exception: `_install_ubuntu_powershell` keeps checking `apt update`
  as a failure, because there it directly follows adding the Microsoft source, and its
  existing tests pin that.
- **Every pipeline element is checked.** A pipeline whose producer can fail (`curl`, `wget
-O-`) checks `${PIPESTATUS[@]}` immediately after the pipeline, before any other command, or
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
- **The nvidia skip becomes reachable.** No dispatcher change is needed beyond base. A docker
  step that can now fail is what arms the existing guard.

### Sub-install inventory

| step        | sub-installs                                                                                                                                   |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| base        | hwe kernel, `check_and_install_nala`, common list, release list                                                                                |
| workstation | nala list, snap list                                                                                                                           |
| powershell  | (one sub-install; return 0 becomes 1)                                                                                                          |
| go          | apt update (advisory), tarball download, extract, move into `/usr/local/go`; a version that does not match `GO_VER` after install is a failure |
| docker      | keyring, source, five `apt install`s, `daemon.json` (already checked), `usermod`                                                               |
| k8s_tools   | kind, telepresence, kubectl (key, source, install), helm snap                                                                                  |
| hashicorp   | consul, vault, nomad, packer, vagrant                                                                                                          |
| cloud_tools | teleport, cloudflared, gcloud, cf-terraforming; azure cleanup stays advisory                                                                   |
| gui_tools   | virtualbox, edge (source helper, install), snaps (each `snap install`, `snap set`), steam; albert unchanged                                    |
| misc        | docker-compose, yq, opentofu; dotnet/tflint/tfsec/tfenv unchanged; autoremove advisory                                                         |

`_install_ubuntu_edge_source`'s own status is currently ignored by gui_tools. It becomes part
of the edge sub-install.

## Error handling

The changes only add failure reporting and stop consuming bad artifacts. A clean run behaves
identically. Every step still returns 0 when every sub-install succeeds, and no new command
runs on the success path except the `PIPESTATUS` reads.

A run that previously reported success over a broken install now returns rc 2 from
`install_ubuntu_packages` and prints `ubuntu packages: failed: …`. `run_setup_or_developer`
already warns and continues on rc 2 (`lib/workflows.sh:514-518`), so `-t developer` still
exits 0 and still runs pyenv, ansible, cargo and aws. The only rc that aborts is base's rc 1,
unchanged.

## Testing

Tests go in `tests/setup_env/linux_ubuntu.bats`, which already has 204 tests and per-step
fixtures. The failure knobs exist: `MOCK_WGET_EXIT`, `MOCK_CURL_EXIT`, `MOCK_APT_EXIT`,
`MOCK_APT_ONLY_EXIT`, `MOCK_NALA_EXIT`, `MOCK_UNZIP_EXIT`, `MOCK_TAR_EXIT`, `MOCK_SNAP_EXIT`.

For each sub-install, one failure test asserts four things:

1. the step's status is non-zero;
2. stderr names the step and the tool;
3. the consuming command never ran (`MOCK_CALLS_FILE` holds no `cp`/`unzip` for that tool);
4. a sibling sub-install in the same step still ran.

Item 4 is what separates design B from a bare `|| return 1`. Item 3 is the destructive-path
guard (`tdd.md` E2).

A single shared knob such as `MOCK_WGET_EXIT` fails every download in a step at once, which
cannot show item 4. Where a step's siblings share a binary, the test needs a per-URL or
per-call failure. The plan adds that to the mock (e.g. `MOCK_WGET_FAIL_URL` matching a
substring, like `tests/mocks/claude`'s `MOCK_CLAUDE_FAIL_ARGS`) with its own mock test.

Additional cases:

- **apt update, both branches.** `apt update` failing alone leaves the step at 0 and prints the
  warning. `apt install` failing makes it non-zero. `MOCK_APT_ONLY_EXIT` drives the second
  case; the plan confirms which subcommand it scopes to.
- **Pipeline producer.** curl fails while gpg succeeds, and the sub-install is still reported
  failed. Without the `PIPESTATUS` check this test passes only when gpg happens to reject
  empty input, so the mock gpg must succeed on empty input to make the case discriminate.
- **Dispatcher.** With the docker step failing for real (an `apt install docker-ce` failure,
  not a stubbed `_install_ubuntu_docker`), nvidia is skipped and both are named.
- **Base rc 2.** A failed common-list install records `base` and later steps still run.
  Unsupported release still returns 1 and runs nothing else.
- **Clean run.** Every step returns 0 with all mocks succeeding. This is already covered by
  existing tests, which must stay green unchanged except where they asserted the old
  return-0-on-failure behaviour, e.g. powershell's.

Every new check gets a mutation control: delete the check and confirm its test goes red.

## Requirements

- **R1.** `[PR1]` Each of `_install_ubuntu_docker`, `_install_ubuntu_k8s_tools`, `_install_ubuntu_hashicorp`, `_install_ubuntu_cloud_tools`, `_install_ubuntu_gui_tools`, `_install_ubuntu_misc`, `_install_ubuntu_workstation` and `_install_ubuntu_go` returns non-zero when any sub-install it attempted failed, and 0 only when all attempted sub-installs succeeded.
- **R2.** `[PR1]` A failed download, extract, key fetch or source write stops its sub-install before any command that consumes the artifact runs.
- **R3.** `[PR1]` A failed sub-install does not prevent sibling sub-installs in the same step from running.
- **R4.** `[PR1]` Each failed sub-install is named on stderr with its step and tool.
- **R5.** `[PR1]` A pipeline whose producer is `curl` or `wget` reports the producer's failure even when the last element succeeds.
- **R6.** `[PR1]` An `apt update` failure logs a warning and does not by itself fail a step, except in `_install_ubuntu_powershell`.
- **R7.** `[PR1]` `_install_ubuntu_powershell` returns 1 on every failure path it currently returns 0 from.
- **R8.** `[PR1]` `_install_ubuntu_base_packages` returns 1 for an unsupported release and 2 when any of its installs failed; `install_ubuntu_packages` returns 1 for the former and records `base` as a failed step and continues for the latter.
- **R9.** `[PR1]` A failing docker step causes `install_ubuntu_packages` to skip nvidia.
- **R10.** `[PR1]` A run where every command succeeds produces the same step statuses (all 0) as before.
- **V1.** Every new check has a mutation control: removing it turns its test red. Record each removal and the red test name in the PR body.
- **V2.** `make test` passes on the Linux development box and in CI.
- **V3.** On a Linux box, add a source pointing at an unreachable host to a scratch sources directory and run `apt update` with `-o Dir::Etc::sourcelist` scoped to it; record its exit code. If it exits 0, R6's rationale is moot but the rule stays harmless.
- **N1.** No change to `_install_ubuntu_rust`, `_install_ubuntu_nvidia`, `_install_ubuntu_brew_packages` or `_install_ubuntu_albert` beyond what R9 needs.
- **N2.** No `set -e`, `set -o pipefail` or ERR/EXIT trap is introduced.
- **N3.** No change to `run_setup_or_developer`'s handling of `install_ubuntu_packages`' return codes.
- **N4.** Cleanup commands and "is installed" probes do not become failures.
