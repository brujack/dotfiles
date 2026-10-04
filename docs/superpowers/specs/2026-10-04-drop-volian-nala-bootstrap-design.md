# Install nala from the Ubuntu archive on every release

- **Date:** 2026-10-04
- **Backlog row closed:** "Volian archive debs install as root with no integrity check" (P2 — bugs and security).
- **Approved:** 2026-10-04, operator: "Approved and get er done"

## Problem

`check_and_install_nala` (`lib/helpers.sh`) installs nala only when it is not already `ii`.
On any Ubuntu release other than 26.04 (`RESOLUTE` unset) it first:

- `wget`s `volian-archive-keyring_0.2.0_all.deb` and `volian-archive-nala_0.2.0_all.deb` from
  GitLab upload URLs, with no sha256 pin, no signature check and no `wget` exit check;
- runs `sudo dpkg --install` on both, as root;
- runs `apt update`, then installs nala.

So whoever controls those URLs runs code as root on a fresh non-26.04 provision. The two debs
carry a keyring, an apt `.sources` file and a `preferences.d` pin to volian's `scar-unstable`
channel, and no maintainer scripts. That was checked with `dpkg-deb -c` on 2026-10-03 against
the current URLs, so it describes today's files, not what the URLs serve tomorrow. Found by the
security-review of dotfiles#310.

## Premise checks

- **The bootstrap is unnecessary on Noble.** Launchpad's published sources for the Ubuntu
  primary archive, queried 2026-10-04, list `nala 0.15.1` in `universe`, pocket `Release`, for
  `noble`. For `jammy` it is `0.11.1~bpo22.04.1` in `Backports`. The volian path dates from
  2023-11 (`29113506`, `af315bea`), when Jammy was current. #145 (`a2fd2912`, 2026-06-17) moved
  26.04 to `apt install nala` and kept Noble on volian "unchanged". Its spec
  (`2026-06-17-ubuntu-2604-pr3-design.md`) gives scope as the reason and states no technical
  one.
- **Nothing on the fleet's Linux dev boxes depends on volian.** Measured 2026-10-04:
  `claude` and `workstation` are both on Ubuntu 26.04, carry no `volian*` package and no
  `volian` file in `/etc/apt/sources.list.d`, and `workstation`'s nala 0.16.0 comes from
  `resolute/universe`. That covers those two machines only. The operator stated on 2026-10-04 that the third
  Linux box, `cruncher` (WSL), is also on 26.04, and that no Ubuntu 24.04 host is still
  provisioned by dotfiles. So two things that would matter only on a Noble host are recorded
  rather than designed for: a leftover volian source and `scar-unstable` pin on an old Noble
  machine, and the fact that a fresh Noble provision now needs `universe` enabled. The 26.04
  path already depends on `universe`, because its nala comes from `resolute/universe`.
- **Every caller refreshes apt lists first.** `lib/linux_ubuntu.sh:39` runs `apt update`
  before the calls at `:43` and `:51`. `lib/linux_shared.sh:54` does the same before `:55`. The
  call at `lib/linux_ubuntu.sh:1335` ends a function that has already run `apt update` several
  times. The 26.04 path relies on this today, so Noble would too.

## Decision

Delete the volian bootstrap. Every Ubuntu release takes the existing 26.04 path:
`sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" nala -y`.

Rejected: **pin each sha256, `sha256sum -c`, and check `wget`.** That keeps root-installed
third-party debs and a third-party apt source pinned to an unstable channel. It also needs
re-pinning whenever volian republishes, for no benefit over the Ubuntu archive's nala.

This removes the two volian `dpkg --install` calls that dotfiles#310 gave `--force-confmiss`.
Its spec's R5/R11 named three archive-setup debs. After this change there is one,
`packages-microsoft-prod.deb`. That spec shipped and is not edited. This spec governs from
here, and ADR-0040 gets a dated amendment note.

### Changes

- `lib/helpers.sh` `check_and_install_nala`: remove the `if [[ -z ${RESOLUTE} ]]; then … fi`
  block (both `wget`s, both `dpkg --install`, its comments, its `apt update`). The surrounding
  Linux/Ubuntu/not-`ii` guards and the `apt install` line are unchanged.
