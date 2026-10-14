# Release asset sha256 pins

- **Date:** 2026-10-13
- **Approved:** 2026-10-13
- **Backlog row:** "helper-installed binaries have no checksum and `wget` follows any redirect"
- **Builds on:** dotfiles#337 (`_sha256_pin_ok`, `_verify_sha256`, the go tarball pins)
- **Scope:** PR A of two. PR A pins kind and yq, gives shellcheck a pin refresher, and retires the
  standalone docker-compose, telepresence and cf-terraforming on Linux. PR B (own spec, after this
  merges) moves the five HashiCorp tools to HashiCorp's GPG-signed apt repo with version holds.

## Problem

`_install_fetched_binary` (`lib/linux_ubuntu.sh`) downloads with a bare `wget`, then extracts and
installs into `/usr/local/bin` with `sudo`, checking nothing about the bytes. Ten tools go through it
from six call lines (kind, telepresence, cf-terraforming, docker-compose, yq, and the five HashiCorp
tools). Premise checked 2026-10-13 by reading the function and its callers, and confirmed by nine
Step 8 lens passes.

Measured 2026-10-13 while reviewing:

1. **`check-versions --update` already breaks shellcheck.** It bumps `SHELLCHECK_VER` and leaves
   `SHELLCHECK_SHA256_AMD64`/`_ARM64` at the old release, so the next update makes the pinned install
   refuse on every Linux box. shellcheck is also pinned at three sites in `.github/workflows/ci.yml`
   (two linux x86_64, one darwin aarch64), checked by `tests/setup_env/shellcheck_pin.bats`.
2. **check-versions compares the installed binary, not the pin** (`_check_one_version`), while
   `-t update` never reinstalls these tools (only `-t setup`/`-t developer` reach
   `install_ubuntu_packages`). On `claude` kind is 0.32.0 against a 0.33.0 pin that equals latest; on
   the Studio Homebrew holds its own versions. Such a check prompts "update X from V to V" and nags
   forever on macOS.
