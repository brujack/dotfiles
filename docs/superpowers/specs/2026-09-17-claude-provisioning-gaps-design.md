# Close the provisioning gaps found moving sessions to `claude`

> **Status:** Draft, revision 6 — spec review pending.

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

**Added in revision 2: `terraform` and `tfsec`.** terraform_ansible
`aws-terraform/ca-central-1/Makefile:18-23` runs `terraform validate`, `tflint` and
`tfsec`. `workstation` has both tools, `claude` has neither. On the Mac and on
`workstation`, terraform comes from **tfenv**:

- The Mac has `brew "tfenv"` (`Brewfile:118`).
- `workstation` has `/usr/local/bin/terraform` and `/usr/local/bin/tfenv` symlinked into a
  `~/.tfenv` clone of `tfutils/tfenv`, whose global version is 1.14.9.
- `run_update` already `git pull`s `~/.tfenv` when it exists (`lib/workflows.sh:632`).
- No `lib/linux_*.sh` provisions tfenv.

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

This is revision 6. It replaces revision 5 (`37b04d9a`); earlier revisions are
`5fdb8df0`, `1987f7c8`, `9fa812a9` and `41eb9352`. The Multi-Lens Review section below records why. One branch, one PR, six
independent parts, each testable alone.

### Part 1: a pyenv rehash hook that registers every shim, whatever `sort` is

The defect is in `pyenv-versions --executables`, which `pyenv-rehash` calls through
`sort -u`. Any actor that runs `pyenv rehash` with uutils `sort` first on `PATH` loses
the `pytest` shim. At least these actors reach it:

- `.zprofile:9` (login zsh).
- `lib/developer.sh:537` and `:567`, run from `setup_env.sh`'s bash.
- `ssh claude '<cmd>'`.
- pyenv's own `install` and `virtualenv` subcommands.

Fixing `PATH` order would take one change per actor. `libexec/pyenv-rehash` offers one
choke point instead. Both lenses and the author read it:

```
186: shopt -s nullglob
193: make_shims $(pyenv-versions --executables)   # the uutils-damaged list
198: IFS=$'\n' scripts=(`pyenv-hooks rehash`) ... source "$script"
205: install_registered_shims
206: remove_stale_shims
```

That is on pyenv 2.8.6 (brew) on `claude` and `workstation`, 2.8.5 on the Studio (the
same lines), and upstream master. `make_shims` takes basenames and calls `register_shim`,
which is additive, so duplicates are harmless. `pyenv-hooks` globs
`$path/rehash/*.bash` and resolves symlinks with `realpath`. pyenv-virtualenv's own
`envs.bash` already calls `make_shims` from a hook, so the pattern is proven.

**The hook.** A tracked file, `pyenv.d/rehash/dotfiles-register-all-executables.bash`:

```bash
# shellcheck shell=bash
# Sourced by pyenv-rehash between make_shims and install_registered_shims.
# pyenv-versions --executables pipes basenames through `sort -u`; uutils sort
# (Ubuntu 26.04) collates py.test and pytest as equal and drops one, so the
# pytest shim is never registered and remove_stale_shims deletes it. Registering
# the same glob here, without sort, restores it for every caller. See
# docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md.
declare -f make_shims >/dev/null || return 0
_dotfiles_rehash_opts="$(shopt -p nullglob dotglob || true)"
shopt -s nullglob dotglob
make_shims "${PYENV_ROOT}"/versions/*/bin/* "${PYENV_ROOT}"/versions/*/envs/*/bin/*
eval "${_dotfiles_rehash_opts}"
unset _dotfiles_rehash_opts
```

- **`|| true` on the capture is load-bearing.** `shopt -p` exits 1 when any named
  option is off, and `pyenv-rehash` runs under `set -e`. Without it the assignment aborts
  every rehash. Round 3 measured this: a scratch `PYENV_ROOT` gave rc 1 and zero shims.
  With `|| true`, both option lines are captured on bash 3.2 and 5.3.
- **The hook owns its glob options.** On `workstation`, `~/.pyenv` is a pyenv 2.7.2 git
  clone with `pyenv.d/rehash/conda.bash`, and that hook runs `shopt -u dotglob nullglob`
  before ours (hooks run in alphabetical order). Without its own `nullglob`, an unmatched
  glob would register a shim literally named `*`. The hook sets both options and then
  restores exactly what its caller had, via `shopt -p`.
- **Contract guard.** If a pyenv upgrade removes or renames `make_shims`, the hook returns
  0 and rehash behaves as stock pyenv. It never aborts rehash under `set -e`. Part 2 is
  what notices that the hook stopped helping.
- **The glob mirrors pyenv's own** (`versions/*/bin/*`, `versions/*/envs/*/bin/*`, no
  executable filter), so the hook cannot add a name pyenv's unsorted list would lack. On
  `workstation` it does re-register names that `conda.bash` deregisters. Those are conda
  shims, and no conda version is installed on any development machine. The plan confirms
  with `ls ~/.pyenv/versions` on all three.
