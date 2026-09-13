# Provision rustup.rs on Linux — design

> **Status: DONE** — shipped in dotfiles#273 (`0c9e08b3`).

Date: 2026-09-12
Status: Done

## Context

`setup_env.sh -t update` reported `[FAIL] rust exit 1` on the Linux `claude` box on
2026-09-12, with:

```
[INFO]  Updating Rust Ubuntu
error: self-update is disabled for this build of rustup
error: you should probably use your system package manager to update rustup
```

`update_rust` (`lib/developer.sh:219`) resolves rustup in two branches:

```bash
if [[ -x ${HOME}/.cargo/bin/rustup ]]; then      # Branch A — rustup.rs
  _rustup="${HOME}/.cargo/bin/rustup"
elif command -v rustup >/dev/null 2>&1; then      # Branch B — whatever is on PATH
  _rustup="rustup"
```

then runs `self update`, `update` and `component add rust-analyzer`, each with
`|| return 1`.

**The repo provisions rustup exactly one way, and it is the way that cannot satisfy
Branch A.** `lib/linux_ubuntu.sh:409` runs `brew_install_formula rustup` and
`Brewfile:107` carries `brew "rustup" # [HAS_RUST]`. Homebrew builds rustup with
self-update compiled out, so on any box this repo provisioned by itself, Branch A is
unreachable, Branch B resolves the linuxbrew binary, and `rustup self update` exits 1 —
failing the section on every run.

**`_install_ubuntu_rust` is misnamed and is the actual gap.** Despite the name it
installs no rustup at all:

```bash
_install_ubuntu_rust() {
  if [[ -n ${HAS_RUST} ]]; then
    printf "Configuring Rust Ubuntu\\n"
    if [[ -f ${HOME}/.cargo/env ]]; then
      . "${HOME}"/.cargo/env
    fi
    if command -v rustup &>/dev/null; then
      rustup self update
      rustup update
      rustup component add rust-analyzer
    fi
  fi
}
```

It assumes something else put rustup there, and its three commands are unguarded — the
same defect as `update_rust`'s, in a second copy.

**Workstation passes only by accident.** It carries `~/.cargo/bin/rustup` as a regular
file (21113232 bytes, `rustup 1.29.1 (d95a37b6a 2026-08-13)`), installed out of band by
a human at some point. Nothing in this repo puts it there. So workstation is drift that
happens to be correct, and claude was the box provisioned faithfully.

Operator ruling, 2026-09-12: rustup.rs belongs on **both** Linux boxes, and the missing
provisioning code is to be written.

## Decision

`_install_ubuntu_rust` installs rustup.rs when it is absent, from a **version-pinned
`rustup-init` verified by sha256 before execution**, then runs the three rustup commands
with failure propagation.

Three properties are load-bearing:

1. **Pinned and checksum-verified, not `curl … | sh`.** `ci.md`'s third-party-binary
   rule requires a pinned version and a verified digest before executing a downloaded
   artifact. The upstream one-liner satisfies neither.
2. **`--no-modify-path` is mandatory, not stylistic.** `rustup-init` edits shell rc files
   by default, and on this fleet `~/.zshrc` and `~/.zprofile` are symlinks into this
   repo — an unguarded run would write into the tracked working tree. Verified on claude:
   after the install the dotfiles tree was clean and no rc file gained a `cargo/env` line.
3. **Failure propagates.** Every step gets `|| return 1`, closing the second copy of the
   unchecked-command defect in the same change.

`Brewfile`'s `brew "rustup"` **stays**. Both Linux boxes carry both binaries today —
linuxbrew's shadows on `PATH` while `update_rust` reaches past it via Branch A — and that
is the shape workstation has run in production. Removing it is a separate decision with
its own blast radius.

## Design

### Constants (`lib/constants.sh`)

Mirrors the `GO_DOWNLOAD_FILENAME` precedent: a pinned artifact with its verification
recorded next to it, and each constant annotated with its real consumer. The file's
existing file-wide `SC2034` directive already covers them.