3. **Three of the ten tools are unused and one is redundant.** No tracked script in any personal repo
   runs `telepresence`, `cf-terraforming` or the hyphenated `docker-compose`; `claude` shows no shell
   history or daemons for them; the operator confirmed neither telepresence nor cf-terraforming is
   used. `docker compose` comes from `docker-compose-plugin` (Docker's signed apt repo, v5.6.0), while
   `/usr/local/bin/docker-compose` on `claude` and `workstation` is a stale v5.1.4. telepresence is
   also stale: its `latest` URL resolved to 2.20.2.

kind and yq are GitHub release assets, and the GitHub releases API publishes a sha256 `digest` for
each asset; neither pinned asset shows a re-upload (`updated_at` within seconds of `created_at`).
Population: kind v0.33.0, yq v4.54.1 and shellcheck v0.11.0, linux amd64 and arm64, from `claude`.

## Design

### 1. URL builder (`lib/linux_ubuntu.sh`)

`_release_asset_url <tool> <arch>` prints the GitHub release download URL for a tool at its pinned
`*_VER` and `amd64` or `arm64`. It returns 2 with no output for an unknown tool and 3 for an arch other than `amd64`/`arm64`.
Every URL has the
shape `https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>`.

| tool       | URL                                                                                                                                         |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| kind       | `https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VER}/kind-linux-${arch}`                                                 |
| yq         | `https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_${arch}`                                                             |
| shellcheck | `https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VER}/shellcheck-v${SHELLCHECK_VER}.linux.${x86_64\|aarch64}.tar.xz` |

kind moves from `kind.sigs.k8s.io/dl/...`, which redirects to this asset, to the asset URL itself.
The installers and the refresher both call the builder, so the URL pinned is the URL installed.
`KIND_URL` and `YQ_URL` are deleted from `lib/constants.sh`, with the `yq` branch of
`_update_url_pins`. The shellcheck installer's `_SHELLCHECK_URL` seam stays, defaulting to the
builder.

### 2. Pins (`lib/constants.sh`)

New for `KIND` and `YQ`: `<TOOL>_SHA256_AMD64`, `<TOOL>_SHA256_ARM64`, `<TOOL>_SHA256_FOR_VER`; and
`SHELLCHECK_SHA256_FOR_VER` beside the existing shellcheck pins. That is 4 new hashes and 3
`_FOR_VER` lines. `<TOOL>_SHA256_FOR_VER` records the `*_VER` the hashes are for. arm64 pins are kept,
matching shellcheck's, although every Linux box is amd64 today.

Phase 2 adds the lines with all-zero hashes and an empty `_FOR_VER`, then runs the refresher; no value
is typed by hand.

`_release_asset_sha <tool> <arch>` prints the pin's variable name and value and returns 2 for an
unknown tool. It is an explicit `case` naming every variable, so a grep for a pin finds its reader.

### 3. Installer (`_install_fetched_binary`)

Two calling forms:

- **Pinned:** `_install_fetched_binary <name> <bin|zip|tar> <member> [<dest>]`, used by kind and yq.
  URL and pin come from the builder for `_LINUX_ARCH`.
- **Unverified (PR B removes it):** `_install_fetched_binary --unverified <name> <url> <kind>
<member> [<dest>]`, accepted only for consul, vault, nomad, packer and vagrant; any other name is
  refused with rc 1. It keeps today's URL-only stamp, so those five do not re-download, and prints
  `<name>: not verified (pending HashiCorp apt, PR B)`.

Pinned form, before the stamp check and before any download:

- unknown tool (builder rc 2): `<name>: unknown tool`, rc 1
- `_LINUX_ARCH` not `amd64` or `arm64` (builder rc 3): `<name>: no pin for arch '<arch>'`, rc 1
- `_FOR_VER` differs from `*_VER`: `<name>: repo constants are inconsistent: pins are for
<for-ver>, <TOOL>_VER is <ver>; fix lib/constants.sh in the repo (scripts/refresh-sha256-pins.sh
<name>)`, rc 1
- missing or malformed pin: `<name>: <VAR> is not a 64-hex sha256; refusing to download`, rc 1

The pinned stamp holds `<url> <sha256>`, so a refreshed pin forces a reinstall, and the old URL-only
kind and yq stamps never match: both reinstall, verified, on the first `-t setup`/`-t developer` after
merge (about 20 MB on amd64).

A `verify` stage between download and extract reports by `_verify_sha256`'s rc: rc 1 `<name>: sha256
mismatch: <VAR> expects <pin>, download is <actual> from <url>; nothing installed, existing binary
kept. Re-run; if it repeats at an unchanged version, upstream changed the asset: investigate before
scripts/refresh-sha256-pins.sh --accept-changed <name>`, rc 3 `<name>: could not read the download to
verify it`, any other rc `<name>: sha256 check could not run (rc N)`. Only rc 1 says "mismatch".
Success prints `<name>: sha256 verified`. Any failed stage installs nothing and writes no stamp.

`--resolve` is deleted with telepresence, its only caller.

Test seams `_FETCHED_URL` and `_FETCHED_SHA256` replace the URL and pin and bypass the `_FOR_VER`
check. They are honoured only when `BATS_TEST_TMPDIR` is set, so a stray export in an interactive
shell cannot replace these two tools' pins. The older `_SHELLCHECK_*`, `_TFLINT_*` and `_TFSEC_*`
seams are not changed here (N2). Caller tests do not use them: they set the real pin variables
(`KIND_SHA256_AMD64`, `KIND_SHA256_FOR_VER`, …) to their fixture's values, so caller-name to
pin-variable wiring runs in every caller test.

### 4. Retiring docker-compose, telepresence and cf-terraforming

Their install calls, `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `CF_TERRAFORMING_VER`,
`DOCKER_COMPOSE_URL` and `DOCKER_COMPOSE_VER` are deleted, so no box installs them again. Binaries
already installed are removed once, by hand, on the two development boxes as part of V2: on `claude`
and `workstation` all three stamps and the binaries' own `version` output were measured matching
(docker-compose v5.1.4, telepresence 2.20.2, cf-terraforming 0.27.0), so the population is fully
known. No code path removes anything. A backlog row records that any other Linux box (the WSL
`wsl2_workstation` profile) keeps its stale copies until removed by hand.

`docker compose` (the plugin) is untouched. The operator confirmed telepresence and cf-terraforming
are unused (terraform_ansible's own session found no invocation; its Cloudflare v5 state came through
`terraform import` and `moved` blocks). The two Brewfile telepresence entries (`Brewfile:24`,
`Brewfile.devtools:5`) are deleted too, with the `datawire/blackbird` tap lines they need
(`Brewfile:3`, `Brewfile.devtools:2`) and that tap's entry in the three `brew trust` calls
(`lib/helpers.sh`, `lib/macos.sh`, `lib/linux_ubuntu.sh`); it serves no other formula. The
`brewfile_drift.bats` fixtures that use the tap name as test data stay. This is the one macOS change in
this PR; removing a Brewfile line does not uninstall the formula from a mac that already has it.
`.config/.zshrc.d/6_path.zsh`'s docker-compose comment and ADR-0041's tool list are updated.

### 5. Pin refresher (`scripts/refresh-sha256-pins.sh`)

A standalone executable, run as its own process and never sourced. It sources the target constants
file once (sourcing `lib/constants.sh` twice in one shell aborts on a readonly array), then
`lib/helpers.sh` and `lib/linux_ubuntu.sh` for `_github_api_base`, `_github_auth_header`,
`_sha256_pin_ok` and `_release_asset_url`. Its tests point `_GITHUB_API` at a fixture served by
`tests/helpers/http_listener.bash`, the existing listener for real-curl GitHub API tests.

`refresh-sha256-pins.sh [--constants <file>] [--accept-changed] [tool…]`:

1. Reads `*_VER` and `_FOR_VER` from the target (default `lib/constants.sh`). Every pin line must
   already exist; a missing line is an error, never appended.
2. Selects the named tools, else every tool whose `_FOR_VER` differs from its `*_VER` (prints
   `pins up to date` when none).
3. For each tool and arch, takes `_release_asset_url`, splits it into owner, repo, tag and asset (any
   URL not of the GitHub release shape is an error), prints `querying <url>`, and reads the asset's
   `digest` from `$(_github_api_base)/repos/<owner>/<repo>/releases/tags/<tag>`, sending
   `GITHUB_TOKEN` through `_github_auth_header` when set. A digest that is absent, not `sha256:`, or
   not 64 hex is an error, and so is any API failure; a 403 or 429 adds `set GITHUB_TOKEN
   (unauthenticated: 60 requests/hour)`. No asset is downloaded. Releases published before GitHub
   added the `digest` field (for example shellcheck v0.9.0, kind v0.20.0) have none, so they cannot
   be pinned this way; the refresher fails closed and they are pinned by hand if ever needed.
4. If a tool's `_FOR_VER` already equals its `*_VER` and a digest differs from the committed pin, it
   prints `<tool>: <arch> asset changed at unchanged version <ver>` with both hashes and exits 1 without
   writing, unless `--accept-changed` was given.
5. Writes hashes and `_FOR_VER` into a same-directory copy, reads every line back with `grep -Fqx`,
   and `mv`s it over the target only if all read back; prints `<VAR> <old> -> <new>` per change. Any
   failure prints tool, arch and cause, removes its copy, leaves the target byte-identical, and exits
   1. An interrupt can leave the copy behind; the target is never partly written.

A hand bump is: edit `*_VER`, run the script, commit both. Until it runs, a bats test fails (Testing),
so a forgotten run is caught at pre-push.

### 6. `check-versions`

**Pin-based check.** `_check_one_pinned_release <tool> <pinned> <repo>` compares the **pin** with
GitHub's latest release: `[OK]` when equal, `[OUTDATED]` when latest is newer, `[WARN]` on a fetch
failure. It never runs the installed binary, so Linux and macOS agree. kind, yq and shellcheck use it.
It goes through the same `_token_refused` gate as `_run_cv_check`, so a refused token counts these
as "not checked", and the refusal message derives its count of token-sending checks from the list
(6 after this change: ruby, vagrant, gitleaks, kind, yq, shellcheck) instead of the literal "5".

**`--update`.** `_prompt_version_update` dispatches shellcheck before printing any prompt: it prints
`shellcheck: bump by hand: SHELLCHECK_VER, scripts/refresh-sha256-pins.sh shellcheck, and the three
SC_VER/SC_SHA256 sites in .github/workflows/ci.yml (darwin hash: gh api
repos/koalaman/shellcheck/releases/tags/v<ver> --jq '.assets[]|select(.name|test("darwin.aarch64.tar.xz"))|.digest|ltrimstr("sha256:")'; the two linux SC_SHA256 values are SHELLCHECK_SHA256_AMD64 after the refresh)`
and changes nothing.

kind and yq get their own arm, `_update_release_pin <tool> <var> <latest>`, after the prompt: it copies
the constants file to a same-directory temp, writes and reads back the new `*_VER`, runs
`refresh-sha256-pins.sh --constants <temp> <tool>`, and `mv`s the temp over the original only if both
succeed, printing `Updated <var> → <latest>` and `<tool>: commit lib/constants.sh and merge the PR, then run
./setup_env.sh -t developer on each Linux box to install <latest>`. On failure the temp is removed, the original is untouched, and it
prints `<tool>: refusing pin update: could not refresh sha256 pins` and not "Updated". The run's exit
code does not change (it stays 1 for any OUTDATED, as today); the printed lines are the signal.

### 7. Older verify call sites

`_install_pinned_release_binary` (tflint, tfsec, shellcheck) and `_install_rustup_rs` print the same
three rc-specific messages as section 3, replacing the single "sha256 mismatch" line #337 deferred.

## Trust model

The pins come from the GitHub releases API digest at the time the refresher ran. They protect every
later install against a changed, truncated or substituted download and a redirect to another host, and
the refresher will not re-pin a changed asset at an unchanged version without `--accept-changed`. They
are not independent provenance: a release compromised before the refresher ran is pinned as is. V1
downloads each pinned asset and hashes it, a derivation independent of the API digest, which catches a
wrong digest or a mis-mapped asset, not a compromised release.

## Testing

- `_release_asset_url`: kind, yq and shellcheck on both arches against a hand-typed URL table; an
  unknown tool returns 2 with no output, in the same file.
- `_release_asset_sha`: each of the 6 pins (4 new, 2 shellcheck) returns its variable name and value;
  unknown tool returns 2.
- Committed constants, named explicitly: each pin passes `_sha256_pin_ok` and each `_FOR_VER` equals
  its `*_VER`. Bumping one `*_VER` alone turns this red.
- Installer unit tests (`tests/setup_env/fetched_binary.bats`) set `_FETCHED_URL` and
  `_FETCHED_SHA256` and keep their assertions; stamp assertions change only to the `<url> <sha256>`
  form; `--resolve` tests are deleted. New: wrong pin (mismatch message with the fixture's real hash
  and the URL, nothing installed, no stamp); malformed, missing and `_FOR_VER`-mismatched pins and an
  unknown tool and an unknown arch (named refusal, no `wget`); rc 3 and rc 126 (their own message, and no "mismatch");
  success prints `sha256 verified` and writes the two-field stamp; a stamp with the right URL and an
  old sha reinstalls; `--unverified` installs for each HashiCorp name with a URL-only stamp and the
  "not verified" line, and is refused for kind; with `BATS_TEST_TMPDIR` unset the seams are ignored: the wget mock records the builder URL and the
  real pin is checked (wrong real pin, mismatch message).
- Caller tests (`tests/setup_env/linux_ubuntu.bats`) set the real pin and `_FOR_VER` variables to
  their fixture's values, and every grep for a URL asserts the URL is non-empty. kind under amd64 and
  under arm64 each installs with its own pin and fails with the pins swapped.
- Retirement: no install call remains for telepresence, cf-terraforming or docker-compose (the
  k8s, cloud-tools and misc steps record no `wget` for them), while kind and yq in the same runs do
  (positive control).
- Refresher (an API shim returning release JSON): writes each digest and `_FOR_VER` to the right
  variable and prints `querying` and the changes; default selects only stale tools and the shim shows
  the stale tool queried and the fresh one not; refuses a changed digest at an unchanged version and
  accepts it with `--accept-changed`; a missing line, a non-GitHub URL, a missing or malformed digest
  and a read-back failure each print their cause, and the target is byte-identical (`cmp`).
- check-versions: kind, yq and shellcheck print `[OK]` or `[OUTDATED]` from a stubbed latest (not
  `[SKIP]`), and an equal pin prints `[OK]` and no prompt; a refused token counts them as not checked
  and the message's count equals the number of gated calls (6); `--update` success changes `*_VER`, pins and `_FOR_VER` together and
  prints both lines; refresh failure leaves the file byte-identical and prints the refusal and not
  "Updated"; shellcheck prints the hand-bump message with no `[y/N]` and changes nothing.
- Older call sites: rc 3 and rc 126 print their own messages and not "mismatch".
- Mutation controls, recorded in the PR: delete the installer's verify stage; swap the arch arms in
  `_release_asset_sha`; let `--unverified` accept any name; make the refresher write the amd64 digest
  to both arches; drop the unchanged-version refusal. Each single change turns a named test red.

## Requirements

- **R1.** `[PR1]` `_release_asset_url <tool> <arch>` returns the URL in section 1's table for kind, yq and shellcheck on both arches, and returns 2 with no output for an unknown tool.
- **R2.** `[PR1]` `lib/constants.sh` defines the 4 new hash pins and 3 `<TOOL>_SHA256_FOR_VER` lines of section 2, each equal to its `*_VER`, and no longer defines `KIND_URL`, `YQ_URL`, `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `CF_TERRAFORMING_VER`, `DOCKER_COMPOSE_URL` or `DOCKER_COMPOSE_VER`.
- **R3.** `[PR1]` In its pinned form, `_install_fetched_binary` refuses with rc 1 and no download on an unknown tool, a `_FOR_VER` mismatch, or a missing or malformed pin, naming the cause, before its stamp check.
- **R4.** `[PR1]` In its pinned form, `_install_fetched_binary` runs `_verify_sha256` between download and extract; on failure it installs nothing, writes no stamp, and says "mismatch" only for rc 1; on success it prints `sha256 verified` and writes a stamp holding the URL and the pin.
- **R5.** `[PR1]` `_install_fetched_binary --unverified` is accepted only for consul, vault, nomad, packer and vagrant, keeps a URL-only stamp and prints the "not verified" line; `--resolve` is removed.
- **R6.** `[PR1]` telepresence, cf-terraforming and docker-compose are no longer installed by any Linux step; the telepresence formulae and `datawire/blackbird` tap lines are deleted from `Brewfile` and `Brewfile.devtools`, and the tap from the three `brew trust` calls; no code path removes binaries.
- **R7.** `[PR1]` `scripts/refresh-sha256-pins.sh` pins from the GitHub releases API digest without downloading assets, refreshes only stale tools unless tools are named, refuses a changed digest at an unchanged version unless `--accept-changed`, never appends missing lines, writes through an atomic read-back replace, and leaves the target byte-identical on any failure.
- **R8.** `[PR1]` `check-versions` compares the pins of kind, yq and shellcheck with GitHub's latest release without running the installed binary, inside the token-refusal gate.
- **R9.** `[PR1]` `check-versions --update` for kind and yq changes `*_VER`, pins and `_FOR_VER` together through a temp copy and `mv`, and on refresh failure leaves `lib/constants.sh` byte-identical and prints the refusal and not "Updated".
- **R10.** `[PR1]` `check-versions --update` prints the shellcheck hand-bump instruction naming the three `ci.yml` sites before any prompt, and changes nothing for shellcheck.
- **R11.** `[PR1]` `_install_pinned_release_binary` and `_install_rustup_rs` print the rc-specific verify messages of R4.
- **R12.** `[PR1]` `CLAUDE.md` documents the refresher and hand-bump procedure, the test-only `_FETCHED_URL`/`_FETCHED_SHA256` seams and the caller-test rule, the pin and `_FOR_VER` naming, the `--unverified` allowlist, the three retired tools and how to remove leftover copies by hand, and the pin-based check-versions.
- **V1.** Download each of the 6 pinned assets once and confirm its sha256 equals its pin; record the comparison in the PR.
- **V2.** After merge, on `claude` and `workstation`: record each retired tool's stamp and `version`, then remove `/usr/local/bin/{docker-compose,telepresence,cf-terraforming}` and their stamps by hand and record the result; then run the k8s and misc install steps with `_DL_STAMP_DIR` pointed at an empty temp dir and confirm kind and yq print `sha256 verified`, then delete that temp dir.
- **V3.** The mutation controls in Testing each turn a named test red; record them in the PR.
- **N1.** No change to how the five HashiCorp tools are downloaded beyond the `--unverified` form (PR B).
- **N2.** No change to how tflint or tfsec pins are bumped.
- **N3.** No change to macOS or Windows installs other than removing telepresence and its tap from the Brewfiles and `brew trust` lists.
- **N4.** `_install_fetched_binary` keeps `wget` for downloads.
- **N5.** No automated edit of `.github/workflows/ci.yml`.
- **N6.** No removal of `docker-compose-plugin`, and no code that deletes installed binaries.

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

### Round 3

Reviewed at commit: `7481b0a4` (all three lenses, PR A scope with four pinned tools)

**Goal-Fit.** Finding: V2 pointed the stamp dir at an empty temp dir, so the stamp-gated docker-compose
removal could never be observed; the `--update` return codes and the catch-all `|| return 1` are read
by nothing (`_tally_cv_out` discards them); shellcheck kept the installed-binary check; the refresher
could read the API `digest` instead of downloading ~260 MB per telepresence bump.
Assumption: telepresence and cf-terraforming are still used. Settled by the operator: neither is.
Disposition: Addressed (operator, 2026-10-13): both retired with docker-compose (PR A pins kind and yq
only); V2 split into a real-stamp removal pass and an empty-dir verify pass; decorative rc clauses
removed and tests assert on output; shellcheck moved to the pin-based check; refresher pins from the
API digest and V1 downloads and hashes independently.

**Ergonomics.** Finding: same V2 and shellcheck findings; the shellcheck arm sat after the `[y/N]`
prompt; the mismatch message had no next step; HashiCorp tools printed nothing, indistinguishable from
a skipped verify; `--unverified <url> <name>` swapped argument order; the token gate for the new checks
was unstated; four absence-only tests lacked positive controls; telepresence had no rollback hint.
Assumption: the forced telepresence 2.32 client works against existing traffic-managers; void now that
telepresence is retired.
Disposition: Addressed (operator, 2026-10-13): shellcheck dispatched before the prompt; next-step
mismatch message with the URL; `not verified (pending PR B)` line; `--unverified <name> <url>`;
token-gated checks with a derived count of 8; positive controls added.

**Risk.** Finding: section 4 hardcoded `sudo rm -f /usr/local/bin/docker-compose`, so the test would
touch the real path through the sudo mock; stamp removal was not ordered after `rm`, and a stamp alone
does not prove the binary is ours; the `--unverified` stamp format was unspecified (a two-field stamp
would re-download the five tools every run); the `_FETCHED_*` seams were honoured in production;
Ctrl-C can leave temp copies beside `lib/constants.sh`.
Assumption: the OSS telepresenceio build is a drop-in for Ambassador's; void now that telepresence is
retired.
Disposition: Addressed (operator, 2026-10-13): `${_DL_BIN_DIR}`; stamp removed only after `rm`;
version-in-stamp ownership check; `--unverified` keeps URL-only stamps; seams honoured only with
`BATS_TEST_TMPDIR`; the interrupt claim narrowed to the target file.

Signals: the corrections again removed surface (4 to 2 pinned tools, 8 to 4 hashes, no downloads in
the refresher, decorative return codes gone). Operator asked for a full round 4.

### Round 4

Reviewed at commit: `a5bd3ba3` (all three lenses)

**Goal-Fit.** Finding: the token-refusal count "8" was stale (6 after this change); the
`_remove_stamped_binary` machinery is permanent code for a one-shot event whose population is fully
measured (6 of 6 stamp/version pairs match on `claude` and `workstation`); the seam-gating test lacked
a positive assertion. Assumption: future releases keep publishing `digest`; fails closed if not.
Disposition: Addressed (operator, 2026-10-13): count 6, derived; retirement is a one-shot manual step
in V2 with a backlog row for other boxes; seam test asserts builder URL and real pin.

**Ergonomics.** Finding: count 8 vs 6; the shellcheck darwin command printed `sha256:`-prefixed values
that do not paste into `ci.yml`; the linux `SC_SHA256` source was unnamed; the retirement "not removed"
message had no way out; rate-limited refresher and `--update` success gave no next step. Assumption:
none uncertain (workstation stamps since measured matching).
Disposition: Addressed (operator, 2026-10-13): `ltrimstr("sha256:")` and the linux source named;
retirement message gone with the function; `GITHUB_TOKEN` hint on 403/429; "commit and merge, then
-t developer".

**Risk.** Finding: count 8 vs 6; `_remove_stamped_binary` undefined for an absent binary, unbounded
`version` call, substring match; unknown arch misreported as unknown tool; seam-gating rationale
inconsistent with the older ungated seams; refresher should use `_github_api_base`, name its sourcing
and shim; pre-digest releases cannot be pinned. Assumption: `digest` stays populated for new releases;
fails closed if not.
Disposition: Addressed (operator, 2026-10-13): retirement function dropped; arch rc 3 with its own
message; rationale narrowed (N2 keeps the older seams); `_github_api_base`, sourcing and the
`http_listener.bash` shim named; pre-digest limitation stated.

Review stopped here (operator, 2026-10-13): round 4's findings were local message, wording and test
fixes plus one more removal, the design shrank in every round (10 tools to 2 pinned, 19 hashes to 4,
no downloads in the refresher, no retirement code), and the remaining risk sits in test apparatus for
Phase 2's first red tests.