- `tests/setup_env/install_functions.bats` (every test that exercises `check_and_install_nala`):
  - delete `check_and_install_nala: volian dpkg --install sees DEBIAN_FRONTEND=noninteractive`;
  - delete `conffile argv: volian dpkg --install restores deleted conffiles (confmiss) on both debs`;
  - `check_and_install_nala installs nala via dpkg and apt on Ubuntu when absent` leaves
    `RESOLUTE` unset and asserts `dpkg --install`, so it goes red after the change. Fold it
    into the new NOBLE test below, which covers the same case.
  - replace `check_and_install_nala on NOBLE uses volian wget path` with a NOBLE test that sets
    `NOBLE=1` and unsets `RESOLUTE` explicitly. Using `argv_probe_stub_path` for `apt`, it
    asserts:
    - the nala install line is exactly
      `[install][-o][Dpkg::Options::=--force-confdef][-o][Dpkg::Options::=--force-confold][nala][-y]`
      (the mocks strip these options from recorded call text, so only an argv probe can see
      them);
    - zero `wget` calls and zero `dpkg --install` calls.
  - keep the RESOLUTE test's assertions, set `RESOLUTE` explicitly in it, and rename it so its
    name no longer contains `volian` (R2).
  - the already-installed test's `refute_grep "dpkg --install"` becomes vacuous. Keep it,
    because its `refute_grep "apt install nala"` still carries that test.
- `tests/scripts/dpkg_sudo_frontend.bats`:
  - the confmiss allow-set becomes `packages-microsoft-prod.deb` only, and the test named
    `--force-confmiss appears exactly at the three archive-setup debs` is renamed to match;
  - drop the `'lib/helpers.sh|sudo.*dpkg --install'` anchor from the real-tree enumeration
    test. The `'lib/linux_ubuntu.sh|sudo.*dpkg -i'` anchor already keeps the dpkg family
    reached. The fixture tests that cover `--install` stay.
- `CLAUDE.md`: the Shell Scripts conffile bullet says confmiss sits only on
  `packages-microsoft-prod.deb`.
- `docs/adr/0040-…`: add a dated amendment note saying the volian path was removed and
  confmiss is on the Microsoft deb only, with a pointer to this spec. The original text stays.
  Because R2 removes every `volian` string from code and tests, the note also carries the
  manual cleanup for any machine provisioned through the old path:
  `sudo rm -f /etc/apt/sources.list.d/volian-archive-scar-unstable.sources /etc/apt/preferences.d/volian-archive-scar-unstable.pref && sudo apt purge -y volian-archive-keyring volian-archive-nala && sudo apt update`.
- `docs/superpowers/README.md`:
  - delete the volian backlog row;
  - narrow the repair-gap row to the Microsoft package only (its guard is `_pwsh_probe_runs`).
- `ai-config/docs/knowledge/dotfiles-apt-upgrade-hazards.md` §2b: one sentence saying the
  volian calls were removed. This is a separate docs-only commit to ai-config, not part of the
  dotfiles PR.

## Testing

TDD: write the new NOBLE test first and watch it fail against the current code (the volian
`wget` runs). Then delete the block, then update the gate and the remaining tests.

Mutation checks:

- re-adding a volian `wget` line turns the NOBLE test red;
- adding `--force-confmiss` to any other dpkg or apt call turns the confmiss allow-set test red;
- deleting the `apt install … nala` line turns both the NOBLE and RESOLUTE tests red;
- dropping `"${APT_CONFFILE_OPTS[@]}"` from the nala `apt install` line turns the NOBLE test red.

## Requirements