- **Install as a copy, not a symlink.** A new `install_pyenv_rehash_hook` in
  `lib/helpers.sh` runs
  `install -m 0644 <repo>/pyenv.d/rehash/dotfiles-register-all-executables.bash`
  into `${PYENV_ROOT:-${HOME}/.pyenv}/pyenv.d/rehash/`.
  - It returns 0 and does nothing when `${PYENV_ROOT}/versions` does not exist. A host
    with no pyenv gets no `pyenv.d` state.
  - Otherwise it creates the directory, and it skips the install when `cmp -s` shows the
    copy is already current.
  - **Why a copy.** Round 4 measured a dangling symlink on brew pyenv 2.8.5 and on `claude`:
    rehash exits 1 with **no stderr**, creates no new shims, and `pyenv init --path` ignores
    the rc. The link would point into the main checkout, and `claude`'s reflog shows that
    checkout on other branches for hours (2026-08-12, 2026-08-24). A copy cannot dangle.
  - **Cost.** After the hook file changes in the repo, the copy stays stale until the next
    refresh.
  - **Called from:** `run_setup_user`, and the `pyenv-shims` section of `run_update`
    (Part 2).
  - On `claude` and the Studio, `pyenv.d` does not exist yet. On `workstation`, `~/.pyenv`
    is a pyenv 2.7.2 git clone, so the copy lands as an untracked file there, and
    `pyenv update` (`developer.sh:487`) tolerates it.
- **macOS:** the hook runs, and it registers only names already in the list from BSD `sort`.
  Round 3 showed this holds only with the `|| true` above, which the suite pins.
- **No `.zprofile` change.** The operator's uncommitted `.zprofile` edit is untouched.

### Part 2: doctor verifies the outcome, whatever the mechanism

Add `_doctor_check_pyenv_shims` to `lib/helpers.sh`, called after
`_doctor_check_gnu_coreutils`. Round 1 dropped this arm as decoration because `make test`
already fails loudly. Round 2 found it is the only detector for a pyenv upgrade silently
retiring Part 1's hook, which would bring D1 back on every 26.04 box with no signal until
a gate breaks. The arm checks the outcome, so it also catches any future rehash defect.

- It returns silently when `${PYENV_ROOT}/versions/ansible/bin` does not exist.
- For every entry there it expects `${PYENV_ROOT}/shims/<name>`. It FAILs naming the
  missing shims, with the remedy `pyenv rehash`, and when all are present it PASSes with
  the count: `pyenv shims: 143 of 143 ansible venv entries shimmed`.
- **No exclusion list.** After a rehash with GNU `sort`, every entry was shimmed on
  `claude` (143/143), `workstation` (144/144) and the Studio (142/142).
- An empty `bin/` WARNs `ansible venv bin is empty`. It never PASSes `0 of 0`.
- Seam: `_OVERRIDE_PYENV_ROOT`.
- **Also runs in `-t update`.** The event that retires the hook, `brew upgrade pyenv`
  (Linux, Mac) or `pyenv update` (a clone), happens inside `-t update`. So a `pyenv-shims`
  section runs after `pip`, in its own block gated on
  `_run_all || UPDATE_BREW || UPDATE_PIP`, and is added to `_UPDATE_SECTION_ORDER` after
  `pip-check`.
  - First it calls `install_pyenv_rehash_hook`, then `pyenv rehash`, using the
    `pyenv` resolved the same way `setup_ansible` resolves it.
    - Why rehash first: `uv sync` in the `pip` section writes console scripts straight into
      the venv without a rehash. Checking before a rehash would WARN on a correct run.
    - The check afterwards therefore reports only shims that a rehash could not produce.
  - Then it records WARN when the same predicate the doctor arm uses (a shared
    `_pyenv_missing_shims` that prints the names) reports any missing shim, and SKIP when
    there is no ansible venv.

### Part 3: cargo plugins, repaired where they break

**Pins.** `CARGO_TOOLS` in `lib/constants.sh`, eight entries, each carrying a consumer
comment. The plan re-derives every consumer with `git grep` and drops any row that has
none.

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

`cargo-fuzz` and `cross` are excluded: no consumer in any repo.

**State.** `_cargo_tool_state <cargo> <crate> <version>` prints one of:

- `ok`: listed at the pin and `<cargo> <sub> --help` exits 0.
- `newer`: listed at a higher version and `--help` exits 0.
- `older`: listed at a lower version.
- `broken`: listed but `--help` exits non-zero.
- `absent`: not listed.

A non-executable subcommand binary makes `cargo <sub> --help` exit 101, measured on `claude` with a scratch `cargo-zzz` at mode 644, so `chmod -x` yields `broken`. `--help` is the probe because `cargo zigbuild --version` exits 2 while all eight exit 0 on
`--help`. A load failure exits 127 whatever the argv. Versions are compared by numeric
components, per `shell.md`'s semver pitfall, and never lexically.

**`install_cargo_tools`** (`lib/developer.sh`):

- When `HAS_RUST` is unset, it prints `cargo tools: skipped (HAS_RUST unset)` and returns
  0.
- `cargo` resolves as `${HOME}/.cargo/bin/cargo` if that is executable, else
  `command -v cargo`. If neither resolves it prints `cargo not found` and returns 1.
- Per pin:
  - `ok` or `newer`: prints `cargo tools: <crate> <installed> ok`. A newer hand install is
    left alone.
  - `absent` or `older`: `cargo install --locked <crate>@<version>`.
  - `broken`: `cargo install --locked --force <crate>@<version>`.
- **tarpaulin links a vendored libgit2 on Linux.** It builds with
  `LIBGIT2_NO_PKG_CONFIG=1`, so `git2-sys` compiles its bundled libgit2 instead of linking
  linuxbrew's. Measured on `claude` on 2026-09-17 with
  `cargo install --locked --root <scratch> cargo-tarpaulin@0.35.2`:
  - `readelf -d` NEEDED lists only `libz.so.1`, `libssl.so.3`, `libcrypto.so.3`,
    `libgcc_s.so.1` and `libc.so.6`, with no RUNPATH.
  - `env -i ldd` shows no linuxbrew path and no `not found`.
  - The binary runs.

  So a brew libgit2 soname bump cannot break a tarpaulin **built this way**. An Ubuntu
  OpenSSL major could, and `broken` recovers from that. No rpath flag is used. Existing
  rpath builds (on `claude`, from 2026-09-17) still probe `ok` and keep their brew link
  until they break. The next `-t update` run then rebuilds them vendored.
