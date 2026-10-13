# Release asset sha256 pins

- **Date:** 2026-10-13
- **Backlog row:** "helper-installed binaries have no checksum and `wget` follows any redirect"
- **Builds on:** dotfiles#337 (`_sha256_pin_ok`, `_verify_sha256`, the go tarball pins)
- **Follow-up, not designed here:** GPG verification of HashiCorp's signed `SHA256SUMS`

## Problem

`_install_fetched_binary` (`lib/linux_ubuntu.sh`) downloads with a bare `wget`, then extracts and
installs into `/usr/local/bin` with `sudo`. It checks nothing about the bytes. Ten tools go through
it: kind, telepresence, consul, vault, nomad, packer, vagrant, cf-terraforming, docker-compose and
yq. Premise checked 2026-10-13 by reading the function and its five callers.

Two more defects surfaced while checking:

1. **`check-versions --update` already breaks shellcheck.** It bumps `SHELLCHECK_VER` but
   `_update_url_pins` treats shellcheck as having "no URL vars to update", so
   `SHELLCHECK_SHA256_AMD64`/`_ARM64` stay at the old release. The next `--update` of shellcheck
   makes `_install_pinned_release_binary` refuse the download on every Linux box. yq and vagrant,
   also bumped by `--update`, would join this the moment they get pins.
2. **telepresence is stale.** It installs `.../download/tel2/linux/<arch>/latest/telepresence`,
   resolved at run time. On 2026-10-13 the amd64 URL resolved to **2.20.2** on S3, while GitHub's latest
   release is **v2.32.2**.

Upstream publishes checksums for most tools, each in its own format: per-asset `.sha256sum`
(kind), `SHA256SUMS` plus a GPG signature (HashiCorp), `checksums.txt` (cf-terraforming,
docker-compose), and a multi-hash `checksums` file (yq). shellcheck and telepresence publish none.
vagrant has no arm64 Linux build. Measured 2026-10-13 against the currently pinned versions, from
`claude`, through the GitHub API and HEAD requests.

## Design

### 1. One URL builder (`lib/linux_ubuntu.sh`)

`_release_asset_url <tool> <arch>` prints the download URL for a tool at its pinned `*_VER` and an
arch (`amd64` or `arm64`). It returns 1 with no output for an unknown tool or an arch the tool does
not ship (vagrant on arm64). It covers the ten fetched tools and shellcheck. Arch names are mapped
inside it, so docker-compose and shellcheck get `x86_64`/`aarch64`.

| tool                                  | URL                                                                                                                                                   |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| kind                                  | `https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-${arch}`                                                                                         |
| telepresence                          | `https://github.com/telepresenceio/telepresence/releases/download/v${TELEPRESENCE_VER}/telepresence-linux-${arch}`                                    |
| consul, vault, nomad, packer, vagrant | `https://releases.hashicorp.com/${tool}/${ver}/${tool}_${ver}_linux_${arch}.zip`                                                                      |
| cf-terraforming                       | `https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_${arch}.tar.gz` |
| docker-compose                        | `https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-linux-${x86_64\|aarch64}`                                   |
| yq                                    | `https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_${arch}`                                                                       |
| shellcheck                            | `https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VER}/shellcheck-v${SHELLCHECK_VER}.linux.${x86_64\|aarch64}.tar.xz`           |

The installers and the pin refresher (section 4) both call it, so the URL that is hashed is the URL
that is installed. `KIND_URL`, `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `DOCKER_COMPOSE_URL`,
`YQ_URL` and `HASHICORP_URL` are deleted from `lib/constants.sh`, along with the `yq` branch of
`_update_url_pins`, which only existed to rewrite `YQ_URL`. The shellcheck installer's `_SHELLCHECK_URL`
seam stays, defaulting to the builder.

The docker-compose URL changes from `docker-compose-$(uname -s)-$(uname -m)` (`Linux`, capital L)
to the lowercase asset name. Both resolve today (HEAD 200, 2026-10-13); the lowercase one is the
asset GitHub lists.

### 2. Pins (`lib/constants.sh`)

New: `TELEPRESENCE_VER="2.32.2"`, and `<TOOL>_SHA256_AMD64` / `<TOOL>_SHA256_ARM64` for `KIND`,
`TELEPRESENCE`, `CF_TERRAFORMING`, `DOCKER_COMPOSE`, `YQ`, `CONSUL`, `VAULT`, `NOMAD` and `PACKER`,
plus `VAGRANT_SHA256_AMD64` only. That is 19 pins, each with a `# read by` comment. Values are
produced by the refresher in Phase 2 and checked by V1, not typed by hand.

