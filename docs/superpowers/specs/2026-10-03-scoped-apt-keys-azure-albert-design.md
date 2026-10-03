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

### 1. One fail-closed keyring builder

The existing `_edge_keyring_has_pinned_fpr` becomes `_keyring_has_pinned_fpr <ring> <fpr>`.
A new `_build_pinned_keyring <key_file> <keyring> <fpr>` builds a keyring as follows:

1. Runs `gpg --dearmor < key_file | sudo tee keyring > /dev/null` through `_MS_GPG_BIN`
   (default `gpg`), so tests can use the real gpg.
2. Succeeds only if gpg's own exit status (`PIPESTATUS[0]`) is 0, the keyring is
   non-empty, **and** the `--show-keys --with-colons` listing holds exactly one `pub:`
   record, whose `fpr` equals the pin.
3. On any failure, `sudo rm -f` the keyring and return 1.

**The single-key rule is new and load-bearing.** Today's check passes if _any_ `fpr:` line
matches the pin. With a vendored file that is safe. Albert's key arrives over the network,
so a response carrying the real key plus an attacker's would pass, and `signed-by` would
then trust both. Counting `pub:` records closes that.

`_install_ubuntu_edge_source` moves onto the shared builder. Its behaviour does not change,
and its existing tests are the regression check.

### 2. `_install_ubuntu_azure_cli`

Extracted from `_install_ubuntu_cloud_tools`, the same way edge was extracted.

- Keyring `${_APT_KEYRINGS_DIR}/microsoft-azure-cli.gpg`, built from the vendored
  `${_MS_KEY_PATH:-${DOTFILES_REPO_ROOT}/keys/microsoft.asc}` and pinned to `MS_GPG_FPR`.
  It does not share edge's bootstrap keyring: edge deletes that keyring once the edge
  package's own `.sources` is live.
- Source `${_APT_SOURCES_DIR}/azure-cli.list`, written directly:
  `deb [arch=$(dpkg --print-architecture) signed-by=<keyring>] https://packages.microsoft.com/repos/azure-cli/ <codename> main`.
  The codename keeps the existing rule: `noble` when `RESOLUTE` is set.
- `add-apt-repository` and the `http://` key fetch are removed.
- If the keyring fails: `log_warn` naming the keyring and the cause, remove the source, and
  **skip** `apt install azure-cli`.

### 3. `_install_ubuntu_albert`

Extracted from `_install_ubuntu_gui_tools`; still gated on `HAS_SNAP`.

- New constant `ALBERT_GPG_FPR="A4B83CD05FDF5C5178482D4A1488EB46E192A257"` in
  `lib/constants.sh`.
- `curl -fsSL "${_ALBERT_KEY_URL:-https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_<release>/Release.key}"`
  to a `mktemp` file, which is removed on every path. The shared builder then produces
  `${_APT_KEYRINGS_DIR}/albert-obs.gpg`.
- Source `${_APT_SOURCES_DIR}/albert.list`:
  `deb [signed-by=<keyring>] https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_<release>/ /`.
- The key is fetched rather than vendored (operator decision, 2026-10-03). OBS extends key
  expiry without changing the fingerprint, so a fingerprint pin follows an extension
  automatically and a vendored copy would not. A changed fingerprint still fails closed.
- A curl failure or a keyring failure takes the same path as azure: warn, no source, no
  install.

### 4. Legacy cleanup

This runs on every pass and is idempotent. Without it, a machine set up before this change
keeps the global keys, and the fix changes nothing there. Removed:

- `${_APT_TRUSTED_DIR}/microsoft.asc.gpg`
- `${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg`
- `${_APT_SOURCES_DIR}/archive_uri-http_packages_microsoft_com_repos_azure-cli_-*.list`
  (globbed: `add-apt-repository` puts the host codename in the name)
- `${_APT_SOURCES_DIR}/packages.microsoft.com_repos_azure-cli.list`
- `${_APT_SOURCES_DIR}/home:manuelschneid3r.list`

Each function removes its own legacy files before it writes the new source. A cleanup that
ran only on success would leave the global key in place exactly when the new keyring cannot
be built.

### Seams

`tests/mocks/sudo` execs real commands, so an unseamed path is a real write to `/etc/apt`
(`tdd.md` E2). Three new variables default to the production paths and are set at setup
scope in `tests/setup_env/linux_ubuntu.bats`:

| variable            | default                   |
| ------------------- | ------------------------- |
| `_APT_SOURCES_DIR`  | `/etc/apt/sources.list.d` |
| `_APT_TRUSTED_DIR`  | `/etc/apt/trusted.gpg.d`  |
| `_APT_KEYRINGS_DIR` | `/usr/share/keyrings`     |

`_ALBERT_KEY_URL` is a fourth seam, so tests never reach the network. It uses a `file://`
URL to a fixture, read by the real curl; `tests/mocks/curl` cannot carry a key through
`-o`. The edge seams (`_EDGE_SOURCES_DIR`, `_EDGE_BOOTSTRAP_KEYRING`) stay as they are.

### Testing

