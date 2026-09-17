# Close the provisioning gaps found moving sessions to `claude`

> **Status:** Draft, revision 2 — spec review pending.

## Problem

On 2026-09-17 the operator moved the ansible, etch-cli, etch-config, ai-devops and math
sessions from the Mac Studio and `workstation` onto the Linux `claude` box (Ubuntu 26.04
`resolute`). A toolchain audit that day found four defects, and each one is measured
below on the host it names. Every figure comes from `claude` unless a row says otherwise.

### D1. Every login shell deletes the `pytest` shim on 26.04

`.zprofile:9` runs `eval "$(pyenv init --path)"`. On pyenv 2.8.6, the output of `--path`
ends with `command pyenv rehash`:

```
$ /home/linuxbrew/.linuxbrew/bin/pyenv init --path zsh | grep -n rehash
7:command pyenv rehash
```

That rehash runs before `.config/.zshrc.d/6_path.zsh` prepends the linuxbrew GNU coreutils
`gnubin` directory. At that point `sort` resolves to `/usr/bin/sort`, which is
`sort (uutils coreutils) 0.8.0`. Its `sort -u` treats `py.test` and `pytest` as equal and
drops one of them ([ADR-0031](../../adr/0031-gnu-coreutils-precedence-on-resolute.md)).
So ADR-0031's fix is in place and correct, but it runs after the rehash that it was meant
to protect.

Reproduced on demand, measured on `claude` for the `ansible` venv. Its 143 binaries are all
shimmed after a correct rehash:

| step                                                       | `~/.pyenv/shims/pytest`                       |
| ---------------------------------------------------------- | --------------------------------------------- |
| `env -i … bash -c 'pyenv rehash'` (GNU sort first on PATH) | present                                       |
| then `zsh +Z -l -i -c 'sleep 3'` (login shell)             | **absent**; the diff removes exactly `pytest` |
| `env -i … zsh +Z -i -c 'sleep 2'` (non-login interactive)  | present                                       |

The consequence is concrete. In a scratch clone on `claude`, `make test` failed with
`make: pytest: No such file or directory` (rc 2) in `math/fib` and in etch-cli. For etch-cli
this happened after all 1129 Rust tests had passed. Every new tmux pane is a login shell,
so a manual rehash lasts only until the next pane opens. `workstation` is unaffected,
because 24.04's `/usr/bin/sort` is GNU.

### D2. Nothing detects a missing shim

The breakage was silent. `_doctor_check_gnu_coreutils` checks which binary provides `sort`
in the doctor's own shell, and that answer can be correct while a _different_ actor, the
login shell, has already run the broken rehash. No check looks at the outcome: a binary in
a pyenv version that has no shim.

### D3. Linux does not provision tools the Mac already gets

The Mac `Brewfile` carries `brew "tflint"` (`:119`), `brew "zig"` (`:134`) and
`brew "powershell"` (`:89`), all tagged `[HAS_DEVTOOLS]`. The Linux formula loop in
`_install_ubuntu_brew_packages` carries none of the three. For `tflint` the loop cannot
help: linuxbrew reports `No available formula with the name "tflint"`, measured on
`claude`. Mac Homebrew reports `tflint: stable 0.61.0`.

Neither platform provisions the cargo plugins. The Studio's copies are hand installs under
`~/.cargo/bin`, and `git grep -nE 'cargo install'` over `lib/` returns nothing. The plugins
are reached by real gates:

- `cargo mutants`: every math `*-rs/Makefile` and etch-cli's `Makefile`.
- `cargo nextest`: math's `scripts/rust-check.sh`. It is already brew-provisioned.
- `cargo semver-checks`, `cargo deny`, `cargo audit`, `cargo insta`, `cargo zigbuild`:
  etch-cli's `Makefile`/`CLAUDE.md`.
- `cargo tarpaulin`: the per-crate coverage gate, and the Definition of Done's coverage
  evidence.

The Studio set, from `cargo install --list` on 2026-09-17:

| crate               | version |
| ------------------- | ------- |
| cargo-audit         | 0.22.1  |
| cargo-deny          | 0.19.4  |
| cargo-fuzz          | 0.13.1  |
| cargo-insta         | 1.47.2  |
| cargo-machete       | 0.9.2   |
| cargo-mutants       | 27.0.0  |
| cargo-semver-checks | 0.47.0  |
| cargo-tarpaulin     | 0.35.2  |
| cargo-zigbuild      | 0.22.3  |
| cross               | 0.2.5   |

