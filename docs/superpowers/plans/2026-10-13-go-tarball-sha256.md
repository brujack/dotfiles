# Go Tarball sha256 Verification Implementation Plan

spec: docs/superpowers/specs/2026-10-13-go-tarball-sha256-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the go tarball's sha256 before extracting it, pin the hashes per arch, and have `check-versions --update` write them.

**Architecture:** Two shared helpers in `lib/helpers.sh` (`_sha256_pin_ok`, `_verify_sha256`) replace the inline checks in the release-binary helper and rustup, and back a new `verify` stage in `_install_go_from_tarball`. `_update_go_pin` fetches both hashes from the go.dev feed before its atomic constants rewrite.

**Tech Stack:** bash, bats, GNU/BSD `sha256sum`, python3 (feed parsing).

## Global Constraints

- Worktree: `/home/bruce/git-repos/personal/dotfiles-go-sha256`, branch `feat/go-tarball-sha256`. All work happens there.
- `sha256sum` is never mocked in any test.
- `make test` takes ~170 s (measured 2026-10-13, 2975 ok). Run it with the Bash tool's `timeout: 600000` and wait for it in-turn; never background it.
- No change to the go stamp format or stamp skip (N1); no work on kind, telepresence, HashiCorp, cf-terraforming, docker-compose, yq (N2); no macOS go change (N3); no change to `_fetch_go_latest` or `_check_one_pin_version` (N4).
- Existing test assertions are never relaxed to make them pass. A test that breaks because verify now runs first gets its own fixture hash.
- Commit message via `caveman:caveman-commit`; end with the session's Co-Authored-By/Claude-Session lines.

## Session-level verification

- `make test` exits 0 on the branch, and CI's six jobs pass.
- V1: `sha256sum` of the real go1.27.2 linux-amd64 and linux-arm64 tarballs equals the pins (orchestrator, Phase 3).
- V2: on `claude`, remove `~/.local/share/dotfiles/installed/go`, run `./setup_env.sh -t developer`, and confirm `/usr/local/go/bin/go version` reports `go1.27.2` (orchestrator, after merge or from the branch).
- V3: the mutation controls named in Tasks 3 and 4 go red; record them in the PR body.

---

### Task 1: sha256 helpers

```yaml-task
id: 1
description: Add _sha256_pin_ok and _verify_sha256 to lib/helpers.sh with their own bats file
role: executor
model: sonnet
tdd: required
requirements: [R1]
acceptance:
  - cmd: bats tests/setup_env/sha256_helpers.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/sha256_helpers.bats]
depends_on: []
```

At base, `tests/setup_env/sha256_helpers.bats` does not exist (bats exits non-zero on the missing file).

Add to `lib/helpers.sh`, near the other small predicates:

```bash
# _sha256_pin_ok <sha> -- rc 0 only for exactly 64 hex characters. Callers that
# must refuse a bad pin before downloading call this first.
_sha256_pin_ok() {
  [[ "${1}" =~ ^[0-9a-fA-F]{64}$ ]]
}

# _verify_sha256 <file> <sha> -- rc 0 match, 1 mismatch, 2 malformed pin,
# 3 file unreadable; any other rc is sha256sum's own (126/127). Logs nothing.
# The pin is checked first: macOS sha256sum exits 0 on a malformed checksum
# line. The -r check exists because sha256sum -c returns 1 for a file it
# cannot open, the same code as a mismatch (measured 2026-10-13: missing file
# on GNU and on the Studio's /sbin/sha256sum, mode-000 as non-root on GNU).
# Uppercase hex is accepted by both (measured 2026-10-13); do not lower-case pins.
_verify_sha256() {
  local _file="$1" _sha="$2"
  _sha256_pin_ok "${_sha}" || return 2
  [[ -r "${_file}" ]] || return 3
  printf '%s  %s\n' "${_sha}" "${_file}" | sha256sum -c - > /dev/null 2>&1
}
```

Tests in a new `tests/setup_env/sha256_helpers.bats` (copy the `setup()` of `tests/setup_env/release_binary.bats`: source `tests/helpers/common.bash`, `load_setup_env`). Write each test, see it fail, then implement:

- fixture file `printf 'abc' > f`; its real hash from `sha256sum f | cut -d' ' -f1`. `_verify_sha256 f <hash>` -> 0.
- one changed byte (`printf 'abd' > f`) -> 1.
- pins `""`, 63 hex, 65 hex, 63 hex plus `g` -> 2, with a **nonexistent** path (proves format is checked before the file).
- valid 64-hex pin on a nonexistent path -> 3.
- the real hash upper-cased (`tr a-f A-F`) -> 0.
- `_sha256_pin_ok` 64 hex -> 0; 63 -> 1; empty -> 1.

---

### Task 2: move release-binary and rustup onto the helpers

