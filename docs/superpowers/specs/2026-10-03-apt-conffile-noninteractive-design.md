# apt/dpkg installs answer conffile prompts without a terminal

- **Date:** 2026-10-03
- **Backlog rows closed:** "`xargs ... nala install -y` in `lib/linux_ubuntu.sh` cannot answer a
  dpkg conffile prompt" and "`_install_ubuntu_powershell` runs `sudo … dpkg -i` with no
  `--force-conf*`" (both P2 — bugs and security).

## Problem

dpkg asks `(Y/I/N/O/D/Z) [default=N] ?` when it configures a package whose conffile differs from
what the package ships. With stdin at EOF it fails with
`end of file on stdin at conffile prompt` and leaves the package `iU` (unpacked, not configured).
Every later apt transaction that touches the package then fails as well.
`DEBIAN_FRONTEND=noninteractive` does not help: it governs debconf, not dpkg's conffile prompt.

Measured, and recorded in `ai-config/docs/knowledge/dotfiles-apt-upgrade-hazards.md`:

- **§2, edited conffile (claude, 2026-09-16).** A throwaway `dotfiles-cfprobe` package served
  from a `file:` apt repo, conffile edited between v1 and v2. `nala install` through the apt
  path with stdin `/dev/null`: rc 1, state `iU`. With
  `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold`: rc 0, state `ii`,
  local edit kept. That population is one package on one machine, through the apt path of
  `nala install`. `nala install ./pkg.deb` goes straight to `dpkg -i` and ignores
  `Dpkg::Options`, so that measurement says nothing about local-deb installs.