```bash
# read by lib/linux_ubuntu.sh:_install_ubuntu_rust
RUSTUP_VER="1.29.1"
# rustup's own naming, NOT _LINUX_ARCH: that maps to Debian/GitHub names
# (amd64/arm64) while rustup publishes under kernel names (x86_64/aarch64).
_RUSTUP_TRIPLE="$(uname -m)-unknown-linux-gnu"
# read by lib/linux_ubuntu.sh:_install_ubuntu_rust
RUSTUP_INIT_URL="https://static.rust-lang.org/rustup/archive/${RUSTUP_VER}/${_RUSTUP_TRIPLE}/rustup-init"
```

Digests, both verified published before pinning (HTTP 200, fetched 2026-09-12):

| triple                      | sha256                                                             |
| --------------------------- | ------------------------------------------------------------------ |
| `x86_64-unknown-linux-gnu`  | `dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71` |
| `aarch64-unknown-linux-gnu` | `15f6e4ce9f583b929c996c91562bad6d4454f3281de858b02cdfdef615fac433` |

Both arches are pinned even though the fleet has no aarch64 Linux box, because the
alternative is a function that fails closed on an architecture nobody tested — a worse
outcome than two table rows. An unrecognised triple is a hard error naming the triple,
never a silent skip.

### The function

```
_install_ubuntu_rust
  └── HAS_RUST unset            → return 0, unchanged
  └── ~/.cargo/bin/rustup exists → skip install (idempotent)
  └── otherwise
        ├── resolve digest for _RUSTUP_TRIPLE, unknown → log_error, return 1
        ├── mktemp -d || return 1
        ├── curl -fsSL -o <tmp>/rustup-init "${RUSTUP_INIT_URL}" || return 1
        ├── sha256sum -c against the pinned digest      || return 1
        ├── chmod +x, then rustup-init -y --no-modify-path || return 1
        └── rm -rf <tmp>
  └── source ~/.cargo/env if present   (unchanged)
  └── rustup self update || return 1
      rustup update      || return 1
      rustup component add rust-analyzer || return 1
```

The idempotency guard is `[[ -x ${HOME}/.cargo/bin/rustup ]]`, and it is worth stating
why that is sufficient **here** and not in general: on Studio that same path is a symlink
into `/opt/homebrew/opt/rustup`, so presence does not prove a rustup.rs install. This
function is `UBUNTU`-gated and both Linux boxes hold a real regular file, so the simple
predicate is correct on every machine that reaches it. A future reader tempted to reuse
the predicate on macOS should not.

`update_rust` is **unchanged**. Its Branch A becomes reachable by provisioning rather
than by luck, which is the whole point; rewriting it would treat the symptom.

### Test seams

`tests/mocks/` carries `curl`, `wget`, `tar`, `gpg` and `rustup`, and **no `sha256sum`
mock**. That absence decides the design: the seam exposes the _expected digest_, so the
real `sha256sum` still runs and the verification is genuinely exercised in both
directions — a matching digest proceeds, a mismatched one refuses. Mocking `sha256sum`
instead would make the check vacuous, which is precisely the absence-claim failure
`behavior.md` warns about.

| seam                      | why it exists                                                                                                                              |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `_RUSTUP_INIT_URL`        | point the download at a `file://` fixture so no test reaches the network                                                                   |
| `_RUSTUP_INIT_SHA256`     | supply the fixture's real digest; drive match **and** mismatch                                                                             |
| `_RUSTUP_INIT_BIN`        | substitute a `rustup-init` stub that records its argv, so `--no-modify-path` is asserted rather than assumed                               |
| `_OVERRIDE_CARGO_BIN_DIR` | select the directory the idempotency guard reads, so both "already installed" and "absent" are reachable without touching a real toolchain |

### The hazard these seams close