```yaml-task
id: 2
description: Replace inline sha256 checks in _install_pinned_release_binary and _install_rustup_rs with the helpers; add rustup pre-download format guard
role: executor
model: sonnet
tdd: required
requirements: [R2]
acceptance:
  - cmd: bats tests/setup_env/release_binary.bats
    exit_code: 0
  - cmd: 'bats -f "_install_rustup_rs" tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
  - cmd: 'grep -q "rustup-init: pinned sha256 is not 64 hex chars" tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [1]
```

At base the `grep` gate exits 1 (no such test).

`_install_pinned_release_binary` (`lib/linux_ubuntu.sh` ~:1579): replace the `[[ ! "${_sha256}" =~ ^[0-9a-fA-F]{64}$ ]]` test with `! _sha256_pin_ok "${_sha256}"`, and the `printf ... | sha256sum -c -` test with `! _verify_sha256 "${_artifact}" "${_sha256}"`. Messages, return codes and ordering do not change. Trim its comment's macOS-sha256sum note to a pointer to `_verify_sha256`.

`_install_rustup_rs` (~:560-610): after `_sha="${_RUSTUP_INIT_SHA256:-${_sha}}"` and **before** `mktemp`, add:

```bash
  if ! _sha256_pin_ok "${_sha}"; then
    log_error "rustup-init: pinned sha256 is not 64 hex chars"
    return 1
  fi
```

and replace its `printf ... | sha256sum -c -` test with `! _verify_sha256 "${_tmp}/rustup-init" "${_sha}"`. Its mismatch message stays `rustup-init sha256 mismatch — refusing to execute` (an rc 3 still prints it; deliberate per spec section 2).

New test in `tests/setup_env/linux_ubuntu.bats` beside the existing rustup sha tests (~:1845-1870): `_RUSTUP_INIT_SHA256=abc` -> status 1, output contains `rustup-init: pinned sha256 is not 64 hex chars`, and no `curl` line in `${MOCK_CALLS_FILE}`. Every existing rustup and release-binary test must pass unchanged.

---

### Task 3: go installer verify stage and pins

```yaml-task
id: 3
description: Add GO_SHA256_* pins, pin/source selection, and a _go_verify stage to _install_go_from_tarball, with tests
role: executor
model: sonnet
tdd: required
requirements: [R3, R4, R5]
acceptance:
  - cmd: 'bats -f "go" tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
  - cmd: 'grep -q "go: sha256 mismatch: _GO_SHA256 expects" tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
  - cmd: 'grep -q "^GO_SHA256_AMD64=\"ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5\"$" lib/constants.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [2]
```

At base both `grep` gates exit 1.

`lib/constants.sh`, directly under `GO_DOWNLOAD_URL`:

```bash
# read by lib/linux_ubuntu.sh:_install_go_from_tarball; written by
# lib/workflows.sh:_update_go_pin in the same edit as GO_DOWNLOAD_FILENAME
GO_SHA256_AMD64="ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5"
GO_SHA256_ARM64="94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8"
```

Append to the comment above `GO_DOWNLOAD_FILENAME`: "and the two `GO_SHA256_*` pins, which `--update` writes in the same edit."

`lib/linux_ubuntu.sh`, a new function above `_install_go_from_tarball`:

```bash
# _go_verify <file> <sha> <source> -- names the real cause; only rc 1 is a mismatch.
_go_verify() {
  local _file="$1" _sha="$2" _src="$3" _rc=0 _actual=""
  _verify_sha256 "${_file}" "${_sha}" || _rc=$?
  case "${_rc}" in
    0) return 0 ;;
    1)
      if _actual="$(sha256sum "${_file}" 2> /dev/null)"; then
        _actual="${_actual%% *}"
      fi
      _sha256_pin_ok "${_actual}" || _actual="unreadable"
      log_warn "go: sha256 mismatch: ${_src} expects ${_sha}, download is ${_actual}"
      ;;
    3) log_warn "go: could not read the download to verify it" ;;
    *) log_warn "go: sha256 check could not run (rc ${_rc})" ;;
  esac
  return 1
}
```

In `_install_go_from_tarball`, declare `local _sha="" _src=""`, and after the stamp check, before `mkdir -p`:

```bash
  if [[ -n ${_GO_SHA256} ]]; then
    _sha="${_GO_SHA256}"; _src="_GO_SHA256"
  else
    case "${_LINUX_ARCH}" in
      amd64) _sha="${GO_SHA256_AMD64}"; _src="GO_SHA256_AMD64" ;;
      arm64) _sha="${GO_SHA256_ARM64}"; _src="GO_SHA256_ARM64" ;;
    esac
  fi
  if [[ -z ${_src} ]]; then
    log_warn "go: no GO_SHA256_* pin for ${_LINUX_ARCH}; refusing to download"
    return 1
  fi
  if ! _sha256_pin_ok "${_sha}"; then
    log_warn "go: ${_src} is not a 64-hex sha256; refusing to download"
    return 1
  fi
```

