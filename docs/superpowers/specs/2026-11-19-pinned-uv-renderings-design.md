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
- **Pin `uv` as a PyPI package in `uv.lock`** (`uv==0.13.0` in a dependency group, run the
  venv's `bin/uv`). It is cheaper, with no installer, but the weekly `uv-lock-refresh` would
  move the renderer, a rendering would gain a `uv` line that ai-config and state-ledger then
  install (contradicting N4), the check would depend on the ansible venv's health
  (`recreate-venv` deletes it), and the lock would pin its own renderer.
- **`brew pin uv`.** Rejected in the 2026-08-20 spec: a `Brewfile` cannot express a pin,
  and pin state is machine-local and untracked.

## Design

### 1. Pins

`lib/constants.sh` gains:

```bash
UV_VER="0.13.0"
UV_SHA256_LINUX_AMD64="1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154"
UV_SHA256_DARWIN_ARM64="a9c1b29002cf3c83f07fa9cd8a887a3be0107d90e23189721221e7257db8e3d6"
UV_SHA256_FOR_VER="0.13.0"
```

These are the values `ci.yml` already pins, in `test-shard` (Linux amd64) and
`test-macos-shard` (darwin arm64). There is no Linux arm64 pin. Every devtools Linux
profile is amd64 (`config/profiles.sh`), so an arm64 digest would have no consumer and
nothing would verify it. `scripts/refresh-sha256-pins.sh` accepts `uv` and refreshes both
digests from `uv-x86_64-unknown-linux-gnu.tar.gz` and `uv-aarch64-apple-darwin.tar.gz`.

### 2. Installer

`_install_pinned_release_binary` stays in `lib/linux_ubuntu.sh`. `setup_env.sh:48` already
sources that file on every platform, so `lib/macos.sh` can call it as it is. The function
gains two things:

- a `targz` kind, beside `zip`, `tarxz` and `raw`. It uses `tar -xzf`, then the same
  find-by-name step as `tarxz`. The uv archive holds `uv` and `uvx` one level down, and
  `-name uv` matches only `uv`.
- `mkdir -p "${_dir}"` before the writability test, run as the invoking user. The test
  `[[ -w "${_dir}" ]] || _as=(sudo)` treats a missing directory as unwritable and would
  `sudo install` into a path that does not exist. For the existing `/usr/local/bin` callers
  (shellcheck, tflint, tfsec) the `mkdir -p` does nothing, and their arguments do not change.

`_sha256_check` already runs on the Studio's `/sbin/sha256sum` (`lib/helpers.sh:21-34`
records the macOS behaviour), so the verify step is portable.

### 3. Install target and callers