- **§2b, deleted conffile (claude, 2026-09-18).** `packages-microsoft-prod` sat at `iU` after
  `/usr/share/keyrings/microsoft-prod.gpg` had been deleted. `--force-confold` keeps the
  current version, which for a deleted file is "absent", so it does not repair this.
  `dpkg --configure --force-confmiss packages-microsoft-prod` reinstalled the keyring and ended
  `ii`. No code in this repo deletes that file (`git log -S'microsoft-prod.gpg'` shows only
  #282, #299, #300, none of which remove it); the cause is outside the repo.

Two stdin shapes reach these call sites:

1. **stdin forced closed.** `lib/linux_ubuntu.sh`'s `xargs -r sudo … nala install -y` lines. GNU
   xargs 4.10.0 gives the child `/dev/null` (verified on claude, §2). These fail on every
   provision that upgrades a package with an edited conffile, interactive or not.
2. **stdin inherited.** Every other `sudo … apt|apt-get install`, and the `dpkg -i` in
   `_install_ubuntu_powershell`. Interactive, the operator can answer the prompt. Run with no
   terminal (`ssh host '…'`, cron, a peer session), they fail the same way. §2b was this shape.

The #280 fix already handles shape 1 for `update_apt_packages`' `nala full-upgrade`
(`lib/linux_shared.sh`), with literal flags at that one site.

## Decision

Answer conffile prompts the way unattended-upgrades does, at every apt/dpkg install site that
runs as part of a dotfiles workflow:

- **confdef + confold everywhere.** Keep the operator's edited file; dpkg writes the package
  copy beside it as `.dpkg-dist`.
- **confmiss only at the three vendor archive-setup `dpkg` installs:** `packages-microsoft-prod.deb`
  (`_install_ubuntu_powershell`) and the two volian debs, `volian-archive-keyring_0.2.0_all.deb` and
  `volian-archive-nala_0.2.0_all.deb` (`check_and_install_nala`, Noble path, `lib/helpers.sh`).
  Each package carries only a vendor apt keyring and/or source, so restoring a deleted file is
  always right there. Elsewhere confmiss would silently undo a deliberate deletion (a cron file or
  apt source removed to disable something), so it is not applied.

  confmiss is load-bearing, not belt-and-braces. Measured on claude, 2026-10-03, with a throwaway
  `dotfiles-cfprobe2` package (one conffile, v1 and v2 differing in it), stdin `/dev/null`
  throughout. That population is one package on one machine; it shows dpkg's behaviour, not any
  particular vendor package's:

  | step                                                                         | rc  | state | conffile             |
  | ---------------------------------------------------------------------------- | --- | ----- | -------------------- |
  | `dpkg -i` v1, then delete the conffile                                       | 0   | `ii`  | absent               |
  | `dpkg -i` v2, no force (reproduces §2b)                                      | 1   | `iU`  | absent               |
  | `dpkg -i --force-confdef --force-confold --force-confmiss` v2, same version  | 0   | `ii`  | restored (v2 copy)   |
  | control, from a fresh `iU`: `--force-confdef --force-confold` only           | 0   | `ii`  | **still absent**     |
  | from `ii` with the conffile deleted: same-version reinstall, confdef+confold | 0   | `ii`  | **still absent**     |
  | same, plus `--force-confmiss`                                                | 0   | `ii`  | restored (v2 copy)   |

  Without confmiss the call stops wedging but leaves the keyring missing. For an archive-setup
  package that means a configured source with no key, and every later `apt update` fails on it.
  The probe also settles a question §2b left open: §2b repaired with `dpkg --configure`, and a
  re-run of `dpkg -i` with the **same** version over an `iU` package repairs the same way. The
  last two rows (measured later the same day, same package) show it also repairs a package
  already `ii` whose conffile was deleted after configuration.

  **The repair reaches a machine only when the call runs.** Each R5 call sits behind its
  caller's install guard: `_install_ubuntu_powershell` returns early when `_pwsh_probe_runs`
  succeeds (`lib/linux_ubuntu.sh:171`), and `check_and_install_nala` installs only when nala is
  not `ii` (`lib/helpers.sh:270`). So on a machine where pwsh or nala already works and the
  vendor keyring was deleted afterwards, the call is skipped and nothing is restored; the symptom
  there is `apt update` failing on a missing `signed-by` file. This spec does not change the
  guards. That state goes to the backlog (R19).

### Mechanism

A shared array in `lib/constants.sh`:

```bash
readonly -a APT_CONFFILE_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
```

- Every `sudo … apt|apt-get|nala` call in `lib/` whose verb configures packages (`install`,
  `reinstall`, `upgrade`, `full-upgrade`, `dist-upgrade`, `build-dep`) carries
  `"${APT_CONFFILE_OPTS[@]}"`. apt accepts `-o` before or after the verb, and so does the gate
  (see Enforcement), so placement is free. In the xargs lines the array is in the fixed part of the
  command, so it expands before xargs runs and reaches every nala invocation. The #280
  `full-upgrade` site moves onto the array. `remove`, `purge`, `autoremove` and `autopurge`
  configure nothing and are left alone.
- The three archive-setup `dpkg` calls carry `--force-confdef --force-confold --force-confmiss`
  as dpkg flags (dpkg does not take `-o`). A comment at each site says why confmiss is there
  and nowhere else. No other `dpkg -i`/`--install` exists in `lib/`, `setup_env.sh` or
  `scripts/` today; one added later needs confdef+confold from the gate and gets confmiss only
  by adding it to the gate's allow-set (see Enforcement).
- **Kept-conffile doctor check.** confold means the operator is no longer prompted when a package
  ships a changed conffile; dpkg writes the package copy beside it as `<file>.dpkg-dist` and moves
  on. ucf-managed configs (17 registered in `/var/lib/ucf/hashfile` on claude, among them
  `/etc/default/grub` and `apt.conf.d/50unattended-upgrades`) do the same under
  `DEBIAN_FRONTEND=noninteractive` but write `<file>.ucf-dist`. A new `_doctor_check_conffile_dist`
  (`lib/helpers.sh`), registered in `run_doctor`, runs on Linux only (`[[ -n ${LINUX} ]] || return 0`,
  the same early-return shape `_doctor_check_gnu_coreutils` uses with `RESOLUTE`). It reads `<root>`
  from a seam `_OVERRIDE_CONFFILE_DIST_ROOT` defaulting to `/etc`. If `<root>` is not a readable
  directory it emits one `doctor_warn` saying the scan could not run, and stops: `find` exits 1
  both for a missing root and for the unreadable subdirectories every real `/etc` has, so its exit
  code cannot separate "clean" from "never searched", and a PASS there would be false. Otherwise it
  runs `find <root> \( -name '*.dpkg-dist' -o -name '*.ucf-dist' \)`. Each file gets one
  `doctor_warn` naming it and the remedy (`diff` it against the live file, merge what you want,
  delete it; an empty diff means just delete it); none gives one `doctor_pass`.
  `*.dpkg-new` and `*.ucf-new` are not matched: they mark an interrupted install, a different state
  with a different remedy. WARN does not fail doctor. The file keeps being reported until the
  operator resolves it, which is the point: confold took away the one-time prompt, and a one-time
  warning would repeat the loss.

  Why not "files created during this run": dpkg extracts with the archive's mtime and the rename to
  `.dpkg-dist` keeps it. Measured on claude, 2026-10-03, same probe package with its conffile
  stamped 2020-01-01, upgraded under confold after an edit: the `.dpkg-dist` had mtime
  `2020-01-01 00:00:00` and ctime of the install, and `find -newer <run marker>` found 0 files
  where `-cnewer` found 1. A presence check needs no timestamp at all.

  Boundary: `find` runs unprivileged with stderr discarded, so a `.dpkg-dist` under a root-only
  directory is missed. Measured on claude: 7 `/etc` directories are unreadable to the user
  (`/etc/multipath`, `/etc/credstore`, `/etc/credstore.encrypted`, `/etc/lvm/backup`,
  `/etc/lvm/archive`, `/etc/polkit-1/rules.d`, `/etc/ssl/private`), and none of the 1028
  conffiles `dpkg-query -W -f='${Conffiles}'` lists lives under any of them. That is one machine;
  the helper's header comment states the boundary. Also on claude: 0 `.dpkg-dist` files exist,
  unprivileged or under sudo, but `/etc/default/grub.ucf-dist` does, byte-identical to
  `/etc/default/grub`. The check will WARN on it on its first run there, and the remedy is to
  delete it.

Rejected:

- **A wrapper function (`apt_install`).** xargs execs binaries and cannot call a shell function.
  And `tests/scripts/dpkg_sudo_frontend.bats` lists "a wrapper between sudo and the tool" as a
  blind spot, so a wrapper would shrink what the existing gate can see.
- **Literal flags at every site.** The same two-option string copied to every site, with nothing
  that keeps the copies equal.
- **An `/etc/apt/apt.conf.d/` drop-in.** It writes system config and changes the operator's own
  interactive apt behaviour. Operator ruled it out.

### Enforcement

`tests/scripts/dpkg_sudo_frontend.bats` already tokenizes every dpkg-running `sudo` call in the
tracked `lib/*.sh`, `setup_env.sh` and `scripts/*.sh` files and judges `DEBIAN_FRONTEND`. It gains
a second, independent verdict over the same call set:

- An `apt`/`apt-get`/`nala` call whose verb is one of the six configuring verbs is `ok` only if
  it carries the `"${APT_CONFFILE_OPTS[@]}"` token, or both
  `Dpkg::Options::=--force-confdef` and `Dpkg::Options::=--force-confold` literally, anywhere in
  the call.
- A `dpkg` call with `-i`, `--install` or `--configure` is `ok` only if it carries
  `--force-confdef` and `--force-confold` anywhere in the call, not only among the leading flags.
  dpkg accepts force options after the archive path, so a leading-flags-only scan would report a
  correct call `bad`.
- **`classify()` learns the array token.** It already skips `-o`, `-c` and `-t` with their values
  when looking for the verb. It now also skips a `"${APT_CONFFILE_OPTS[@]}"` token, so
  `apt "${APT_CONFFILE_OPTS[@]}" install x` is classified as an `install` instead of dropping out
  of both verdicts as verb `"${APT_CONFFILE_OPTS[@]}"`. This is our own token, not a new shell
  form, so it does not conflict with the file's "do not teach the tokenizer a new shell form"
  rule. That rule exists for third-party constructs that would otherwise be false positives.
- **confmiss allow-set.** The test holds an explicit list of the three archive-setup debs. Each
  `dpkg` record naming one of them must carry `--force-confmiss`. No other record may. Each name
  must match exactly one record, so a reworded or deleted line fails instead of passing
  "no other call carries it" vacuously.
- **Non-vacuity, per verdict.** The frontend verdict keeps its non-empty guard over the whole call
  set. The conffile verdict asserts separately that the number of records it **judged** is
  greater than zero, because `remove`/`autoremove` calls keep the shared set non-empty even if
  the configuring-verb classifier matches nothing.
- **Failure message.** A `bad` conffile record prints the file and line plus the fix: add
  `"${APT_CONFFILE_OPTS[@]}"` (or, in a file that cannot source `lib/constants.sh`, the two
  literal `-o Dpkg::Options::=` options) to an apt/apt-get/nala call, or
  `--force-confdef --force-confold` to a `dpkg` call. It names the knowledge doc section for why.

What the token check cannot see: the array's contents, and a token sitting in a trailing comment
(`judge` does not strip trailing comments, already a listed false-positive class for the frontend
verdict). The argv tests in Testing step 2 are the only check on what the array actually holds,
so they are required, not optional. The existing blind-spot list applies unchanged to the new
verdict. The call count is not restated here; it is derived by the tokenizer.

## Testing

TDD, vertical slices:

1. **Gate first.** Fixture cases for the new verdict, then run it against the real tree and watch
   it go red on the unfixed sites before fixing any of them.
2. **Behaviour, one test per call shape.** An argv-recording stub on `PATH` for `nala`, `apt` and
   `dpkg`, reached through `tests/mocks/sudo`. Assert the recorded argv contains each option as a
   separate argument for an xargs+nala site, a direct `apt install` site, the powershell
   `dpkg -i` and one volian `dpkg --install`, plus `--force-confmiss` for the last two. This shows
   the array expands at run time, which a text check cannot.
3. **Kept-conffile doctor check.** Point `_OVERRIDE_CONFFILE_DIST_ROOT` at a fixture directory
   (the real `/etc` is never searched under bats). Cases: a `.dpkg-dist` and a `.ucf-dist` in a
   nested subdirectory are each reported with path and remedy; a `.dpkg-dist` whose mtime is set to
   2020 with `touch -d` is still reported, pinning the measured defect class; a `.dpkg-new` is not
   reported; an empty root gives one PASS and no WARN; a missing root gives one WARN and no PASS;
   `LINUX` unset gives no output; `_DOCTOR_FAILED` stays `0` (`lib/helpers.sh` initialises it to
   0, so "unset" is never the state). The end-to-end `run_doctor` tests stub every sub-check by
   name: 4 in `tests/setup_env/unit.bats` and 1 in `tests/setup_env/plugin_node_paths.bats`, as
   counted at `69642b86`. Each gains a `_doctor_check_conffile_dist` stub; re-count with
   `grep -rn '_doctor_check_plugin_node_paths() {' tests` before relying on these numbers.
4. **Mutation check.** Remove `"${APT_CONFFILE_OPTS[@]}"` from one xargs line and confirm both
   the gate and the argv test go red. Remove `--force-confmiss` from one volian line and confirm
   the confmiss check goes red. Make the configuring-verb list match nothing and confirm the
   judged-count assertion goes red. Make the doctor check's `find` match nothing and confirm the
   nested-file and old-mtime cases go red.

The real-tool proof is V1 and V2 below. The bats suite never runs a real apt or dpkg.

## Requirements

- **R1.** `[PR1]` `lib/constants.sh` defines `APT_CONFFILE_OPTS` as a readonly array holding exactly `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold`.
- **R2.** `[PR1]` Every `sudo` call the R8 gate judges as `apt`, `apt-get` or `nala` with `install`, `reinstall`, `upgrade`, `full-upgrade`, `dist-upgrade` or `build-dep`, in any tracked `lib/*.sh`, `setup_env.sh` or `scripts/*.sh`, carries `"${APT_CONFFILE_OPTS[@]}"`, or, in a file that cannot source `lib/constants.sh`, the two `-o Dpkg::Options::=` options literally.
- **R3.** `[PR1]` The five `xargs -r sudo … nala install -y` lines in `lib/linux_ubuntu.sh` carry `"${APT_CONFFILE_OPTS[@]}"` in the fixed part of the command, before the package names xargs appends.
- **R4.** `[PR1]` `update_apt_packages`' `nala full-upgrade` in `lib/linux_shared.sh` uses `"${APT_CONFFILE_OPTS[@]}"` in place of its literal options.
- **R5.** `[PR1]` `_install_ubuntu_powershell`'s `dpkg -i` of `packages-microsoft-prod.deb` and `check_and_install_nala`'s two `dpkg --install` calls of `volian-archive-keyring_0.2.0_all.deb` and `volian-archive-nala_0.2.0_all.deb` each carry `--force-confdef --force-confold --force-confmiss`, with a comment at each saying why confmiss is there and nowhere else.
- **R6.** `[PR1]` No apt, apt-get, nala or dpkg call in `lib/`, `setup_env.sh` or `scripts/` other than the three R5 calls carries `--force-confmiss`.
- **R7.** `[PR1]` `scripts/bootstrap_linux.sh`'s `apt-get install` carries `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold` literally.
- **R8.** `[PR1]` `tests/scripts/dpkg_sudo_frontend.bats` gains a conffile verdict over the same call set as its frontend verdict: configuring apt/apt-get/nala verbs need the array token or both literal options anywhere in the call, and `dpkg -i`/`--install`/`--configure` need `--force-confdef` and `--force-confold` anywhere in the call. It fails on any `bad` record.
- **R9.** `[PR1]` The conffile verdict asserts its own judged-record count is greater than zero, separate from the frontend verdict's non-empty guard.
- **R10.** `[PR1]` `classify()` skips a `"${APT_CONFFILE_OPTS[@]}"` token when looking for the verb, so `apt "${APT_CONFFILE_OPTS[@]}" install x` is classified as `install`.
- **R11.** `[PR1]` The test holds an explicit allow-set of the three R5 deb names; each name matches exactly one `dpkg` record, that record carries `--force-confmiss`, and no record outside the set does.
- **R12.** `[PR1]` A `bad` conffile record's failure message names the file and line, the array (or the two literal options for a file that cannot source `lib/constants.sh`) as the apt fix, `--force-confdef --force-confold` as the dpkg fix, and `dotfiles-apt-upgrade-hazards.md` §2.
- **R13.** `[PR1]` Fixture cases cover: array token after the verb `ok`, array token before the verb `ok`, literal pair `ok`, missing options `bad`, only one of the pair `bad`, dpkg force flags after the archive path `ok`, and a `remove` call not judged.
- **R14.** `[PR1]` Argv-recording tests assert the options arrive as separate arguments at an xargs+nala site, a direct `apt install` site, the powershell `dpkg -i` and one volian `dpkg --install`, the last two also receiving `--force-confmiss`.
- **R15.** `[PR1]` `_doctor_check_conffile_dist` in `lib/helpers.sh`, called from `run_doctor`, returns immediately unless `LINUX` is set, and lists every `*.dpkg-dist` and `*.ucf-dist` under the root given by `_OVERRIDE_CONFFILE_DIST_ROOT` (default `/etc`) with no timestamp test, emitting one `doctor_warn` per file naming it and the `diff`/merge/delete remedy, and one `doctor_pass` when there are none.
- **R16.** `[PR1]` When the root is not a readable directory, `_doctor_check_conffile_dist` emits one `doctor_warn` saying the scan could not run and no `doctor_pass`; it never calls `doctor_fail`; its header comment states that an unprivileged `find` misses files under root-only directories and that `*.dpkg-new`/`*.ucf-new` are deliberately not matched.
- **R17.** `[PR1]` Tests cover: a nested `.dpkg-dist` and a nested `.ucf-dist` each reported with path and remedy, a `.dpkg-dist` with a 2020 mtime still reported, a `.dpkg-new` not reported, an empty root giving one PASS, a missing root giving one WARN and no PASS, `LINUX` unset giving no output, and `_DOCTOR_FAILED` equal to 0 after every case.
- **R18.** `[PR1]` Every end-to-end `run_doctor` test that stubs sub-checks by name also stubs `_doctor_check_conffile_dist`.
- **R19.** `[PR1]` One backlog row covers machines this change does not repair: packages other than the three R5 packages already left at `iU` by an earlier conffile failure, and the three R5 packages at `ii` with a vendor keyring or source deleted, which the R5 callers' install guards skip.
- **V1.** On claude, re-run the §2 `dotfiles-cfprobe` probe through a changed `xargs … nala install` line (stdin `/dev/null`, edited conffile, v1 to v2). Expect rc 0, state `ii`, local edit kept, `.dpkg-dist` written, and `setup_env.sh -t doctor` WARNing on it. Then delete it and `/etc/default/grub.ucf-dist` (identical to `/etc/default/grub`, verified by `diff`) and confirm the next doctor run PASSes.
- **V2.** Done at spec time on claude, 2026-10-03, recorded in Decision: same-version `dpkg -i --force-confdef --force-confold --force-confmiss` over an `iU` package with a deleted conffile gave rc 0, `ii`, file restored; without confmiss, rc 0, `ii`, file still absent. Before merge, re-run with the R5 flags copied from the final code over both starting states the Decision table records: `iU` with the conffile deleted, and `ii` with the conffile deleted (same-version reinstall). Expect rc 0, `ii`, file restored in both.
- **V3.** Mutation: dropping the array from one xargs line turns both the R8 gate and the R14 argv test red; dropping `--force-confmiss` from one volian line turns the R11 check red; making the configuring-verb list match nothing turns the R9 count red; making the doctor `find` match nothing turns the R17 reported-file cases red.
- **N1.** No file is written under `/etc/apt/apt.conf.d/` or anywhere else outside the repo.
- **N2.** `--force-confmiss` is not added to any call other than the three R5 calls.
- **N3.** `remove`, `purge`, `autoremove` and `autopurge` calls are not changed.
- **N4.** `Vagrantfile` is not changed; it has its own backlog row.
- **N5.** No wrapper function is introduced between `sudo` and apt, apt-get, nala or dpkg.
- **N6.** `_doctor_check_conffile_dist` does not run `find` under sudo, and does not move, delete or merge any `.dpkg-dist` or `.ucf-dist` file.
- **N7.** No `.dpkg-dist` reporting is added to `run_update`, `run_setup_or_developer` or `_UPDATE_SECTION_ORDER`.

## Multi-Lens Review

Reviewed at commit: `992dcc3d` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building; premises verified (5 xargs sites at `lib/linux_ubuntu.sh:46,47,52,53,70`, #280 literals at `lib/linux_shared.sh:70-72`, R5 at `:202`, R7 at `scripts/bootstrap_linux.sh:35`, before-verb placement argument correct per `classify()`). Gap: `lib/helpers.sh:275,277` (`dpkg --install` of the volian keyring and nala debs, Noble path of `check_and_install_nala`) are judged by R8 but named by no requirement, so Phase 2's "watch it go red" step hits them with no mandate. R6/N2 is an absence check protected only by the shared non-empty call set.
Assumption: the xargs sites always take nala's apt path (honouring `Dpkg::Options`) rather than `dpkg -i`; refuted if a package list holds a local `.deb` path. Checked by the author: `grep -nE '\.deb|/' ubuntu_*_packages.txt` returns nothing.
Disposition: Addressed (operator, 2026-10-03) — `helpers.sh:275,277` added to R5 with confmiss (operator chose confmiss for the volian keyring/source debs, same class as packages-microsoft-prod); R6 confmiss absence now backed by R11's exact-match allow-set. Assumption checked: `grep -nE '\.deb|/' ubuntu_*_packages.txt` returns nothing.

### Ergonomics

Finding: (1) same `helpers.sh:275,277` gap. (2) The conffile verdict's empty-set guard is over the frontend call set, which `remove`/`autoremove` keep non-empty, so a classifier that judges zero configuring calls passes. (3) Array-before-verb drops out of both verdicts silently; the existing failure message names only DEBIAN_FRONTEND and the spec defines none for the new verdict. (4) Advisory: nothing surfaces new `.dpkg-dist` files, so an upstream conffile change now arrives unannounced; suggests a `-t update`/doctor advisory.
Assumption: `dpkg -i --force-confmiss` repairs the §2b state (same-version deb over an `iU` package with a deleted conffile). §2b measured `dpkg --configure --force-confmiss`; V2 tests a newer version over `ii`. Settled by a throwaway-package probe on claude.
Disposition: Addressed (operator, 2026-10-03) — (1) as Goal-Fit; (2) R9 judged-count; (3) R10 `classify()` skips the array token, placement rule removed, R12 failure message; (4) operator chose to add it to this spec: R15–R18 `.dpkg-dist` advisory. Assumption probed on claude before disposition: holds (Decision table, V2).

### Risk

Finding: Sound and proportionate. Probes: `nala install --help` documents `-o` pass-through (nala 0.16.0); `dpkg --force-help` lists confdef/confold/confmiss; the array token survives the tokenizer as one token; re-sourcing a `readonly -a` behaves like the file's existing readonly scalars; no `lib/` code deletes `microsoft-prod.gpg` (only the azure legacy cleanup at `linux_ubuntu.sh:641-645` removes Microsoft files, different ones). Gaps: (1) judged-subset emptiness, as Ergonomics (2); the confmiss check must assert exactly one matched record, or a reworded line passes "no other call does" vacuously. (2) The token check cannot see the array's contents or a token in a trailing comment; R10 is the only contents check and must stay. (3) dpkg flag placement unspecified; copying `classify()`'s leading-flag loop would false-fail a flag after the `.deb` path. (4) `helpers.sh:275,277`; volian-archive-keyring is keyring-only, so the confmiss argument applies to it too — give it confmiss or say why not.
Assumption: same as Ergonomics — same-version `dpkg -i --force-confmiss` over an `iU` package with a deleted conffile ends `ii` with the file restored.
Disposition: Addressed (operator, 2026-10-03) — (1) R9 and R11; (2) R14 argv tests stated as the only contents check, required; (3) dpkg force flags matched anywhere in the call, R8/R13; (4) volian debs in R5 with confmiss. Assumption probed: holds; confmiss shown load-bearing by the confold-only control.

### Round 2

Reviewed at commit: `931f40e0` (round-1 revisions). All three lenses re-run in full, since round 1 changed design substance.

**Goal-Fit (r2).** Finding: R1–R14 core proportionate and sound. The run-scoped `.dpkg-dist` advisory (old R15–R18) reports nothing in production: dpkg keeps the archive mtime on `.dpkg-dist`, so `find -newer started_at` misses it; four of its six cases pass on a helper that finds nothing. Simpler path: one persistent `doctor` check with no marker. Assumption: `.dpkg-dist` mtime is the archive's, not install time. Measured by the author on claude with the probe package: mtime `2020-01-01`, `-newer` 0, `-cnewer` 1 — holds.
Disposition: Addressed (operator, 2026-10-03) — operator chose the doctor check; old R15–R18 replaced by `_doctor_check_dpkg_dist` [renamed `_doctor_check_conffile_dist` in round 3] (new R15–R18), N7 added.

**Ergonomics (r2).** Finding: same mtime defect; R15/R17 mismatch (helper's only output was `log_warn` on stderr, so `run_update` had no found/none signal); no SKIP arms for the `conffiles` row; warning shown once then gone; unreadable-directory misses invisible to the operator. Assumption: same as Goal-Fit, settled the same way.
Disposition: Addressed (operator, 2026-10-03) — doctor check removes the marker, the summary row and the SKIP question; the warning persists until resolved and carries the `diff` remedy; unreadable directories measured (7 on claude, 0 conffiles under them) and stated as a boundary in R16.

**Risk (r2).** Finding: same mtime defect, with a `dpkg-deb -x` reproduction; `_DOTFILES_RUN_TMPDIR`/`started_at` wiring, summary width, ordering tests, volian confmiss blast radius, R11 exact-match and the array-token skip all checked clean. Assumption: whether conffiles that would get a `.dpkg-dist` live under root-only `/etc` directories. Measured by the author on claude: 7 unreadable directories, 0 of 1028 conffiles under them — holds on that machine.
Disposition: Addressed (operator, 2026-10-03) — advisory replaced by the doctor check; boundary measured and recorded in Decision.

### Round 3 (scoped)

Reviewed at commit: `69642b86`. Risk lens only, scoped to the new doctor-check text (Decision bullet, Testing steps 3–4, R15–R18, V1, V3, N6–N7); the rest was unchanged since round 2.

**Risk (r3).** Finding: (1) ucf-managed configs keep-local as `*.ucf-dist`, which the check never matched; `/etc/default/grub.ucf-dist` already exists on claude (17 ucf-registered files). (2) `find` exits 1 for both a missing root and the unreadable subdirectories of a real `/etc`, so "none" can PASS over a scan that never ran. (3) `_DOCTOR_FAILED` is initialised to 0, never unset; the stubbing tests are 4 in `unit.bats` plus 1 in `plugin_node_paths.bats`. macOS gating, WARN-cannot-fail, speed (8 ms) and mounts checked clean. Assumption: every kept-local divergence lands as `*.dpkg-dist` — refuted on claude by the ucf class.
Disposition: Addressed (operator, 2026-10-03) — operator chose to widen to `*.ucf-dist` (check renamed `_doctor_check_conffile_dist`); root-readable guard WARNs instead of PASSing; R17 asserts `-eq 0`; Testing step 3 names both stub files. Operator chose no further lens round: every round has removed surface, and these fixes are a pattern, a guard and wording.
[Correction, 2026-10-03, from the operator's external architectural review: "every round has removed surface" is false for the change as a whole. Round 1 added the run-scoped advisory, round 2 replaced it with a doctor check (still a component round 0 did not have), and round 3 widened its pattern and added a guard. Shrinkage held only within the advisory component. The stop rests on artifact location instead: round 3's findings were a pattern, a guard and wording inside the newest text, and none touched the R1–R14 core already re-verified in rounds 1 and 2.]

### External review (operator's architect session, after round 3)

Findings: (1) the R5 confmiss repair only runs past each caller's install guard, so an `ii` package with a deleted keyring on a machine with working pwsh/nala is never repaired, and the probe had not measured `ii`; (2) R8 judges `scripts/*.sh` but only R7 named a `scripts/` site; (3) the round-3 stop rationale read the direction signal on the component rather than the whole change.
Disposition: Addressed (author, 2026-10-03, at operator's direction) — (1) measured on claude: same-version reinstall over `ii` with the conffile deleted restores it only with confmiss; guard dependency stated in Decision, R19 widened to the guarded `ii` state; (2) R2 widened to every call the gate judges, with the literal-options rule; `git ls-files 'scripts/*.sh'` shows `bootstrap_linux.sh:35` is the only such site today; (3) correction note added above.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
