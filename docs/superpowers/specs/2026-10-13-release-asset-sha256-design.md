# Release asset sha256 pins

- **Date:** 2026-10-13
- **Backlog row:** "helper-installed binaries have no checksum and `wget` follows any redirect"
- **Builds on:** dotfiles#337 (`_sha256_pin_ok`, `_verify_sha256`, the go tarball pins)
- **Scope:** PR A of two. PR A pins the GitHub-hosted tools and removes the standalone
  docker-compose. PR B (own spec, after this merges) moves the five HashiCorp tools to HashiCorp's
  GPG-signed apt repo with version holds, which replaces the earlier "HashiCorp GPG" follow-up.

## Problem

`_install_fetched_binary` (`lib/linux_ubuntu.sh`) downloads with a bare `wget`, then extracts and
installs into `/usr/local/bin` with `sudo`. It checks nothing about the bytes. Ten tools go through
it from six call lines: kind, telepresence, cf-terraforming, docker-compose, yq and the five
HashiCorp tools. Premise checked 2026-10-13 by reading the function and its callers, and confirmed by
all six Step 8 lens passes.

Found while checking, all measured 2026-10-13:

1. **`check-versions --update` already breaks shellcheck.** It bumps `SHELLCHECK_VER` and leaves
   `SHELLCHECK_SHA256_AMD64`/`_ARM64` at the old release, so the next update makes the pinned install
   refuse on every Linux box. shellcheck is also pinned at three sites in `.github/workflows/ci.yml`
   (two linux x86_64, one darwin aarch64), and `tests/setup_env/shellcheck_pin.bats` checks the
   versions match.
2. **telepresence is stale.** It installs `.../tel2/linux/<arch>/latest/telepresence`, which for
   amd64 resolved to **2.20.2** on S3; GitHub's latest release is **v2.32.2**.
3. **check-versions does not see kind, telepresence or cf-terraforming,** and where it does see a
   tool it compares the _installed_ binary with upstream (`_check_one_version`). `-t update` never
   reinstalls these tools (only `-t setup`/`-t developer` reach `install_ubuntu_packages`), so on
   `claude` kind is 0.32.0 against a 0.33.0 pin, and on the Studio Homebrew holds its own versions.
   An installed-vs-latest check would prompt "update X from V to V" and nag forever on macOS.
4. **The standalone docker-compose is redundant.** `_install_ubuntu_docker` installs
   `docker-compose-plugin` from Docker's signed apt repo (`docker compose version`: v5.6.0 on
   `claude`), while `/usr/local/bin/docker-compose` there is a stale v5.1.4 that no tracked script
   runs.

Upstream checksums for the four tools PR A pins: per-asset `.sha256sum` (kind), `checksums.txt`
(cf-terraforming), a multi-hash `checksums` file (yq), none (telepresence). Every one of them is a
GitHub release asset with a sha256 `digest` in the releases API (kind's `kind.sigs.k8s.io/dl` URL
redirects to it), and none shows a re-upload (`updated_at` within seconds of `created_at`).
Population: the four assets at their pinned versions plus shellcheck v0.11.0, queried from `claude`.

## Design

### 1. URL builder (`lib/linux_ubuntu.sh`)

`_release_asset_url <tool> <arch>` prints the URL for a tool at its pinned `*_VER` and `amd64` or
`arm64`. It returns **2** with no output for an unknown tool. All five tools ship both arches.

| tool            | URL                                                                                                                                                   |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| kind            | `https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-${arch}`                                                                                         |
| telepresence    | `https://github.com/telepresenceio/telepresence/releases/download/v${TELEPRESENCE_VER}/telepresence-linux-${arch}`                                    |
| cf-terraforming | `https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_${arch}.tar.gz` |
| yq              | `https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_${arch}`                                                                       |
| shellcheck      | `https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VER}/shellcheck-v${SHELLCHECK_VER}.linux.${x86_64\|aarch64}.tar.xz`           |

The installer and the refresher both call it, so the URL hashed is the URL installed. `KIND_URL`,
`TELEPRESENCE_URL`, `CF_TERRAFORMING_URL` and `YQ_URL` are deleted from `lib/constants.sh`, with the
`yq` branch of `_update_url_pins`. `HASHICORP_URL` stays for PR B. The shellcheck installer's
`_SHELLCHECK_URL` seam stays, defaulting to the builder.