All five existing `_install_ubuntu_rust` tests run against a fake `HOME` with no
`~/.cargo/bin/rustup`, so **every one of them would newly enter the install path**.
Unseamed, that is five tests attempting a real network download, and `tdd.md` E2 is
explicit that a test whose _failing_ path reaches outside the repo is worse than the bug
it guards.

This is not hypothetical in this file. `tests/setup_env/developer.bats:500` already
carries the scar:

> A filtered PATH is not inert — it leaves `~/.cargo/bin` reachable, which is how an
> earlier version of this test ran a real `rustup self update` against the operator's
> toolchain (tdd.md E2).

New tests therefore follow that precedent: a fixture bin plus `HOME="${BATS_TEST_TMPDIR}"`,
never a filtered `PATH`.

## Callers

Enumerated before editing, including tests and transitively — the rule this repo
corrected twice, at a re-plan each time.

| tier              | site                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------ |
| direct            | `lib/linux_ubuntu.sh:13`, inside `install_ubuntu_packages`                           |
| transitive        | `lib/workflows.sh:231`, inside `run_setup_or_developer`                              |
| entry points      | `setup_env.sh:97` — `-t setup` and `-t developer`. **`-t update` does not reach it** |
| tests, direct     | 5 in `tests/setup_env/linux_ubuntu.bats:219-285`                                     |
| tests, sibling    | 6 + a fail-fast block in `tests/setup_env/developer.bats:435+`                       |
| tests, transitive | 11 references to `install_ubuntu_packages` in `tests/setup_env/workflows.bats`       |

One existing test needs a name change rather than an assertion change:
`linux_ubuntu.bats:228`, _"HAS_RUST set skips rustup curl (brew provides rustup)"_, greps
for `sh.rustup.rs` — the curl-pipe-to-shell form this design deliberately does not use —
so the assertion still holds while the name becomes false. That is the stale-reference
problem `behavior.md` describes, and the remedy is to rename, not to reconcile the
assertion.

## Verification

Measured on claude 2026-09-12, by performing the design by hand before writing it —
recorded output, not predicted:

```
/tmp/tmp.bTCt29wnMM/rustup-init: OK          # sha256sum -c against the pinned digest
rustup 1.29.1 (d95a37b6a 2026-08-13)         # 21113232 bytes, regular file
SELF_RC=0   rustup unchanged - 1.29.1        # the exact command that had been failing
UPD_RC=0
COMP_RC=0   component rust-analyzer is up to date
```

Tracked tree clean afterwards and no rc file modified, confirming `--no-modify-path`.

A subsequent full `setup_env.sh -t update` on claude reported:

```
23 sections: 18 OK, 0 failed, 2 warnings, 3 skipped
[OK]   rust                 updated
```

Acceptance for the change itself is `make test` plus a new test asserting the install
path runs `rustup-init` with `--no-modify-path` and refuses on a digest mismatch.

## Alternatives rejected

- **Make `update_rust` tolerate a package-managed rustup** (skip `self update` when
  rustup is not rustup.rs). Rejected: it encodes the broken provisioning as supported,
  and diverges the two Linux boxes permanently.
- **Drop `brew "rustup"`.** Out of scope and larger than it looks — the brew binary is
  what currently answers `command -v rustup` on both boxes.
- **`curl https://sh.rustup.rs | sh`.** Fails `ci.md`'s verification rule; also the exact
  string an existing test asserts is absent.

## Scope widened 2026-09-12, after implementation began

The spec above covers rustup. Investigating why `-t update` failed on claude surfaced
five more defects of **one class** — a Linux install path naming something it cannot
install, or doing something wrong, with nothing checking the result — so they ship
together rather than as six branches through the same two files.