The target is versioned: `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv`, the same
path on both platforms, passed as `_RELEASE_BIN_DIR`. A versioned path lets two pins
coexist, so a branch on either side of a `UV_VER` bump resolves its own binary on a shared
machine. Five bumps have landed so far (#226, #306, #331, #414, #445), and the
concurrent sessions on `claude` straddle each one. The path is user-owned, so no sudo. It is
not on `PATH`, so the everyday `uv` stays brew's. Superseded versions stay on disk; each
is one file of about 50 MB, and pruning them is not part of this change.

- **Linux:** `_install_ubuntu_uv_pinned`, gated on `HAS_DEVTOOLS`. On amd64 it installs;
  on any other arch it warns and returns 0. It is called in the same position as
  `_install_ubuntu_shellcheck` (setup and developer).
- **macOS:** `install_uv_pinned_macos` in `lib/macos.sh`, gated on `HAS_DEVTOOLS`, called
  wherever the mac devtools installs run. On arm64 it installs; on any other arch it warns
  and returns 0.
- **Update:** a new `-t update` section, `pinned-uv`, runs in full runs only (not
  `--brew-only`). It needs both `_update_record_start`/`_update_record_end` and an
  `_UPDATE_SECTION_ORDER` entry (`lib/update_summary.sh:5`). The section decides the skip
  itself, outside the installer: no `HAS_DEVTOOLS`, or an unsupported platform/arch, is
  `_update_skip` with the reason, so it never records OK for an install that did not happen.
  Installer rc 0 is OK and rc 1 is FAIL.
- **Direct:** `make install-pinned-uv` sources the checkout's own `lib/constants.sh`,
  `lib/helpers.sh` (which defines `_sha256_pin_ok`, `_sha256_check` and `log_error`, all
  called by the installer) and `lib/linux_ubuntu.sh`, plus `lib/macos.sh` on Darwin, and calls the platform installer, ignoring `HAS_DEVTOOLS`, since an
  explicit request outranks the capability gate. It is the remedy the resolver names, and
  the one a `UV_VER` bump author runs from the bump branch's worktree. A full `-t update`
  runs from the main checkout at master, installs master's `UV_VER`, and also does a real
  `git push` and `rsync --delete`, so it is the wrong remedy for both cases.
- `_RELEASE_BIN_DIR` is set as a command prefix on the uv installer call only, never
  assigned in the calling shell, so it cannot leak into the shellcheck, tflint or tfsec installs. The installer skips when the copy at the target already
  reports the pinned version, so an update with no bump makes no network call.

The version regex for both the skip check and the resolver is `^uv 0\.13\.0( |$)`, built
from `UV_VER` with the dots escaped. The anchor and the `( |$)` stop `0.13.01` from matching.

### 4. Resolver

`resolve_pinned_uv` in `lib/helpers.sh` prints the path of the pinned `uv`, or refuses.
Callers must source `lib/constants.sh` first, because the regex and the default path come
from `UV_VER`. An empty `UV_VER` returns 1 with `UV_VER is not set; source lib/constants.sh`,
so the dependency fails loudly rather than as a version mismatch.

- Path: `${PINNED_UV_BIN:-${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv}`. It never
  searches `PATH` and never falls back to `resolve_uv`.
- rc 0: the file is executable and `--version` matches the regex. It prints the path.
- rc 1: the file exists but is not executable, or it reports another version. Messages:
  `pinned uv at <path> is not executable` and
  `pinned uv at <path> reports <output>, expected uv 0.13.0`. Under the versioned default
  path, rc 1 means a corrupt install, not a pending bump.
- rc 2: the file is absent. Message:
  `pinned uv not found at <path>; run make install-pinned-uv`.

### 5. Consumers

- `scripts/sync-requirements-ci.sh` sources `lib/constants.sh` beside `lib/helpers.sh`,
  and calls `resolve_pinned_uv` instead of `resolve_uv` for both `sync` and `check`. Its
  `UV_BIN` seam is replaced by `PINNED_UV_BIN`, and the tests that drive it through
  `UV_BIN` (`tests/setup_env/requirements_ci.bats:463`, `:492`) move to `PINNED_UV_BIN`.
- In the `Makefile`, `check-requirements-ci` and `check-lock` decide inside the recipe, not
  at parse time. Each recipe runs one `bash -c` that sources `lib/constants.sh` and
  `lib/helpers.sh` and calls `resolve_pinned_uv`, then branches on its rc. No other target
  parses or runs `uv --version`. On rc 1 or rc 2 the recipe prints the resolver's message and
  fails, locally and in CI alike. An absent pinned `uv` fails closed rather than skipping: a
  skip let the pre-push hook pass without running the check, and the remedy is one command.
  These two targets therefore no longer use `REQUIRE_TOOLS_REFUSE`. The
  `UV := $(shell command -v uv)` variable and the `ifeq ($(UV),)` branches go. The tests that
  pin them change, not merely move: in `tests/scripts/makefile_lint_scope.bats` the
  skip loop (`_n -eq 18`) and the refuse loop (`_n -eq 6`) assert the old skip and
  `REQUIRE_TOOLS_REFUSE` text for these two targets, so their uv rows are deleted and the
  counts become 12 and 4. The "`REQUIRE_TOOLS=1` is inert when every tool is present" case
  (~:1421) guards on `command -v uv`; it guards on `resolve_pinned_uv` instead. The
  `:1300` `ifeq ($(UV),)` assertion goes with the branch it pins.
- Cost, accepted: on every machine the first push after this merges fails until
  `make install-pinned-uv` runs once, including machines without `HAS_DEVTOOLS`. The failure
  names the command.
- Unchanged: the venv `uv sync` callers (`lib/developer.sh:627`, `:690`,
  `lib/workflows.sh:1229`), and `scripts/refresh-uv-lock.sh`'s own direct `uv` calls. That
  script also runs `make sync-requirements-ci` and the checks, so it reaches the resolver
  through component 6.

Measured 2026-11-19 (one machine, one constraint change): a `uv.lock` written by brew
0.13.9 after changing `ruff==0.17.4` to `0.17.3` passes the pinned 0.13.0's `lock --check`
(rc 0), and `sync` then `check` under 0.13.0 report all five OK. So the everyday workflow,
"edit `pyproject.toml`, run `uv lock`" with brew's `uv`, stays green under the pinned check.

Measured again 2026-11-19 with a genuinely new marker-bearing dependency (`wmi==1.5.1 ;
sys_platform == 'win32'`, 269 to 270 packages resolved) locked by brew 0.13.9: pinned
`lock --check` rc 0, and `sync` then `check` five OK.

Accepted risk: a future brew `uv` may write a lock (`uv.lock` is `version = 1`,
`revision = 5` today) that 0.13.0 rejects. That does not break this design specifically,
because CI's pinned 0.13.0 would reject it too and force a pin bump either way. Before each
bump, check it with brew `uv lock`, then the pinned `uv lock --check`.

### 6. CI

The three inline `UV_VER`/`UV_SHA256` blocks stay inline, because the runner installs `uv`
before any repo code runs. Each job with an `Install uv (pinned)` step (`test-shard`,
`test-macos-shard`, and the `uv-lock-refresh.yml` job) sets
`PINNED_UV_BIN: /usr/local/bin/uv` in its job `env:`, the path its install step writes.
Without it, `uv-lock-refresh`'s `make sync-requirements-ci` fails closed:
`scripts/sync-requirements-ci.sh`'s own resolver call returns rc 2.
(`scripts/refresh-uv-lock.sh:258` runs that target without `REQUIRE_TOOLS`, and
`Makefile:335` has no guard.) A new bats test parses each workflow per job and asserts
that every `UV_VER` equals `lib/constants.sh`'s `UV_VER`, and that each `UV_SHA256` equals
the constant for that job's asset. It parses per job; it does not grep the whole file
(CLAUDE.md).

## Testing

TDD, one behaviour at a time.

- **Resolver:** absent (rc 2 plus the message); non-executable (rc 1); reports `uv 0.13.9`
  (rc 1); reports `uv 0.13.01` (rc 1, the prefix trap); empty `UV_VER` (rc 1 plus its
  message); reports `uv 0.13.0 (x86_64…)` (rc 0, prints the path). Default path with no
  `PINNED_UV_BIN`: under a fixture `HOME`, it is `<HOME>/.local/share/dotfiles/pinned/uv-0.13.0/uv`.
  The stubs live in `tests/stubs/` and are reached only through `PINNED_UV_BIN`.
- **Installer:** `targz` installs `uv` and not `uvx`; a missing target directory is created
  without sudo (the recording `sudo` shim sees no call); Linux amd64 and darwin arm64 select
  their asset and digest; any other arch warns and returns 0 on each platform. The existing
  skip-when-current, digest-mismatch and download-failure tests stay green unchanged.
- **Update section:** `pinned-uv` appears in the summary order; with `HAS_DEVTOOLS` unset it
  records a skip and does not call the installer; installer rc 1 records FAIL; with the pinned
  version already present, the installer makes no `curl` call.
- **Direct target:** `make install-pinned-uv` calls the installer with `HAS_DEVTOOLS` unset,
  and afterwards the shell's `_RELEASE_BIN_DIR` is still unset. The test puts `tests/mocks/curl`
  on `PATH` with `MOCK_CURL_STDOUT` set to a fixture archive whose real digest is the pin under
  test, and points `HOME` and `_RELEASE_TMP_ROOT` at `BATS_TEST_TMPDIR`, so it makes no
  network call (N5).
- **Consumers (positive control):** with a stub `uv` on `PATH` that renders the 0.13.9
  marker, and a `PINNED_UV_BIN` stub that renders the committed content, `check` reports
  all OK. Swap the two and it reports `DRIFT`. The swap proves the check reads the pinned
  binary, not `PATH`.
- **Makefile:** rc 2 and rc 1 each fail with the resolver's message, with and without
  `REQUIRE_TOOLS=1`;
  `make lint` does not invoke the resolver (a recording `PINNED_UV_BIN` stub sees no call),
  with the positive control that the same stub records a call under `make check-lock`.
- **CI pin equality:** the per-job parser finds three `UV_VER` occurrences (a count of 0
  fails, it does not pass), and a deliberately mismatched fixture workflow fails.

## Requirements

- **R1.** `lib/constants.sh` defines `UV_VER="0.13.0"`, `UV_SHA256_LINUX_AMD64="1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154"`, `UV_SHA256_DARWIN_ARM64="a9c1b29002cf3c83f07fa9cd8a887a3be0107d90e23189721221e7257db8e3d6"` and `UV_SHA256_FOR_VER="0.13.0"`, and defines no `UV_SHA256_LINUX_ARM64`.
- **R2.** `scripts/refresh-sha256-pins.sh` accepts `uv` as a tool argument and rewrites `UV_SHA256_LINUX_AMD64`, `UV_SHA256_DARWIN_ARM64` and `UV_SHA256_FOR_VER`.
- **R3.** `_install_pinned_release_binary` remains in `lib/linux_ubuntu.sh`, and the shellcheck, tflint and tfsec callers pass the same arguments as before.
- **R4.** `_install_pinned_release_binary` accepts kind `targz`, which extracts with `tar -xzf` and installs the regular file named exactly `<name>` found in the archive.
- **R5.** `_install_pinned_release_binary` runs `mkdir -p` on its target directory as the invoking user before the writability test, so a missing user-owned directory is never written with sudo.
- **R6.** On Linux with `HAS_DEVTOOLS` set, `_install_ubuntu_uv_pinned` installs `uv` into `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/` from `uv-x86_64-unknown-linux-gnu.tar.gz` with `UV_SHA256_LINUX_AMD64` when `_LINUX_ARCH` is amd64, and on any other arch it logs a warning and returns 0.
- **R7.** On macOS with `HAS_DEVTOOLS` set, `install_uv_pinned_macos` installs `uv` into `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/` from `uv-aarch64-apple-darwin.tar.gz` with `UV_SHA256_DARWIN_ARM64` on arm64, and on any other arch it logs a warning and returns 0.
- **R8.** The version regex used by the install skip check and by `resolve_pinned_uv` is `^uv 0\.13\.0( |$)`, derived from `UV_VER`, so `uv 0.13.01` does not satisfy it.
- **R9.** `-t update` full runs (not `--brew-only`) have a `pinned-uv` section, listed in `_UPDATE_SECTION_ORDER`, that records `_update_skip` without calling the installer when `HAS_DEVTOOLS` is unset or the platform/arch is unsupported, and otherwise calls the platform installer between `_update_record_start` and `_update_record_end`, recording FAIL on installer rc 1.
- **R10.** `resolve_pinned_uv` reads only `${PINNED_UV_BIN:-${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv}`, never `PATH`, and returns 0 printing the path when it is executable and its `--version` matches R8's regex.
- **R11.** `resolve_pinned_uv` returns 2 with `pinned uv not found at <path>; run make install-pinned-uv` when the file is absent.
- **R12.** `resolve_pinned_uv` returns 1 with `pinned uv at <path> is not executable` for a non-executable file, with `pinned uv at <path> reports <output>, expected uv 0.13.0` for a version mismatch, and with `UV_VER is not set; source lib/constants.sh` when `UV_VER` is empty.
- **R13.** `scripts/sync-requirements-ci.sh` sources `lib/constants.sh`, obtains `uv` only from `resolve_pinned_uv` for both `sync` and `check`, and no longer reads `UV_BIN`.
- **R14.** The `Makefile` targets `check-requirements-ci` and `check-lock` call `resolve_pinned_uv` inside their recipes; on rc 1 or rc 2 they print the resolver's message and fail, with or without `REQUIRE_TOOLS=1`; and the `Makefile` no longer defines `UV := $(shell command -v uv)`.
- **R15.** Every workflow job with an `Install uv (pinned)` step (`test-shard`, `test-macos-shard`, and the job in `uv-lock-refresh.yml`) sets `PINNED_UV_BIN: /usr/local/bin/uv` in its job `env:`.
- **R16.** A bats test parses `.github/workflows/ci.yml` and `uv-lock-refresh.yml` per job, finds exactly three `UV_VER` values, asserts each equals `lib/constants.sh`'s `UV_VER` and each `UV_SHA256` equals the constant for its job's asset, and fails on zero matches.
- **R17.** A bats test runs `scripts/sync-requirements-ci.sh check` with a `PATH` stub `uv` that renders a differing marker and a `PINNED_UV_BIN` stub that renders the committed content and expects all OK; with the two stubs swapped it expects `DRIFT`.
- **R18.** `make install-pinned-uv` sources the checkout's `lib/constants.sh`, `lib/helpers.sh` and `lib/linux_ubuntu.sh`, plus `lib/macos.sh` on Darwin, and calls the platform installer regardless of `HAS_DEVTOOLS`.
- **R19.** The uv installer call passes `_RELEASE_BIN_DIR` as a command prefix, and no code assigns `_RELEASE_BIN_DIR` in the calling shell.
- **R20.** The backlog row "`uv` ships unpinned and no check in this repo can see it drift" is closed, citing this spec.
- **V1.** On `claude`, after `make install-pinned-uv`, `~/.local/share/dotfiles/pinned/uv-0.13.0/uv --version` prints `uv 0.13.0`, and `make test` prints `OK: requirements-runtime-ci.txt matches uv.lock` and exits 0 with brew `uv` 0.13.9 still first on `PATH`.
- **V2.** On the Studio, after the mac install path runs, `~/.local/share/dotfiles/pinned/uv-0.13.0/uv --version` prints `uv 0.13.0`.
- **V3.** CI is green on the PR, and the `test-shard` and `test-macos-shard` logs show `OK: requirements-runtime-ci.txt matches uv.lock` with no skip notice.
- **N1.** No change to `PATH` in any shell startup file, hook or Makefile.
- **N2.** No removal or pinning of brew's `uv`, and no `Brewfile` change.
- **N3.** No change to which `uv` the venv `uv sync` callers use, or to `scripts/refresh-uv-lock.sh`'s own direct `uv` calls (`_UV_BIN`).
- **N4.** No change to `UV_VER`'s value, and no re-rendering of any `requirements-ci*.txt`.
- **N5.** No network access inside `make test`.

## Multi-Lens Review

Reviewed at commit: `82309809` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building; the premise was reproduced (pinned 0.13.0 gives five OK, brew 0.13.9 gives the `pywinpty` DRIFT). Two gaps. (1) Each `UV_VER` bump leaves the single install slot at the old version, so rc 1 blocks every push until `-t developer` runs, and `-t update` never reaches the installer. (2) `UV_SHA256_LINUX_ARM64` has no consumer: no devtools Linux profile is arm64.
Assumption: That only the uv version, not local uv config, makes renderings differ. Checked 2026-11-19: under `env -i` with an empty `HOME`, brew 0.13.9 still gives the same single DRIFT, and 0.13.0 gives five OK.
Disposition: Addressed (operator, 2026-11-19): versioned install path `pinned/uv-${UV_VER}/uv`, absent version is rc 2 with remedy `-t update`, new `pinned-uv` update section; `UV_SHA256_LINUX_ARM64` dropped.

### Ergonomics

Finding: A single unversioned slot treated as fatal on mismatch (rc 1) makes every bump block pushes on every machine. Concurrent sessions on `claude` straddling a bump cannot both pass, and the named remedy is a full `-t developer`. Five past bumps (#226, #306, #331, #414, #445). Proposed: versioned path, absent version as rc 2, installer in `-t update`.
Assumption: That `UV_VER` bumps stay operator-initiated (no Renovate custom manager, no refresh workflow change). Settled by `grep -n customManagers renovate.json` and operator intent.
Disposition: Addressed (operator, 2026-11-19): versioned path lets both sides of a bump coexist; the bump remedy is a routine `-t update`. `renovate.json` has no `customManagers` (grep rc 1).

### Risk

Finding: (1) R9/R12 silently removed the `UV_BIN` and Makefile `UV=` seams that `tests/setup_env/requirements_ci.bats:463,492` and `tests/scripts/makefile_lint_scope.bats:1300,1358-1359` drive. (2) The resolver needs `UV_VER`, but `scripts/sync-requirements-ci.sh` sources only `lib/helpers.sh`. (3) The Makefile three-way rc was unspecified; a parse-time `$(shell)` would run `uv --version` on every make parse. (4) Moving the installer to `lib/helpers.sh` is churn: `setup_env.sh:48` already sources `lib/linux_ubuntu.sh` on every platform. mkdir is safe for existing callers; refresh path fails closed; no R contradicts an N.
Assumption: That pinned 0.13.0 accepts a `uv.lock` written by brew's newer uv. Checked 2026-11-19 (one machine, one constraint change `ruff==0.17.4` to `0.17.3`): pinned `lock --check` rc 0, `sync` then `check` five OK.
Disposition: Addressed (operator, 2026-11-19): seams migrate to `PINNED_UV_BIN` with the four test sites named; script sources `lib/constants.sh` and empty `UV_VER` returns its own rc 1; resolver runs in-recipe only; installer stays in `lib/linux_ubuntu.sh`.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `756cdaa6` (all three lenses re-run after the round-1 revision)

Goal-Fit — Finding: no defect; the cheaper PyPI-package pin was never priced. Assumption: none uncertain that breaks this design specifically.
Disposition: Accepted (operator, 2026-11-19): recorded as a rejected alternative with reasons.

Ergonomics — Finding: the `-t update` remedy is heavy (real push and rsync), runs from master so a bump branch never installs its own `UV_VER`, and a missing pinned `uv` let `make test` pass by skipping. Assumption: newer brew locks stay readable by 0.13.0.
Disposition: Addressed (operator, 2026-11-19): `make install-pinned-uv` is the remedy; an absent pinned `uv` now fails closed; the lock assumption is accepted, since CI's 0.13.0 fails identically.

Risk — Finding: no rc-to-status mapping for `pinned-uv`, and an in-installer gate would record OK for no install; V1 was satisfiable by a skip; section 6 misstated the refresh failure path; `_RELEASE_BIN_DIR` could leak. Assumption: same lock-revision risk.
Disposition: Addressed (operator, 2026-11-19): section-level skip, rc 1 FAIL, full runs only; V1 asserts the OK line; section 6 corrected; R19 makes `_RELEASE_BIN_DIR` a prefix.

### Round 3 (scoped Risk re-review)

Reviewed at commit: `d995b328` (changed sections only)

Finding: `make install-pinned-uv` did not source `lib/helpers.sh` (or `lib/macos.sh` on Darwin); fail-closed contradicts the skip and refuse loops in `makefile_lint_scope.bats` (counts 18 and 6) and its `command -v uv` inert guard; the direct-target test had no network seam; the `make lint` no-call test lacked a positive control. CI wiring (three jobs) confirmed correct; no R contradicts an N.
Assumption: a brew-locked new marker-bearing dependency passes 0.13.0's `lock --check`. Checked with `wmi`: rc 0, five OK.
Disposition:
