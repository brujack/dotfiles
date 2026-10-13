# Go tarball sha256 verification

- **Date:** 2026-10-13
- **Backlog row:** "go tarball installed without checksum verification"
- **Follow-up:** backlog row "helper-installed binaries have no checksum and `wget` follows any
  redirect" is a separate cycle. This spec adds the helper it will reuse and designs nothing for it.

## Problem

`_install_go_from_tarball` (`lib/linux_ubuntu.sh`) runs `wget -O <tmp>/go.tgz "${GO_DOWNLOAD_URL}"`
and then `tar -xzf`. It checks nothing about the bytes. The tree is then `chown root:root` and moved
into `/usr/local/go`. This breaks `ci.md`'s third-party binary rule (pin a version **and** verify a
sha256 before use), which tflint, tfsec, shellcheck and rustup-init already follow.

Premise checked 2026-10-13 by reading `lib/linux_ubuntu.sh:459-530`: no `sha256sum`, no `GO_SHA256*`
constant, and no caller verifies the file. The feed has the data. The live
`https://go.dev/dl/?mode=json` lists, for `go1.27.2` (the current pin):

| file                          | sha256                                                             |
| ----------------------------- | ------------------------------------------------------------------ |
| `go1.27.2.linux-amd64.tar.gz` | `ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5` |
| `go1.27.2.linux-arm64.tar.gz` | `94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8` |

Population: one feed fetch, from `claude`, on 2026-10-13. The values are pinned as read. V1 checks
them against a real download.

## Design

### 1. Shared helpers (`lib/helpers.sh`)

Today the sha256 check is copied in two places. `_install_pinned_release_binary` has a 64-hex guard
on the pin and `sha256sum -c`. `_install_rustup_rs` has `sha256sum -c` only and **no** format guard.
macOS `sha256sum` exits 0 on a malformed checksum line (measured, recorded in the
`_install_pinned_release_binary` comment). A rustup pin that is empty or mistyped therefore cannot
fail on the Studio's test run. Go would be a third copy.

Two functions:

- `_sha256_pin_ok <sha>`: rc 0 when the value is exactly 64 hex characters, else rc 1. Callers that
  must refuse a bad pin **before** downloading call it first.
- `_verify_sha256 <file> <sha>`: rc 2 when the pin fails `_sha256_pin_ok` (checked first, so no caller
  can skip it). rc 1 when `printf '%s  %s\n' <sha> <file> | sha256sum -c -` fails. rc 0 on a match.
  It logs nothing; each caller keeps its own message.

`sha256sum` is never mocked. The rule already stated for rustup and the release-binary helper still
holds: a mock makes every mismatch case vacuous.

### 2. Consumers

**`_install_pinned_release_binary`.** Its inline guard becomes `_sha256_pin_ok` (still before the
download). Its inline `sha256sum -c` becomes `_verify_sha256`. Messages and return codes do not
change. Its existing tests are the regression guard.

**`_install_rustup_rs`.** Gains the pre-download format guard through `_sha256_pin_ok`, with the
message `rustup-init: pinned sha256 is not 64 hex chars`. Its check becomes `_verify_sha256`. The
mismatch message `rustup-init sha256 mismatch — refusing to execute` does not change.

**`_install_go_from_tarball`.** Before the workdir is made, choose the pin:

```bash
case "${_LINUX_ARCH}" in
  amd64) _sha="${GO_SHA256_AMD64}" ;;
  arm64) _sha="${GO_SHA256_ARM64}" ;;
  *)     _sha="" ;;
esac
_sha="${_GO_SHA256:-${_sha}}"
```

The source of the value is recorded alongside it: `_GO_SHA256` when the seam is set, else
`GO_SHA256_AMD64` or `GO_SHA256_ARM64`, else `no GO_SHA256_* pin for ${_LINUX_ARCH}`. If
`_sha256_pin_ok "${_sha}"` fails, log `go: <source> is not a 64-hex sha256; refusing to download` and
return 1 before downloading. An unsupported arch, an empty pin and a mistyped pin all take this path. Today an
unsupported arch downloads a tarball that does not exist, so failing early changes the message, not
the outcome.

A new stage goes into the existing `elif` chain, between `download` and `extract`:

```bash
elif ! _verify_sha256 "${_tmp}/go.tgz" "${_sha}"; then
  _stage="verify"
```

Before setting the stage, a mismatch logs one line naming the source, the expected hash and the
actual hash of the downloaded file: `go: sha256 mismatch: <source> expects <sha>, download is
<actual>`. The actual hash is computed only on this failure path; if computing it fails, `<actual>`
reads `unreadable`. The operator can then tell a truncated download (re-run) from a mistyped pin
(compare with the feed), since the tarball itself is deleted with `${_tmp}`.

The stage flow already makes any failed stage remove `${_tmp}`, log `go: <stage> failed` and return 1
without reaching the swap. So a mismatch leaves `/usr/local/go` and `go.old` exactly as they were, and
writes no stamp.

The stamp check is unchanged. A machine whose stamp matches `GO_DOWNLOAD_URL` skips before any
download. A tree installed before this change stays unverified until the next pin bump. That is
accepted: rewriting the stamp format to force a re-download on every Linux box buys verification of
bytes that are already installed and running.

`_GO_SHA256` is a test seam with the same shape as `_TFLINT_SHA256` and `_RUSTUP_INIT_SHA256`. It
grants nothing that editing `lib/constants.sh` does not already grant.

### 3. Pins (`lib/constants.sh`)

`GO_SHA256_AMD64` and `GO_SHA256_ARM64` go directly under `GO_DOWNLOAD_URL`, set to the two values in
the table above. Each has a `# read by` comment, as its neighbours do. The comment above
`GO_DOWNLOAD_FILENAME` already says the pin and the filename move together. It gains: "and the two
`GO_SHA256_*` pins, which `--update` writes in the same edit."

### 4. Pin writer (`lib/workflows.sh`)

New `_fetch_go_sha256 <version>`. It fetches the same feed (`curl -sf --max-time 10`) and prints
`<amd64-sha> <arm64-sha>` for the stable entry `go<version>`. It returns rc 1 with empty output when
any of these hold: curl fails, the body is not JSON, no stable entry has that version, either linux
`.tar.gz` file is missing, or either `sha256` is not 64 hex characters. `_fetch_go_latest` and
`_check_one_pin_version` do not change. The extra fetch happens only on `--update` after the operator
answers `y`.

`_update_go_pin <latest>`:

1. Keeps the X.Y.Z guard.
2. Calls `_fetch_go_sha256 "${_latest}"` **before** copying `constants.sh`. On failure it prints
   `go: refusing pin update: no sha256 for <latest> in the go.dev feed` and returns 1. Nothing is
   written.
3. In the same temp copy as `GO_VER` and `GO_DOWNLOAD_FILENAME`, it rewrites `^GO_SHA256_AMD64=".*"`
   and `^GO_SHA256_ARM64=".*"`.
4. Reads all four lines back with `grep -Fqx` before the `mv`, as it already does for two. A failed
   read-back names the variable and leaves `constants.sh` unchanged.

A refused update returns 1 from `_update_go_pin`. `_tally_cv_out` does not check
`_prompt_version_update`'s rc, so the remaining tools are still prompted, and the run already exits 1
because go was OUTDATED. That is intended: one refused pin must not cancel the operator's other
updates. Do not add `|| return` at that call site.

**Trust model.** `--update` takes the version and its hashes from the same go.dev fetch. The pins
therefore protect every install after pin time against a corrupt or truncated download, a redirect to
another host, and a re-publication under the same filename. They do not protect against go.dev serving
bad bytes and a matching hash at the moment the pin is written. This is the same model as the tflint,
tfsec, shellcheck and rustup pins.

## Testing

All go installer tests already use a real tarball (`_make_go_tarball`) and real `tar`. They change as
follows:

- `_make_go_tarball` exports `_GO_SHA256` as the real `sha256sum` of the tarball it builds, so the
  tests that use it pass because the bytes really match, not because the check is bypassed.
- Go tests that do **not** call `_make_go_tarball` would otherwise read the committed pin and fail at
  `verify` before the stage they test. Each such test exports `_GO_SHA256` as the real hash of its
  own download fixture. At 07ddce67 these are the tests in `tests/setup_env/linux_ubuntu.bats` that
  assert `go: extract failed` (junk file, `nobin.tgz`, `link.tgz`) and the tar-failure test asserting
  `^tar ` was called. Find the full set by running the go tests after the verify stage lands, not
  from this list. **Their assertions must not be relaxed**: each still asserts the stage it names
  (`extract failed`, a `tar` call). A test changed to assert only a non-zero status would pass at
  `verify` and stop testing `extract`.