### 2. Pins (`lib/constants.sh`)

New: `TELEPRESENCE_VER="2.32.2"`; for `KIND`, `TELEPRESENCE`, `CF_TERRAFORMING` and `YQ`:
`<TOOL>_SHA256_AMD64`, `<TOOL>_SHA256_ARM64` and `<TOOL>_SHA256_FOR_VER`; and
`SHELLCHECK_SHA256_FOR_VER` beside the existing shellcheck pins. That is 8 new hashes and 5
`_FOR_VER` lines. `<TOOL>_SHA256_FOR_VER` is the `*_VER` the hashes were computed for. arm64 pins
are kept, matching shellcheck's, although every Linux box is amd64 today.

Phase 2 adds the lines with all-zero hashes and an empty `_FOR_VER`, then runs the refresher, so no
value is typed by hand.

`_release_asset_sha <tool> <arch>` prints the pin's variable name and value, and returns 2 for an
unknown tool. It is an explicit `case` naming every variable, so a grep for a pin finds its reader.

### 3. Installer (`_install_fetched_binary`)

Two calling forms:

- **Pinned:** `_install_fetched_binary <name> <bin|zip|tar> <member> [<dest>]`. URL and pin come
  from the builder for `_LINUX_ARCH`.
- **Unverified (PR B removes it):** `_install_fetched_binary --unverified <url> <name> <kind>
<member> [<dest>]`, accepted only for `consul`, `vault`, `nomad`, `packer` and `vagrant`. Any other
  name with `--unverified` is refused with rc 1, so a pinned tool cannot opt out.

Pinned form, before the stamp check and before any download:

- unknown tool (builder rc 2): `<name>: unknown tool`, rc 1
- `<TOOL>_SHA256_FOR_VER` differs from `*_VER`: `<name>: repo constants are inconsistent: pins are
for <for-ver>, <TOOL>_VER is <ver>; fix lib/constants.sh in the repo (scripts/refresh-sha256-pins.sh
<name>)`, rc 1
- missing or malformed pin: `<name>: <VAR> is not a 64-hex sha256; refusing to download`, rc 1

The stamp file holds `<url> <sha256>`, so a refreshed pin forces a reinstall. Old URL-only stamps
never match, so every pinned tool reinstalls, verified, on the first `-t setup`/`-t developer` after
merge (roughly 210 MB on amd64, mostly telepresence; one cached `sudo` session).

A `verify` stage between download and extract reports by `_verify_sha256`'s rc: rc 1
`<name>: sha256 mismatch: <VAR> expects <pin>, download is <actual>; nothing installed, existing
binary kept`, rc 3 `<name>: could not read the download to verify it`, any other rc
`<name>: sha256 check could not run (rc N)`. Only rc 1 says "mismatch". Success prints
`<name>: sha256 verified`. Any failed stage installs nothing and writes no stamp.

`--resolve` is deleted; telepresence was its only caller. telepresence moves from 2.20.2 to 2.32.2
on its first run; compatibility of a 2.32 client with a 2.20 traffic-manager already in a cluster is
unmeasured, so V2 records `telepresence version`.

Test seams `_FETCHED_URL` and `_FETCHED_SHA256` (read only when non-empty) replace the URL and pin and
bypass the `_FOR_VER` check. They are for unit tests of the installer only. Caller tests set the real
pin variables (`KIND_SHA256_AMD64`, `KIND_SHA256_FOR_VER`, …) to their fixture's values, so the
caller-name to pin-variable wiring runs in every caller test.

### 4. docker-compose removal

`_install_ubuntu_misc` stops installing docker-compose. When `${_DL_STAMP_DIR}/docker-compose`
exists, which proves this repo installed the binary, it runs `sudo rm -f /usr/local/bin/docker-compose`
and removes the stamp, printing `docker-compose: removed standalone binary; use docker compose`. A
`/usr/local/bin/docker-compose` without that stamp is left alone. `DOCKER_COMPOSE_VER` and
`DOCKER_COMPOSE_URL` are deleted, and the comments in `.config/.zshrc.d/6_path.zsh` and ADR-0041 that
name it are updated. The Docker plugin, macOS and Windows are untouched.

### 5. Pin refresher (`scripts/refresh-sha256-pins.sh`)