| defect                                                                                                                                                                                        | fix                                                                                        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `brew_install_formula go-task/tap/go-task` resolves to a macOS **Cask** that shells out to `/usr/bin/xattr` and exits **127** on Linux. Failed on every Linux run since it was added          | install core `go-task`                                                                     |
| `git-cliff` `kcov` `mdbook` `bun` `codeburn` absent from the Linux list entirely; workstation had them as hand-installs                                                                       | added; `bun` from core rather than `oven-sh/bun/bun`, same upstream-moved story as go-task |
| `codex` is a Cask, and `brew_formula_installed` greps `brew list --formula` in both branches, so an installed cask never matches and would reinstall every run                                | `brew_cask_installed` / `brew_install_cask`                                                |
| `brew_install_formula` ended on an unchecked `brew install`, and all 33 call sites were unchecked — this is what hid the go-task 127                                                          | `\|\| return 1`, plus a tri-state accumulator                                              |
| `install_homebrew` unchecked inside an `if/elif`, so a fresh box installed brew and then **skipped the entire package list** for that run                                                     | `\|\| return 1`, then fall through                                                         |
| `claude plugins install <bare-name>` registered at **project** scope against whatever cwd the run had, so `claude plugins update` later reported "not installed at scope user" for 12 plugins | `claude plugin install -s user <plugin>@<marketplace>`                                     |

**Failure policy is rc-2 partial success**, per operator ruling, mirroring
`install_git_hooks_all_repos`: 0 clean, 1 hard failure, 2 partial with the failed
packages named. A bare `|| return 1` in `install_ubuntu_packages` would abort a whole
fresh-machine bootstrap because one upstream formula was briefly unavailable — the
opposite of what a bootstrap should do — while unchecked calls report success over
packages that never landed.

### NVIDIA

No GPU stack existed anywhere in the repo (zero hits for `nvidia`, `nouveau`, `cuda`,
`HAS_GPU` across `lib/`, `config/`, `Brewfile`, `ubuntu_*.txt`). claude has an RTX 2060
SUPER that was running **nouveau** with no driver, no CUDA and no `nvidia-smi`, so
`ollama` ran CPU-only on a box with an idle GPU.

Gated on **hardware**, not on a capability flag: `claude` and `workstation` both map to
`linux_workstation`, so a `HAS_*` flag would fire the driver install on any future
GPU-less box with that profile, and on WSL2 where the driver lives Windows-side.
`_nvidia_gpu_present` matches PCI vendor `10de:` via `lspci -nn`.

The driver comes from Ubuntu's own repo (`nvidia-driver-610` → `610.57.04-0ubuntu0.26.04.3`
on resolute). The container toolkit needs NVIDIA's repo, and its signing key is **not**
checksum-pinned the way rustup-init is — NVIDIA publishes no digest. The mitigation is
`signed-by=`, scoping the key to that one repo. Recorded as a known limitation; note it
is also exactly what teleport, cloudflare and gcloud already do in this file.

Installing does **not** bind the driver: nouveau holds the card until reboot, so the
function warns rather than implying success. Verified end to end on claude — driver
installed, reboot, `nvidia-smi` reporting the 2060 SUPER on `610.57.04`, `nouveau`
unloaded, boot id changed.

### Drift

`_update_check_brewfile_drift` at `workflows.sh:716` is ungated, so on Linux it grades a
box against the **macOS** Brewfile — 82 "missing" formulae on claude, of which ~93% are
mac-only GNU tools, `chruby` where Linux uses rbenv, and an arm64 cask. It now SKIPs on
Linux. **Open:** two existing tests (`Linux OK when formulae and taps match`, `Linux WARN
for formula drift`) deliberately specify Linux drift behaviour that this removes. Awaiting
a ruling on whether Linux drift stays unmeasured or gets a manifest derived from
`_install_ubuntu_brew_packages`.

## Related

- `docs/superpowers/specs/2026-05-28-coverage-developer-gaps-design.md` — covers
  `update_rust`'s branch structure. **Stale**: it describes a nextest arm and a line range
  that no longer match the function, though its Branch A/B analysis still holds.
- `ci.md` — third-party binary download rule (pin + `sha256sum -c`).
- `tdd.md` E2 — a test's failure mode must be inert.
