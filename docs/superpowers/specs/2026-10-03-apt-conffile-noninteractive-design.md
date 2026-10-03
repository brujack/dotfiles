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
- **confmiss only at the `packages-microsoft-prod.deb` `dpkg -i`.** That package carries only
  the Microsoft apt keyring and source, so restoring a deleted file is always right there.
  Elsewhere it would silently undo a deliberate deletion (a cron file or apt source removed to
  disable something), so it is not applied.

### Mechanism

A shared array in `lib/constants.sh`:

```bash
readonly -a APT_CONFFILE_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
```

- Every `sudo … apt|apt-get|nala` call in `lib/` whose verb configures packages (`install`,
  `reinstall`, `upgrade`, `full-upgrade`, `dist-upgrade`, `build-dep`) carries
  `"${APT_CONFFILE_OPTS[@]}"` **after the verb**. Placement matters: the tokenizer reads the
  first non-flag token after the tool as the verb, so `apt "${APT_CONFFILE_OPTS[@]}" install`
  would be read as verb `"${APT_CONFFILE_OPTS[@]}"`, and the call would drop out of both
  verdicts (frontend and conffile) unseen. In the xargs lines the array is in the fixed part of the
  command, so it expands before xargs runs and reaches every nala invocation. The #280
  `full-upgrade` site moves onto the array. `remove`, `purge`, `autoremove` and `autopurge`
  configure nothing and are left alone.
- `_install_ubuntu_powershell`'s `dpkg -i` carries
  `--force-confdef --force-confold --force-confmiss` as dpkg flags (dpkg does not take `-o`).
  A comment on that line says why confmiss is there and nowhere else.
- `scripts/bootstrap_linux.sh` runs before anything under `lib/` is sourced, so it cannot use
  the array. Its single `apt-get install` carries the two `-o Dpkg::Options::=` options
  literally. This puts the bootstrap inside the enforcement scope below instead of carving out
  an exemption for it.

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
  `Dpkg::Options::=--force-confdef` and `Dpkg::Options::=--force-confold` literally.
- A `dpkg` call with `-i`, `--install` or `--configure` is `ok` only if it carries
  `--force-confdef` and `--force-confold`.
- confmiss is checked separately and positively: the `packages-microsoft-prod.deb` call carries
  `--force-confmiss`, and no other call does.

The existing blind-spot list in that file applies unchanged to the new verdict. The call count is
not restated here. It is derived by the tokenizer, and the test fails if the derived set is empty.

## Testing

TDD, vertical slices:

1. **Gate first.** Fixture cases for the new verdict: a configuring call without the options is
   `bad`, with the array token is `ok`, with the literal pair is `ok`, with only one of the pair
   is `bad`, `remove` without options is not judged. Then run the gate against the real tree and
   watch it go red on the unfixed sites before fixing any of them.
2. **Behaviour, one test per call shape.** An argv-recording stub on `PATH` for `nala`, `apt` and
   `dpkg`, reached through `tests/mocks/sudo`. Assert the recorded argv contains each option as a
   separate argument for an xargs+nala site, a direct `apt install` site, and the `dpkg -i` site,
   plus `--force-confmiss` for the last. This shows the array expands at run time, which a text
   check cannot.
3. **Mutation check.** Remove `"${APT_CONFFILE_OPTS[@]}"` from one xargs line and confirm both
   the gate and the argv test go red. Remove `--force-confmiss` and confirm the confmiss check
   goes red.

The real-tool proof is V1 and V2 below. The bats suite never runs a real apt or dpkg.

## Requirements

- **R1.** `[PR1]` `lib/constants.sh` defines `APT_CONFFILE_OPTS` as a readonly array holding exactly `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold`.
- **R2.** `[PR1]` Every `sudo` call in tracked `lib/*.sh` and `setup_env.sh` running `apt`, `apt-get` or `nala` with `install`, `reinstall`, `upgrade`, `full-upgrade`, `dist-upgrade` or `build-dep` carries `"${APT_CONFFILE_OPTS[@]}"`, placed after the verb.
- **R3.** `[PR1]` The five `xargs -r sudo … nala install -y` lines in `lib/linux_ubuntu.sh` carry `"${APT_CONFFILE_OPTS[@]}"` in the fixed part of the command, before the package names xargs appends.
- **R4.** `[PR1]` `update_apt_packages`' `nala full-upgrade` in `lib/linux_shared.sh` uses `"${APT_CONFFILE_OPTS[@]}"` in place of its literal options.
- **R5.** `[PR1]` `_install_ubuntu_powershell`'s `dpkg -i` of `packages-microsoft-prod.deb` carries `--force-confdef --force-confold --force-confmiss`, with a comment saying why confmiss is there and nowhere else.
- **R6.** `[PR1]` No apt, apt-get, nala or dpkg call in `lib/`, `setup_env.sh` or `scripts/` other than the R5 call carries `--force-confmiss`.
- **R7.** `[PR1]` `scripts/bootstrap_linux.sh`'s `apt-get install` carries `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold` literally.
- **R8.** `[PR1]` `tests/scripts/dpkg_sudo_frontend.bats` gains a conffile verdict over the same call set as its frontend verdict: configuring apt/apt-get/nala verbs need the array token or both literal options, and `dpkg -i`/`--install`/`--configure` need `--force-confdef` and `--force-confold`. It fails on any `bad` record and on an empty call set.
- **R9.** `[PR1]` The R8 verdict has fixture cases for: array token `ok`, literal pair `ok`, missing options `bad`, only one of the pair `bad`, and a `remove` call not judged.
- **R10.** `[PR1]` Argv-recording tests assert the options arrive as separate arguments at an xargs+nala site, a direct `apt install` site and the R5 `dpkg -i`, which also receives `--force-confmiss`.
- **R11.** `[PR1]` A backlog row is added for repairing machines already left at `iU` by an earlier conffile failure.
- **V1.** On claude, re-run the §2 `dotfiles-cfprobe` probe through a changed `xargs … nala install` line (stdin `/dev/null`, edited conffile, v1 to v2). Expect rc 0, state `ii`, local edit kept, `.dpkg-dist` written.
- **V2.** On claude, with a throwaway package whose conffile is deleted after install, run `dpkg -i` with the R5 options on a newer version. Expect rc 0, state `ii`, conffile restored.
- **V3.** Mutation: dropping the array from one xargs line turns both the R8 gate and the R10 argv test red, and dropping `--force-confmiss` turns the R6/R5 check red.
- **N1.** No file is written under `/etc/apt/apt.conf.d/` or anywhere else outside the repo.
- **N2.** `--force-confmiss` is not added to any call other than the R5 `dpkg -i`.
- **N3.** `remove`, `purge`, `autoremove` and `autopurge` calls are not changed.
- **N4.** `Vagrantfile` is not changed; it has its own backlog row.
- **N5.** No wrapper function is introduced between `sudo` and apt, apt-get, nala or dpkg.