Insert between the `wget` and `tar` arms of the `elif` chain:

```bash
  elif ! _go_verify "${_tmp}/go.tgz" "${_sha}" "${_src}"; then
    _stage="verify"
```

Add `_GO_SHA256` to the function's seam comment.

Tests (`tests/setup_env/linux_ubuntu.bats`, go section ~:978-1260 and ~:2150-2185):

1. `_make_go_tarball` exports `_GO_SHA256="$(sha256sum "${BATS_TEST_TMPDIR}/go.tgz" | cut -d' ' -f1)"`.
2. Run `bats -f go tests/setup_env/linux_ubuntu.bats`. Every go test that now fails at `verify` (expected: the junk-file, `nobin.tgz` and `link.tgz` `go: extract failed` tests, and the tar-failure test asserting `^tar `) exports `_GO_SHA256` as the real hash of **its own** download fixture. Do not change their assertions.
3. New tests, each asserting status 1 unless stated:
   - wrong 64-hex `_GO_SHA256` over a real fixture: output has `go: sha256 mismatch: _GO_SHA256 expects <pin>, download is <fixture's real hash>` and `go: verify failed`; `bin/v` still `old` (`_seed_go`); no `^mv ` call; no stamp file.
   - `_GO_SHA256` of 63 hex, and one with a `g`: no `^wget ` call; `go: _GO_SHA256 is not a 64-hex sha256; refusing to download`.
   - `_GO_SHA256` unset, `_LINUX_ARCH=amd64`, `GO_SHA256_AMD64=""`: no wget; `go: GO_SHA256_AMD64 is not a 64-hex sha256`.
   - `_GO_SHA256=""` with `GO_SHA256_AMD64` = fixture hash: status 0, installs (empty seam means unset).
   - `_LINUX_ARCH=riscv64`, `_GO_SHA256` unset: no wget; `go: no GO_SHA256_* pin for riscv64; refusing to download`.
   - `_GO_SHA256` unset, `_LINUX_ARCH=amd64`, `GO_SHA256_AMD64` = fixture hash, `GO_SHA256_ARM64` = wrong: status 0. Swapped: status 1.
   - `_go_verify <nonexistent> <valid pin> X`: output `go: could not read the download to verify it`, not `mismatch`.
   - `_go_verify` with `PATH` set to a shim dir **only**, holding a non-executable `sha256sum` (mode 644) and nothing else needed: output `go: sha256 check could not run (rc 126)`, not `mismatch`. A prepended shim does not work (real `sha256sum` wins).
   - `GO_SHA256_AMD64` and `GO_SHA256_ARM64`, named explicitly, each pass `_sha256_pin_ok`.
4. Mutation control (report in the task result, then revert): delete the `elif ! _go_verify` arm -> the wrong-hash test fails; swap the `amd64`/`arm64` arms -> one arch test fails.

---

### Task 4: pin writer fetches and writes the hashes

```yaml-task
id: 4
description: Add _fetch_go_sha256 and make _update_go_pin write and read back GO_SHA256_AMD64/ARM64 atomically
role: executor
model: sonnet
tdd: required
requirements: [R6, R7]
acceptance:
  - cmd: bats tests/setup_env/check_versions_feeds.bats
    exit_code: 0
  - cmd: 'grep -q "_fetch_go_sha256" tests/setup_env/check_versions_feeds.bats'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/check_versions_feeds.bats]
depends_on: [3]
```

At base the `grep` gate exits 1.

`lib/workflows.sh`, after `_fetch_go_latest`:

```bash
# Prints "<amd64-sha> <arm64-sha>" for stable release go<version>; rc 1 and
# empty output when the release, either linux tarball, or either 64-hex sha256
# is missing. Feeds _update_go_pin only.
_fetch_go_sha256() {
  local _version="$1" _body
  [[ "${_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
  _body=$(curl -sf --max-time 10 'https://go.dev/dl/?mode=json') || return 1
  printf '%s' "${_body}" | python3 -c '
import json, re, sys
want = "go" + sys.argv[1]
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
if not isinstance(data, list):
    sys.exit(1)
for entry in data:
    if not isinstance(entry, dict) or entry.get("stable") is not True or entry.get("version") != want:
        continue
    files = entry.get("files")
    if not isinstance(files, list):
        sys.exit(1)
    shas = {f.get("filename"): f.get("sha256") for f in files if isinstance(f, dict)}
    out = []
    for arch in ("amd64", "arm64"):
        s = shas.get(want + ".linux-" + arch + ".tar.gz")
        if not isinstance(s, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", s):
            sys.exit(1)
        out.append(s)
    print(" ".join(out))
    sys.exit(0)
sys.exit(1)
' "${_version}"
}
```

