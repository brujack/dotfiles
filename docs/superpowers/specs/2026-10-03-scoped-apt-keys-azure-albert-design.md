# Scoped, pinned apt keys for azure-cli and albert

- **Date:** 2026-10-03
- **Backlog row:** "Unscoped Microsoft apt key and http azure-cli source" (P2 — bugs and security)

## Problem

Two apt sources in `lib/linux_ubuntu.sh` trust a key machine-wide:

- **azure-cli** (`_install_ubuntu_cloud_tools`) fetches `microsoft.asc` over plain
  `http://packages.microsoft.com/keys/microsoft.asc`, dearmors it into the global
  `/etc/apt/trusted.gpg.d/microsoft.asc.gpg`, and adds an `http://` source with no
  `signed-by` via `add-apt-repository`.
- **albert** (`_install_ubuntu_gui_tools`, `HAS_SNAP`) fetches its OBS key over `https`
  but writes it into the global `/etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg`, and its
  source is `http://` with no `signed-by`.

A key in `trusted.gpg.d` signs for **every** source on the machine. The azure key fetch has
no transport integrity, so anyone on the path can substitute a key and gain root package
installs on every Linux machine that runs setup. The albert key fetch has transport
integrity, but a compromised OBS project key would still be trusted for Ubuntu's own
archive.

### Premise, measured 2026-10-03

| Claim                                                  | Command                                                                              | Population                                              | Result                                                                                                                              |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------ | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| The global keys exist on live machines                 | `ls /etc/apt/trusted.gpg.d/`                                                         | `claude` and `workstation` (the two Linux dev machines) | both hold `microsoft.asc.gpg` and `home_manuelschneid3r.gpg`                                                                        |
| The global Microsoft key is the one `MS_GPG_FPR` pins  | `gpg --show-keys --with-colons`                                                      | `claude`'s copy                                         | `fpr` `BC528686B50D79E339D3721CEB3E94ADBE1229CF`                                                                                    |
| The vendored `keys/microsoft.asc` can verify azure-cli | `gpg --verify` of `repos/azure-cli/dists/noble/InRelease`                            | that one suite, fetched 2026-10-03                      | signer `EB3E94ADBE1229CF`, the same key                                                                                             |
| Albert's OBS key fingerprint                           | `gpg --show-keys` on `claude`'s global copy                                          | one key                                                 | `A4B83CD05FDF5C5178482D4A1488EB46E192A257`, expires 2027-02-10                                                                      |
| Nothing else depends on the global keys                | grep of `sources.list.d` for `microsoft`/`manuelschneid3r` lines without `signed-by` | `claude` and `workstation`                              | only the azure-cli and albert sources; edge and `microsoft-prod` carry their own `Signed-By`                                        |
| The albert repo serves https end to end                | `curl -sSIL` on a pool `.deb`                                                        | one file, from `claude`'s network location              | `302` to `https://slc-mirror.opensuse.org/…`, then `200`. Mirror choice is geographic, so this proves nothing about other locations |