A standalone executable, run as its own process and never sourced; it sources the target constants
file once (sourcing `lib/constants.sh` twice in one shell aborts on a readonly array).

`refresh-sha256-pins.sh [--constants <file>] [--accept-changed] [tool…]`:

1. Reads `*_VER` and `_FOR_VER` from the target (default `lib/constants.sh`). Every pin line must
   already exist; a missing line is an error, never appended.
2. Selects the named tools, else every tool whose `_FOR_VER` differs from `*_VER` (prints
   `pins up to date` when none). Unchanged tools are never re-downloaded.
3. For each tool and arch prints `fetching <url>`, then downloads with
   `curl -fsSL --proto =https --proto-redir =https --max-time 600` and hashes it.
4. If a tool's `_FOR_VER` already equals its `*_VER` and a new hash differs from the committed one,
   prints `<tool>: <arch> asset changed at unchanged version <ver>` with old and new hashes and exits
   1 without writing, unless `--accept-changed` was given. That flag is the only sanctioned re-pin at
   an unchanged version, for a deliberate upstream rebuild.
5. Writes hashes and `_FOR_VER` into a same-directory copy, reads every line back with `grep -Fqx`,
   and `mv`s it over the target only if all read back; prints `<VAR> <old> -> <new>` per change. Any
   failure prints tool, arch and cause, leaves the target byte-identical, and exits 1.

A hand bump is: edit `*_VER`, run the script, commit both. Until the script runs, a bats test fails
(section 7), so a forgotten run is caught at pre-push.

### 6. `check-versions`

**Pin-based check.** New `_check_one_pinned_release <tool> <pinned> <repo>` compares the **pin**
with GitHub's latest release: `[OK]` when equal, `[OUTDATED]` when latest is newer, `[WARN]` on a
fetch failure. It does not run the installed binary, so it behaves the same on Linux and macOS and
never offers an update to the version already pinned. kind, telepresence, cf-terraforming and yq use
it (yq moves off the installed-binary check). The token-refusal message derives its count of
GitHub-token checks from the list instead of the literal "5", and its tests assert the derived count.

**`--update`** for those four tools goes through a new arm in `_prompt_version_update`, not the
catch-all: `_update_release_pin <tool> <var> <latest>` copies the constants file to a same-directory
temp, writes and reads back the new `*_VER`, runs `refresh-sha256-pins.sh --constants <temp> <tool>`,
and `mv`s the temp over the original only if both succeed. On failure the temp is removed, the
original is untouched, it prints `<tool>: refusing pin update: could not refresh sha256 pins`, and
returns 1. On success it prints `<tool>: run ./setup_env.sh -t developer on each Linux box to
install <latest>`. A Ctrl-C leaves the original intact.

**shellcheck** gets its own arm that prompts nothing and prints
`shellcheck: bump by hand: SHELLCHECK_VER, scripts/refresh-sha256-pins.sh shellcheck, and the three SC_VER/SC_SHA256 sites in .github/workflows/ci.yml (darwin hash: gh api repos/koalaman/shellcheck/releases/tags/v<ver> --jq '.assets[]|select(.name|test("darwin.aarch64.tar.xz"))|.digest')`,
then returns 1.

The catch-all arm (ruby, zsh, gitleaks, vagrant) gains `|| return 1`.

### 7. Older verify call sites

`_install_pinned_release_binary` (tflint, tfsec, shellcheck) and `_install_rustup_rs` print the same
three rc-specific messages as section 3, replacing the single "sha256 mismatch" line #337 deferred.

## Trust model

The pins are hashes of what the upstream URL served when the refresher ran. They protect every later
install against a changed, truncated or substituted download and a redirect to another host, and the
refresher will not re-pin a changed asset at an unchanged version without `--accept-changed`. They
are not independent provenance; V1 cross-checks against the GitHub API `digest`, which catches a
corrupted fetch, not a compromised release.

## Testing

- `_release_asset_url`: all five tools on both arches against a hand-typed URL table (not derived
  from the function); an unknown tool returns 2 with no output, in the same file.
- `_release_asset_sha`: each of the 10 pins (8 new, 2 shellcheck) returns its variable name and
  value; unknown tool returns 2.
- Committed constants, named explicitly: every pin passes `_sha256_pin_ok` and every `_FOR_VER`
  equals its `*_VER`. Bumping one `*_VER` alone turns this red.