`_update_go_pin`: after the X.Y.Z guard and **before** `cp`:

```bash
  local _shas="" _amd="" _arm=""
  _shas=$(_fetch_go_sha256 "${_latest}") || _shas=""
  read -r _amd _arm <<< "${_shas}"
  if ! _sha256_pin_ok "${_amd}" || ! _sha256_pin_ok "${_arm}"; then
    printf "  go: refusing pin update: no sha256 for %s in the go.dev feed\n" "${_latest}"
    return 1
  fi
```

In the temp copy, after `_update_url_pins`: `sed -i.bak -e "s|^GO_SHA256_AMD64=\".*\"|GO_SHA256_AMD64=\"${_amd}\"|" -e "s|^GO_SHA256_ARM64=\".*\"|GO_SHA256_ARM64=\"${_arm}\"|" "${_tmp}"; rm -f "${_tmp}.bak"`. Add two read-back checks in the existing style (`grep -Fqx 'GO_SHA256_AMD64="'"${_amd}"'"'`), each printing `  go: pin update failed: GO_SHA256_AMD64 is not <sha>` (resp. ARM64) and removing the temp file. Update the function's header comment to say four lines move together. Do not add `|| return` at `_tally_cv_out`'s call site.

Tests (`tests/setup_env/check_versions_feeds.bats`):

- `_fetch_go_sha256` with `MOCK_CURL_STDOUT` from the file's existing go fixture (`_go_fixture`, extended with `sha256` fields if absent): prints both hashes for the version present; rc 1 + empty for missing arm64 file, missing `sha256`, 63-char hash, unknown version, `MOCK_CURL_EXIT=22`, non-JSON.
- Every existing `_update_go_pin` test (~:395-595) gets a stub defined in the test: `_fetch_go_sha256() { [[ "$1" == "<the test's target version>" ]] || return 1; printf '%s %s\n' "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..64})"; }`. Success-path tests additionally assert the copy contains `GO_SHA256_AMD64="aaa…"` and `GO_SHA256_ARM64="bbb…"` (64 each). Read-back failure tests still assert the read-back message they name.
- New: stub returns 1 -> `_update_go_pin` returns 1, prints `no sha256 for`, and the constants copy is byte-identical before and after (`cmp`).
- Mutation control (report, then revert): call `_fetch_go_sha256 "${_series}"` instead of `"${_latest}"` -> a success-path test fails.

---

### Task 5: documentation

```yaml-task
id: 5
description: Document the go sha256 pins and _GO_SHA256 seam in CLAUDE.md (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R8]
acceptance:
  - cmd: 'grep -q "GO_SHA256_AMD64" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "_GO_SHA256" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md]
depends_on: [4]
```

At base both `grep` gates exit 1. `make test` is not a gate here: no test reads `CLAUDE.md` (pinned by `tests/scripts/docs_inert_premise.bats`). The orchestrator runs `make test` once after this task.

- `check-versions` entry (Entry Points): where it says `--update` writes go (`GO_VER` plus `GO_DOWNLOAD_FILENAME`, atomically…), add the two `GO_SHA256_*` pins and that the update is refused when the go.dev feed lacks either hash.
- Test Seams: add a bullet beside `_GO_INSTALL_ROOT`: `_GO_SHA256` (`lib/linux_ubuntu.sh:_install_go_from_tarball`) — a non-empty value replaces the arch pin; `_make_go_tarball` exports the fixture's real hash; any go test using another download fixture exports that fixture's own hash; `sha256sum` is never mocked.
- Keep each addition to one or two lines.

---

## Orchestrator steps

- [ ] After Task 5: `make test` (timeout 600000), confirm rc 0.
- [ ] Phase 3 via `finishing-a-development-branch`; V1 and V3 evidence go in the PR body.
- [ ] Set this plan's row in `docs/superpowers/README.md` to Done and add the `> **Status: DONE**` banner when the PR merges.

## Non-goal check

Reviewer run 2026-10-13 against N1-N4 (`spec_contract.py` output; N2's text is truncated at its line
break by that tool, and the reviewer judged it against the full list in this plan's Global Constraints).

| Non-goal | Verdict | Reviewer note | Resolution |
| -------- | ------- | ------------- | ---------- |
| N1 | CLEAR | verify stage goes after the stamp check; stamp format and skip unchanged | none needed |
| N2 | CLEAR | Task 2 moves existing checks onto helpers; adds no checksums for excluded tools | none needed |
| N3 | CLEAR | no step touches macOS go | none needed |
| N4 | CLEAR | `_fetch_go_sha256` is new; `_fetch_go_latest` and `_check_one_pin_version` unchanged | none needed |