`_release_asset_sha <tool> <arch>` prints the pin for a tool and arch and returns 1 when none
exists. It is an explicit `case` naming every variable, not indirect expansion, so a grep for a pin
finds its reader. It also prints the variable name on a second line, for messages.

### 3. Installer (`_install_fetched_binary`)

The `<url>` argument is dropped: the installer derives the URL and pin from its `<name>` through
`_release_asset_url` and `_release_asset_sha` for `_LINUX_ARCH`. One new test seam,
`_FETCHED_SHA256`, replaces the pin when non-empty, as `_GO_SHA256` does for go.

Before the workdir is made, the installer refuses with rc 1 and no download when:

- there is no URL for this arch: `<tool>: no <arch> build; refusing to download`
- there is no pin: `<tool>: no sha256 pin for <arch>; refusing to download`
- the pin fails `_sha256_pin_ok`: `<tool>: <VAR> is not a 64-hex sha256; refusing to download`

A `verify` stage runs between download and extract and reports the cause by `_verify_sha256`'s rc,
as `_go_verify` does: rc 1 `<tool>: sha256 mismatch: <VAR> expects <pin>, download is <actual>`,
rc 3 `<tool>: could not read the download to verify it`, any other rc
`<tool>: sha256 check could not run (rc N)`. Only rc 1 prints "mismatch". Any failed stage already
removes the workdir, installs nothing and writes no stamp.

`--resolve` and its code are deleted. telepresence was its only caller, and a pinned version has
nothing to resolve.

Callers stop naming a URL. The four HashiCorp tools and vagrant loop over names as today, and
vagrant on arm64 now refuses explicitly instead of downloading a 404.

Every tool's stamp holds its URL, and the URLs change (telepresence, docker-compose) or stay the
same (the rest). Changed URLs reinstall once. That is wanted for telepresence, which moves from
2.20.2 to 2.32.2.

### 4. Pin refresher (`scripts/refresh-sha256-pins.sh`)

`refresh-sha256-pins.sh [tool…]` (default: all eleven) refreshes pins for the pinned versions:

1. Reads `*_VER` by sourcing the target constants file (`${_OVERRIDE_CONSTANTS_PATH:-lib/constants.sh}`)
   in a subshell, so it hashes the versions on disk, not those of the shell that called it.
2. For each tool and each arch it ships, downloads `_release_asset_url`'s URL with
   `curl -fsSL --proto =https --proto-redir =https --max-time 600` into a temp dir and hashes it.
3. Writes every new pin into a same-directory copy of the constants file, reads each back with
   `grep -Fqx`, and `mv`s the copy over the original only if all read back. Any download, hash or
   read-back failure prints the tool, arch and cause, leaves the constants file byte-identical and
   exits 1.

It prints `<VAR> <old> -> <new>` per changed pin, so a reviewer sees the change in the run as well as
the diff. It is how a hand-bumped tool (kind, telepresence, the HashiCorp tools, cf-terraforming,
docker-compose) gets new pins: edit `*_VER`, run the script, commit both.

### 5. `check-versions --update`

For yq, vagrant and shellcheck, `_update_version_pin` copies the constants file aside, writes the
new version, then runs `refresh-sha256-pins.sh <tool>` against it. If the refresher fails, it puts
the copy back, prints `<tool>: refusing pin update: could not refresh sha256 pins`, and returns 1,
so the version and pins never disagree. As with go, a refused update leaves the other prompts
running.

### 6. Older verify call sites

`_install_pinned_release_binary` (tflint, tfsec, shellcheck) and `_install_rustup_rs` branch on
`_verify_sha256`'s rc with the same three messages as section 3, replacing their single
"sha256 mismatch" line, which #337 left for this follow-up.

## Trust model

The pins are hashes of what the upstream URL served when the refresher ran. They protect every later
install against a changed, truncated or substituted download, and against a redirect to another host.
They are not independent provenance: a release compromised before the refresher runs is pinned as
is. V1 cross-checks against upstream's own checksum files where they exist, which catches a
corrupted fetch but not a compromised release. The HashiCorp GPG follow-up is the provenance step.

