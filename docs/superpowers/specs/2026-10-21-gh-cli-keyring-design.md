# install_github_cli_linux: no clobber on a failed fetch, seamed paths, run first

- **Date:** 2026-10-21
- **Status:** Draft (Phase 1)
- **Trigger:** backlog P2 rows "`install_github_cli_linux` writes an empty keyring on a failed
  fetch" and "`install_github_cli_linux` tests reach real `/etc/apt` paths"
  (`docs/superpowers/README.md`), plus the ordering defect the first row names. Raised by Step 8
  round 1 of `specs/2026-10-17-apt-stale-signer-detection-design.md` (finding 3).

## Problem

Three claims, each checked on 2026-10-21.

**1. A failed fetch empties the live keyring: true by construction, not observed on the fleet.**
`lib/developer.sh:512` runs
`wget -qO- <url> | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null`.
`tee` truncates its target before reading stdin. Measured in a scratch directory (one machine,
`claude`, a fixture file rather than the real keyring): a 7-byte file piped from
`wget -qO- http://127.0.0.1:9/nope | tee` ended at 0 bytes and the pipeline returned rc 0. Apt
then treats `github-cli.list`'s `signed-by` as unusable and every `apt update` reports the source
unsigned. On the real machines the defect has not fired: `/etc/apt/keyrings/githubcli-archive-keyring.gpg`
is a 4528-byte binary OpenPGP key on both `claude` and `workstation` (the only two Linux development
boxes; read with `ls -l` and `file`). The key is binary, not armored.

**2. Tests reach real `/etc/apt`: true.** The two `install_github_cli_linux` tests in
`tests/setup_env/workflows.bats` run the function through `tests/mocks/sudo`, which execs the
real `tee` against the hardcoded `/etc/apt/keyrings/...` and `/etc/apt/sources.list.d/github-cli.list`.
They are inert only because the suite runs unprivileged.

**3. The ordering hides the remedy, and the `|| return 1` is dead.** `run_developer_or_ansible`
(`lib/workflows.sh:615`) calls `install_github_cli_linux || return 1` after four npm installs,
`install_ruby_tools` and `install_ruby`, each `|| return 1`. The stale-signer remedy for this key
is "run `-t developer`", which reaches the re-fetch only if all six earlier steps succeed. The
function also always returns 0: its last command is `if [[ -x $(command -v gh) ]]; then ...; fi`,
and an `if` whose condition is false and has no `else` returns 0 (measured:
`bash -c 'f(){ if false; then :; fi; }; f; echo rc=$?'` prints `rc=0`). So the caller's
`|| return 1` can never fire, and an apt failure installing `gh` is reported to nobody.

The existing helper already solves claim 1. `_install_apt_keyring <url> <keyring> <armored|binary>`
(`lib/linux_ubuntu.sh:1577`) fetches with `curl -f` to a temp dir, installs `0644` to `<keyring>.new`
and renames over `<keyring>`, leaving the existing keyring untouched on any failure. Seven callers
use it (nvidia, docker, k8s, teleport, cloudflare, gcloud, virtualbox). `_write_apt_source_list`
(`:1297`) refuses to write a source whose keyring is empty. `_install_ubuntu_docker` is the pattern
this design copies: `_DOCKER_KEYRING`/`_DOCKER_SOURCES_LIST` seams, keyring and source failures
recorded but not fatal, `sudo -H apt update || :`.

## Design

### `install_github_cli_linux` (`lib/developer.sh`)

Unchanged guard: the body runs only when `UBUNTU` is set; otherwise return 0.

```bash
local _keyring="${_GH_CLI_KEYRING:-/etc/apt/keyrings/githubcli-archive-keyring.gpg}"
local _list="${_GH_CLI_SOURCES_LIST:-/etc/apt/sources.list.d/github-cli.list}"
local _rc=0
sudo mkdir -p "$(dirname "${_keyring}")"
_install_apt_keyring https://cli.github.com/packages/githubcli-archive-keyring.gpg "${_keyring}" binary || {
  log_warn "github cli: keyring: install failed"
  _rc=1
}
_write_apt_source_list "github cli" "source list" "${_keyring}" "${_list}" \
  "deb [arch=$(dpkg --print-architecture) signed-by=${_keyring}] https://cli.github.com/packages stable main" \
  || _rc=1
sudo -H apt update || :
sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" gh || {
  log_warn "github cli: gh: install failed"
  _rc=1
}
return "${_rc}"
```

- A failed keyring fetch leaves an existing keyring as it was. An existing `github-cli.list` is
  rewritten only when the keyring is non-empty, so the source and its signer stay consistent.
- The install is still attempted after a keyring or source failure. An already-installed `gh`
  from a previous good keyring stays installable, and apt is the authority on whether the repo is
  usable. This matches docker.
- `sudo chmod go+r` is removed: `_install_apt_keyring` installs with `-m 0644`.
- The trailing `gh is installed` printf is removed. It was the source of the always-0 return and
  reports nothing apt's own output does not.

### `run_developer_or_ansible` (`lib/workflows.sh`)

The GitHub CLI step moves to straight after `_dotfiles_run_tmpdir_setup`, before `_require_npm_pins`.
It is no longer fatal: its rc is kept, the rest of the chain runs unchanged, and the function ends
with that rc.

```bash
run_developer_or_ansible() {
  _dotfiles_run_tmpdir_setup || return 1
  local _gh_rc=0
  if [[ -n ${LINUX} ]]; then
    install_github_cli_linux || _gh_rc=2
  fi
  _require_npm_pins || return 1
  ... (unchanged npm, ruby, setup_ansible, clone_personal_repos) ...
  if [[ ${_gh_rc} -ne 0 ]]; then
    log_warn "github cli install incomplete; see the warnings above"
  fi
  _ledger_write_run_entry "developer" "${_gh_rc}" || true
  return "${_gh_rc}"
}
```

