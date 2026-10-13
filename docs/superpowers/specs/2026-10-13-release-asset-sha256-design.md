# Release asset sha256 pins

- **Date:** 2026-10-13
- **Backlog row:** "helper-installed binaries have no checksum and `wget` follows any redirect"
- **Builds on:** dotfiles#337 (`_sha256_pin_ok`, `_verify_sha256`, the go tarball pins)
- **Follow-up, not designed here:** GPG verification of HashiCorp's signed `SHA256SUMS`

## Problem

`_install_fetched_binary` (`lib/linux_ubuntu.sh`) downloads with a bare `wget`, then extracts and
installs into `/usr/local/bin` with `sudo`. It checks nothing about the bytes. Ten tools go through
it, from six call lines: kind, telepresence, consul, vault, nomad, packer, vagrant,
cf-terraforming, docker-compose and yq. Premise checked 2026-10-13 by reading the function and its
callers, and confirmed independently by all three round-1 lenses.

Three more defects surfaced while checking:

1. **`check-versions --update` already breaks shellcheck.** It bumps `SHELLCHECK_VER` but
   `_update_url_pins` treats shellcheck as having "no URL vars to update", so
   `SHELLCHECK_SHA256_AMD64`/`_ARM64` stay at the old release and the next `--update` makes the
   pinned install refuse on every Linux box. shellcheck is also pinned in `.github/workflows/ci.yml`
   (`SC_VER`, `SC_SHA256`, including a darwin hash), and `tests/setup_env/shellcheck_pin.bats`
   asserts the two versions match, so a bump also has to edit CI by hand.
2. **telepresence is stale.** It installs `.../download/tel2/linux/<arch>/latest/telepresence`,
   resolved at run time. On 2026-10-13 the amd64 URL resolved to **2.20.2** on S3, while GitHub's
   latest release is **v2.32.2**.
3. **check-versions sees 3 of these 11 tools.** It checks yq, vagrant and shellcheck. kind,
   telepresence, consul, vault, nomad, packer, cf-terraforming and docker-compose are never
   reported, so pinning telepresence would freeze it silently.

Upstream checksums: per-asset `.sha256sum` (kind), `SHA256SUMS` plus a GPG signature (HashiCorp),
`checksums.txt` (cf-terraforming, docker-compose), a multi-hash `checksums` file (yq), none
(shellcheck, telepresence). Every GitHub-hosted asset also carries a sha256 `digest` in the releases
API. Our pinned assets show no re-upload: each one's `updated_at` is within seconds of its
`created_at`. vagrant has no arm64 Linux build: today an arm64 box installs the amd64 zip, because
`_install_ubuntu_hashicorp` forces `_arch="amd64"` for vagrant. All measured 2026-10-13 from
`claude`, against the currently pinned versions.

## Design

### 1. One URL builder (`lib/linux_ubuntu.sh`)

`_release_asset_url <tool> <arch>` prints the download URL for a tool at its pinned `*_VER` and an
arch (`amd64` or `arm64`). It returns 1 with no output for an unknown tool or an arch the tool does
not ship (vagrant on arm64). It covers the ten fetched tools and shellcheck, and maps arch names
internally (`x86_64`/`aarch64` for docker-compose and shellcheck).

| tool                                  | URL                                                                                                                                                   |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| kind                                  | `https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-${arch}`                                                                                         |
| telepresence                          | `https://github.com/telepresenceio/telepresence/releases/download/v${TELEPRESENCE_VER}/telepresence-linux-${arch}`                                    |
| consul, vault, nomad, packer, vagrant | `https://releases.hashicorp.com/${tool}/${ver}/${tool}_${ver}_linux_${arch}.zip`                                                                      |
| cf-terraforming                       | `https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_${arch}.tar.gz` |
| docker-compose                        | `https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VER}/docker-compose-linux-${x86_64\|aarch64}`                                  |
| yq                                    | `https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_${arch}`                                                                       |
| shellcheck                            | `https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VER}/shellcheck-v${SHELLCHECK_VER}.linux.${x86_64\|aarch64}.tar.xz`           |