- **macOS: no flag, which is unmeasured.** The Studio's hand-installed tarpaulin links
  `/opt/homebrew/opt/libgit2/lib/libgit2.1.9.dylib`, so a brew bump can break it there, and
  the `broken` → `--force` path in `-t update` is the recovery. The flag is not applied on
  macOS until it has been measured there.
- Tri-state return: 0 all `ok`/`newer`; 2 some crates failed (named on stderr); 1 `cargo`
  unresolvable.

**Call sites.**

- `run_setup_or_developer`, after the platform installs:
  `install_cargo_tools || log_warn "cargo tools incomplete — see above"`.
- **`run_update`**, as a `cargo-tools` section:
  - It is **its own block, placed after the `_run_all`-only "git-based tools" block**
    (after `lib/workflows.sh:711`), gated on `_run_all || UPDATE_BREW`. `update_rust` sits
    inside that `_run_all`-only block, so a section placed next to it would be unreachable
    from `--brew-only`. Only its display position in `_UPDATE_SECTION_ORDER` comes directly
    after `rust`.
  - `--brew-only` repairs a binary that a brew upgrade broke. `--pip-only`,
    `--gems-only` and `--claude-only` render it `SKIP`.
  - **`--brew-only` can compile.** On a first run, or after a pin bump, every `absent` or
    `older` crate builds, which can take tens of minutes. This is stated, not hidden.
  - With `HAS_RUST` unset it calls `_update_skip "cargo-tools" "HAS_RUST not set"`, never
    `[OK]`.
  - The rc maps to a status the same way `git-hooks` does: 2 is WARN, 1 is FAIL.
  - When all tools are `ok`, the cost is one list read plus eight `--help` probes (0.13 s on
    `claude`).
- **Pins get staleness reports through `check-versions`.** `run_check_versions` is
  GitHub-release based, and two things break it here: `cargo-audit` releases carry
  monorepo tags (`cargo-audit/v…`), and `~/.cargo/bin` is not on the non-interactive
  `PATH`, so its `command -v` probe would SKIP everything.
  - A small `_check_cv_cargo_tools` therefore reads each crate's `max_stable_version` from
    `https://crates.io/api/v1/crates/<crate>`, sending
    `-A "dotfiles check-versions (bjackson@pobox.com)"`. crates.io returns **403** to
    curl's default User-Agent: measured from the Studio, `claude` and `workstation` on
    2026-09-17, and the same request with `-A` returned 200. It prints `[OK]` or
    `[OUTDATED] … latest=<v>` in the same format, counting toward the existing totals.
  - It is report-only (no in-place `--update` prompt), because the pins live in one array.
  - This is what surfaces a `cargo-semver-checks` pin falling behind the rustdoc format
    that `update_rust` moves on. The `--help` probe cannot see that.
- **No cargo doctor arm.** `-t update`'s summary is where the result is read.

**Rollout cost, stated.** `workstation` has `HAS_RUST` and today only `cargo-auditable`
and `cargo-nextest`, so its first `-t developer` or `-t update` compiles all eight, tens of
minutes. The Studio has all eight at the pins and compiles nothing. `personal_laptop` and
`wsl2_workstation` also carry `HAS_RUST` and are unmeasured. On the WSL VM this is expected
to be substantially longer, and the first run there is the operator's call.

### Part 4: Linux terraform tooling (`zig`, `tflint`, `tfsec`, tfenv)

**4a. `zig`.** Add it to the `_install_ubuntu_brew_packages` formula loop. `brew install
zig` gave 0.16.0 on `claude`, the Studio's version.

**4b. `tflint` and `tfsec` through one pinned release-binary helper.** The two share an
identical sequence: pinned version, per-arch sha256, download, `sha256sum -c`, extract,
install. That sequence is exactly where a hand copy drops the verify step, so two
consumers are enough to justify one helper here.

`_install_pinned_release_binary <name> <version> <url> <sha256> <kind> <version-line-regex>`:

- `<kind>` is `zip` or `raw`.
- It runs `${_RELEASE_BIN_DIR:-/usr/local/bin}/<name>`, never the copy on `PATH`, and
  skips when that binary's version output has a **whole line** matching
  `<version-line-regex>`, anchored `^…$`. A substring match is not enough, because
  `tflint --version` also prints an "out of date … latest is X" line.
- Otherwise: `curl -fsSL` into a `mktemp -d` removed by a subshell `EXIT` trap (per
  `shell.md`), `sha256sum -c`, extract per kind, then `install -m 0755` into
  `${_RELEASE_BIN_DIR:-/usr/local/bin}`, prefixed with `sudo` only when that directory is
  not writable by the caller.
- It returns 1 on any failure, and a checksum failure installs nothing.
- Seams: `_RELEASE_BIN_DIR` and per-tool URL/SHA overrides. `sha256sum` is never mocked.
- Call site: `_install_ubuntu_tflint` and `_install_ubuntu_tfsec`, gated on
  `HAS_DEVTOOLS`, called beside the OpenTofu block. Each is advisory: `|| log_warn`, as
  `dotnet` is.

