# Pinned uv for the requirements renderings and the lock check

## Problem

`make check-requirements-ci` renders the five `requirements-ci*.txt` files from `uv.lock`
with whatever `uv` `resolve_uv` finds first, and compares them with the committed copies.
CI installs a pinned, checksum-verified `uv` 0.13.0 (`.github/workflows/ci.yml` job
`test-shard` and job `test-macos-shard`, and `uv-lock-refresh.yml`). Developer machines
get `brew "uv"` unpinned (`Brewfile:124`, deliberately, per
`specs/2026-08-20-brewfile-uv-design.md`), and `-t update` runs `brew upgrade --yes`.

Two `uv` releases can render the same lock differently. Measured 2026-11-19 on `claude`
(population: this repo's `uv.lock` at `d43fc60b`, one machine, two `uv` binaries):

| uv                                                                 | `scripts/sync-requirements-ci.sh check` | `uv lock --check` |
| ------------------------------------------------------------------ | --------------------------------------- | ----------------- |
| 0.13.0, the CI pin, fetched and verified against the pinned sha256 | all five OK, rc 0                       | OK                |
| 0.13.9, Homebrew, upgraded 2026-11-17                              | `DRIFT: requirements-runtime-ci.txt`    | OK                |

The drift is one environment marker:

```
< pywinpty==3.1.2 ; os_name == 'nt' \
> pywinpty==3.1.2 ; os_name == 'nt' and sys_platform != 'linux' \
```

`check-requirements-ci` is a `make test` prerequisite and the pre-push hook runs
`make test` on every non-inert push, so every dotfiles push from `claude` fails. The
renderings are correct, which CI shows: master and #462 are green under 0.13.0. The local
check reports drift because the local tool differs from CI's.

The 2026-08-20 spec rejected the pinned-binary option "for now", because nothing yet
consumed `uv`. It also predicted that skew would first show up as "a lockfile
disagreement", and backlog row "`uv` ships unpinned and no check in this repo can see it
drift" carries that deferral. The renderings are that consumer now. `uv lock --check`
agrees under both versions today. It is covered here too because it is the same class of
problem and the same one-line change.

Gates already in the path, and whether they catch the hazard: CI pins 0.13.0, so it does
not reproduce local skew; the pre-push hook is the gate that fires (falsely); nothing
checks that the local `uv` equals the CI pin.

## Decision

Pin a second `uv` on the development machines for the rendering check and the lock check.
Leave brew's `uv` in place for everyday use. Make the pin a single source in
`lib/constants.sh`, and add a test that the CI copies agree with it.

Rejected:

- **Bump the CI pin to 0.13.9 and re-render.** This fixes today's skew and comes back on
  the next `brew upgrade`.
- **A version guard only**, with no install. It turns a misleading DRIFT into an honest
  refusal, but the push is still blocked and the fix is manual.
- **Fetch the pinned `uv` on demand inside the check.** It needs the network inside
  `make test`, which breaks offline pushes.
- **`brew pin uv`.** Rejected in the 2026-08-20 spec: a `Brewfile` cannot express a pin,
  and pin state is machine-local and untracked.

## Design

### 1. Pins

`lib/constants.sh` gains:

```bash
UV_VER="0.13.0"
UV_SHA256_LINUX_AMD64="1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154"
UV_SHA256_LINUX_ARM64="3ccfb6af6e242433eb552f7d9676abd5412c6595c497e990d9c8cb7b5bd4d2c3"
UV_SHA256_DARWIN_ARM64="a9c1b29002cf3c83f07fa9cd8a887a3be0107d90e23189721221e7257db8e3d6"
UV_SHA256_FOR_VER="0.13.0"
```

Linux amd64 and darwin arm64 are the values `ci.yml` already pins (`test-shard`,
`test-macos-shard`). Linux arm64 comes from the release's published
`uv-aarch64-unknown-linux-gnu.tar.gz.sha256`, fetched 2026-11-19; the same file for amd64
matched the CI pin, which is the control for reading it. `scripts/refresh-sha256-pins.sh` accepts `uv` and
refreshes all three digests. Assets:
`uv-{x86_64,aarch64}-unknown-linux-gnu.tar.gz` and `uv-aarch64-apple-darwin.tar.gz`.

### 2. Shared installer

Move `_install_pinned_release_binary` from `lib/linux_ubuntu.sh` to `lib/helpers.sh`,
which both platforms source. Its body does not change, except for two additions that uv
needs:

- a `targz` kind, beside `zip`, `tarxz` and `raw`. It uses `tar -xzf`, then the same
  find-by-name step as `tarxz`. The uv archive holds `uv` and `uvx` one level down, and
  `-name uv` matches only `uv`.
- `mkdir -p "${_dir}"` before the writability test, done as the invoking user. The test
  `[[ -w "${_dir}" ]] || _as=(sudo)` sees a missing directory as unwritable and would
  `sudo install` into a path that does not exist.

The existing `_sha256_check` already runs on the Studio's `/sbin/sha256sum`
(`lib/helpers.sh:21-34` records the macOS behaviour), so the verify step is portable.
Existing callers (shellcheck, tflint, tfsec) keep their arguments.

### 3. Install target and callers

Target: `${HOME}/.local/share/dotfiles/pinned/uv`, the same path on both platforms. It is
passed as `_RELEASE_BIN_DIR` for this one call. It is user-owned, so no sudo; it is not on
`PATH`, so the everyday `uv` stays brew's; and it avoids the macOS `/usr/local/bin` limits.

- **Linux:** `_install_ubuntu_uv_pinned`, gated on `HAS_DEVTOOLS`, in the same position as
  `_install_ubuntu_shellcheck`. The `_LINUX_ARCH` case picks the asset and digest; any other
  arch warns and returns 0, as shellcheck does.
- **macOS:** `install_uv_pinned_macos` in `lib/macos.sh`, gated on `HAS_DEVTOOLS`, called
  wherever the mac devtools installs run. Any arch other than `arm64` warns and returns 0.

Version regex for the skip check: `^uv 0\.13\.0( |$)`, built from `UV_VER` with dots
escaped. The anchor and the `( |$)` stop `0.13.01` from matching.

### 4. Resolver

`resolve_pinned_uv` in `lib/helpers.sh` prints the path of the pinned `uv`, or refuses.

- Path: `${PINNED_UV_BIN:-${HOME}/.local/share/dotfiles/pinned/uv}`. It never searches
  `PATH` and never falls back to `resolve_uv`.
- rc 0: the file is executable and `--version` matches the regex in component 3. It
  prints the path.
- rc 1: the file exists but is not executable, or reports another version. Messages:
  `pinned uv at <path> is not executable` and
  `pinned uv at <path> reports <output>, expected uv 0.13.0`.
- rc 2: the file is absent. Message:
  `pinned uv not found at <path>; run ./setup_env.sh -t developer`.

### 5. Consumers

- `scripts/sync-requirements-ci.sh` calls `resolve_pinned_uv` instead of `resolve_uv` for
  both `sync` and `check`.
- In the `Makefile`, `check-requirements-ci` and `check-lock` take `uv` from
  `resolve_pinned_uv`, not from `UV := $(shell command -v uv)`. On rc 2 they keep today's
  missing-tool shape: skip with the message above, or refuse under `REQUIRE_TOOLS=1`
  (`REQUIRE_TOOLS_REFUSE`). On rc 1 they fail.
- Cost, accepted: a machine without the pinned `uv` used to run `check-lock` under brew's
  `uv` and now skips it. CI still runs it under `REQUIRE_TOOLS=1`, and the remedy is printed.
- Unchanged: the venv `uv sync` callers (`lib/developer.sh:627`, `:690`,
  `lib/workflows.sh:1229`) and `scripts/refresh-uv-lock.sh`, which runs only in CI under
  the pinned `uv`.

### 6. CI

The three inline `UV_VER`/`UV_SHA256` blocks stay inline, because the runner installs `uv`
before any repo code runs. Each job with an `Install uv (pinned)` step (`test-shard`,
`test-macos-shard`, and the `uv-lock-refresh.yml` job, whose `scripts/refresh-uv-lock.sh`
runs make targets under `REQUIRE_TOOLS=1`) exports `PINNED_UV_BIN=/usr/local/bin/uv`, the
path its install step writes. A new bats test
parses each workflow per job and asserts that every `UV_VER` equals `lib/constants.sh`'s
`UV_VER`, and that each `UV_SHA256` equals the constant for that job's asset. Per CLAUDE.md
it parses per job; it does not grep the whole file.

## Testing

TDD, one behaviour at a time.

- **Resolver:** absent (rc 2 plus message); non-executable (rc 1); reports `uv 0.13.9`
  (rc 1); reports `uv 0.13.01` (rc 1, the prefix trap); reports `uv 0.13.0 (x86_64…)` (rc 0,
  prints the path). The stubs live in `tests/stubs/` and are reached only through
  `PINNED_UV_BIN`.
- **Installer:** `targz` extracts and installs `uv` and not `uvx`; a missing target
  directory is created without sudo (the recording `sudo` shim sees no call); the Linux and
  darwin asset and digest selection, one case each. The existing skip-when-current,
  digest-mismatch and download-failure tests move with the helper and must stay green
  unchanged.
- **Consumers (positive control):** with a stub `uv` on `PATH` that renders the 0.13.9
  marker and a `PINNED_UV_BIN` stub that renders the committed content, `check` reports all
  OK. Swap the two and it reports `DRIFT`. The swap is the control proving the check reads
  the pinned binary, not `PATH`.
- **Makefile:** rc 2 skips locally and refuses under `REQUIRE_TOOLS=1`; rc 1 fails in both.
- **CI pin equality:** the per-job parser finds three `UV_VER` occurrences (a count of 0 is a
  failure, not a pass), and a deliberately mismatched fixture workflow fails it.

## Requirements

- **R1.** `lib/constants.sh` defines `UV_VER="0.13.0"`, `UV_SHA256_LINUX_AMD64="1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154"`, `UV_SHA256_DARWIN_ARM64="a9c1b29002cf3c83f07fa9cd8a887a3be0107d90e23189721221e7257db8e3d6"`, a 64-hex `UV_SHA256_LINUX_ARM64`, and `UV_SHA256_FOR_VER="0.13.0"`.
- **R2.** `scripts/refresh-sha256-pins.sh` accepts `uv` as a tool argument and rewrites all three `UV_SHA256_*` values and `UV_SHA256_FOR_VER`.
- **R3.** `_install_pinned_release_binary` is defined in `lib/helpers.sh` and not in `lib/linux_ubuntu.sh`, and the existing shellcheck, tflint and tfsec callers pass the same arguments as before.
- **R4.** `_install_pinned_release_binary` accepts kind `targz`, which extracts with `tar -xzf` and installs the regular file named exactly `<name>` found in the archive.
- **R5.** `_install_pinned_release_binary` runs `mkdir -p` on its target directory as the invoking user before the writability test, so a missing user-owned directory is never written with sudo.
- **R6.** On Linux with `HAS_DEVTOOLS` set, `_install_ubuntu_uv_pinned` installs `uv` into `${HOME}/.local/share/dotfiles/pinned/` with the asset and digest for `_LINUX_ARCH` (amd64 or arm64), and on any other arch it logs a warning and returns 0.
- **R7.** On macOS with `HAS_DEVTOOLS` set, `install_uv_pinned_macos` installs `uv` into `${HOME}/.local/share/dotfiles/pinned/` from `uv-aarch64-apple-darwin.tar.gz` with `UV_SHA256_DARWIN_ARM64`, and on any arch other than arm64 it logs a warning and returns 0.
- **R8.** The skip check's version regex is `^uv 0\.13\.0( |$)`, derived from `UV_VER`, so `uv 0.13.01` does not satisfy it.
- **R9.** `resolve_pinned_uv` reads only `${PINNED_UV_BIN:-${HOME}/.local/share/dotfiles/pinned/uv}`, never `PATH`, and returns 0 printing the path when it is executable and its `--version` matches R8's regex.
- **R10.** `resolve_pinned_uv` returns 2 with `pinned uv not found at <path>; run ./setup_env.sh -t developer` when the file is absent.
- **R11.** `resolve_pinned_uv` returns 1 with `pinned uv at <path> is not executable` for a non-executable file, and with `pinned uv at <path> reports <output>, expected uv 0.13.0` for a version mismatch.
- **R12.** `scripts/sync-requirements-ci.sh` obtains `uv` only from `resolve_pinned_uv`, for both `sync` and `check`.
- **R13.** The `Makefile` targets `check-requirements-ci` and `check-lock` obtain `uv` only from `resolve_pinned_uv`; on rc 2 they skip with the R10 message, or refuse under `REQUIRE_TOOLS=1`; on rc 1 they fail.
- **R14.** Every workflow job with an `Install uv (pinned)` step (`test-shard`, `test-macos-shard`, and the job in `uv-lock-refresh.yml`) sets `PINNED_UV_BIN: /usr/local/bin/uv` in its job `env:`.
- **R15.** A bats test parses `.github/workflows/ci.yml` and `uv-lock-refresh.yml` per job, finds exactly three `UV_VER` values, asserts each equals `lib/constants.sh`'s `UV_VER` and each `UV_SHA256` equals the constant for its job's asset, and fails on zero matches.
- **R16.** A bats test runs `scripts/sync-requirements-ci.sh check` with a `PATH` stub `uv` that renders a differing marker and a `PINNED_UV_BIN` stub that renders the committed content and expects all OK; with the two stubs swapped it expects `DRIFT`.
- **R17.** The backlog row "`uv` ships unpinned and no check in this repo can see it drift" is closed, citing this spec.
- **V1.** On `claude`, after `./setup_env.sh -t developer`, `~/.local/share/dotfiles/pinned/uv --version` prints `uv 0.13.0` and `make test` passes with brew `uv` at 0.13.9 still first on `PATH`.
- **V2.** On the Studio, after the mac install path runs, `~/.local/share/dotfiles/pinned/uv --version` prints `uv 0.13.0`.
- **V3.** CI is green on the PR, and the `test-shard` and `test-macos-shard` logs show `OK: requirements-runtime-ci.txt matches uv.lock` from the pinned path, with no skip notice.
- **N1.** No change to `PATH` in any shell startup file, hook or Makefile.
- **N2.** No removal or pinning of brew's `uv`, and no `Brewfile` change.
- **N3.** No change to which `uv` the venv `uv sync` callers use, or to `scripts/refresh-uv-lock.sh`'s own direct `uv` calls (`_UV_BIN`); only the make targets it invokes change, through R13.
- **N4.** No change to `UV_VER`'s value and no re-rendering of any `requirements-ci*.txt`.
- **N5.** No network access inside `make test`.