`cargo-nextest` is on the Studio list too (0.9.136), but both platforms already get it
from brew, so it stays out of this set.

**tarpaulin needs one Linux-specific build flag.** A plain `cargo install --locked
cargo-tarpaulin@0.35.2` on `claude` links linuxbrew's `libgit2` dynamically: `git2-sys`
finds it through `pkg-config`. The build embeds no rpath, so the binary dies at startup
with `error while loading shared libraries: libgit2.so.1.9`. Rebuilding with
`RUSTFLAGS="-C link-args=-Wl,-rpath,/home/linuxbrew/.linuxbrew/lib"` gave a working
binary. `ldd` over every `~/.cargo/bin/cargo-*` then reported no `not found` line.

### D4. `pwsh` never installs on a box that first provisioned before the RESOLUTE fix

`_install_ubuntu_powershell` skips everything while
`~/software_downloads/packages-microsoft-prod.deb` exists. The guard keys on the
downloaded artifact, not on `pwsh`. On `claude`:

- The `.deb` is present.
- `/etc/apt/sources.list.d/microsoft-prod.list` reads
  `https://packages.microsoft.com/ubuntu/26.04/prod resolute main`, which carries zero
  powershell packages (measured 2026-09-12 and recorded in the function's own comment).
- `apt-cache policy powershell` prints nothing.
- `command -v pwsh` is absent.

The RESOLUTE fallback to the 24.04 config was added on 2026-09-12. It sits inside the
skipped branch, so it can never reach a box that downloaded the 26.04 config earlier. The
function also never checks the `apt install` exit status, so the original failure printed
and returned 0.

## Design

This is revision 2 and replaces the round-1 design. The Multi-Lens Review section below
records why. One branch, one PR, four independent parts, each testable alone.

### Part 1: a pyenv rehash hook that registers every shim, whatever `sort` is

The defect is not in `.zprofile`. It is in `pyenv-versions --executables`, which
`pyenv-rehash` calls through `sort -u`. Any actor that runs `pyenv rehash` with uutils
`sort` ahead of GNU loses the `pytest` shim, and at least these reach it:

- `.zprofile:9` (login zsh).
- `lib/developer.sh:537` and `:567` (`setup_ansible`, `recreate_python_venv`), from
  `setup_env.sh`'s bash, where no gnubin is on `PATH`.
- `ssh claude '<cmd>'`, which resolves `sort` to `/usr/bin/sort` (measured by the
  goal-fit lens).
- pyenv's own `install` and `virtualenv` subcommands.

Fixing `PATH` order would need one change per actor. pyenv 2.8.6 offers one choke point
instead. In `libexec/pyenv-rehash`, the author read the following order:

```
193: make_shims $(pyenv-versions --executables)   # the uutils-damaged list
196: # Allow plugins to register shims.
198: IFS=$'\n' scripts=(`pyenv-hooks rehash`)   ... source "$script"
205: install_registered_shims
206: remove_stale_shims
```

`make_shims` takes basenames of the paths it is given and calls `register_shim` for each.
With bash >= 4 that is an associative-array assignment, so duplicates are harmless and no
`sort` is involved. A hook sourced at line 198 can therefore register the complete set
before anything is installed or removed.

**The hook.** Add a tracked file `pyenv.d/rehash/dotfiles-register-all-executables.bash`:

```bash
# shellcheck shell=bash
# Sourced by pyenv-rehash between make_shims and install_registered_shims.
# pyenv-versions --executables pipes basenames through `sort -u`; uutils sort
# (Ubuntu 26.04) collates py.test and pytest as equal and drops one, so the
# pytest shim is never registered and remove_stale_shims deletes it. Registering
# the same glob here, without sort, restores it for every caller. See
# docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md.
shopt -s dotglob
make_shims "${PYENV_ROOT}"/versions/*/bin/* "${PYENV_ROOT}"/versions/*/envs/*/bin/*
shopt -u dotglob
```

- **The glob mirrors pyenv's own.** `pyenv-versions --executables` globs
  `"$versions_dir"/*/bin/* "$versions_dir"/*/envs/*/bin/*` under `dotglob nullglob`, with
  no executable filter. The hook registers exactly that set, so it cannot add a shim pyenv
  would not have made.
- `nullglob` is already on when hooks are sourced (`pyenv-rehash` sets it before line 193),
  so the hook leaves it alone. `dotglob` is off at that point, so the hook restores it to
  off.
- **Install.** `setup_dotfile_symlinks` links the file with `safe_link` to
  `${PYENV_ROOT:-${HOME}/.pyenv}/pyenv.d/rehash/`, creating the directory. pyenv searches
  `${PYENV_ROOT}/pyenv.d` (`libexec/pyenv:96`). That directory does not exist on `claude`
  today, so the link cannot shadow anything.
- **macOS.** The hook runs there too and is a no-op: GNU/BSD `sort` already keeps both
  names, and the extra registrations are duplicates.
- **No `.zprofile` change.** The operator's uncommitted `.zprofile` edit in the main
  checkout is therefore untouched.
- **Rejected in round 1:** a `.zprofile` `PATH` prepend (covers one actor);
  `pyenv init --path --no-rehash` (leaves no automatic rehash); `LC_ALL=C` (unmeasured,
  one call site).

**D2 is resolved by removing the cause, not by a detector.** The round-1 doctor shim arm
is dropped. `make test` already fails loudly on a missing `pytest`, and nothing runs doctor
on `claude` on a schedule, so the arm added attribution without detection.

### Part 2: provision the cargo plugins, verified by running them

**Pins.** Add `CARGO_TOOLS` to `lib/constants.sh`: eight entries, each with its consumer
stated in a comment.

| crate | version | consumer |
| --- | --- | --- |
| cargo-audit | 0.22.1 | etch-cli `Makefile`; math `scripts/sbom-sign.sh` |
| cargo-deny | 0.19.4 | etch-cli `Makefile` |
| cargo-insta | 1.47.2 | etch-cli `Makefile` |
| cargo-machete | 0.9.2 | etch-cli `Makefile` |
| cargo-mutants | 27.0.0 | math `*-rs/Makefile`; etch-cli `Makefile`; `mutation-pr` skill |
| cargo-semver-checks | 0.47.0 | etch-cli `Makefile` |
| cargo-tarpaulin | 0.35.2 | per-crate coverage gate; DoD coverage evidence |
| cargo-zigbuild | 0.22.3 | etch-cli `Makefile` |

`cargo-fuzz` and `cross` are excluded: the goal-fit lens found zero references across
math, etch-cli, terraform_ansible and ai-config. The plan re-derives every consumer with
`git grep` before pinning, and drops any row that has none.

**Readiness is "runs", not "listed".** Both lenses found that a version match in
`cargo install --list` says nothing about whether the binary loads. tarpaulin links seven
linuxbrew sonames, including `libgit2.so.1.9` and `libllhttp.so.9.4`, and `-t update` runs
`brew upgrade` then `brew cleanup` (`lib/helpers.sh:164,175`). So one routine update can
leave a listed binary that dies at load. Define one helper used by both install and doctor:

`_cargo_tool_state <cargo> <crate> <version>` prints exactly one of:

- `ok`: the list has `<crate> v<version>:` **and** `<cargo> <sub> --help` exits 0, where
  `<sub>` is the crate name without its `cargo-` prefix.
- `wrong-version`: the list has the crate at a different version.
- `broken`: the list has the version but `--help` exits non-zero.
- `absent`: the crate is not in the list.

The probe is `--help`, not `--version`. On `claude`, all eight exited 0 on `--help`, but
`cargo zigbuild --version` exits 2. A load failure exits 127 regardless of argv, as
measured on `claude` for tarpaulin before the rpath rebuild.

**`install_cargo_tools`** (`lib/developer.sh`):

- Returns 0 immediately when `HAS_RUST` is unset. It prints
  `cargo tools: skipped (HAS_RUST unset)`, so a skipped run can be told apart from a clean
  one.
- Resolves `cargo` as `${HOME}/.cargo/bin/cargo` when executable, else `command -v cargo`.
  When neither exists it returns 1 with `cargo not found`.
- Reads `cargo install --list` once, then for each pin acts on `_cargo_tool_state`:
  - `ok`: print `cargo tools: <crate> <version> ok`.
  - `absent` or `wrong-version`: `cargo install --locked <crate>@<version>`.
  - `broken`: `cargo install --locked --force <crate>@<version>`. Without `--force`, cargo
    reports the version already installed and does nothing.
- On Linux, `cargo-tarpaulin` builds with
  `RUSTFLAGS="-C link-args=-Wl,-rpath,${_brew_lib}"`, where `_brew_lib` is
  `$(brew --prefix)/lib`, resolved once. That flag gave a working binary on `claude`.
  Building a vendored libgit2 instead would remove the soname exposure. The plan measures
  one candidate (`LIBGIT2_NO_PKG_CONFIG=1`) with `ldd` and prefers it if `ldd` shows no
  linuxbrew libgit2. Otherwise the `broken` → `--force` path is the recovery.
- Return is tri-state, like `_install_ubuntu_brew_packages`: 0 all `ok` after the run,
  2 some crates failed (named on stderr), 1 `cargo` unresolvable.
- Called from `run_setup_or_developer` after the platform installs, advisory:
  `install_cargo_tools || log_warn "cargo tools incomplete — see above; setup_env.sh -t doctor reports the gap"`.
- **Not in `-t update`.** A broken binary is repaired by the next `-t setup`/`-t developer`,
  which doctor tells the operator to run.

**Rollout cost, stated.** `workstation` has `HAS_RUST` and today carries only
`cargo-auditable` and `cargo-nextest`. The first `-t developer` there compiles all eight
crates, tens of minutes. Until then doctor reports eight WARNs. Macs with `HAS_RUST` carry
hand installs at the pinned versions, so they report `ok` and compile nothing.

### Part 3: `zig` and `tflint` on Linux

**3a. `zig`.** Add `zig` to the `_install_ubuntu_brew_packages` formula loop. On
2026-09-17, `brew install zig` on `claude` installed 0.16.0, the Studio's version.

**3b. `tflint`.** Add `_install_ubuntu_tflint` to `lib/linux_ubuntu.sh`, gated on
`HAS_DEVTOOLS`, called beside the OpenTofu block.

- Pins in `lib/constants.sh`: `TFLINT_VER="0.61.0"`,
  `TFLINT_SHA256_AMD64="ca4e4e8cb7cc3436f2b6979e9c4fd4e2623a66fcca1ad1fe12f8669967636ae2"`,
  `TFLINT_SHA256_ARM64="999c25cfdb5208fe1133dec6b219e666a39fc2a7a0786a781dc9924ea5945ebf"`.
  Both come from the release's `checksums.txt`, fetched 2026-09-17.
- Skips when `tflint --version` reports `TFLINT_VER`.
- Otherwise it downloads `tflint_linux_${_LINUX_ARCH}.zip` with `curl -fsSL`, verifies it
  with `sha256sum -c`, extracts, and runs `sudo install -m 0755` to
  `/usr/local/bin/tflint`.
- Returns 1 on a download or checksum failure. A checksum failure installs nothing.
- The amd64 binary from exactly this route on `claude` was byte-identical to
  `workstation`'s `/usr/local/bin/tflint` (sha256 `51ade70d…8a1b`).
- Seams `_TFLINT_URL`, `_TFLINT_SHA256`, `_TFLINT_BIN_DIR`, following `_RUSTUP_INIT_*`: the
  digest is exposed and `sha256sum` is never mocked.

### Part 4: `pwsh` installs on a box whose first attempt failed

Rewrite the guard in `_install_ubuntu_powershell`:

1. If `command -v pwsh` resolves, print `pwsh is installed` and return 0.
2. Otherwise, always download the Microsoft config `.deb` for the resolved release
   (`24.04` under `RESOLUTE`, as today) and run `dpkg -i`. This replaces a stale
   `microsoft-prod.list`.
3. Run `apt update`, then `apt install powershell -y`, checking every exit status.
4. On any failure, `log_warn` naming the failed step and return 0. The dispatcher calls
   this function second, with `|| return 1`, so a hard failure would abort the bootstrap
   over one upstream repository.

Accepted costs, measured:

- **Repointing `microsoft-prod.list`.** On `claude` nothing installed comes from it:
  azure-cli has its own list, and `dotnet-*-10.0` comes from Ubuntu `resolute-updates`.
  The risk lens confirmed the noble feed carries no `dotnet-*-10.0`. Two lenses checked
  noble `powershell`'s Depends (`libgcc1`, `libicu76|…`, `libssl3`) and found them
  satisfied on `claude` by `libgcc-s1`, `libicu78` and `libssl3t64`.
- **Repeated work while `pwsh` keeps failing.** Each `-t setup`/`-t developer` run
  downloads again, runs `dpkg -i` and `apt update`, then warns. That costs time only, and
  it is the price of never skipping on an artifact again.

### Part 5: `doctor` reports the dev tools

Add `_doctor_check_dev_tools` to `lib/helpers.sh`, called from `run_doctor` after
`_doctor_check_tools`. It WARNs rather than FAILs, because every install it reports on is
advisory.

- `HAS_DEVTOOLS`: `pwsh`, `tflint` and `zig` must resolve **and** run
  (`pwsh -NoProfile -Command exit`, `tflint --version`, `zig version`). Output is PASS or
  WARN.
- `HAS_RUST`:
  - `cargo` resolves the same way as `install_cargo_tools`.
  - Unresolvable `cargo` is one WARN, `cargo not found — run setup_env.sh -t developer`,
    never eight.
  - Otherwise, one line per `CARGO_TOOLS` entry from `_cargo_tool_state`. `ok` is PASS.
    `absent`, `wrong-version` and `broken` each WARN with that word and the remedy
    `setup_env.sh -t developer`.
  - If `CARGO_TOOLS` is empty, the arm WARNs `no cargo tools pinned` and does not PASS.
- Neither capability set: the arm prints nothing.

## Verification

End-to-end, on the real hosts after merge. Every PASS-expected case below has a paired
negative, so no case can pass only because nothing ran.

1. **Hook covers a non-login actor.** On `claude`, after `setup_env.sh -t setup_user`
   links the hook, run `ssh claude 'PYENV_ROOT=$HOME/.pyenv /home/linuxbrew/.linuxbrew/bin/pyenv rehash'`.
   This rehash uses uutils `sort`. Expected: `~/.pyenv/shims/pytest` present.
   - **Negative control:** temporarily move the hook link aside, repeat, and expect
     `pytest` absent. Restore it and rehash again. (The operator is told before this
     step, because it deletes a shim for a few seconds.)
2. **The original failures pass.** On `claude`, run `setup_env.sh -t recreate-venv`, open
   a login shell, then `make test` in a clone of math `fib`. Expected: the shim is
   present, and rc 0 where it was rc 2.
3. **Doctor reads runnability.** On `claude`, `setup_env.sh -t doctor` shows eight cargo
   PASS lines and PASS for `pwsh`, `tflint` and `zig`.
   - **Negative control:** `chmod -x ~/.cargo/bin/cargo-machete`, then doctor. Expected:
     `cargo-machete … broken` WARN. Restore with `chmod +x`.
4. **Install repairs `broken`.** With `cargo-machete` still made non-executable as in
   case 3, `setup_env.sh -t developer` prints a `--force` reinstall for `cargo-machete`
   only, and prints `… ok` lines for the other seven. The assertion is on those printed
   lines, not on an absence of compiles.
5. **`workstation` rollout.** Doctor shows eight `absent` WARNs, as stated above. Then
   `-t developer` compiles them and doctor shows eight PASS.

In the suite:

- Every new function gets tests for both branches of every guard, its error paths, and
  idempotency.
- The hook is tested by sourcing it with a stub `make_shims` that records its arguments,
  against a fixture `PYENV_ROOT`. The assertions:
  - both `py.test` and `pytest` are registered;
  - a dotfile in `bin/` is registered;
  - `dotglob` is off afterwards;
  - an empty `versions/` registers nothing and does not error.
- `_cargo_tool_state` is tested for all four states against a fixture `cargo` whose
  `install --list` output and per-subcommand `--help` exit codes are set by the test.
- The `sha256sum` mismatch test for `tflint` asserts that nothing was installed.

## Out of scope

- `gitleaks`, `cosign`, `etch`: absent on the Studio too, so `claude` is at parity.
- `terraform`, `tfsec`: no terraform_ansible gate invokes them. Its Makefiles use `tofu`.
- `cargo-fuzz`, `cross`: no consumer found (see Part 2).
- `USER.md`'s session-placement text, which still names the Studio and `workstation`.
  That is an ai-config docs edit and ships separately.

## Multi-Lens Review

Reviewed at commit: `41eb9352` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding:

1. Part 1 fixes the wrong layer. Rehash also runs under uutils `sort` from
   `lib/developer.sh:537` and `:567` (bash), from `ssh claude '<cmd>'`, and from pyenv's
   own install and virtualenv paths. `pyenv-rehash` sources `pyenv-hooks rehash` after
   `make_shims $(pyenv-versions --executables)` and before
   `install_registered_shims`/`remove_stale_shims`. A tracked hook under
   `${PYENV_ROOT}/pyenv.d/rehash/` that calls `make_shims "$PYENV_ROOT"/versions/*/bin/*`
   would therefore fix every actor with no `PATH` ordering. The author verified this
   ordering in `pyenv-rehash` 2.8.6.
2. The tarpaulin rpath build breaks silently when brew bumps libgit2's soname. Part 3a
   skips the rebuild on the version match, and Part 5 reads the same list.
3. `cargo-fuzz` and `cross` have no consumer: zero hits across math, etch-cli,
   terraform_ansible and ai-config. `cargo-machete`'s consumer, etch-cli's `Makefile`,
   is unnamed.
4. Part 2 is close to decoration: `make test` already fails loudly, and nothing runs
   doctor on `claude` on a schedule.
5. The verification cases are PASS-shaped. Part 5 has no positive control.

Assumption: the login shell is the only rehash actor that matters. It is refuted if
`PYENV_ROOT=~/.pyenv pyenv rehash` over ssh (uutils `sort`) removes the shim, or if
provisioning runs on `claude` are ever started over ssh.
Disposition: Addressed. The operator chose "apply all revisions": Part 1 became a pyenv rehash hook; the doctor shim arm was dropped; runnability via `_cargo_tool_state`; fuzz and cross dropped with consumers named; verification rewritten with negative controls.

### Ergonomics

Finding:

1. tarpaulin links 7 linuxbrew sonames (`libgit2.so.1.9`, `libllhttp.so.9.4`,
   `libssh2.so.1`, `libssl.so.3`, and others). `-t update` runs `brew upgrade` plus
   `brew cleanup`, so a routine update breaks it, and neither Part 3a nor Part 5 notices.
   The Mac links `libgit2.1.9.dylib`, so the same exposure applies there.
2. Verification case 5 is wrong. `workstation` has `HAS_RUST` and only
   `cargo-auditable`/`cargo-nextest` installed, so doctor prints 10 new WARNs until
   `-t developer` compiles all ten crates. That rollout cost is not stated.
3. Case 4 passes vacuously if `install_cargo_tools` never runs. Part 5 does not say how
   doctor resolves `cargo`, or what it reports when `cargo` is not found.
4. Part 4 re-downloads, runs `dpkg -i` and `apt update` on every run while `pwsh` keeps
   failing. This cost is unstated. The lens checked the noble `powershell` Depends and
   found them satisfiable on `claude`.

Assumption: a cargo tool installed at the pinned version keeps working. It is refuted
by `ldd` plus any minor-soname bump of libgit2 or llhttp.
Disposition: Addressed. `broken` state plus `--force` reinstall and a doctor that runs binaries; workstation rollout cost stated; doctor `cargo` resolution and not-found verdict specified; case 4 asserts the printed lines; pwsh repeat cost accepted in writing.

### Risk

Finding:

1. Same as Goal-Fit 1. `setup_env.sh -t recreate-venv` on `claude` deletes the shim again
   after Part 1, because `developer.sh:567` calls `pyenv rehash` under bash with no
   gnubin on PATH. No verification case runs recreate-venv.
2. Same as Ergonomics 1 for tarpaulin. Suggests a doctor arm that executes the binary,
   or vendoring libgit2 (possibly `LIBGIT2_NO_PKG_CONFIG=1`, unverified).
3. Same as Ergonomics 3: doctor's `cargo` resolution is unspecified, and an empty list
   must not PASS.
4. Part 4's repeated download is time-only. The noble feed carries no `dotnet-*-10.0`,
   so the stated accepted cost holds.
5. Case 4 needs to assert the skip lines, not an absence of compiles.

Assumption: the login-shell rehash is the recurring one. It is refuted by running
`setup_env.sh -t recreate-venv` on `claude` and then `test -e ~/.pyenv/shims/pytest`.
Disposition: Addressed. The hook covers recreate-venv and ssh actors, and verification case 2 runs `-t recreate-venv`; the vendored-libgit2 route is measured in the plan, with `--force` recovery otherwise; the empty-list doctor case WARNs.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