| tool | version | artifact | version line | amd64 sha256 | arm64 sha256 |
| --- | --- | --- | --- | --- | --- |
| tflint | 0.61.0 | `tflint_linux_<arch>.zip` | `^TFLint version 0\.61\.0$` | `ca4e4e8cb7cc3436f2b6979e9c4fd4e2623a66fcca1ad1fe12f8669967636ae2` | `999c25cfdb5208fe1133dec6b219e666a39fc2a7a0786a781dc9924ea5945ebf` |
| tfsec | 1.28.14 | `tfsec-linux-<arch>` (raw) | `^v1\.28\.14$` | `a32d0799bbefababaa4fcd814da9f4d251cd932789590b99d1d5fcb89ace6f68` | `7b872b0e8f398abebc21ab78f6c0535029ff649f0d18f0f3454a01bece3006a2` |

- The version-line formats were measured on `workstation`: `TFLint version 0.61.0`, and
  tfsec's banner followed by `v1.28.4`.
- `workstation`'s tfsec is a regular hand-installed file at 1.28.4, so the pin replaces it
  with 1.28.14. That is not a symlink, so nothing is managed through it.
- tfsec is archived upstream in favour of Trivy. It is pinned because a gate calls it.
- The header comment in `lib/constants.sh` naming `TFLINT_VER`/`TFSEC_VER` as deleted dead
  pins is corrected in the same edit.

**4c. terraform through tfenv, matching the Mac and `workstation`.** Add
`_install_ubuntu_tfenv`, gated on `HAS_DEVTOOLS`:

1. If `~/.tfenv` is absent, `git clone https://github.com/tfutils/tfenv.git ~/.tfenv`.
   That is the layout `run_update`'s existing `tfenv` section already pulls.
2. For each of `tfenv` and `terraform` in `/usr/local/bin`:
   - Absent: `sudo ln -s "${HOME}/.tfenv/bin/<name>" "/usr/local/bin/<name>"`.
   - Already a symlink into `~/.tfenv/bin`: leave it.
   - Anything else (a regular file, or a symlink elsewhere): `log_warn` naming the path,
     and **do not touch it**. Overwriting is how revision 3 would have silently replaced
     tfenv.
3. If `~/.tfenv/version` is absent, run `tfenv install ${TERRAFORM_VER}` then
   `tfenv use ${TERRAFORM_VER}`. If it exists, the operator chose a version, so leave it
   (`workstation` stays on 1.14.9). tfenv checks the download against HashiCorp's
   `SHA256SUMS`. That is a **same-origin** integrity check: `tfenv-install` skips PGP
   verification unless gpg or keybase is configured (measured on `workstation`,
   `libexec/tfenv-install:318-376`). It is weaker than the in-repo sha256 pins used for
   `tflint` and `tfsec`, and is accepted because it matches how terraform already arrives
   on the Mac and on `workstation`.
4. Any failure: `log_warn` and return 0.

- `TERRAFORM_VER` ("1.15.6") gains a `lib/` consumer, and its annotation is updated.
- ca-central-1 requires `>= 1.14.0`, which both versions satisfy.
- **The helper is not used for terraform.**

### Part 5: `pwsh` installs on a box whose first attempt failed

1. If `pwsh -NoProfile -Command exit` exits 0, print `pwsh is installed` and return 0. The
   guard tests that pwsh runs, the same as Part 6.
2. Otherwise download the Microsoft config `.deb` for the resolved release (`24.04` under
   `RESOLUTE`) and `dpkg -i` it. That replaces a stale `microsoft-prod.list`.
3. `apt update`, then `apt install powershell -y`, checking every exit status.
4. On failure, `log_warn` naming the step and return 0, so one upstream repository cannot
   abort the bootstrap.

Measured and accepted:

- **noble `pwsh` runs on resolute.** `powershell_7.6.2-1` extracted into a scratch
  directory on `claude` ran and printed `7.6.2`, rc 0.
- **Repointing `microsoft-prod.list` affects nothing installed.** azure-cli has its own
  list, and `dotnet-*-10.0` comes from Ubuntu `resolute-updates`. The noble feed carries no
  `dotnet-*-10.0`.
- **While `pwsh` keeps failing, every run repeats download, `dpkg -i` and `apt update`.**
  That costs time only.

### Part 6: doctor reports the Linux dev tools (Linux only)

`_doctor_check_dev_tools` in `lib/helpers.sh`, after `_doctor_check_tools`. It WARNs,
never FAILs, because every install it reports on is advisory.

- Gated on `LINUX` **and** `HAS_DEVTOOLS`. Macs get these tools from the `Brewfile`, and
  stock macOS has no `timeout`, so the arm does not run there. On `claude`, `timeout` is
  `/usr/bin/timeout` (uutils).
- Tools: `pwsh`, `tflint`, `zig`, `terraform`, `tfsec`. Each must resolve **and**
  run its version probe under `timeout 10`, since a hung binary must not block doctor.
- Off Linux or without `HAS_DEVTOOLS`: prints nothing.
- The probes run from `${HOME}`, so `terraform` resolves tfenv's global version and no
  project-local `.terraform-version` can steer the result.

## Verification

End-to-end, after merge. Cases that exercise install code run where the tool is genuinely
absent. Cases that delete a shim run against a **scratch copy of `PYENV_ROOT`**, never
`claude`'s live one, because five sessions use it.

1. **The hook fixes the uutils actor.**
   - Setup: on `claude`, `cp -a ~/.pyenv/versions/ansible` into a scratch `PYENV_ROOT` with
     empty `shims/` and a `pyenv.d/rehash/` holding a copy of the hook.
   - Run `/home/linuxbrew/.linuxbrew/bin/pyenv rehash` with `PYENV_ROOT` set to the scratch
     copy. `ssh` gives uutils `sort`.
   - Expected: `shims/pytest` present.
   - **Negative:** the same scratch root without the hook gives `pytest` absent. This
     proves the control can fail.
2. **The hook is safe with nullglob off.** Same scratch root plus a stub
   `pyenv.d/rehash/aaa.bash` that runs `shopt -u nullglob dotglob`, and a second version
   directory with no `bin/` entries. Expected: no shim named `*`, `pytest` present.
3. **The login shell no longer breaks gates.** On `claude`, after `-t setup_user` links
   the hook, first assert that `~/.pyenv/pyenv.d/rehash/dotfiles-register-all-executables.bash` is a
   regular file (`test -f` and `! test -L`) and `cmp`-equal to the repo copy. Then:
   - Open a login shell, then run `make test` in a clone of math `fib`. Expected: rc 0,
     where it was rc 2 before.
   - **Negative:** already recorded in D1 (rc 2 before the change).
4. **The Part 2 doctor arm can fail.** Point `_OVERRIDE_PYENV_ROOT` at case 1's no-hook
   scratch root. Expected: FAIL naming `pytest`. Pointed at the hooked root: PASS with a
   non-zero count.
5. **pwsh and tfenv install for real on `claude`.** `pwsh`, tfenv, `terraform`, `tfsec`
   and `zig` are absent there, while `tflint` is hand-installed. Run
   `setup_env.sh -t doctor` first. Expect exactly four WARNs (`pwsh`, `terraform`, `tfsec`,
   `zig`) and one PASS (`tflint`): that is the negative. Then run `setup_env.sh -t developer`. Expected:
   - `microsoft-prod.list` reads `24.04`.
   - `/usr/local/bin/terraform` and `/usr/local/bin/tfenv` are symlinks into `~/.tfenv/bin`.
   - `terraform version`'s first line is `Terraform v1.15.6`.
   - A second `-t doctor` shows PASS for all five.
6. **Release-binary installs run for real without touching `/usr/local/bin`.** On
   `claude`, call `_install_pinned_release_binary` for `tflint` and `tfsec` with
   `_RELEASE_BIN_DIR` set to a scratch directory the caller owns, so no `sudo`. Expected:
   both binaries, each with its anchored version line. The existing
   `/usr/local/bin/tflint` must not cause a skip.
   - **Negative:** a wrong sha256 override leaves the scratch directory empty.
7. **Cargo and zig install for real on `workstation`, and tfenv is preserved.**
   - Record `readlink /usr/local/bin/terraform` and `cat ~/.tfenv/version` (1.14.9).
   - Run `setup_env.sh -t doctor`. Expected: a `zig` WARN, the negative.
   - Run `setup_env.sh -t developer`. Expected: eight crate installs and a `zig` install
     printed.
   - Run `-t doctor` again. Expected: `zig` PASS, the `readlink` unchanged, and the
     version file still 1.14.9.
8. **`-t update --brew-only` repairs `broken` and preserves `newer`.** This runs a real
   `brew upgrade` on `workstation`, a side effect the operator accepts by running it. On `workstation`
   after case 7, `chmod -x ~/.cargo/bin/cargo-machete`, then
   `setup_env.sh -t update --brew-only`. Expected: the `cargo-tools` section prints one
   `--force` reinstall and seven `… ok` lines. The assertion is on those lines.

In the suite:

- Every new function: both branches of every guard, the error paths, and idempotency.
- Hook tests source the file with a stub `make_shims` over a fixture `PYENV_ROOT`:
  - `pytest` and `py.test` are both registered, and a dotfile entry is registered.
  - **With `nullglob` off on entry:** an empty version dir registers no literal `*`, and
    `nullglob`/`dotglob` are restored to off afterwards.
  - With both options on on entry: they are restored to on.
  - With `make_shims` undefined: the hook returns 0 and registers nothing.
- `_cargo_tool_state`: all five states, against a fixture `cargo` whose list output and
  per-subcommand exit codes the test sets. The version comparison is tested at `0.9.2`
  vs `0.10.0`, which a lexical comparison gets wrong.
- `_doctor_check_pyenv_shims`: PASS with count, FAIL naming the missing shims, empty-`bin`
  WARN, and silence without a venv.
- `_doctor_check_dev_tools`:
  - PASS (resolves and runs).
  - WARN when absent.
  - WARN when it resolves but the probe exits non-zero. This is the case that proves "runs,
    not resolves".
  - WARN when the probe times out, using a stub that sleeps past a lowered timeout seam.
  - Silence without `HAS_DEVTOOLS`.
- `_install_pinned_release_binary`: a sha256 mismatch installs nothing; the skip on a
  matching version; both `kind` extractors (`zip`, `raw`).
- `run_update`'s `cargo-tools` section:
  - rc 2 renders WARN and rc 1 renders FAIL.
  - `--pip-only` renders SKIP.
  - **`--brew-only` records a non-SKIP status.** This proves the block placement: the
    SKIP assertion alone also passes when the section is unreachable.
  - `HAS_RUST` unset renders SKIP with its reason.
- Hook test **under `set -e`** with `dotglob` off on entry, the default: rehash-like
  caller survives and options are restored. This is the case that fails without
  `|| true`.
- `install_pyenv_rehash_hook`:
  - with no `versions/` it creates nothing;
  - it creates the directory and copies the hook;
  - `cmp`-equal means no rewrite;
  - a changed source is re-copied;
  - the result is a regular file, not a symlink.
- The `pyenv-shims` update section: `pyenv rehash` is called before the check; WARN naming a missing shim; SKIP without a venv;
  SKIP under `--gems-only`.
- `_check_cv_cargo_tools` against a fixture crates.io response: `[OK]`, `[OUTDATED]`
  with `latest=`, and `[WARN]` on a failed fetch. Also assert that the `curl` argv
  recorded by `tests/mocks/curl` carries `-A` with a non-empty User-Agent; the fixture
  alone cannot see a missing header.
- `_install_pinned_release_binary`: a `PATH` binary at the pinned version does not cause
  a skip when `_RELEASE_BIN_DIR` is empty.
- `_install_ubuntu_tfenv`, each against a fixture `/usr/local/bin`:
  - absent paths get symlinks;
  - an existing `~/.tfenv` symlink is left;
  - a regular file is left, with a WARN;
  - an existing `version` file suppresses `tfenv use`.
- The anchored version probe: fixture output carrying the pin only inside an
  "out of date … latest is 0.61.0" line must not skip.

## Out of scope

- `gitleaks`, `cosign`, `etch`: absent on the Studio too, so `claude` is at parity.
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

### Round 2 (revision 2, reviewed at commit `9fa812a9`)

**Goal-Fit.**

Finding:

1. The repair runs at the wrong time. `-t update` (`brew upgrade` + `cleanup`) is what
   breaks tarpaulin, yet `install_cargo_tools` is not in `-t update`, and the Part 5 cargo
   arm fails the same reads-it test that removed the shim arm. Suggests calling
   `install_cargo_tools` at the end of `-t update` and dropping the Part 5 cargo arm.
2. "Every PASS case has a paired negative" is false. `claude` already carries every tool
   by hand, so cases 3 and 5 pass without the new install code running, and no host case
   runs `_install_ubuntu_tflint` or Part 4.
3. Case 2 runs `-t recreate-venv` on the host where five live sessions use the venv.
4. Out-of-scope is wrong: `aws-terraform/ca-central-1/Makefile:18-23` runs `terraform`,
   `tflint` and `tfsec`. `workstation` has both; `claude` has neither. The author verified
   this.
5. A dangling hook link makes every rehash exit 1 under `set -e`. It fails safe but loudly.

Assumption: tarpaulin breaking on a routine update is frequent enough to justify the
`broken` machinery. Settle with `brew log libgit2`: how often has the soname changed?
Disposition: Addressed (revision 3). `install_cargo_tools` runs at the end of `-t update`; the cargo doctor arm is dropped; host cases exercise the real installs; the claim about paired negatives is removed; no `recreate-venv` on `claude`; `terraform`/`tfsec` added; the dangling-link behaviour is recorded.

**Ergonomics.**

Finding:

1. Doctor runtime is fine: 0.13s for eight `--help` probes on `claude`, 1.15s for `pwsh`
   on the Studio. Not raised.
2. The Part 4 guard (`command -v pwsh`) and the doctor probe (`pwsh` runs) test different
   things, so a crashing `pwsh` would loop forever.
3. Case 5 miscounts: `workstation` also lacks `zig`, so it shows 9 WARNs, not 8.
4. The paired-negative claim is overstated (as Goal-Fit 2).
5. Repairing `broken` costs a full `-t developer`. The real exposure is libgit2 or OpenSSL
   only (`readelf -d` NEEDED), not seven sonames.
6. `wrong-version` downgrades hand-upgraded newer installs to the pin.
7. "Cannot shadow" is false on `workstation`: `~/.pyenv` is a pyenv 2.7.2 git clone that
   already has `pyenv.d/rehash/conda.bash` and `source.bash`.
8. Case 1's negative control deletes live shims on `claude`. Use a scratch `PYENV_ROOT`.
9. Rollout cost is unmeasured for `personal_laptop` and `wsl2_workstation`.

Assumption: noble `pwsh` starts on resolute. **Checked by the author on 2026-09-17:** noble
`powershell_7.6.2-1` extracted with `dpkg-deb -x` into a scratch directory on `claude`
ran `pwsh -NoProfile` and printed `7.6.2`, rc 0. Confirmed.
Disposition: Addressed (revision 3). The pwsh guard tests that pwsh runs; case counts are corrected; `newer` installs are preserved; the exposure is restated from `readelf -d`; the hook text names `workstation`; negative controls use a scratch `PYENV_ROOT`; rollout cost is stated for laptop/WSL.

**Risk.**

Finding:

1. "`nullglob` is already on" is false on `workstation`. Hooks sort alphabetically, and
   `conda.bash`'s `conda_exists` runs `shopt -u dotglob nullglob` first. With nullglob
   off, an unmatched glob registers a shim named `*`, and under bash 3.2 the unquoted loop
   expands it against the cwd. This is latent today. The hook must save its caller's
   options, set its own, and restore them.
2. A missing `make_shims` (after a pyenv upgrade) or a dangling link aborts every rehash
   under `set -e`, and with the D2 detector dropped nothing reports it. Guard with
   `declare -f make_shims >/dev/null || return 0`, as pyenv-virtualenv's `envs.bash` does.
3. The paired-negative claim is false. No suite tests cover `_doctor_check_dev_tools`'s
   branches, and the empty-`versions/` hook test passes whenever the harness sets nullglob.
4. Doctor runs binaries with no timeout. `~/.cargo/bin/cargo` is the rustup proxy and can
   download a toolchain under a `rust-toolchain.toml`. Latent.

Assumption: the pyenv hook contract (`make_shims` in scope; hooks sourced between
`make_shims` and `remove_stale_shims`) survives brew pyenv upgrades. Settle with
`git log -p -- libexec/pyenv-rehash` upstream, and re-grep after each upgrade.
Disposition: Addressed (revision 3). The hook owns and restores `nullglob`/`dotglob`; `declare -f make_shims` guard; the Part 2 outcome doctor arm is restored as the upgrade detector; doctor probes run under `timeout 10` from `${HOME}`; suite tests cover every doctor branch and the nullglob-off hook case.

### Round 3 (revision 3, reviewed at commit `1987f7c8`)

**Goal-Fit.**

Finding:

1. **Blocking.** Part 4's terraform row replaces tfenv. The Mac uses `brew "tfenv"`
   (`Brewfile:118`), and on `workstation` `/usr/local/bin/terraform` is a symlink to
   `~/.tfenv/bin/terraform`, with versions 1.3.5, 1.9.0 and 1.14.9. GNU `install`
   replaces that symlink with a regular file, so tfenv would silently stop managing
   terraform. `terraform` was also never in D3.
2. Case 8's `chmod -x` → `broken` mapping is unmeasured.
3. `claude` already has a hand-installed `/usr/local/bin/tflint`.

Assumption: tfenv is the intended terraform manager on Linux, as on the Mac. The author
checked: `run_update` already has a tfenv section that `git pull`s a `~/.tfenv` clone
(`lib/workflows.sh:632`); `workstation`'s clone is `tfutils/tfenv`, last pulled
2026-04-28; `claude` has none; no `lib/linux_*.sh` provisions it.
Disposition: Addressed (revision 4). The operator chose "revision 4, everything": terraform now comes through tfenv on Linux (Part 4c), never overwriting a non-tfenv path or an existing version choice; D3 names terraform and tfsec; `chmod -x` → rc 101 → `broken` is measured; case 6 uses a scratch bin dir.

**Ergonomics.**

Finding:

1. **Blocker.** Same tfenv overwrite as Goal-Fit 1. Case 7 would trigger it.
2. The `cargo-tools` section has no flag gate, so `--pip-only` and friends would run it,
   including a first-run compile.
3. With `HAS_RUST` unset it returns 0, so the summary shows `[OK] cargo-tools`. It should
   use `_update_skip`.
4. Part 6 is titled Linux but gates on `HAS_DEVTOOLS`, so Macs are in scope. `timeout`
   exists on macOS only through brew coreutils, so without it every probe exits 127.
5. Case 7 needs an explicit `-t doctor` before and after. Case 8 needs a flag gate to be
   practical.
6. The version-probe skip is a substring match, which `terraform version`'s
   "out of date" line can satisfy.

Assumption: `LIBGIT2_NO_PKG_CONFIG=1` gives a tarpaulin with no linuxbrew dependency. It
may still link linuxbrew openssl. Settle with `ldd <bin> | grep linuxbrew` after building
with the flag. **Checked by the author on 2026-09-17:** a scratch build on `claude` has no
linuxbrew NEEDED, no RUNPATH, and runs. Confirmed.
Disposition: Addressed (revision 4). The cargo-tools update section is gated on `_run_all || UPDATE_BREW`, renders SKIP without `HAS_RUST`, and sits after `rust` in the section order; Part 6 is Linux-only; version probes are anchored whole-line regexes; case 7 runs doctor before and after; case 8 uses `--brew-only`.

**Risk.**

Finding:

1. **Blocker, measured end to end.** `shopt -p nullglob dotglob` exits 1 when any named
   option is off, and `pyenv-rehash` runs under `set -e`. So the hook's
   `x="$(shopt -p …)"` aborts every rehash: a scratch `PYENV_ROOT` gave rc 1 and zero
   shims on brew pyenv (macOS), against rc 0 with both shims without the hook. Fix:
   `"$(shopt -p nullglob dotglob || true)"`, verified to survive `set -e` and capture
   both lines on bash 3.2 and 5.3.
2. **Blocker.** tfenv overwrite, as above.
3. Part 6 gates on `HAS_DEVTOOLS`, and Macs lack a system `timeout`.
4. Case 3 is PASS-shaped. Add `test -L` on the hook link, and delete the shim in a scratch
   root first.

Assumption: every dev machine's login pyenv sources `${PYENV_ROOT}/pyenv.d/rehash`
between `make_shims` and `install_registered_shims`. Checked on `workstation`'s 2.7.2
clone (lines 191/196/203), so it holds today. Part 2's doctor arm refutes it after any
pyenv update.
Disposition: Addressed (revision 4). `shopt -p … || true`, with a suite case under `set -e`; tfenv is preserved (Part 4c, verification case 7); Part 6 is Linux-only; case 3 asserts the hook link first.

### Round 4 (revision 4, reviewed at commit `5fdb8df0`)

All three lenses ran the real hook end to end against pyenv's `pyenv-rehash` under
`set -e`, with a scratch `PYENV_ROOT` and a `sort` that drops `pytest`:

| lens | pyenv | extra condition | result |
| --- | --- | --- | --- |
| Goal-Fit | 2.8.5 on the Studio | none | clean |
| Risk | 2.8.x | bash 3.2 and 5.3, `conda.bash`-style `shopt -u` first | rc 0, `pytest` present, no `*` shim |
| Ergonomics | linuxbrew pyenv on `claude` | none | clean |

Without the hook, the risk lens saw `pytest` removed.

**Goal-Fit.**

Finding:

1. DESIGN. Part 4b does not say which binary the skip check runs. If it runs the one on
   `PATH`, `claude`'s hand-installed `/usr/local/bin/tflint` makes case 6 skip, and its
   negative passes vacuously. It must run `${_RELEASE_BIN_DIR}/<name>`.
