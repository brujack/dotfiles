# Release Asset sha256 Pins (PR A) Implementation Plan

spec: docs/superpowers/specs/2026-10-13-release-asset-sha256-design.md
scope: PR1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** kind and yq install only bytes whose sha256 matches an in-repo pin taken from the GitHub releases API, shellcheck pins can be refreshed by script, and the unused telepresence, cf-terraforming and standalone docker-compose are no longer installed.

**Architecture:** A URL builder and a pin lookup in `lib/linux_ubuntu.sh` feed both `_install_fetched_binary` (which gains a verify stage and a `<url> <sha256>` stamp) and a standalone `scripts/refresh-sha256-pins.sh` that writes pins from the API `digest` field. `check-versions` compares pins, not installed binaries, for kind, yq and shellcheck, and its `--update` moves kind/yq pins through the refresher.

**Tech Stack:** bash, bats-core, GNU make, python3 (`-I`, json only) for API JSON parsing, curl, the shared `tests/helpers/http_listener.bash`.

## Global Constraints

- Messages are copied verbatim from the spec; do not paraphrase them.
- `sha256sum` is never mocked; tests compute real digests of their fixtures.
- Hex checks use `[[:xdigit:]]` or `_sha256_pin_ok`, never `[0-9a-fA-F]` (glibc UTF-8 ranges match `é`).
- No `trap ... EXIT|RETURN` in `lib/*.sh` (`scripts/check-lib-exit-traps.sh`); clean up explicitly.
- Every test that reaches an installer sets `_DL_STAMP_DIR`, `_DL_TMP_ROOT`, `_DL_BIN_DIR` under `BATS_TEST_TMPDIR`; `tests/mocks/sudo` execs real commands.
- No test reads or writes the real `lib/constants.sh` except the committed-constants test (read-only); writers work on a copy.
- Only Task 3 contacts the network (three GitHub API requests).
- New test seams `_FETCHED_URL`, `_FETCHED_SHA256`, `_REFRESH_ASSET_URL`, `_OVERRIDE_REFRESH_PINS` are honoured only when `BATS_TEST_TMPDIR` is non-empty.
- Every `# shellcheck disable=` carries a reason on the same line.
- Commit messages via `caveman:caveman-commit`; trailers `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Wy6Xbft4DukNA5fDr3Vggp`.

## Verification Planning

- **Whole change:** `make test` exits 0 on the branch (baseline on `f4b31c1f`: rc 0, 3012 `ok`, 182 s on `claude`). CI green on all seven jobs.
- **V1:** the orchestrator downloads the 6 pinned assets (kind, yq: `kind-linux-{amd64,arm64}`, `yq_linux_{amd64,arm64}`; shellcheck `linux.{x86_64,aarch64}.tar.xz`) into a fresh scratch dir and compares `sha256sum` to the committed pins; 6 of 6 equal, recorded in the PR body.
- **V3:** five mutation controls, each applied alone in a scratch copy and run against its named test file; each turns at least one named test red; recorded in the PR body.
- **V2 (after merge):** on `claude` and `workstation`, record stamp and `version` for the three retired binaries, remove `/usr/local/bin/{docker-compose,telepresence,cf-terraforming}` and their stamps by hand, then run `_install_ubuntu_k8s_tools` and `_install_ubuntu_misc` with `_DL_STAMP_DIR` pointed at an empty temp dir and confirm `kind: sha256 verified` and `yq: sha256 verified`.
- **Edge cases that must be exercised:** wrong pin, malformed pin, `_FOR_VER` mismatch, unknown tool, unknown arch, verify rc 3 and rc 126, old-sha stamp, `--unverified` refused for kind, seams ignored outside bats, changed digest at an unchanged version, API 403, missing pin line, read-back failure, refused token count.

## Deviations from spec prose (not from Requirements)

- `.config/.zshrc.d/6_path.zsh`'s docker-compose comment is left as is. It lists Docker Desktop's macOS shims (`docker-compose`, `docker-compose-v1`, …) under `~/.docker/bin`, not the retired Linux `/usr/local/bin/docker-compose`, so it remains accurate.
- Section 5's listener is extended with an optional response body, status and request-path log (`tests/helpers/http_listener.bash`), since it serves a fixed `tag_name` body today.
- A fourth bats-gated seam, `_REFRESH_ASSET_URL`, lets the refresher's non-GitHub-URL error be tested; the builder never emits one.
- The `not verified` line prints when an `--unverified` tool is installed, not on an up-to-date skip.

---

## Gates

`make test` takes 182 s on `claude` (measured on `f4b31c1f`), under the Bash tool's 600 s cap, so every
task's gate is the aggregate `make test` plus `make lint`. Run it in the foreground with
`timeout: 600000`, redirected to a file, and capture `$?` on the next line; never pipe it into
`tail`. Tasks run sequentially (several share `lib/linux_ubuntu.sh` and its bats file).

### Task 1: URL builder and pin lookup

```yaml-task
id: 1
description: Add _release_asset_url and _release_asset_sha plus placeholder pin lines, with their tests
role: executor
model: sonnet
tdd: required
requirements: [R1]
acceptance:
  - cmd: bats tests/setup_env/release_asset_pins.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, lib/constants.sh, tests/setup_env/release_asset_pins.bats]
depends_on: []
```

**Files:** create `tests/setup_env/release_asset_pins.bats` (setup: `source tests/helpers/common.bash; load_setup_env`). Add both functions to `lib/linux_ubuntu.sh` directly above `_install_fetched_binary`'s header comment. Add pin lines to `lib/constants.sh` after `KIND_VER`, `YQ_VER` and the shellcheck pins, each with a `# read by lib/linux_ubuntu.sh:_release_asset_sha` comment.

- [ ] Write failing tests: URL table for kind, yq, shellcheck on `amd64` and `arm64`, hand-typed (spec section 1), with `KIND_VER`/`YQ_VER`/`SHELLCHECK_VER` set in-test to `1.2.3`; unknown tool → `status 2`, empty output; arch `riscv64` → `status 3`, empty output. `_release_asset_sha`: set all six pin variables to six distinct 64-hex strings in-test and assert each tool/arch prints `<VAR> <value>`; unknown tool → `status 2`; unknown arch → `status 3`.
- [ ] Run, confirm red for "command not found".
- [ ] Implement. `_release_asset_url <tool> <arch>`: `case` on tool; shellcheck maps `amd64→x86_64`, `arm64→aarch64`; any other arch returns 3 before printing. `_release_asset_sha <tool> <arch>`: explicit `case` naming every variable, e.g. `kind:amd64) printf '%s %s\n' KIND_SHA256_AMD64 "${KIND_SHA256_AMD64}"`.
- [ ] Add to `lib/constants.sh`: `KIND_SHA256_AMD64`, `KIND_SHA256_ARM64`, `YQ_SHA256_AMD64`, `YQ_SHA256_ARM64` each `"` + 64 zeros + `"`; `KIND_SHA256_FOR_VER=""`, `YQ_SHA256_FOR_VER=""`, `SHELLCHECK_SHA256_FOR_VER=""`. Task 3 fills them; do not type real hashes.
- [ ] Gates green; commit.

**Interfaces — Produces:** `_release_asset_url <tool> <arch>` → stdout URL, rc 0 / 2 unknown tool / 3 unknown arch. `_release_asset_sha <tool> <arch>` → stdout `<VAR> <value>`, same rcs. Tools: `kind yq shellcheck`; arches `amd64 arm64`.

### Task 2: Pin refresher

```yaml-task
id: 2
description: Add scripts/refresh-sha256-pins.sh and extend the test HTTP listener with body, status and path log
role: executor
model: sonnet
tdd: required
requirements: [R7]
acceptance:
  - cmd: bats tests/scripts/refresh_sha256_pins.bats tests/helpers_http_listener.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/refresh-sha256-pins.sh, tests/scripts/refresh_sha256_pins.bats, tests/helpers/http_listener.bash, tests/helpers_http_listener.bats]
depends_on: [1]
```

**Listener:** optional env `HTTP_LISTENER_BODY_FILE` (response body; default unchanged `{"tag_name": "v9.9.9"}`), `HTTP_LISTENER_STATUS` (default 200), and append `self.path` + newline to `${_dir}/paths` on every request. Add one test per option to `tests/helpers_http_listener.bats`; existing tests stay green.

**Script** (`#!/usr/bin/env bash`, executable, no `set -e`, functions plus a sourcing-guard-free `main "$@"`):

1. Args: `--constants <file>` (default `<repo>/lib/constants.sh`, repo from `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` resolved once at top), `--accept-changed`, tool names from `kind yq shellcheck`; anything else → usage on stderr, rc 2.
2. `source` the constants file once, then `lib/helpers.sh`, `lib/linux_ubuntu.sh`.
3. Per tool: `VER=${TOOL^^}_VER`, pins `${TOOL^^}_SHA256_{AMD64,ARM64}`, `${TOOL^^}_SHA256_FOR_VER`; first `grep -q "^${VAR}=" <target>` for all three pin vars, else `<tool>: <VAR> line missing in <file>; add it, then re-run`, rc 1. No tool named: select tools whose `_FOR_VER` != `*_VER`; none → print `pins up to date`, rc 0.
4. URL per arch from `_release_asset_url` (bats-only override `_REFRESH_ASSET_URL`); require `^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/]+)$` else `<tool>: <url> is not a GitHub release asset URL`, rc 1. Print `querying <url>` per arch.
5. One API call per tool: `curl -sS --max-time 20 --noproxy 127.0.0.1 -o <body> -w '%{http_code}' $(_github_api_base)/repos/<o>/<r>/releases/tags/<tag>`, adding `-H @-` fed by `_github_auth_header "${GITHUB_TOKEN}"` only when `GITHUB_TOKEN` is non-empty. Non-200 → `<tool>: GitHub API returned <code> for <api-url>`, plus `; set GITHUB_TOKEN (unauthenticated: 60 requests/hour)` for 403/429; rc 1.
6. Digest: `python3 -I -c` reading the body file, printing the matching asset's `digest` or nothing. Require `sha256:` prefix and `_sha256_pin_ok` on the rest, else `<tool>: <arch>: no usable sha256 digest for <asset> (got '<raw>')`, rc 1.
7. `_FOR_VER == *_VER` and a digest differs from the pin, without `--accept-changed`: `<tool>: <arch> asset changed at unchanged version <ver>: pin <old>, API <new>`, rc 1, nothing written.
8. Write: `mktemp "<dir>/.refresh-pins.XXXXXXXX"`, `cp -p target tmp`, `sed -i` each `^VAR=".*"$` line, then `grep -Fqx "VAR=\"new\""` for every var; all pass → `mv -f tmp target` and print `<VAR> <old> -> <new>` per changed var; any failure → `<tool>: <arch|->: <cause>`, `rm -f tmp`, rc 1.

**Tests** (`tests/scripts/refresh_sha256_pins.bats`): copy `lib/constants.sh` into `BATS_TEST_TMPDIR`, set its `*_VER` lines to `1.2.3`, start the listener with a body file of release JSON (two assets, distinct digests per arch), `export _GITHUB_API="${HTTP_LISTENER_URL}"`, `GITHUB_TOKEN=""`; `teardown` calls `stop_http_listener`. Cases: writes both arch digests to the right variables and `_FOR_VER`; default selects only the stale tool (`paths` holds its tag, not the fresh tool's); unchanged-version refusal and `--accept-changed`; each failure (missing line, `_REFRESH_ASSET_URL=https://example.invalid/x`, digest absent, digest `md5:…`, status 403 hint, read-back failure via a single-quoted `KIND_SHA256_AMD64='…'` line) prints its cause and `cmp` shows the target byte-identical. One listener serves one request: each case needs at most one API call.

**Interfaces — Produces:** `scripts/refresh-sha256-pins.sh [--constants <file>] [--accept-changed] [tool…]`, rc 0 written or up to date, 1 failure, 2 usage.

### Task 3: Fill the pins from the API

```yaml-task
id: 3
description: Run the refresher against lib/constants.sh and add the committed-constants test
role: executor
model: sonnet
tdd: required
requirements: [R2]
acceptance:
  - cmd: bats tests/setup_env/release_asset_pins.bats
    exit_code: 0
  - cmd: 'grep -c "^KIND_SHA256_AMD64=\"0\{64\}\"" lib/constants.sh'
    exit_code: 1
  - cmd: make test
    exit_code: 0
max_retries: 2
files_touched: [lib/constants.sh, tests/setup_env/release_asset_pins.bats]
depends_on: [2]
```

- [ ] Write the failing committed-constants test in `release_asset_pins.bats`: source the real `lib/constants.sh` (via `load_setup_env`), and for the six variables named one by one (`KIND_SHA256_AMD64` … `SHELLCHECK_SHA256_ARM64`) assert `_sha256_pin_ok` and that none is 64 zeros; assert `KIND_SHA256_FOR_VER == KIND_VER`, same for YQ and SHELLCHECK. Run: red (zeros, empty `_FOR_VER`).
- [ ] Run `scripts/refresh-sha256-pins.sh kind yq shellcheck` (network: three API requests). Expect 4 kind/yq hash lines and 3 `_FOR_VER` lines changed; the two shellcheck hashes must NOT change (they already equal the API digest). If shellcheck hashes change or any error prints, stop and report — do not edit pins by hand.
- [ ] Test green; gates; commit.

### Task 4: Retire telepresence, cf-terraforming and docker-compose

```yaml-task
id: 4
description: Remove the three tools' Linux installs, constants and tests, and telepresence's Brewfile entries and tap
role: executor
model: sonnet
tdd: required
requirements: [R6]
acceptance:
  - cmd: 'git grep -nI -e TELEPRESENCE -e CF_TERRAFORMING -e DOCKER_COMPOSE -e datawire -- lib Brewfile Brewfile.devtools setup_env.sh'
    exit_code: 1
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, lib/constants.sh, lib/helpers.sh, lib/macos.sh, Brewfile, Brewfile.devtools, tests/setup_env/linux_ubuntu.bats]
depends_on: [3]
```

- [ ] Write the failing retirement test in `linux_ubuntu.bats`: with `HAS_K8S=1 HAS_DEVTOOLS=1` run `_install_ubuntu_k8s_tools`, `_install_ubuntu_cloud_tools`, `_install_ubuntu_misc` (existing fixture helpers for those steps); assert `MOCK_CALLS_FILE` has no `wget` line matching `telepresence|cf-terraforming|docker-compose`, and (positive control) has `wget` lines for kind and yq. Red today.
- [ ] Delete: the telepresence block in `_install_ubuntu_k8s_tools`, the cf-terraforming block in `_install_ubuntu_cloud_tools`, the docker-compose block in `_install_ubuntu_misc` (fix its rc comment to name yq, opentofu, nala); `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `CF_TERRAFORMING_VER`, `DOCKER_COMPOSE_URL`, `DOCKER_COMPOSE_VER` and their comments in `lib/constants.sh`.
- [ ] Delete `tap "datawire/blackbird"` and the telepresence formula from `Brewfile` and `Brewfile.devtools`; remove `datawire/blackbird` from the `brew trust` calls in `lib/helpers.sh`, `lib/macos.sh`, `lib/linux_ubuntu.sh`. Leave `brewfile_drift.bats` fixtures alone.
- [ ] Delete or rewrite every test that asserts the three tools (k8s, cloud_tools, misc, the end-to-end fixture around the `case` on `*cf-terraforming*` and the tool loop listing all eleven). Keep each step's remaining assertions; don't weaken kind/yq assertions.
- [ ] Gates; commit.

### Task 5: Verifying installer

```yaml-task
id: 5
description: Pinned and --unverified forms of _install_fetched_binary with refusals, verify stage, two-field stamp and bats-only seams
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R4, R5]
acceptance:
  - cmd: bats tests/setup_env/fetched_binary.bats
    exit_code: 0
  - cmd: 'git grep -nI -e KIND_URL -e YQ_URL -e "--resolve" -- lib/linux_ubuntu.sh lib/constants.sh'
    exit_code: 1
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, lib/helpers.sh, lib/constants.sh, tests/setup_env/fetched_binary.bats, tests/setup_env/linux_ubuntu.bats]
depends_on: [4]
```

**Helper (`lib/helpers.sh`, below `_verify_sha256`):** `_sha256_check <name> <file> <var> <pin> <url> <tail>` → runs `_verify_sha256`; rc 0 silent; rc 1 `log_warn "<name>: sha256 mismatch: <var> expects <pin>, download is <actual> from <url>; <tail>"` (actual via `sha256sum`, `unreadable` if not 64-hex); rc 3 `<name>: could not read the download to verify it`; other `<name>: sha256 check could not run (rc N)`; returns the `_verify_sha256` rc.

**Installer:** rewrite the header comment and parsing.
- `--unverified <name> <url> <kind> <member> [<dest>]`: name ∉ `consul vault nomad packer vagrant` → `log_warn "<name>: --unverified is only for the HashiCorp tools"`, rc 1. URL-only stamp and today's flow; after a successful install print `<name>: not verified (pending HashiCorp apt, PR B)`.
- Pinned `<name> <bin|zip|tar> <member> [<dest>]`: URL from `_release_asset_url <name> "${_LINUX_ARCH}"` unless bats seam `_FETCHED_URL`; pin from `_release_asset_sha` unless bats seam `_FETCHED_SHA256` (which also skips the `_FOR_VER` check). Refusals, before the stamp check and `mkdir`, in this order: builder rc 2 → `<name>: unknown tool`; rc 3 → `<name>: no pin for arch '<arch>'`; `<NAME>_SHA256_FOR_VER` != `<NAME>_VER` → spec's "repo constants are inconsistent…" line; `_sha256_pin_ok` fails → `<name>: <VAR> is not a 64-hex sha256; refusing to download`. All rc 1 via `log_warn`.
- Stamp text `<url> <sha256>`; skip when stamp equals it and dest executable.
- After `wget`, before extract: `_sha256_check` with tail `nothing installed, existing binary kept. Re-run; if it repeats at an unchanged version, upstream changed the asset: investigate before scripts/refresh-sha256-pins.sh --accept-changed <name>`; failure → `_stage=verify`, nothing installed, no stamp. Success → `printf '%s: sha256 verified\n'`.
- Delete `--resolve`; delete `KIND_URL`, `YQ_URL` from `lib/constants.sh`.
- Callers: `_install_fetched_binary kind bin kind`, `_install_fetched_binary yq bin yq`, HashiCorp loop `_install_fetched_binary --unverified "${_tool}" "<url>" zip "${_tool}"`.

**Tests:** convert `fetched_binary.bats` to the pinned form with both seams (helper `_seam_for <file>` exporting `_FETCHED_URL="${URL}"` and `_FETCHED_SHA256` = real sha of the file; recompute after `_make_zip`/`_make_tar`); stamp assertions become `"${URL} ${_FETCHED_SHA256}"`; delete `--resolve` tests. Add every new case in the spec's Testing bullet for the installer, including: rc 3 and rc 126 by redefining `_verify_sha256` in the test (assert no "mismatch"); `--unverified` for each of the five names and refused for kind; seams ignored outside bats (blank `BATS_TEST_TMPDIR` around the call only; wget records the builder URL; a wrong real `KIND_SHA256_AMD64` gives the mismatch line). In `linux_ubuntu.bats` callers set `KIND_SHA256_AMD64`/`_FOR_VER` and YQ equivalents to the fixture's sha and the current `*_VER`; kind under `_LINUX_ARCH=arm64` installs with `KIND_SHA256_ARM64` and fails with the pins swapped; every URL grep asserts the URL is non-empty first.

### Task 6: rc-specific messages at the older verify sites

```yaml-task
id: 6
description: Use _sha256_check in _install_pinned_release_binary and _install_rustup_rs
role: executor
model: sonnet
tdd: required
requirements: [R11]
acceptance:
  - cmd: bats tests/setup_env/release_binary.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/release_binary.bats, tests/setup_env/linux_ubuntu.bats]
depends_on: [5]
```

- [ ] Failing tests: for each site, rc 3 and rc 126 (redefine `_verify_sha256`) print `could not read the download to verify it` / `sha256 check could not run (rc 126)` and no `mismatch`; rc 1 still prints `sha256 mismatch` with the variable, expected, actual and URL.
- [ ] Replace each bare `_verify_sha256 … || log_error "… sha256 mismatch …"` with `_sha256_check`. Names and tails: `_install_pinned_release_binary` var label `pinned sha256`, tail `refusing to install`; rustup var `RUSTUP_INIT_SHA256_*` (the one chosen), tail `refusing to execute`. Keep each site's cleanup and rc.
- [ ] Gates; commit.

### Task 7: Pin-based check-versions and --update

```yaml-task
id: 7
description: _check_one_pinned_release for kind, yq and shellcheck; derived token count; shellcheck hand-bump; _update_release_pin
role: executor
model: sonnet
tdd: required
requirements: [R8, R9, R10]
acceptance:
  - cmd: bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/check_versions_feeds.bats, tests/setup_env/workflows.bats]
depends_on: [6]
```

- `_check_one_pinned_release <tool> <pinned> <repo>`: `_fetch_github_latest`; empty → `  [WARN]     %-12s could not fetch latest version`; equal → `[OK]` line, rc 0; else `[OUTDATED]` line with `pinned=` and `latest=`, rc 1. Same printf widths as `_check_one_version`, no `installed=`. Never runs the tool.
- `run_check_versions`: `_run_cv_pinned_release` wrapper with the same `_token_refused` gate as `_run_cv_check`; kind (`kubernetes-sigs/kind`, `KIND_VER`), yq, shellcheck move to it. Print the line-break WARN after the checks, as `the ${_unchecked} checks that send it were not run`, so the count is derived (6).
- `_prompt_version_update`: first statement, `shellcheck` → print the spec's hand-bump line verbatim and return 0 with no prompt. After a yes: `kind|yq` → `_update_release_pin`; the `*)` arm is unchanged.
- `_update_release_pin <tool> <var> <latest>`: constants via `_OVERRIDE_CONSTANTS_PATH` or the default; `mktemp "<dir>/.constants.XXXXXXXX"`; `cp -p`; `sed` the `^<var>="…"` line; `grep -Fqx` read-back; run `${_OVERRIDE_REFRESH_PINS (bats-only):-<repo>/scripts/refresh-sha256-pins.sh} --constants <tmp> <tool>`; both ok → `mv -f`, print `  Updated <var> → <latest>` and the spec's "commit lib/constants.sh and merge the PR…" line; else `rm -f` tmp, print `  <tool>: refusing pin update: could not refresh sha256 pins`, rc 1.
- Delete `_update_url_pins`'s `yq` arm and its test (`_update_url_pins updates YQ_URL for yq`).
- Tests: stub `_fetch_github_latest`; `[OK]`/`[OUTDATED]` for each of the three with the tool absent from `PATH` (proves no binary run); equal pin → no `[y/N]`; refused token → `6 not checked` and `the 6 checks`; update stubs in both files for the new call counts (3 `_check_one_version`, 3 `_check_one_pinned_release`); `--update` success via a stub refresher that writes a known pin into `--constants` (assert `*_VER`, pin and `_FOR_VER` all changed); refresher failure → `cmp` byte-identical, refusal printed, no `Updated`; shellcheck prints the hand-bump line, no `[y/N]`, `cmp` identical.

### Task 8: Documentation

```yaml-task
id: 8
description: CLAUDE.md, ADR-0046, ADR-0041 tool list, ADR index, README and backlog rows (docs only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R12]
acceptance:
  - cmd: 'grep -q "refresh-sha256-pins.sh" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "_FETCHED_SHA256" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "0046" docs/adr/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0046-release-asset-pins-from-the-github-api-digest.md, docs/adr/README.md, docs/adr/0041-ubuntu-installs-stage-then-rename-and-stamp.md, README.md, docs/superpowers/README.md]