The installers and the refresher both call it, so the URL that is hashed is the URL that is
installed. `DOCKER_COMPOSE_VER` drops its leading `v` (`"5.6.0"`) so every `*_VER` here is X.Y.Z for
check-versions. `KIND_URL`, `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `DOCKER_COMPOSE_URL`,
`YQ_URL` and `HASHICORP_URL` are deleted from `lib/constants.sh`, along with the `yq` branch of
`_update_url_pins`. Their only readers are the callers, that branch, and tests (checked with
`git grep`; nothing in `scripts/` or `.github/` reads them). The shellcheck installer's
`_SHELLCHECK_URL` seam stays, defaulting to the builder.

### 2. Pins (`lib/constants.sh`)

New: `TELEPRESENCE_VER="2.32.2"`, and for `KIND`, `TELEPRESENCE`, `CF_TERRAFORMING`,
`DOCKER_COMPOSE`, `YQ`, `CONSUL`, `VAULT`, `NOMAD` and `PACKER`: `<TOOL>_SHA256_AMD64`,
`<TOOL>_SHA256_ARM64` and `<TOOL>_SHA256_VER`. For `VAGRANT`: `VAGRANT_SHA256_AMD64` and
`VAGRANT_SHA256_VER`. `SHELLCHECK_SHA256_VER` is added beside the existing shellcheck pins. That is
19 hashes and 11 version stamps. The arm64 pins are kept although every Linux box is amd64 today,
matching the existing shellcheck arm64 pins, so an arm64 box is supported rather than refused.

`<TOOL>_SHA256_VER` records the `*_VER` the hashes were computed for. Values are written by the
refresher in Phase 2 and checked by V1, never typed by hand.

`_release_asset_sha <tool> <arch>` prints the pin's variable name and value, and returns 1 when the
tool has no pin for that arch. It is an explicit `case` naming every variable, not indirect
expansion, so a grep for a pin finds its reader.

### 3. Installer (`_install_fetched_binary`)

The `<url>` argument is dropped: the installer derives the URL and pin from `<name>` and
`_LINUX_ARCH`. Two test seams, both read only when non-empty: `_FETCHED_URL` replaces the URL and
`_FETCHED_SHA256` replaces the pin (and skips the version-stamp check), as `_GO_SHA256` does for go.

Before the stamp check, in this order:

- no build for this arch: `<tool>: no <arch> build; skipping`, rc **0** (vagrant on arm64 is a
  known, permanent gap, not a failure to report on every run)
- `<TOOL>_SHA256_VER` differs from `*_VER`: `<tool>: pins are for <stamp-ver>, <TOOL>_VER is <ver>;
run scripts/refresh-sha256-pins.sh <tool>`, rc 1, no download
- no pin, or the pin fails `_sha256_pin_ok`: `<tool>: <VAR> is not a 64-hex sha256; refusing to
download`, rc 1, no download

The stamp file holds `<url> <sha256>`, so a refreshed pin forces a reinstall. A stamp in the old
URL-only form never matches, so every tool reinstalls once after this lands. That is what makes the
first run after merge verify every installed tool.

A `verify` stage runs between download and extract and reports by `_verify_sha256`'s rc, as
`_go_verify` does: rc 1 `<tool>: sha256 mismatch: <VAR> expects <pin>, download is <actual>`,
rc 3 `<tool>: could not read the download to verify it`, any other rc
`<tool>: sha256 check could not run (rc N)`. Only rc 1 prints "mismatch". On success it prints
`<tool>: sha256 verified`. Any failed stage removes the workdir, installs nothing and writes no
stamp.

`--resolve` and its code are deleted. telepresence was its only caller.

telepresence moves from 2.20.2 to 2.32.2 on its first run. Whether a 2.32 client works against a
traffic-manager already installed in a cluster by 2.20 is unmeasured; V2 records `telepresence
version` on each box.

### 4. Pin refresher (`scripts/refresh-sha256-pins.sh`)

A standalone executable, run as its own process and never sourced. It sources the target constants
file exactly once: sourcing `lib/constants.sh` twice in one shell aborts on
`APT_CONFFILE_OPTS: readonly variable` (measured by the Risk lens).

`refresh-sha256-pins.sh [--constants <file>] [tool…]`:

1. Reads `*_VER` and `<TOOL>_SHA256_VER` from the target file (default `lib/constants.sh`).
2. Selects tools: those named, else every tool whose `<TOOL>_SHA256_VER` differs from its `*_VER`.
   With nothing to do it prints `pins up to date` and exits 0. A default run therefore downloads
   only what a version bump made stale.
3. For each selected tool and each arch it ships, downloads `_release_asset_url`'s URL with
   `curl -fsSL --proto =https --proto-redir =https --max-time 600` and hashes it.
4. **Refuses to change a pin whose version did not change.** If a tool's `<TOOL>_SHA256_VER`
   already equals its `*_VER` and a new hash differs from the committed pin, it prints
   `<tool>: <arch> asset changed at unchanged version <ver>; refusing (investigate before
re-pinning)` and exits 1 without writing. A substituted asset is exactly what the pins exist to
   catch, so the tool that writes them must not launder one.
5. Writes all new pins and `<TOOL>_SHA256_VER` into a same-directory copy, reads each line back with
   `grep -Fqx`, and `mv`s the copy over the target only if all read back. Any failure prints tool,
   arch and cause, leaves the target byte-identical, and exits 1.

It prints `<VAR> <old> -> <new>` per changed line. A hand bump is: edit `*_VER`, run the script,
commit both. The bats suite fails until the script has run (R2's test), so a forgotten run is caught
at pre-push, not on the boxes.

### 5. `check-versions`

**Coverage.** `run_check_versions` adds `_run_cv_check` lines for kind, telepresence, consul, vault,
nomad, packer, cf-terraforming and docker-compose, each against its GitHub repo
(`kubernetes-sigs/kind`, `telepresenceio/telepresence`, `hashicorp/<tool>`,
`cloudflare/cf-terraforming`, `docker/compose`) with its own `version` command and an X.Y.Z regex.
They are GitHub-token checks, so a refused token skips them like the existing five.

**`--update` for the ten fetched tools** (the 8 above plus yq and vagrant) follows `_update_go_pin`:
copy the constants file to a same-directory temp, write the new `*_VER` there and read it back, run
`refresh-sha256-pins.sh --constants <temp> <tool>`, and `mv` the temp over the original only if both
succeed. On any failure the temp is removed, the original is untouched, and it prints
`<tool>: refusing pin update: could not refresh sha256 pins` and returns 1. A Ctrl-C at any point
leaves the original intact.

**shellcheck** is reported but not updated: `--update` prints
`shellcheck: bump by hand: SHELLCHECK_VER, scripts/refresh-sha256-pins.sh shellcheck, and SC_VER/SC_SHA256 in .github/workflows/ci.yml`
and returns 1, like homebrew-install's report-only arm. This closes the stale-pin defect without
designing a writer for `ci.yml`.

`_prompt_version_update`'s catch-all arm gains `|| return 1`, so a refused update no longer prints
`Updated <VAR>`.

### 6. Older verify call sites

`_install_pinned_release_binary` (tflint, tfsec, shellcheck) and `_install_rustup_rs` print the same
three rc-specific messages as section 3, replacing their single "sha256 mismatch" line, which #337
left for this follow-up.

## Trust model

The pins are hashes of what the upstream URL served when the refresher ran. They protect every later
install against a changed, truncated or substituted download and against a redirect to another host,
and the refresher refuses to re-pin a changed asset at an unchanged version. They are not independent
provenance: a release compromised before the refresher runs is pinned as is. V1 cross-checks against
the GitHub API `digest` and HashiCorp's `SHA256SUMS`, which catches a corrupted fetch, not a
compromised release. The HashiCorp GPG follow-up is the provenance step.

## Testing

- `_release_asset_url`: every tool on both arches against a hand-typed table of expected URLs (not
  derived from the function); in the same file, vagrant arm64 and an unknown tool return 1 with no
  output.
- `_release_asset_sha`: each of the 19 pins comes back for its tool and arch with its variable name;
  vagrant arm64 returns 1.
- Committed constants, named explicitly: every pin passes `_sha256_pin_ok`, and every
  `<TOOL>_SHA256_VER` equals its `*_VER`. A mutation that bumps one `*_VER` alone turns this red.
- Existing `tests/setup_env/fetched_binary.bats` tests set `_FETCHED_URL` and `_FETCHED_SHA256` (the
  real hash of their own fixture) and keep their assertions; stamp assertions change only to the new
  `<url> <sha256>` form. The `--resolve` tests are deleted with the feature. Tests in
  `tests/setup_env/linux_ubuntu.bats` that read the deleted `*_URL` constants are rewritten to read
  `_release_asset_url`, and each asserts the URL it greps for is non-empty.
- New installer tests: wrong pin (mismatch with the fixture's real hash, nothing installed, no
  stamp); malformed pin, missing pin and version-stamp mismatch (named refusal, no `wget`); vagrant
  arm64 (skip message, rc 0, no `wget`); rc 3 and rc 126 (no "mismatch"); success prints
  `sha256 verified`; amd64 and arm64 select their own pin (passes under its arch, fails with the pins
  swapped); a stamp holding the right URL and an old sha reinstalls.
- Refresher (curl shim on PATH writing URL-dependent content, so the arches hash differently): writes
  the right hash and `_SHA256_VER` to the right variables and prints the changes; default selects
  only tools with a version mismatch; refuses a changed hash at an unchanged version. Each failure
  case (failed download, non-https URL via a test-only override of `_release_asset_url`, read-back
  failure, changed asset) asserts the printed cause and that the shim was called, and that the target
  is byte-identical (`cmp`).
- `check-versions`: each new tool is reported; `--update` for a fetched tool changes both `*_VER` and
  pins on success; with the refresher failing the file is byte-identical, the refusal prints, and
  "Updated" does not; shellcheck prints the hand-bump message and changes nothing.
- Older call sites: rc 3 and rc 126 print their messages and not "mismatch".
- Mutation controls, recorded in the PR: delete the installer's verify stage; swap the arch arms in
  `_release_asset_sha`; make the refresher write the amd64 hash to both arches; drop the unchanged-
  version refusal; drop `|| return 1` from the catch-all arm. Each single change turns a named test red.

## Requirements

- **R1.** `[PR1]` `_release_asset_url <tool> <arch>` returns the URL in section 1's table for each of the eleven tools and both arches, and returns 1 with no output for vagrant on arm64 or an unknown tool.
- **R2.** `[PR1]` `lib/constants.sh` defines `TELEPRESENCE_VER="2.32.2"`, `DOCKER_COMPOSE_VER` without a leading `v`, the 19 hash pins and 11 `<TOOL>_SHA256_VER` stamps of section 2, each stamp equal to its `*_VER`, and no longer defines `KIND_URL`, `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `DOCKER_COMPOSE_URL`, `YQ_URL` or `HASHICORP_URL`.
- **R3.** `[PR1]` Before its stamp check, `_install_fetched_binary` skips with rc 0 for an arch with no build, and refuses with rc 1 and no download on a version-stamp mismatch, a missing pin, or a malformed pin, naming the cause.
- **R4.** `[PR1]` `_install_fetched_binary` runs `_verify_sha256` between download and extract; on failure it installs nothing and writes no stamp and prints "mismatch" only for rc 1; on success it prints `sha256 verified` and writes a stamp holding the URL and the pin.
- **R5.** `[PR1]` `--resolve` is removed from `_install_fetched_binary`.
- **R6.** `[PR1]` `scripts/refresh-sha256-pins.sh` refreshes only tools whose `_SHA256_VER` differs from `*_VER` unless tools are named, writes hashes and stamps with an atomic read-back replace, refuses a changed hash at an unchanged version, and leaves the target byte-identical on any failure.
- **R7.** `[PR1]` `check-versions` reports kind, telepresence, consul, vault, nomad, packer, cf-terraforming and docker-compose.
- **R8.** `[PR1]` `check-versions --update` for the ten fetched tools changes `*_VER` and that tool's pins together through a temp copy and `mv`, and on a refresh failure leaves `lib/constants.sh` byte-identical, prints the refusal and does not print "Updated".
- **R9.** `[PR1]` `check-versions --update` for shellcheck changes nothing and prints the hand-bump instruction naming `ci.yml`.
- **R10.** `[PR1]` `_install_pinned_release_binary` and `_install_rustup_rs` print the rc-specific verify messages of R4.
- **R11.** `[PR1]` `CLAUDE.md` documents the refresher, the `_FETCHED_URL`/`_FETCHED_SHA256` seams, the pin and stamp naming, the hand-bump procedure, and the new check-versions coverage.
- **V1.** Each GitHub-hosted pin equals the releases API `digest` for its asset, and each HashiCorp pin equals the line in that version's `SHA256SUMS`; record the comparison in the PR.
- **V2.** After merge, on `claude` and `workstation`, run the k8s, hashicorp, cf-terraforming and misc install steps with `_DL_STAMP_DIR` pointed at an empty temp dir; every tool prints `sha256 verified`, telepresence reports 2.32.2, and nothing prints a verify failure.
- **V3.** The mutation controls in Testing each turn a named test red; record them in the PR.
- **N1.** No GPG signature verification (separate follow-up).
- **N2.** No change to how tflint or tfsec pins are bumped.
- **N3.** No change to macOS installs.
- **N4.** `_install_fetched_binary` keeps `wget` for downloads.
- **N5.** No automated edit of `.github/workflows/ci.yml`.

## Multi-Lens Review

Reviewed at commit: `f5e68ec8` (round 1, first draft)

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