- Every `_update_go_pin` success-path and read-back test in
  `tests/setup_env/check_versions_feeds.bats` gets the hashes it needs either by stubbing
  `_fetch_go_sha256` as a function printing two 64-hex values, or by a fixture feed with `curl` and
  `python3` added to `_shim_path`. The stub is preferred, since `_fetch_go_sha256` has its own feed
  tests. Each read-back failure test must still fail at the read-back it names, asserted by message.
- New: a wrong 64-hex `_GO_SHA256` returns 1, prints both `go: sha256 mismatch: _GO_SHA256 expects
<pin>, download is <actual>` with the fixture's real hash as `<actual>`, and `go: verify failed`. It
  leaves the seeded tree (`bin/v` still reads `old`), makes no `mv` call, and writes no stamp.
- New: a malformed pin (empty, 63 characters, non-hex) returns 1 with **no** `wget` call and prints
  `go: _GO_SHA256 is not a 64-hex sha256; refusing to download`.
- New: `_LINUX_ARCH=riscv64` with `_GO_SHA256` unset returns 1 with no `wget` call and prints
  `no GO_SHA256_* pin for riscv64`.
- New: the committed `GO_SHA256_AMD64` and `GO_SHA256_ARM64` both pass `_sha256_pin_ok`. This catches a
  malformed committed value, not a wrong one; V1 covers wrong.
- New: with `_GO_SHA256` unset and `_LINUX_ARCH=amd64`, the pin read is `GO_SHA256_AMD64`. The test sets
  `GO_SHA256_AMD64` to the fixture's hash and `GO_SHA256_ARM64` to a wrong value, and the install
  succeeds. A second case swaps the two pins and the install fails. Either case alone passes under the
  opposite mutation.
- Helpers, in a new `tests/setup_env/sha256_helpers.bats`: match is 0, one changed byte is 1, malformed
  pins (empty, 63, 65, `g`-containing) are 2 **without reading the file** (the path is nonexistent and
  the rc is still 2), and an uppercase hex pin is accepted.
- `_install_rustup_rs`: a malformed `_RUSTUP_INIT_SHA256` fails with no `curl` call.
- `_fetch_go_sha256`: fixture feed returns both hashes; missing arm64 file, missing `sha256`, 63-char
  hash, unknown version, curl failure and non-JSON each give rc 1 with empty output.
- `_update_go_pin`: on a temp copy of the real `lib/constants.sh`, writes all four lines. With
  `_fetch_go_sha256` failing, the file stays byte-identical (`cmp`).
- Mutation controls, run by hand and recorded in the PR: delete the `verify` `elif` and the
  wrong-hash test goes red; swap the arch `case` arms and one of the two arch tests goes red.

## Requirements

- **R1.** `[PR1]` `lib/helpers.sh` defines `_sha256_pin_ok` (rc 0 only for exactly 64 hex characters)
  and `_verify_sha256 <file> <sha>` (rc 2 malformed pin, rc 1 mismatch, rc 0 match), and
  `_verify_sha256` checks the pin format before reading the file.
- **R2.** `[PR1]` `_install_pinned_release_binary` and `_install_rustup_rs` call those helpers instead
  of an inline `sha256sum -c`, and `_install_rustup_rs` rejects a malformed pin before downloading.
- **R3.** `[PR1]` `lib/constants.sh` defines `GO_SHA256_AMD64="ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5"`
  and `GO_SHA256_ARM64="94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8"`.
- **R4.** `[PR1]` `_install_go_from_tarball` returns 1 without downloading when the pin selected for
  `_LINUX_ARCH` (or `_GO_SHA256`) fails `_sha256_pin_ok`, naming the source of the value in its
  message.
- **R5.** `[PR1]` `_install_go_from_tarball` runs `_verify_sha256` on the downloaded tarball before
  extracting it, and on failure logs the source, expected hash and actual hash, then returns 1 with
  `go: verify failed`, leaving the install root unchanged and writing no stamp.
- **R6.** `[PR1]` `_fetch_go_sha256 <version>` prints `<amd64> <arm64>` from the go.dev feed and
  returns 1 with empty output when either linux tarball or either 64-hex `sha256` is missing.