depends_on: [7]
```

- `CLAUDE.md`, one bullet each in the existing Test Seams / Key Conventions / `check-versions` entry (no figures, no `file:line`): refresher usage and hand bump (edit `*_VER`, run the script, commit both); `_FETCHED_URL`/`_FETCHED_SHA256` bats-only and the caller-test rule (callers set the real pin and `_FOR_VER`); `_REFRESH_ASSET_URL`, `_OVERRIDE_REFRESH_PINS`; pin naming `<TOOL>_SHA256_{AMD64,ARM64}` + `_FOR_VER`; the `--unverified` allowlist; the three retired tools and `sudo rm /usr/local/bin/<tool>` plus `rm ~/.local/share/dotfiles/installed/<tool>` for leftovers; the pin-based check-versions and the shellcheck hand-bump.
- ADR-0046 (Nygard, status Accepted): pins from the API digest, trust model (spec section "Trust model"), `--accept-changed`, why not checksum files or downloads. Index row.
- ADR-0041: drop the three tools from its tool list and the telepresence stamp sentence; add one line: stamps for pinned tools now hold `<url> <sha256>` (ADR-0046).
- README: update any mention of the retired tools or the check-versions tool list.
- Backlog (`docs/superpowers/README.md`): rewrite row "helper-installed binaries have no checksum…" to cover only the five HashiCorp tools (PR B, HashiCorp apt with holds); in "`check-versions` covers under half the pins" drop kind, docker-compose and cf-terraforming; add `| retired Linux binaries on other boxes | docker-compose, telepresence, cf-terraforming stay in /usr/local/bin on any Linux box other than claude and workstation until removed by hand (ADR-0046) |`.
- Orchestrator runs `make test` after this task.

## Orchestrator steps


- [ ] After Task 3: V1. In a fresh scratch dir, download the six asset URLs from `_release_asset_url` and compare `sha256sum` with each pin; save the table for the PR body.
- [ ] After Task 8: `make test` (record rc and count); V3 mutation controls, each in a scratch copy of the worktree: (a) delete the installer's verify call → `fetched_binary.bats` red; (b) swap the `kind` arch arms in `_release_asset_sha` → `release_asset_pins.bats` red; (c) let `--unverified` accept any name → `fetched_binary.bats` red; (d) refresher writes the amd64 digest to both arches → `refresh_sha256_pins.bats` red; (e) drop the unchanged-version refusal → `refresh_sha256_pins.bats` red. Confirm each mutation is present on disk before running.
- [ ] Phase 3: `finishing-a-development-branch`. PR body carries V1, V3, coverage from CI, and the V2 steps as post-merge.

## Non-goal check

Run 2026-10-13 by a fresh reviewer against `nongoal-check.md` with the spec's N1-N6. All six CLEAR; no plan revision or amendment needed.

| N | verdict | reviewer's basis |
| --- | --- | --- |
| N1 | CLEAR | Task 5 changes the HashiCorp loop only to the `--unverified` form; stamp and flow unchanged |
| N2 | CLEAR | no task changes how tflint/tfsec pins are bumped; Task 6 touches only verify messages |
| N3 | CLEAR | the only macOS change is Task 4's removal of telepresence and `datawire/blackbird` from the Brewfiles and `brew trust` calls |
| N4 | CLEAR | Task 5 keeps `wget` and adds verification after it; curl is used only by the refresher's API calls |
| N5 | CLEAR | `.github/workflows/ci.yml` is in no task's `files_touched` |
| N6 | CLEAR | Task 4 removes only the install; retired binaries are removed by hand (V2); the `rm -f` calls touch temp files only |