Real gpg via `_MS_GPG_BIN`, as the edge tests do. A new test-only fixture,
`tests/fixtures/albert-obs.asc`, holds the OBS public key. The fixture expires 2027-02-10.
`--show-keys` still lists expired keys, and the check is by fingerprint, so the fixture's
expiry does not break the tests.

The builder is tested directly, plus once through each caller. Cases:

| case                                  | expected                                                                                    |
| ------------------------------------- | ------------------------------------------------------------------------------------------- |
| pinned key                            | keyring holds exactly the pinned fingerprint; returns 0                                     |
| wrong key                             | returns 1; keyring absent                                                                   |
| pinned key with a second key appended | returns 1; keyring absent                                                                   |
| truncated key                         | returns 1; keyring absent                                                                   |
| gpg exits non-zero                    | returns 1; keyring absent                                                                   |
| azure, good key                       | `azure-cli.list` holds `https://` and `signed-by=<keyring>`; `apt install azure-cli` called |
| azure, bad key                        | no `azure-cli.list`; `apt install azure-cli` not called; WARN names the keyring             |
| albert, good key                      | `albert.list` holds `https://` and `signed-by=`; `apt install albert` called                |
| albert, curl fails                    | no `albert.list`, no keyring, no install; temp file removed                                 |
| legacy cleanup                        | every file in §4 removed, including a glob-matched `archive_uri-…-resolute.list`            |
| legacy cleanup on the failure path    | global keys removed even when the new keyring fails                                         |
| second run                            | the same files, byte-identical                                                              |
| no `http://` sources left             | no `.list` either function writes contains `http://`                                        |

The existing test "removes stale azure-cli sources before add-apt-repository" is replaced by
the legacy-cleanup case, which asserts on real files rather than the mock log. Assertions on
absence carry a positive control: the good-key case in the same file proves the mechanism
writes when it should (`tdd.md` E5).

## Verification after merge

Run `./setup_env.sh -t developer` on `claude`, then:

- `ls /etc/apt/trusted.gpg.d/` lists neither legacy key.
- `/etc/apt/sources.list.d/` holds `azure-cli.list` and `albert.list`, both `https` and
  `signed-by`, and no `archive_uri-http…azure-cli…` file.
- `sudo apt update` exits 0 with no `NO_PUBKEY` for either source.
- `az version` and `albert --version` still run.

## Out of scope

- Per-command failure checking inside `_install_ubuntu_*` steps (its own backlog row).
- VirtualBox's `http://` source, which is already `signed-by`.
- Edge's source logic, beyond moving onto the shared builder.

## Requirements

- **R1.** `_build_pinned_keyring` returns 1 and leaves no keyring when gpg exits non-zero, the keyring is empty, the listing holds more than one `pub:` record, or the single key's fingerprint differs from the pin.
- **R2.** `_install_ubuntu_edge_source` builds its keyring through `_build_pinned_keyring`, and every existing edge test passes unchanged.
- **R3.** `lib/linux_ubuntu.sh` contains no `http://packages.microsoft.com` URL and no `add-apt-repository` call for azure-cli.
- **R4.** `_install_ubuntu_azure_cli` writes `${_APT_SOURCES_DIR}/azure-cli.list` with an `https://packages.microsoft.com/repos/azure-cli/` URL and `signed-by=${_APT_KEYRINGS_DIR}/microsoft-azure-cli.gpg`, built from the vendored key and pinned to `MS_GPG_FPR`.
- **R5.** `lib/constants.sh` defines `ALBERT_GPG_FPR="A4B83CD05FDF5C5178482D4A1488EB46E192A257"`.
- **R6.** `_install_ubuntu_albert` fetches the key over `https` to a temp file it always removes, and writes `${_APT_SOURCES_DIR}/albert.list` with an `https://download.opensuse.org/` URL and `signed-by=${_APT_KEYRINGS_DIR}/albert-obs.gpg`.
- **R7.** When a keyring cannot be built, or albert's key fetch fails, the function logs a WARN naming the keyring, writes no source, and does not run `apt install` for that package.
- **R8.** Each function removes its legacy files (Design §4), including the globbed `archive_uri-http_packages_microsoft_com_repos_azure-cli_-*.list`, before attempting the new keyring, so they are removed on both the success and the failure path.
- **R9.** `_APT_SOURCES_DIR`, `_APT_TRUSTED_DIR`, `_APT_KEYRINGS_DIR` and `_ALBERT_KEY_URL` are honoured by the code, and set at setup scope in `tests/setup_env/linux_ubuntu.bats`.
- **R10.** Tests cover every row of the Testing table with real gpg and the `tests/fixtures/albert-obs.asc` fixture, and the mock-log purge test is replaced by one that asserts on real files.
- **V1.** After merge, `./setup_env.sh -t developer` on `claude` leaves no legacy key in `/etc/apt/trusted.gpg.d/`, and `sudo apt update` exits 0 with no `NO_PUBKEY`.
- **V2.** `az version` and `albert --version` run on `claude` after that setup.
- **N1.** No change to any other `_install_ubuntu_*` source or key handling except edge's move onto the shared builder.
- **N2.** No vendored copy of the albert key outside `tests/fixtures/`.
- **N3.** No test reaches the network or writes under the real `/etc/apt` or `/usr/share/keyrings`.