- Installer unit tests (`tests/setup_env/fetched_binary.bats`) set `_FETCHED_URL` and
  `_FETCHED_SHA256` and keep their assertions; stamp assertions change only to the `<url> <sha256>`
  form; `--resolve` tests are deleted. New: wrong pin (mismatch with the fixture's real hash, nothing
  installed, no stamp); malformed, missing and `_FOR_VER`-mismatched pins (named refusal, no `wget`);
  unknown tool (rc 1, no `wget`); rc 3 and rc 126 (no "mismatch"); success prints `sha256 verified`;
  a stamp with the right URL and an old sha reinstalls; `--unverified` accepted for each HashiCorp
  name and refused for every other name.
- Caller tests (`tests/setup_env/linux_ubuntu.bats`) set the real pin and `_FOR_VER` variables to
  their fixture's values instead of the seams, and every grep for a URL asserts the URL is non-empty.
  amd64 and arm64 select their own pin through a caller (passes under its arch, fails with the pins
  swapped).
- docker-compose: with a stamp, the binary and stamp are removed and the message prints; without a
  stamp, an existing `/usr/local/bin/docker-compose` (fixture dir) is untouched; no install is
  attempted either way.
- Refresher (curl shim writing URL-dependent content): writes each hash and `_FOR_VER` to the right
  variable; prints `fetching` per asset and the changes; default selects only stale tools; refuses a
  changed hash at an unchanged version and accepts it with `--accept-changed`; a missing line is an
  error. Each failure case asserts the printed cause, that the shim was called, and that the target
  is byte-identical (`cmp`).
- check-versions: each of the four tools prints `[OK]` or `[OUTDATED]` from a stubbed latest (not
  `[SKIP]`); a pin equal to latest never prompts; `--update` success changes `*_VER`, pins and
  `_FOR_VER` together and prints the `-t developer` line; refresh failure leaves the file
  byte-identical, prints the refusal and not "Updated"; shellcheck prints the hand-bump message with
  no prompt and changes nothing; the token-refusal count matches the list.
- Older call sites: rc 3 and rc 126 print their messages and not "mismatch".
- Mutation controls, recorded in the PR: delete the installer's verify stage; swap the arch arms in
  `_release_asset_sha`; let `--unverified` accept any name; make the refresher write the amd64 hash
  to both arches; drop the unchanged-version refusal; route the four tools through the catch-all arm.
  Each single change turns a named test red.

## Requirements