- **R1.** `[PR1]` `check_and_install_nala` in `lib/helpers.sh` contains no `wget`, no `dpkg --install` and no `volian` text, and installs nala with `sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" nala -y` on every Ubuntu release.
- **R2.** `[PR1]` No tracked file under `lib/`, `scripts/`, `setup_env.sh` or `tests/` contains the text `volian`.
- **R3.** `[PR1]` A bats test with `NOBLE=1` and `RESOLUTE` unset asserts, through `argv_probe_stub_path apt`, that `check_and_install_nala` runs exactly `install -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold nala -y` as separate arguments, and makes zero `wget` calls and zero `dpkg --install` calls.
- **R4.** `[PR1]` The confmiss allow-set in `tests/scripts/dpkg_sudo_frontend.bats` is exactly `packages-microsoft-prod.deb`, and the whole file passes.
- **R5.** `[PR1]` The real-tree enumeration test in `tests/scripts/dpkg_sudo_frontend.bats` no longer names a `lib/helpers.sh` dpkg site, and still names at least one `dpkg` site.
- **R6.** `[PR1]` `CLAUDE.md` states that `--force-confmiss` appears only at the `packages-microsoft-prod.deb` install.
- **R7.** `[PR1]` `docs/adr/0040-apt-conffile-prompts-answered-unattended.md` carries a dated amendment note naming the volian removal, this spec, and the manual cleanup command for a machine provisioned through the old path; its original Decision text is unchanged.
- **R8.** `[PR1]` `docs/superpowers/README.md` has no volian backlog row, and its repair-gap row names only the Microsoft package and `_pwsh_probe_runs`.
- **R9.** `[PR1]` No test that exercises `check_and_install_nala` asserts a `dpkg --install` call, and every such test sets or unsets `RESOLUTE` explicitly.
- **V1.** Mutations: re-adding a volian `wget` turns the R3 test red; adding `--force-confmiss` to another dpkg or apt call turns the confmiss test red; deleting the nala `apt install` line turns the NOBLE and RESOLUTE tests red; dropping the options array from that line turns the R3 test red.
- **V2.** `make test` passes, and the changed bats files pass on the Mac Studio (bundle clone, bare env).
- **N1.** No code removes volian packages or sources from machines that already have them.
- **N2.** `_install_ubuntu_powershell` and `packages-microsoft-prod.deb` handling are unchanged.
- **N3.** No new `apt update` call is added.
- **N4.** The 2026-10-03 apt-conffile spec's text is not edited.

## Multi-Lens Review

Reviewed at commit: `347301b5` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The design is right, and removal beats pinning. Gap: `install_functions.bats`, "check_and_install_nala installs nala via dpkg and apt on Ubuntu when absent", leaves `RESOLUTE` unset and asserts `dpkg --install`, so it goes red, and the Changes list did not name it. It also inherits `RESOLUTE` from the parent shell. The already-installed test's dpkg refute becomes vacuous; its apt refute still carries it. Premises re-verified: Launchpad gives noble 0.15.1 universe Release, and `apt-cache policy nala` in an `ubuntu:24.04` container gives Candidate 0.15.1; callers update first.
Assumption: `universe` is enabled on every non-26.04 Ubuntu host this runs on. Settled by `apt-cache policy nala` on each 24.04 host.
Disposition: Addressed (operator, 2026-10-04): the missed test is folded into the NOBLE test (R9), and RESOLUTE is set explicitly. On the assumption, the operator stated that all three Linux boxes, including `cruncher` (WSL), are on 26.04 and that no 24.04 host is provisioned. The 26.04 path already depends on `universe`.

### Ergonomics

Finding: Hosts provisioned through the old path keep volian's source and `scar-unstable` pin with no report, and R2 removes every repo trail. The mocks' recorded-text stripping means R3 could not see the options on the nala line. Callers ignoring the function's return code is pre-existing and unchanged. Jammy only reaches the function via the update path.
Assumption: no live Noble host still carries volian. Settled by `ls /etc/apt/sources.list.d /etc/apt/preferences.d | grep -i volian` on each Noble host.
Disposition: Addressed (operator, 2026-10-04): there is no 24.04 host; all three Linux boxes are on 26.04, and `claude` and `workstation` were measured volian-free. The manual cleanup command goes in the ADR-0040 amendment (R7) as the remaining trail. R3 now asserts the exact argv through `argv_probe_stub_path`, and V1 adds the matching mutation. No doctor check.

### Risk