## Testing

- `_release_asset_url`: every tool on both arches against a hand-typed table of expected URLs (an
  oracle derived from the table above, not from the function); vagrant arm64 and an unknown tool
  return 1 with no output.
- `_release_asset_sha`: each of the 19 pins comes back for its tool and arch, with its variable
  name; vagrant arm64 returns 1. Every committed pin passes `_sha256_pin_ok`, named explicitly.
- `_install_fetched_binary`, existing tests in `tests/setup_env/fetched_binary.bats`: each sets
  `_FETCHED_SHA256` to the real hash of its own download fixture and keeps every assertion. The
  `--resolve` tests are deleted with the feature.
- New installer tests: wrong pin (mismatch message with the fixture's real hash, nothing installed,
  no stamp); malformed and missing pins and vagrant on arm64 (refusal, no `wget`); rc 3 and rc 126
  via `_verify_sha256` (no "mismatch"); amd64 and arm64 each select their own pin (each case passes
  under its own arch and fails with the pins swapped).
- Refresher: a curl shim on PATH writes content that depends on the URL, so each arch hashes
  differently. It writes the right hash to the right variable, prints the changes, and is
  byte-identical on a failed download (`cmp`), a non-https URL, or a read-back failure.
- `check-versions --update` for yq, vagrant and shellcheck: on success both version and pins change;
  with the refresher failing, the constants file is byte-identical and the refusal is printed.
- Older call sites: rc 3 and rc 126 print their messages and not "mismatch".
- Mutation controls, recorded in the PR: delete the installer's verify stage; swap the arch arms in
  `_release_asset_sha`; make the refresher write the amd64 hash to both variables; drop the restore
  on a failed `--update`. Each single change turns a named test red.

## Requirements

- **R1.** `[PR1]` `_release_asset_url <tool> <arch>` returns the URL in section 1's table for each of the eleven tools and both arches, and returns 1 with no output for vagrant on arm64 or an unknown tool.
- **R2.** `[PR1]` `lib/constants.sh` defines `TELEPRESENCE_VER="2.32.2"` and the 19 pins named in section 2, and no longer defines `KIND_URL`, `TELEPRESENCE_URL`, `CF_TERRAFORMING_URL`, `DOCKER_COMPOSE_URL`, `YQ_URL` or `HASHICORP_URL`.
- **R3.** `[PR1]` `_install_fetched_binary` refuses before downloading when the arch has no build, the pin is missing, or the pin is malformed, naming the cause.
- **R4.** `[PR1]` `_install_fetched_binary` runs `_verify_sha256` between download and extract and, on failure, installs nothing, writes no stamp, and prints "mismatch" only for rc 1.
- **R5.** `[PR1]` `--resolve` is removed from `_install_fetched_binary`.
- **R6.** `[PR1]` `scripts/refresh-sha256-pins.sh` writes the hashes of `_release_asset_url`'s downloads into the matching pins with an atomic read-back replace, and leaves the constants file byte-identical on any failure.
- **R7.** `[PR1]` `check-versions --update` for yq, vagrant and shellcheck refreshes that tool's pins with the new version, and restores the constants file and returns 1 if the refresh fails.
- **R8.** `[PR1]` `_install_pinned_release_binary` and `_install_rustup_rs` print the rc-specific verify messages of R4.
- **R9.** `[PR1]` `CLAUDE.md` documents the refresher, the `_FETCHED_SHA256` seam, the pin naming, and that a hand-bumped `*_VER` needs a refresher run.
- **V1.** Each pin the refresher writes matches upstream's own checksum file where one exists (kind, the HashiCorp tools, cf-terraforming, docker-compose, yq); record the comparison in the PR.
- **V2.** After merge, on `claude` and `workstation`, run the k8s, hashicorp, cf-terraforming and misc install steps; every tool installs, telepresence reports 2.32.2, and no step prints a verify failure.
- **V3.** The mutation controls in Testing each turn a named test red; record them in the PR.
- **N1.** No GPG signature verification (separate follow-up).
- **N2.** No change to how tflint or tfsec pins are bumped (they are not in `check-versions`).
- **N3.** No change to macOS installs.
- **N4.** No new download tool for installs: `_install_fetched_binary` keeps `wget`.