- rc 2 means "the run completed but a step was partial". This follows the repo's 0/1/2 convention
  (`install_ubuntu_packages`, `install_git_hooks_all_repos`), where 1 is a hard failure that
  stopped the run. `setup_env.sh`'s `_run_or_exit` exits with that code, so `-t developer` and
  `-t ansible` exit 2. They are the last step in `setup_env.sh`'s chain for both types.
- The ledger entry records the rc. `_ledger_write_run_entry` sets `success: false` for any
  non-zero rc, so a partial run is not recorded as a success.
- Every hard failure (`|| return 1`) after the gh step keeps its current behaviour: it returns 1
  and writes no ledger entry, as it does today.

### Testing

`tests/setup_env/workflows.bats` sets `_GH_CLI_KEYRING` and `_GH_CLI_SOURCES_LIST` under
`BATS_TEST_TMPDIR` at `setup()` scope, so no test can reach the real `/etc/apt`. It also points
`_APT_KEY_TMP_ROOT` at a test-owned directory, since BSD `mktemp -d` ignores `TMPDIR`. The gh key is
`binary`, so `_install_apt_keyring` never calls gpg and `_APT_KEY_GPG_BIN` needs no setting.

New or changed tests, each RED before its code:

1. Failed fetch (`MOCK_CURL_EXIT=22`) with a pre-seeded keyring: the keyring's bytes are unchanged,
   the function returns 1, a `github cli: keyring: install failed` warning is printed, and
   `apt install gh` is still called.
2. Failed fetch with no keyring: no list file is written (`_write_apt_source_list` refuses).
3. Successful fetch: the keyring holds exactly `MOCK_CURL_STDOUT`'s bytes, the list holds the
   `signed-by=<seamed keyring>` line, and the function returns 0.
4. `apt install gh` fails (`MOCK_APT_FAIL_SUBCMD`): returns 1 with the `gh: install failed` warning.
5. Not Ubuntu: returns 0 and makes no `curl`, `apt` or `sudo` call.
6. The two existing tests (`DEBIAN_FRONTEND`, `apt install gh`) keep passing under the seams.
7. `run_developer_or_ansible`, gh stubbed to return 1: `setup_ansible` and `clone_personal_repos`
   still run, the function returns 2, and the ledger entry is written with rc 2.
8. `run_developer_or_ansible`, gh stubbed to return 0 and `install_ruby` stubbed to return 1: the
   gh stub's call is recorded **before** the ruby stub's in `MOCK_CALLS_FILE` (ordering), and the
   function returns 1.
9. `run_developer_or_ansible` with `LINUX` unset: gh is not called, rc 0 (existing macOS path).

Test 7 is the one that fails if the step is fatal again. Test 8 fails if the step moves back below
the npm and ruby steps. Test 1 fails against the old `wget | tee` (the keyring ends at 0 bytes).

## Out of scope

- `claude` has gh twice. `/home/linuxbrew/.linuxbrew/bin/gh` from the linuxbrew list
  (`lib/linux_ubuntu.sh:1425`) shadows apt's `/usr/bin/gh`, while `workstation` has only the apt
  one. Whether apt gh should be installed at all is a separate decision, filed as a backlog row.
- Making the rest of `run_developer_or_ansible` non-short-circuit.
- A doctor check for an empty or stale gh keyring (the stale-signer spec owns signer detection).

## Requirements

- **R1.** `[gh-keyring]` `install_github_cli_linux` installs the keyring only through `_install_apt_keyring <url> <keyring> binary`; no `wget` or `tee` writes the keyring.
- **R2.** `[gh-keyring]` A failed key fetch leaves an existing keyring byte-identical and makes `install_github_cli_linux` return 1 with a warning naming the keyring stage.
- **R3.** `[gh-keyring]` The source list is written only through `_write_apt_source_list`, so no list is written when the keyring is absent or empty.
- **R4.** `[gh-keyring]` `apt install gh` is attempted after a keyring or source failure, and its failure makes the function return 1 with a warning naming `gh`.
- **R5.** `[gh-keyring]` The keyring and list paths are read from `_GH_CLI_KEYRING` and `_GH_CLI_SOURCES_LIST`, defaulting to `/etc/apt/keyrings/githubcli-archive-keyring.gpg` and `/etc/apt/sources.list.d/github-cli.list`.
- **R6.** `[gh-order]` `run_developer_or_ansible` calls `install_github_cli_linux` (on `LINUX`) before `_require_npm_pins`.
- **R7.** `[gh-order]` A non-zero rc from `install_github_cli_linux` does not stop `run_developer_or_ansible`: every later step still runs, and when none of them hard-fails the function returns 2.
- **R8.** `[gh-order]` On that partial path the ledger entry is written with exit code 2; a hard failure later in the chain still returns 1 and writes no entry.
- **R9.** `[gh-tests]` `tests/setup_env/workflows.bats` sets `_GH_CLI_KEYRING` and `_GH_CLI_SOURCES_LIST` under `BATS_TEST_TMPDIR` in `setup()`.
- **V1.** `make test` exits 0 and CI is green, including `bash-coverage` at or above 91%.
- **V2.** On `claude`, after merge, `-t developer` leaves `/etc/apt/keyrings/githubcli-archive-keyring.gpg` a valid binary key (`file` reports an OpenPGP public key) and `sudo apt update` reports no error for `cli.github.com`.
- **N1.** No change to `_install_apt_keyring` or `_write_apt_source_list`.
- **N2.** No change to the fail-fast behaviour of any step in `run_developer_or_ansible` other than the GitHub CLI step.
- **N3.** No change to which machines install apt `gh` or linuxbrew `gh`.