- **R7.** `[PR1]` `_update_go_pin` refuses the update before touching `constants.sh` when
  `_fetch_go_sha256` fails, and otherwise writes and reads back `GO_VER`, `GO_DOWNLOAD_FILENAME`,
  `GO_SHA256_AMD64` and `GO_SHA256_ARM64` in one atomic replace.
- **R8.** `[PR1]` `CLAUDE.md`'s `check-versions` entry and Test Seams list name the go sha256 pins and
  the `_GO_SHA256` seam.
- **V1.** Download the real `go1.27.2.linux-amd64.tar.gz` on `claude` and confirm `sha256sum` equals
  `GO_SHA256_AMD64`. Download the arm64 file and confirm `GO_SHA256_ARM64` the same way.
- **V2.** Run `./setup_env.sh -t developer` on `claude` with the go stamp removed, and confirm go
  installs and `/usr/local/go/bin/go version` reports `go1.27.2`.
- **V3.** Mutation controls in Testing go red and are recorded in the PR body.
- **N1.** No change to the go stamp format or the stamp skip condition.
- **N2.** No checksum work for kind, telepresence, the HashiCorp tools, cf-terraforming,
  docker-compose or yq.
- **N3.** No change to macOS go installation (`brew "go"`).
- **N4.** No change to `_fetch_go_latest`'s output or to `_check_one_pin_version`.

## Multi-Lens Review

Reviewed at commit: `07ddce67` (spec as first written and self-reviewed, before Step 8 dispatch)

### Goal-Fit

Finding: No blocking issues. Premise re-verified (`lib/linux_ubuntu.sh:478` wget, `:480` tar, no
`GO_SHA*`; live feed matches R3). Every added mechanism changes a decision. Two minor notes: (a) R2,
the rustup/release-binary move onto the helper, goes past the backlog row and could ship as its own PR;
(b) `--update` reads the version and its hash from go.dev in one fetch, so the pin protects against
later corruption, redirects and re-publication, not against a go.dev compromised at pin time. The spec
should say that in one sentence.
Assumption: No uncertain assumption found.
Disposition: (a) Accepted, reason: about six lines per call site, and splitting would leave rustup's missing format guard open. (b) Addressed: Trust model paragraph added to Design section 4.

### Ergonomics

Finding: (1) A mismatch logs only `go: verify failed`, and the tarball is then deleted. Log the
variable name, the expected hash and the actual hash before the stage line. (2) The pre-download
refusal names `_LINUX_ARCH` even when the bad value came from `_GO_SHA256`. Name the source. (3) The
spec should state that a refused pin update leaves the rest of the check-versions prompts running
(`_tally_cv_out` ignores `_prompt_version_update`'s rc; exit is already 1 from OUTDATED). (4) No test
checks the committed `GO_SHA256_*` values. Asserting both pass `_sha256_pin_ok` catches a malformed
value, not a wrong one. (5) Malformed-pin and riscv64 tests should also assert the message.
Assumption: The Studio's `/sbin/sha256sum` accepts an uppercase-hex pin. Settled 2026-10-13 over
`ssh studio`: uppercase pin rc 0, mismatch rc 1.
Disposition: Addressed, all five: mismatch line with source/expected/actual; refusal names its source; rc-ignoring stated in section 4; committed-pin format test added; malformed-pin and riscv64 tests assert messages.

### Risk

Finding: The Testing claim that exporting `_GO_SHA256` from `_make_go_tarball` keeps every existing
install test passing is false. (1) Four go tests never call `_make_go_tarball` and fall back to the real
pin, so `verify` fires before `extract`: `tests/setup_env/linux_ubuntu.bats` around `:1105`, `:1128`,
`:1140` assert `go: extract failed`, and `:2171` asserts `tar` ran. Relaxing them to "status 1" would
silently turn extract-stage tests into verify tests. Each must export `_GO_SHA256` as its own fixture's
hash. (2) About nine `_update_go_pin` tests in `tests/setup_env/check_versions_feeds.bats` (`:395-595`)
are refused at the new fetch: they set no feed, and `_shim_path` (`:368`) carries neither `curl` nor
`python3`. They need a fixture feed carrying the target version's hashes, or a stubbed
`_fetch_go_sha256`. Sourcing order, destructive widening and vacuity all checked clean.
Assumption: No uncertain assumption found.
Disposition: Addressed: Testing now requires each go test that skips `_make_go_tarball` to export its own fixture's hash without relaxing its stage assertion, and `_update_go_pin` tests to stub `_fetch_go_sha256`.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