**A second defect found while verifying.** The existing stale-source purge removes
`packages.microsoft.com_repos_azure-cli.list` and `azure-cli.list`. On both machines the
file `add-apt-repository` actually wrote is
`archive_uri-http_packages_microsoft_com_repos_azure-cli_-resolute.list`, which neither
`rm` matches. The test guarding the purge (`linux_ubuntu.bats`, "removes stale azure-cli
sources before add-apt-repository") greps the mock call log for an `rm` line, so it passes
whatever filename `add-apt-repository` produces.

## Design

Revised after review round 2 (operator, 2026-10-03): azure-cli moves to linuxbrew, so the
azure half no longer needs an apt key at all. Only albert keeps an apt source.

### 1. azure-cli moves to linuxbrew

- Add `azure-cli` to the formula list in `_install_ubuntu_brew_packages`. Linuxbrew ships a
  `2.90.0` `x86_64_linux` bottle, the same version apt serves, and macOS already installs it
  from `Brewfile:12`. There is no `arm64_linux` bottle; no Linux machine in the fleet is
  arm64 (accepted).
- The azure block in `_install_ubuntu_cloud_tools` is deleted: the `http://` key fetch, the
  `add-apt-repository` call, the stale-source `rm` lines and `apt install azure-cli`.
- **Migration, in `_install_ubuntu_brew_packages` after the formula loop:** only when
  `brew_formula_installed azure-cli` succeeds **and** `dpkg -s azure-cli` reports it
  installed, run `sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y azure-cli`. Gating
  on the brew install means a failed brew install never leaves the machine with no `az`.
  The removal's failure is added to `_failed`.
- `az` then resolves from linuxbrew, which interactive zsh puts on `PATH`
  (`6_path.zsh`). Nothing in `lib/` or `setup_env.sh` invokes `az`; a non-interactive actor
  loses `/usr/bin/az` (accepted: no such caller exists).

### 2. One fail-closed keyring builder

The existing `_edge_keyring_has_pinned_fpr` becomes `_keyring_has_pinned_fpr <ring> <fpr>`.
A new `_build_pinned_keyring <key_file> <keyring> <fpr>`:

1. Runs `gpg --dearmor < key_file | sudo tee keyring > /dev/null` through `_MS_GPG_BIN`
   (default `gpg`).
2. Succeeds only if gpg's own exit status (`PIPESTATUS[0]`) is 0 **and** the
   `--show-keys --with-colons` listing holds exactly one `pub:` record whose `fpr` equals
   the pin. An empty keyring fails the count.
3. On any failure, `sudo rm -f` the keyring and return 1.

**The single-key rule is new and load-bearing.** Today's check passes if *any* `fpr:` line
matches. Albert's key arrives over the network, so a response carrying the real key plus an
attacker's would pass and `signed-by` would trust both. Measured: two concatenated armor
blocks dearmor to 2 `pub:` records on gpg 2.4.8 and 2.5.24.

Key validity (revoked, expired) is not checked. apt rejects a revoked or expired signer
itself, so a check here would only move the failure from `apt update` to a WARN.

`_install_ubuntu_edge_source` moves onto the shared builder. The vendored
`keys/microsoft.asc` holds exactly one `pub:`, so edge's behaviour does not change, and its
existing tests are the regression check. `_MS_GPG_BIN` keeps its name although it now also
governs the albert key: renaming it would edit edge's tests. The comment at
`lib/linux_ubuntu.sh:789` ("unseamed albert writes") is updated.

### 3. `_install_ubuntu_albert`

Extracted from `_install_ubuntu_gui_tools`; still gated on `HAS_SNAP`.

- New constant `ALBERT_GPG_FPR="A4B83CD05FDF5C5178482D4A1488EB46E192A257"` in
  `lib/constants.sh`.
- The key is fetched with
  `curl -fsSL "${_ALBERT_KEY_URL:-https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_<release>/Release.key}"`
  into a temp file under `mktemp -d "${_ALBERT_TMP_ROOT:-${TMPDIR:-/tmp}}/albert-key.XXXXXXXX"`,
  removed on every path. This is the `_RELEASE_TMP_ROOT` pattern (`lib/linux_ubuntu.sh:909`):
  BSD `mktemp` ignores `TMPDIR` without a template.
- The key is fetched rather than vendored (operator decision, 2026-10-03). OBS extends key
  expiry without changing the fingerprint, so a fingerprint pin follows an extension.
- On success, the shared builder produces `${_APT_KEYRINGS_DIR}/albert-obs.gpg`, then
  `${_APT_SOURCES_DIR}/albert.list` is written as
  `deb [signed-by=<keyring>] https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_<release>/ /`,
  then `apt install albert`. Returns 0.
- **Fetch failure** (curl non-zero): keep the existing `albert.list` and `albert-obs.gpg`
  untouched, since both were verified against the pin when written. `log_warn "albert key
  fetch failed (<url>); keeping last verified source"`, skip `apt install`, return 2.
  (Operator decision, 2026-10-03: a network blip must not drop a working source.)
- **Key failure** (the builder returns 1: wrong fingerprint, more than one key, gpg
  failure): remove `albert.list`, WARN with the fetched fingerprint(s) beside
  `ALBERT_GPG_FPR` and the remedy (verify the new key out of band, then edit
  `lib/constants.sh`), skip `apt install`, return 2.
- **Key expiry.** The key on the fleet expires 2027-02-10. Only `-t developer`/`-t setup`
  refetch it; `-t update` runs `update_apt_packages` alone (`lib/workflows.sh:860-862`).
  After an OBS extension, `-t update` reports `EXPKEYSIG` for this source until
  `-t developer` is re-run, which is the remedy. This is today's behaviour too.

### 4. Return codes

`_install_ubuntu_albert` returns 0 or 2. `_install_ubuntu_gui_tools` must return non-zero
after the rest of the step runs when it does, so the step loop (`lib/linux_ubuntu.sh:28`)
names `gui_tools` in `ubuntu packages: failed:`. The caller returns whatever its last
command returned today, and that must not change on the success path: capture the child's
rc and return non-zero at the end only when it failed. A trailing `return "${_rc}"` with
`_rc=0` would mask the last command's status.

What the operator sees: `run_setup_or_developer` maps rc 2 to `log_warn "ubuntu packages
incomplete"` and `-t developer` **exits 0**. The failure is reported on stderr only.

### 5. Legacy cleanup

Runs on every pass, idempotent, and before any new key work, so it happens on the success
and the failure path alike. Without it, a machine set up before this change keeps the global
keys and nothing changes there.

In `_install_ubuntu_cloud_tools`, where the azure block was:

- `${_APT_TRUSTED_DIR}/microsoft.asc.gpg`
- `${_APT_SOURCES_DIR}/archive_uri-http_packages_microsoft_com_repos_azure-cli_-*.list`
  (globbed: `add-apt-repository` puts the host codename in the name)
- `${_APT_SOURCES_DIR}/packages.microsoft.com_repos_azure-cli.list`
- `${_APT_SOURCES_DIR}/azure-cli.list`

In `_install_ubuntu_gui_tools`, **outside** the `HAS_SNAP` gate, before the albert call:

- `${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg`
- `${_APT_SOURCES_DIR}/home:manuelschneid3r.list`

Outside the gate because a machine-wide third-party key must go whatever the profile:
`cruncher` (`wsl2_workstation`) has no `snap` capability, so `_install_ubuntu_albert` never
runs there, and a key left from an earlier profile would otherwise stay trusted.

The azure source must go with the key: a source left behind without its key fails
`apt update` with `NO_PUBKEY`.

### Seams

`tests/mocks/sudo` execs real commands, so an unseamed path is a real write to `/etc/apt`
(`tdd.md` E2). New variables, defaulting to the production values, set at setup scope in
`tests/setup_env/linux_ubuntu.bats`:

| variable | default |
| --- | --- |
| `_APT_SOURCES_DIR` | `/etc/apt/sources.list.d` |
| `_APT_TRUSTED_DIR` | `/etc/apt/trusted.gpg.d` |
| `_APT_KEYRINGS_DIR` | `/usr/share/keyrings` |
| `_ALBERT_TMP_ROOT` | `${TMPDIR:-/tmp}` |

`_ALBERT_KEY_URL` is a production escape hatch for the key URL. Tests stay off the network
without it: `tests/mocks/curl` is first on `PATH`, never fetches, and writes
`MOCK_CURL_STDOUT` to the `-o` target (it only `touch`es the target when that is unset).
Tests feed the fixture's armored text through `MOCK_CURL_STDOUT` per test, never at setup
scope (every curl call in the file would then emit the key), and drive the fetch failure
with `MOCK_CURL_EXIT`.

### Testing

Real gpg via `_MS_GPG_BIN`, as the edge tests do. A test-only fixture,
`tests/fixtures/albert-obs.asc`, holds the OBS public key (it expires 2027-02-10; the check
is by fingerprint and `--show-keys` lists expired keys, so expiry does not break the tests).

| case | expected |
| --- | --- |
| builder, pinned key | keyring holds exactly the pinned fingerprint; returns 0 |
| builder, wrong key | keyring path pre-seeded and asserted present; then returns 1 and keyring absent |
| builder, pinned key plus a second key appended | as above |
| builder, truncated key | as above |
| builder, gpg exits non-zero | as above |
| albert, good key | `albert.list` holds `https://` and `signed-by=`; `apt install albert` called; returns 0 |
| albert, fetch fails (`MOCK_CURL_EXIT`) | a pre-seeded `albert.list` and keyring asserted present, then unchanged afterwards; WARN names the URL; no install; returns 2 |
| albert, wrong fingerprint | pre-seeded `albert.list` asserted present, then absent; WARN prints the fetched fingerprint and `ALBERT_GPG_FPR`; no install; returns 2 |
| albert, temp dir | `_ALBERT_TMP_ROOT` holds a directory during the run (asserted via the fixture) and is empty after, on both the success and fetch-fail paths |
| gui_tools propagation | albert returning 2 makes `_install_ubuntu_gui_tools` return non-zero, and `install_ubuntu_packages` names `gui_tools` |
| gui_tools success path | with albert succeeding, `_install_ubuntu_gui_tools`' return is unchanged from today |
| legacy cleanup | every file in §5 seeded and asserted present; then removed, including a glob-matched `archive_uri-…-resolute.list` |
| albert legacy cleanup without `HAS_SNAP` | seeded and asserted present; `HAS_SNAP` unset; both albert legacy files removed and `_install_ubuntu_albert` not called |
| legacy cleanup on a key failure | seeded and asserted present; global keys removed even when the albert keyring fails |
| second run | `albert.list` asserted present; byte-identical after a second run |
| azure brew install | `brew install azure-cli` called by `_install_ubuntu_brew_packages` |
| azure apt migration | with brew `azure-cli` present and `dpkg -s azure-cli` succeeding: `apt-get remove -y azure-cli` called with `DEBIAN_FRONTEND=noninteractive` on the sudo line |
| azure apt migration skipped | with brew `azure-cli` absent: no `apt-get remove azure-cli` |
| no azure apt path left | `_install_ubuntu_cloud_tools` calls neither `add-apt-repository` nor `apt install azure-cli` |

Every row asserting an absence, an equality or an unchanged file carries its own presence
assertion in the same test (`tdd.md` E5).

Existing tests that change: `:1416` ("always calls apt install azure-cli"), `:1454`
(`dpkg --print-architecture`), `:1487` (noble on RESOLUTE) and `:1497` (stale-source purge,
greps the mock log) are deleted or replaced by the azure and legacy rows above. `:1568`
("HAS_SNAP installs albert") sets `MOCK_CURL_STDOUT` to the fixture, since the empty
`touch`ed key would now fail the builder.

## Verification after merge

Run `./setup_env.sh -t developer` on **both** `claude` and `workstation` (both carry the
old apt azure-cli install, the `http` source and both global keys, measured 2026-10-03),
then on each:

- `ls /etc/apt/trusted.gpg.d/` lists neither legacy key.
- `/etc/apt/sources.list.d/` holds `albert.list` (`https`, `signed-by`) and no azure-cli
  file.
- `sudo apt update` exits 0 with no `NO_PUBKEY` or `EXPKEYSIG`.
- `dpkg -s azure-cli` reports not installed; `command -v az` resolves under
  `/home/linuxbrew`; `az version` and `albert --version` run.
- `cruncher` (WSL2) was unreachable at review time. Before it next runs setup, check that
  `grep -rLE 'signed-by|Signed-By' /etc/apt/sources.list.d/ | xargs -r grep -lE 'microsoft|manuelschneid3r'`
  prints only the two legacy files.
- Albert pool `.deb`s redirect to a geo-chosen mirror and apt refuses https-to-http. Only
  `claude`'s location was measured (10 of 10 https, no http mirror in the mirrorlist);
  accepted at review.

## Out of scope

- Per-command failure checking inside `_install_ubuntu_*` steps (its own backlog row).
- VirtualBox's `http://` source, which is already `signed-by`.
- Edge's source logic, beyond moving onto the shared builder.
- A doctor check for albert's or azure's source (review round 2, accepted).

## Requirements

- **R1.** `_build_pinned_keyring` returns 1 and leaves no keyring when gpg exits non-zero, the listing does not hold exactly one `pub:` record, or that record's fingerprint differs from the pin.
- **R2.** `_install_ubuntu_edge_source` builds its keyring through `_build_pinned_keyring`, and no existing edge test is modified.
- **R3.** `_install_ubuntu_brew_packages` installs `azure-cli`, and `lib/linux_ubuntu.sh` contains no `packages.microsoft.com/repos/azure-cli` URL, no `add-apt-repository` call for azure-cli and no `apt install azure-cli`.
- **R4.** When brew's `azure-cli` is installed and `dpkg -s azure-cli` succeeds, `_install_ubuntu_brew_packages` runs `sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y azure-cli`; when brew's `azure-cli` is absent it does not.
- **R5.** `lib/constants.sh` defines `ALBERT_GPG_FPR="A4B83CD05FDF5C5178482D4A1488EB46E192A257"`.
- **R6.** On success `_install_ubuntu_albert` writes `${_APT_SOURCES_DIR}/albert.list` with an `https://download.opensuse.org/` URL and `signed-by=${_APT_KEYRINGS_DIR}/albert-obs.gpg`, and returns 0.
- **R7.** On a key fetch failure `_install_ubuntu_albert` leaves an existing `albert.list` and `albert-obs.gpg` unchanged, logs a WARN naming the URL, skips `apt install albert`, and returns 2.
- **R8.** On a key failure `_install_ubuntu_albert` removes `albert.list`, logs a WARN printing the fetched fingerprint(s) and `ALBERT_GPG_FPR`, skips `apt install albert`, and returns 2.
- **R9.** The albert key is fetched into a directory created under `_ALBERT_TMP_ROOT` with an explicit `mktemp -d` template, removed on every path.
- **R10.** A non-zero return from `_install_ubuntu_albert` makes `_install_ubuntu_gui_tools` return non-zero after the rest of the step runs, without changing its return on the success path.
- **R11.** The legacy files in Design §5, including the globbed `archive_uri-http_packages_microsoft_com_repos_azure-cli_-*.list`, are removed on every run, before any new key work; the albert legacy files are removed regardless of `HAS_SNAP`.
- **R12.** `_APT_SOURCES_DIR`, `_APT_TRUSTED_DIR`, `_APT_KEYRINGS_DIR`, `_ALBERT_TMP_ROOT` and `_ALBERT_KEY_URL` are honoured by the code, and the first four are set at setup scope in `tests/setup_env/linux_ubuntu.bats`.
- **R13.** Tests cover every row of the Testing table with real gpg and `tests/fixtures/albert-obs.asc` fed per test through `MOCK_CURL_STDOUT`, and the tests at `linux_ubuntu.bats:1416`, `:1454`, `:1487`, `:1497` and `:1568` are changed as the Testing section states.
- **V1.** After merge, `./setup_env.sh -t developer` on `claude` and on `workstation` leaves no legacy key in `/etc/apt/trusted.gpg.d/`, and `sudo apt update` exits 0 with no `NO_PUBKEY`.
- **V2.** After that setup on each of `claude` and `workstation`, `dpkg -s azure-cli` reports not installed, `command -v az` resolves under `/home/linuxbrew`, and `az version` and `albert --version` run.
- **N1.** No change to any other `_install_ubuntu_*` source or key handling except edge's move onto the shared builder and the azure block's removal.
- **N2.** No vendored copy of the albert key outside `tests/fixtures/`.
- **N3.** No test reaches the network or writes under the real `/etc/apt` or `/usr/share/keyrings`.
- **N4.** No key-validity (revoked/expired) check in the builder.

## Multi-Lens Review

Reviewed at commit: `3e3b7ab5` (Step 7 self-review commit, before Step 8 dispatch)

Claims re-checked by the author before recording, 2026-10-03: the azure-cli `resolute` suite
exists (`2.90.0-1~resolute`, signed `EB3E94ADBE1229CF`); `keys/microsoft-2025.asc` exists
(`AA86F75E427A19DD33346403EE4D7792F748182B`) and neither azure-cli suite is signed by it
yet; `tests/mocks/curl` is first on `PATH` and only `touch`es `-o` unless `MOCK_CURL_STDOUT`
is set; the step loop at `lib/linux_ubuntu.sh:28` records a step as failed only on its
non-zero return; `cruncher` (the only `wsl2_workstation`) refused ssh on port 22, so it is
unsurveyed.

### Goal-Fit

Finding:
1. Worth building. The single-`pub:` rule is load-bearing: two concatenated armored keys
   dearmor to 2 `pub:` records on gpg 2.4.8, which the old any-`fpr` check accepts.
2. Reads-it test fails on the failure path. R7 sets no return code, so a keyring failure
   never reaches `ubuntu packages: failed:` and `-t developer` exits 0. Combined with R8
   (legacy source removed first), an installed `az`/`albert` silently stops updating. Doctor
   checks neither tool.
3. The `noble` fallback carried forward is stale: `repos/azure-cli/dists/resolute` serves
   `2.90.0-1~resolute`, signed by the pinned key.
4. R1's "keyring is empty" clause has no test row and is subsumed by the `pub:` count.

Assumption: Each repo stays signed by the one key pinned. Azure is genuinely uncertain:
Microsoft publishes `microsoft-2025.asc` and already signs `ubuntu/26.04/prod` with it.
Refute by `gpg --verify` of `repos/azure-cli/dists/<suite>/InRelease` against the pinned
keyring.
Disposition: Addressed (operator, 2026-10-03: "yes" to the proposed dispositions) — F2: new functions return 2, callers surface it (Return codes section, R7, R11); F3: `noble` fallback dropped (R4); F4: emptiness clause dropped from R1. Assumption (Microsoft re-key) Accepted, reason: no azure-cli suite is signed by the 2025 key today and the failure is loud in `apt update`; recovery written into §2.

### Ergonomics

Finding:
1. A Microsoft re-key fails as `NO_PUBKEY` from `apt update`, not as the WARN: the vendored
   file still matches `MS_GPG_FPR`, so the keyring builds and the source is written. The
   spec does not say what the operator sees or how to recover.
2. The albert WARN cannot distinguish rotation from tampering from a network failure. It
   should print the fetched fingerprint beside `ALBERT_GPG_FPR` and name the remedy (verify
   out of band, edit `lib/constants.sh`). No caller-level wrong-fingerprint albert test.
3. No return code (same as Goal-Fit 2).
4. "Second run byte-identical" and "no `http://` sources left" pass when nothing is written;
   each needs an in-test presence assertion.
5. `_MS_GPG_BIN` now governs a non-Microsoft key; the comment at `lib/linux_ubuntu.sh:789`
   ("unseamed albert writes") goes stale.

Assumption: azure-cli keeps signing with `EB3E94ADBE1229CF`; refute as in Goal-Fit.
Disposition: Addressed (operator, 2026-10-03, same answer) — F2: albert WARN prints fetched fingerprint and pin plus the remedy (§3, R7); F3: as Goal-Fit F2; F4: in-test presence assertions on every absence/equality row; F5: comment at `:789` updated, `_MS_GPG_BIN` name kept because renaming edits edge tests. F1 and the Assumption Accepted, reason: as Goal-Fit Assumption.

### Risk

Finding:
1. The albert test seam cannot work: `tests/mocks/curl` shadows the real curl, ignores the
   URL, and `touch`es `-o`, so the good-key case builds an empty keyring and the curl-fails
   case cannot be driven by a missing fixture. Use `MOCK_CURL_STDOUT` / `MOCK_CURL_EXIT`.
   The spec's stated reason ("cannot carry a key through -o") is false.
2. Two more existing tests assert on `add-apt-repository` and break under R3:
   `linux_ubuntu.bats:1454` (arch) and `:1487` (noble). The spec names only `:1497`.
3. Four rows can pass on nothing (second run, no `http://`, both legacy-cleanup rows if
   fixtures were never seeded or the seams are ignored). A separate good-key test is not a
   control on this test's run.
4. Global-key deletion surveyed on 2 of 3 Linux hosts; `cruncher` unchecked. Another
   unsigned Microsoft source there would silently lose verification.
5. The builder ignores validity: a revoked (`pub:r`) pinned key still gets a source written.
6. Pool `.deb`s redirect to a geo-chosen mirror; apt refuses https-to-http. Acknowledged in
   the spec; low risk.

Assumption: Nothing on any host that runs `-t developer` still needs the global keys.
Refute with
`grep -rLE 'signed-by|Signed-By' /etc/apt/sources.list.d/ | xargs grep -lE 'microsoft|manuelschneid3r'`
on every Ubuntu host; only the two legacy files may print.
Disposition: Addressed (operator, 2026-10-03, same answer) — F1: tests drive curl through `MOCK_CURL_STDOUT`/`MOCK_CURL_EXIT` (Seams); F2: `:1454` and `:1487` rewritten (Testing, R10); F3: presence assertions; F5: revoked key rejected (§1, R1). F4/Assumption Accepted, reason: `cruncher` is the backup box and rarely runs setup; the check command is in Verification after merge. F6 Accepted, reason: acknowledged in the spec, one geography measured.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (reviewed at commit `01d862cc`, all three lenses)

Goal-Fit — Finding: (1) azure-cli has a linuxbrew bottle at the apt version and macOS
already uses it; moving it deletes the azure keyring, source, pin, re-key exposure and the
azure arm of R11. (2) The rc-2 verdict reaches no durable consumer (`-t developer` exits 0;
doctor checks neither tool). (3) The revoked-key rule's rationale contradicts the expired
one, and it has no fixture. (4) "temp file removed" is vacuous on macOS CI (BSD `mktemp`).
Assumption: none uncertain left; each candidate was measured.
Disposition: Addressed (operator, 2026-10-03: "brew for azure-cli looks good,
recommendations look good") — F1: azure moves to linuxbrew (§1, R3, R4); F3: revoked rule
dropped (N4); F4: `_ALBERT_TMP_ROOT` seam (R9). F2 Accepted, reason: keep-last-good on fetch
failure leaves only a fingerprint mismatch, which is rare and explained by the WARN.

Ergonomics — Finding: (1) after OBS extends the key, `-t update` hits `EXPKEYSIG` until
`-t developer` is re-run, and nothing says so. (2) a transient fetch failure deletes a
working albert source. (3) "reports it" implies a failing exit; it is exit 0, stderr only.
(4) builder failure rows pass when nothing is written; temp-file row vacuous on macOS.
(5) the curl-failure WARN should name the URL.
Assumption: `Release.key` always carries one key, including during an OBS rotation.
Disposition: Addressed (same answer, plus operator 2026-10-03: "keep last good source on
fetch failure") — F1: remedy named in §3; F2: fetch failure keeps the last verified source
(R7); F3: §4 reworded; F4: pre-seeded keyring rows and `_ALBERT_TMP_ROOT`; F5: WARN names
the URL (R7). Assumption Accepted, reason: a two-key `Release.key` fails closed with a WARN
naming both fingerprints, which is the right outcome for an unannounced key change.

Risk — Finding: (1) `:1568` breaks under an empty `touch`ed key. (2) builder failure rows
lack a presence control. (3) the revoked row has no fixture. Confirmed sound: the revoked
flag, `MOCK_CURL_STDOUT` byte fidelity, the single-key rule, R11's scope.
Assumption: every location redirects pool `.deb`s to an https mirror.
Disposition: Addressed (same answer) — F1: `:1568` sets `MOCK_CURL_STDOUT` (R13); F2:
pre-seeded rows; F3: rule dropped (N4). Assumption Accepted, reason: 10 of 10 https from
`claude` and the mirrorlist names no http mirror.