Finding: (1) the same missed test as Goal-Fit; (2) R2 conflicted with keeping the RESOLUTE test unchanged, because its name contains `volian`; (3) existing negative assertions become vacuous (minor); (4) `dpkg_sudo_frontend.bats` stays non-vacuous with the single Microsoft dpkg site, but the "three archive-setup debs" test name goes stale; (5) nothing else reads `RESOLUTE` inside the function or depends on volian; (6) Jammy is not a real case. Premise verified via Launchpad (noble, resolute, jammy).
Assumption: `universe` is enabled on every Noble target. Settled by `grep -h Components /etc/apt/sources.list.d/ubuntu.sources` on actual Noble targets.
Disposition: Addressed (operator, 2026-10-04): the RESOLUTE test and the confmiss test get renamed, and the missed test is listed (R9). On the assumption: there are no Noble targets (operator).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Amendments

- finding R9 (2026-10-04, reviewer A): NOT-BUILT — The diff unsets or sets RESOLUTE in the non-Linux, non-Ubuntu, already-installed, RESOLUTE and NOBLE tests, and removes every `dpkg --install` positive assertion. It does not show the unchanged test that ends just before the RESOLUTE test, at new line ~177 (`grep -qE '^frontend: apt install nala .*DEBIAN_FRONTEND=noninteractive$'`), which exercises check_and_install_nala. I found no evidence that this test sets or unsets RESOLUTE explicitly.
- R9 reviewed: the unchanged test at tests/setup_env/install_functions.bats:167 ("apt install nala sees DEBIAN_FRONTEND=noninteractive") sets `export RESOLUTE=1` at line 170; it sat outside the diff hunk, so the reviewer could not see it. All six tests exercising check_and_install_nala set or unset RESOLUTE (lines 136, 145, 157, 170, 183, 196); workflows.bats:706 only stubs the function. No test asserts dpkg --install.

## Spec alignment (2026-10-04)

- spec: docs/superpowers/specs/2026-10-04-drop-volian-nala-bootstrap-design.md
- anchor: f67c5b6db9c2e9d3787f571cca0356dad9f459b7
- in scope: R1, R2, R3, R4, R5, R6, R7, R8, R9
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |
| R9 | A | NOT-BUILT | The diff unsets or sets RESOLUTE in the non-Linux, non-Ubuntu, already-installed, RESOLUTE and NOBLE tests, and removes every `dpkg --install` positive assertion. It does not show the unchanged test that ends just before the RESOLUTE test, at new line ~177 (`grep -qE '^frontend: apt install nala .*DEBIAN_FRONTEND=noninteractive$'`), which exercises check_and_install_nala. I found no evidence that this test sets or unsets RESOLUTE explicitly. | - R9 reviewed: the unchanged test at tests/setup_env/install_functions.bats:167 ("apt install nala sees DEBIAN_FRONTEND=noninteractive") sets `export RESOLUTE=1` at line 170; it sat outside the diff hunk, so the reviewer could not see it. All six tests exercising check_and_install_nala set or unset RESOLUTE (lines 136, 145, 157, 170, 183, 196); workflows.bats:706 only stubs the function. No test asserts dpkg --install. |

### Reviewed

- R9 reviewed: the unchanged test at tests/setup_env/install_functions.bats:167 ("apt install nala sees DEBIAN_FRONTEND=noninteractive") sets `export RESOLUTE=1` at line 170; it sat outside the diff hunk, so the reviewer could not see it. All six tests exercising check_and_install_nala set or unset RESOLUTE (lines 136, 145, 157, 170, 183, 196); workflows.bats:706 only stubs the function. No test asserts dpkg --install.

### Verifications

- V1: All four mutations red: re-added volian wget -> NOBLE and RESOLUTE tests red; dropped options array -> NOBLE test red; deleted nala apt install line -> NOBLE, RESOLUTE and DEBIAN_FRONTEND tests red; stray --force-confmiss on the powershell apt line -> confmiss test red.
- V2: make test 2396/2396 ok, rc 0, at 80a6da69; Mac Studio bundle clone, bare env: 80/80 ok for the two changed bats files.