2. APPARATUS. `claude` already has `tflint`, and case 5's doctor negative also WARNs on
   `zig` and `tfsec`.
3. DESIGN (claim scope). "A brew libgit2 soname bump cannot break it" holds only for fresh
   installs. `claude`'s existing rpath tarpaulin probes `ok` and is never rebuilt until it
   breaks.
4. DESIGN. The pins never move and `--help` cannot see staleness: `cargo-semver-checks`
   depends on the rustdoc JSON format, which `update_rust` moves on every update. Wire
   `CARGO_TOOLS` into `check-versions`, or leave that crate unpinned.

Assumption: pinned `cargo-semver-checks` 0.47.0 keeps working across `rustup update`.
Disposition: Addressed (revision 5). The skip check runs `${_RELEASE_BIN_DIR}/<name>`; case 5 lists exact WARN/PASS counts; the tarpaulin claim is scoped to fresh builds; `_check_cv_cargo_tools` reports stale pins from crates.io.

**Ergonomics.**

Finding:

1. DESIGN, measured. A dangling hook link makes rehash fail **silently**: rc 1, 0 bytes of
   stderr, no new shims, stale shims kept. This was checked on brew 2.8.5 and on `claude`.
   `pyenv init --path` ignores the rc. The main checkout has been off master for hours
   (`claude` reflog, 2026-08-12 and 08-24). Options: install a copy rather than a link, or
   add a doctor check that the link resolves.
2. DESIGN, minor. Part 2 runs only when someone runs doctor, while the event that retires
   the hook (`brew upgrade pyenv`) happens inside `-t update`. Suggests running the shim
   check at the end of `-t update`.
3. DESIGN, minor. `--brew-only` can now trigger a first-run compile of tens of minutes.
   `update_rust` sits inside the `_run_all`-only block, so the new section must be its own
   block.
4. APPARATUS. Case 8 runs a real `brew upgrade` on `workstation`.
5. APPARATUS. Case 5's negative under-lists the WARNs.
6. Not raised: doctor probes take 0.02-0.24 s; `claude` compiles nothing.

Assumption: the main checkout always carries the hook file. Refuted by the reflog above.
Disposition: Addressed (revision 5). The operator chose "revision 5, then plan": the hook is installed as a copy; the shim check also runs in `-t update`; the cargo-tools block is standalone with its `--brew-only` compile cost stated; case 8 names its brew side effect; case 5 lists exact counts.

**Risk.**

Finding:

1. DESIGN. The section placement is contradictory. `update_rust` is inside the
   `_run_all`-only block (`lib/workflows.sh:589-711`), so "directly after `rust`, gated on
   `_run_all || UPDATE_BREW`" is unreachable for `--brew-only`, and case 8 fails. It needs
   its own block after `:711`, with only the display order after `rust`. APPARATUS: no
   suite case proves `--brew-only` runs it.
2. DESIGN, measured on brew pyenv under bash 3.2 and 5.3. Same as Ergonomics 1: the
   dangling link is silent, not loud.
3. DESIGN, minor. Part 4c's `sudo ln -s` has no destination; name `/usr/local/bin/<name>`.
   tfenv's check against HashiCorp `SHA256SUMS` is same-origin only, and PGP is skipped
   without gpg/keybase (`tfenv-install:318-376`), which is weaker than the in-repo pins.
4. APPARATUS. Case 6 leaves root-owned files in scratch, because the helper always uses
   `sudo`.

Assumption: the main checkout always has the hook file. Refuted by the reflog.
Disposition: Addressed (revision 5). Standalone cargo-tools block plus a `--brew-only` suite case; hook copied not linked; `ln` destination named; tfenv same-origin checksum stated; `sudo` only when the bin dir is not writable.

### Round 5 (scoped risk review of revision 5 changes, reviewed at commit `37b04d9a`)

Finding:

1. DESIGN, measured. crates.io returns **403** to curl's default User-Agent (tested from
   the Studio, `claude` and `workstation`), and 200 with `-A 'dotfiles-check (<contact>)'`.
   `_check_cv_cargo_tools` must send a User-Agent. The fixture test cannot catch this, so
   add a suite assertion that the curl argv carries `-A`.
2. APPARATUS. Cases 1 and 3 still say "link" and `test -L`, which fails on a correct copy
   install.
3. DESIGN, minor. The `pyenv-shims` section never converges. `uv sync` writes the venv
   without a rehash, so a new console script WARNs on the same run. Run `pyenv rehash`
   before the check.
4. DESIGN, minor. `install_pyenv_rehash_hook` creates `~/.pyenv/pyenv.d/rehash/` on a host
   with no pyenv. Gate it on an existing `${PYENV_ROOT}/versions`.
5. Checked clean: `/usr/local/bin` is not user-writable on any of the three hosts, so
   production still uses `sudo`; the block placement is reachable from `--brew-only`; the
   copy is refreshed before the check.

Assumption: pyenv upgrades change the rehash internals often enough to justify a check in
`-t update`. **Checked by the author on 2026-09-17** in `workstation`'s pyenv clone (a
shallow 303-commit history): `libexec/pyenv-rehash` has 8 commits since 2025-12-05,
including `47871b2d rehash: drop redundant sort -u from make_shims call` and
`8037f226 rehash: streamline executables discovery`. The internals churn, so the rationale
holds.
Disposition: Addressed (revision 6). The operator chose "apply fixes, one more scoped review": crates.io requests send a User-Agent, with a suite argv assertion; cases 1 and 3 check for a regular copied file; `pyenv rehash` runs before the update shim check; the hook install is gated on `${PYENV_ROOT}/versions`.