- **R1.** `[PR1]` `_release_asset_url <tool> <arch>` returns the URL in section 1's table for kind, telepresence, cf-terraforming, yq and shellcheck on both arches, and returns 2 with no output for an unknown tool.
- **R2.** `[PR1]` `lib/constants.sh` defines `TELEPRESENCE_VER="2.32.2"`, the 8 new hash pins and 5 `<TOOL>_SHA256_FOR_VER` lines of section 2 each equal to its `*_VER`, and no longer defines `KIND_URL`, `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `YQ_URL`, `DOCKER_COMPOSE_VER` or `DOCKER_COMPOSE_URL`.
- **R3.** `[PR1]` In its pinned form, `_install_fetched_binary` refuses with rc 1 and no download on an unknown tool, a `_FOR_VER` mismatch, or a missing or malformed pin, naming the cause, before its stamp check.
- **R4.** `[PR1]` `_install_fetched_binary` runs `_verify_sha256` between download and extract in its pinned form; on failure it installs nothing, writes no stamp and says "mismatch" only for rc 1; on success it prints `sha256 verified` and writes a stamp holding the URL and the pin.
- **R5.** `[PR1]` `_install_fetched_binary --unverified` is accepted only for consul, vault, nomad, packer and vagrant, and `--resolve` is removed.
- **R6.** `[PR1]` `_install_ubuntu_misc` no longer installs docker-compose, and removes `/usr/local/bin/docker-compose` and its stamp only when that stamp exists.
- **R7.** `[PR1]` `scripts/refresh-sha256-pins.sh` refreshes only tools whose `_FOR_VER` differs from `*_VER` unless tools are named, refuses a changed hash at an unchanged version unless `--accept-changed` is given, never appends missing lines, writes through an atomic read-back replace, and leaves the target byte-identical on any failure.
- **R8.** `[PR1]` `check-versions` compares the pins of kind, telepresence, cf-terraforming and yq with GitHub's latest release, without running the installed binary.
- **R9.** `[PR1]` `check-versions --update` for those four tools changes `*_VER`, pins and `_FOR_VER` together through a temp copy and `mv`, and on refresh failure leaves `lib/constants.sh` byte-identical, prints the refusal and does not print "Updated".
- **R10.** `[PR1]` `check-versions --update` for shellcheck prompts nothing, changes nothing and prints the hand-bump instruction naming the three `ci.yml` sites.
- **R11.** `[PR1]` `_install_pinned_release_binary` and `_install_rustup_rs` print the rc-specific verify messages of R4.
- **R12.** `[PR1]` `CLAUDE.md` documents the refresher and its hand-bump procedure, the `_FETCHED_URL`/`_FETCHED_SHA256` seams and the caller-test rule, the pin and `_FOR_VER` naming, the `--unverified` allowlist, the docker-compose removal, and the pin-based check-versions.
- **V1.** Each new pin equals the releases API `digest` for its asset; record the comparison in the PR.
- **V2.** After merge, on `claude` and `workstation`, run the k8s, cf-terraforming and misc install steps with `_DL_STAMP_DIR` pointed at an empty temp dir (after noting whether a docker-compose stamp existed); kind, telepresence, cf-terraforming and yq each print `sha256 verified`, `telepresence version` reports 2.32.2, and docker-compose is removed where it was stamped.
- **V3.** The mutation controls in Testing each turn a named test red; record them in the PR.
- **N1.** No change to how the five HashiCorp tools are downloaded (PR B).
- **N2.** No change to how tflint or tfsec pins are bumped.
- **N3.** No change to macOS or Windows installs.
- **N4.** `_install_fetched_binary` keeps `wget` for downloads.
- **N5.** No automated edit of `.github/workflows/ci.yml`.
- **N6.** No removal of `docker-compose-plugin` or any `docker-compose` binary this repo did not stamp.

## Multi-Lens Review

Reviewed at commit: `f5e68ec8` (round 1, first draft; covered all ten fetched tools)

### Goal-Fit

Finding: Worth building; premises confirmed. (1) vagrant on arm64 installs an amd64 binary today,
not a 404. (2) V2 could pass without verifying anything, because the URL-only stamp skips unchanged
tools. (3) Nothing ties a pin to its version: a hand bump without the refresher passes `make test`
and CI, then shows as a tamper-looking mismatch on every box. (4) arm64 pins have no consumer today;
the refresher's non-https test had no seam.
Assumption: assets at a pinned version are never re-uploaded. Checked: every pinned asset's
`updated_at` is within seconds of `created_at`; no re-upload.
Disposition: Addressed (operator, 2026-10-13): vagrant premise corrected and arm64 now skips with rc 0;
stamp is `url sha`, V2 uses an empty stamp dir and requires `sha256 verified`; `<TOOL>_SHA256_VER`
stamps with a bats equality test and an installer refusal; arm64 pins kept with the reason stated;
non-https test overrides `_release_asset_url`.

### Ergonomics

Finding: (1) Forgotten refresher runs fail late and look like tampering. (2) 8 of 11 tools are
invisible to check-versions; telepresence would freeze. (3) A refused `--update` still prints
"Updated" (`_prompt_version_update` catch-all ignores the rc; confirmed at `lib/workflows.sh:1614`).
(4) A default refresher run downloads ~1.1 GB and would silently re-pin a substituted asset at an
unchanged version. (5) The releases API `digest` is a cheap independent check. (6) vagrant arm64
refusal would fail the hashicorp step every run. (7) Refresher failure tests could pass on a no-op.
Assumption: assets stay byte-stable at a pinned version (same check as Goal-Fit; no re-upload seen).
Disposition: Addressed (operator, 2026-10-13): version stamps plus pre-push test; the 8 tools added
to check-versions with `--update` through the refresher (operator chose "add all 8 now"); catch-all
gains `|| return 1`; refresher defaults to stale tools and refuses a changed asset at an unchanged
version; V1 uses the API `digest`; vagrant arm64 skips; failure tests assert cause and shim call.

### Risk

Finding: (1) The 38 existing `fetched_binary` tests use `example.invalid` URLs and cannot keep their
assertions once `<url>` is dropped. (2) Deleting the `*_URL` constants makes four `linux_ubuntu.bats`
greps vacuous. (3) Copy-aside-then-restore is not atomic under Ctrl-C, the version sed has no
read-back, and "Updated" still prints. (4) Sourcing `lib/constants.sh` twice aborts on a readonly
array (measured). (5) URL-only stamps skip verification on unchanged tools. (6) shellcheck's pin also
lives in `ci.yml`, so a successful `--update` turns `make test` red. (7) vagrant arm64 refusal fails
the step; telepresence 2.20 to 2.32 cluster compatibility is unmeasured.
Assumption: running the install steps after merge actually downloads every tool; false where stamps
match. Resolved by the `url sha` stamp format, which every existing stamp fails.
Disposition: Addressed (operator, 2026-10-13): `_FETCHED_URL` seam; constant-reading tests rewritten
with non-empty assertions; `--update` uses temp copy plus `mv` with read-back; refresher is a
standalone process that sources once; `url sha` stamps; shellcheck `--update` is report-only with a
hand-bump message (N5); vagrant skips; telepresence compatibility recorded in V2.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `e745ba79` (all three lenses, round-1 revision)

**Goal-Fit.** Finding: HashiCorp's signed apt repo carries all five HashiCorp tools at the pinned
versions (measured on noble and resolute), which would remove half the mechanism and bring GPG
provenance forward; the standalone docker-compose duplicates `docker-compose-plugin`; section 5 did
not name where the new `--update` arms dispatch, and the natural place (`_update_url_pins`, after
`_update_version_pin`'s in-place `sed`) breaks R8 and R9; the arm64 pins and the installer-side stamp
refusal were close to decoration; "each new tool is reported" passes on a `[SKIP]` line.
Assumption: the HashiCorp tools must stay as direct downloads; settled by the operator choosing the
apt repo for PR B. HashiCorp release timestamps show `created == updated` for all five.
Disposition: Addressed (operator, 2026-10-13): split into PR A (this spec) and PR B (HashiCorp via
apt with holds); docker-compose removed; dedicated `--update` arms named; pin-based check tests
require `[OK]`/`[OUTDATED]`.

**Ergonomics.** Finding: blocker, `_check_one_version` compares the installed binary with latest
while `-t update` never reinstalls these tools, so it prompts "update X from V to V" and re-downloads
(measured: 7 tools on `claude` installed behind pins that equal latest); a successful `--update` gave
no next step; the refresher downloads silently; the shellcheck message missed the darwin hash and the
third `ci.yml` site; the installer's `_FOR_VER` message told a box to edit tracked constants; the
mismatch message gave no next action; `_SHA256_VER` reads like a hash variant; first-run cost
unstated; one test could pass on `[SKIP]`.
Assumption: HashiCorp assets are byte-stable (moved to PR B, which uses signed apt instead).
Disposition: Addressed (operator, 2026-10-13): pin-based check-versions; `-t developer` next-step
line; `fetching <url>` per asset; full shellcheck instruction with the darwin digest command; message
fixes; `_SHA256_FOR_VER` naming; first-run cost stated; tests require a verdict line.

**Risk.** Finding: check-versions on macOS would report Homebrew's versions forever and let a stale
Linux pin show `[OK]`; an unknown tool name would "skip" with rc 0 (shared rc with no-arch); the seams
being process-wide means no caller test exercises the pin wiring; the literal "5 checks" goes stale;
re-pinning at an unchanged version had no sanctioned path; the refresher's first run had no defined
bootstrap; a running telepresence daemon could mismatch after the upgrade.
Assumption: non-GitHub hosts serve byte-stable assets; PR A pins only GitHub-hosted assets.
Disposition: Addressed (operator, 2026-10-13): pin-based check; unknown tool is rc 2 and an install
refusal, and the arch-skip arm is gone (all pinned tools ship both arches); caller tests set the real
pin variables; derived token-check count; `--accept-changed`; placeholder lines then a refresher run;
telepresence version recorded in V2.

Signals at this point: findings were still design-level, and the corrections removed surface (10 to 4
pinned tools, 19 to 8 hashes, the vagrant arm, the arch-skip arm, docker-compose), so a full round 3
follows.

