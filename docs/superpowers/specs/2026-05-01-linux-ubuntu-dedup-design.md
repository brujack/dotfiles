# linux_ubuntu.sh Deduplication — Design Spec

**Date:** 2026-05-01
**Status:** Accepted

## Context

`lib/linux_ubuntu.sh` contains two functions with severe copy-paste duplication:

**`_install_ubuntu_powershell` (lines 69–123, 54 lines)**
Four `if [[ -n ${BIONIC/FOCAL/JAMMY/NOBLE} ]]` blocks that are byte-for-byte
identical — only the `printf "pwsh is installed Ubuntu <Name>"` message differs.
The body works without any version-conditional logic because `$(lsb_release -rs)`
in the URL is already runtime-adaptive. Each block is 9 lines; three of the four
blocks are dead copies.

**`_install_ubuntu_go` (lines 125–302, 178 lines)**
Two separate `case ${GO_VER} in` statements:

1. Lines 128–166: 11-arm case that computes `pkgs_to_remove`. Each arm is one
   line that decrements the minor version by 1 (e.g. `1.26` → `golang-1.25-go
golang-1.25-src`). This is pure arithmetic, not logic.
2. Lines 170–297: 11-arm case for the actual install. The first 5 arms (1.16–1.20)
   are identical 2-line blocks (add-apt-repository + apt install). The last 6 arms
   (1.21–1.26) are byte-for-byte identical 14-line tarball-install blocks — the
   same wget/tar/mv sequence copy-pasted six times.

Both functions have existing BATS tests in `tests/setup_env/linux_ubuntu.bats`.

## Decision

Apply **Extract Method** to both functions. No behavior changes — only structural
improvements.

### `_install_ubuntu_powershell`

Replace the four copy-paste blocks with a single unconditional block guarded by
the existing outer `[[ -f ... ]]` check. Drop the per-version `printf` suffix
(it's noise — the installed message already says "pwsh is installed"). Keep BIONIC
guard removal as a separate cleanup only if it's already dead (it is: `BIONIC` is
Ubuntu 18.04, EOL April 2023, and no machine profile sets it).

### `_install_ubuntu_go` — version removal

Replace the 11-arm `case` with arithmetic string manipulation:

```bash
local _minor
_minor=$(printf '%s' "${GO_VER}" | cut -d. -f2)
local _prev_minor=$(( _minor - 1 ))
pkgs_to_remove="golang-1.${_prev_minor}-go golang-1.${_prev_minor}-src"
```

The unsupported-version guard moves to the top of the function, before both
case statements, so it covers both in one place.

### `_install_ubuntu_go` — tarball install

Extract the 14-line tarball block into a private helper:

```bash
_install_go_from_tarball() {
  if [[ ! -f ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ]]; then
    wget -O ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ${GO_DOWNLOAD_URL}
    tar xvf ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} -C ${HOME}/software_downloads/
    if [[ -d /usr/local/go ]]; then sudo rm -rf /usr/local/go; fi
    if [[ -d ${HOME}/software_downloads/go ]]; then
      sudo mv ${HOME}/software_downloads/go /usr/local/go
      sudo chmod 755 /usr/local/go
      sudo chown -R root:root /usr/local/go
    fi
    if [[ -d ${HOME}/software_downloads/go ]]; then rm -rf ${HOME}/software_downloads/go; fi
  fi
}
```

Then `_install_ubuntu_go` uses two branches:

```bash
if [[ ${GO_VER} < "1.21" ]]; then
  sudo add-apt-repository ppa:longsleep/golang-backports -y
  sudo -H apt install "golang-${GO_VER}-go" -y
else
  _install_go_from_tarball
fi
```

The second case statement collapses to ~4 lines.

## Step-by-Step Plan

### Step 1 — Confirm tests pass before touching anything

```bash
make test
```

Expected: all tests green.

### Step 2 — Refactor `_install_ubuntu_powershell`

- Replace the four `if [[ -n ${BIONIC/FOCAL/JAMMY/NOBLE} ]]` blocks with one
  unconditional block (the `[[ ! -f deb ]]` guard stays)
- Replace the four per-version `printf "pwsh is installed Ubuntu <Name>"` messages
  with one generic `printf "pwsh is installed\n"`
- Run `make test` — all tests must pass unchanged

### Step 3 — Commit Step 2

```
refactor: collapse _install_ubuntu_powershell copy-paste into single block
```

### Step 4 — Extract `_install_go_from_tarball` helper

- Add the private helper directly above `_install_ubuntu_go`
- Run `make test` — all tests must pass unchanged (no callers changed yet)

### Step 5 — Refactor `_install_ubuntu_go` install case

- Replace the 11-arm second `case` with the `< "1.21"` branch + `_install_go_from_tarball`
- Run `make test`

### Step 6 — Refactor `_install_ubuntu_go` removal case

- Replace the 11-arm first `case` with the arithmetic approach
- Move the unsupported-version guard to the top of the function
- Run `make test`

### Step 7 — Commit Steps 4–6

```
refactor: eliminate _install_ubuntu_go case duplication via extract method
```

### Step 8 — Run full test suite and lint

```bash
make test
```

## Risk Assessment

**`_install_ubuntu_powershell`:** Very low. The four blocks are byte-for-byte
identical except the `printf` string. Collapsing them cannot change behavior
on any Ubuntu version. The only observable difference is the printed name suffix,
which is cosmetic. Tests cover FOCAL, JAMMY, and NOBLE — they assert `wget` is
called and `dpkg` is called, not the printf output.

**`_install_ubuntu_go` arithmetic removal:** Low. The arithmetic
`minor - 1` produces exactly the same strings as the case arms for every version
in range. Verify by tracing: GO_VER=1.26 → minor=26 → prev=25 → `golang-1.25-go
golang-1.25-src`. Matches case arm exactly. The unsupported-version guard becomes
a simple range check (`minor < 16 || minor > 26`), or we keep the `*` default and
rely on the existing `return 1`.

**`_install_ubuntu_go` tarball extract:** Low. The helper is called exactly where
each case arm was. No new control flow is introduced. Existing test `_install_ubuntu_go:
version >=1.21 calls wget for tarball` will cover the helper path.

**Test coverage:** `tests/setup_env/linux_ubuntu.bats` covers the key behaviors.
No test asserts on the internal case structure — tests assert on mock call log
entries (`wget`, `add-apt-repository`), so they survive this refactor unchanged.

## Consequences

**Improves:**

- `_install_ubuntu_powershell`: 54 lines → ~18 lines; adding a new Ubuntu version
  requires zero changes to this function
- `_install_ubuntu_go`: 178 lines → ~45 lines; adding a new Go tarball version
  requires zero changes (it's already handled by `else`); adding a new PPA version
  requires zero changes too
- Next version bump in `lib/constants.sh` is the only file that needs editing

**Tradeoffs accepted:**

- `_install_go_from_tarball` is a new private function — adds one entry to the
  function namespace, but the name is unambiguous
- The `"1.21"` string comparison (`[[ ${GO_VER} < "1.21" ]]`) relies on
  lexicographic sort working correctly for two-part semver with major=1 and
  minor ≤ 99; this is safe for the versions in use

## Related

- `lib/constants.sh` — `GO_VER`, `GO_DOWNLOAD_FILENAME`, `GO_DOWNLOAD_URL` (read-only; unchanged)
- `tests/setup_env/linux_ubuntu.bats` — existing tests must pass without modification
