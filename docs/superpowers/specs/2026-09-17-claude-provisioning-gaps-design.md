# Close the provisioning gaps found moving sessions to `claude`

> **Status:** Draft — spec review pending.

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

One branch, one PR, four independent parts. Each part is testable alone.

### Part 1: order `.zprofile` so the login rehash sees GNU `sort`

On Linux, prepend the linuxbrew coreutils `gnubin` directory **before**
`eval "$(pyenv init --path)"` in `.zprofile`:

```zsh
_gnubin_linux="${_OVERRIDE_GNUBIN_LINUX:-/home/linuxbrew/.linuxbrew/opt/coreutils/libexec/gnubin}"
[[ -d "${_gnubin_linux}" ]] && export PATH="${_gnubin_linux}:${PATH}"
unset _gnubin_linux
```

- **Same seam and default as `6_path.zsh`.** `_OVERRIDE_GNUBIN_LINUX` and the
  `/home/linuxbrew/.linuxbrew/opt/coreutils/libexec/gnubin` default already appear in two
  places (`6_path.zsh` and `lib/helpers.sh`), and a test asserts they are equal. This adds
  a third reader of the same default. The existing equality test must be extended to cover
  it, or the three copies can drift.
- **Gated on `-d`, not on `RESOLUTE` or `LINUX`.** This matches `6_path.zsh`. The directory
  exists only where the coreutils formula was installed, and that install is itself gated
  on `RESOLUTE`. `.zprofile` sources `config/profiles.zsh` first, but `LINUX` comes from
  `detect_env`, not from the profile table, so it is not reliably set at this point. The
  `-d` guard needs no platform variable and is false on every Mac.
- **`6_path.zsh` keeps its own prepend.** A non-login interactive shell never reads
  `.zprofile`, so the existing prepend is still the only route for that actor. The
  duplicate `PATH` entry is removed by `typeset -U path` at the top of `6_path.zsh`.
- **Rejected: `pyenv init --path --no-rehash`.** The oh-my-zsh pyenv plugin already calls
  `pyenv init - --no-rehash zsh`. Removing the login rehash as well would leave no
  automatic rehash at all, so shims would go stale after every `uv sync`.
- **Rejected: `LC_ALL=C` around the eval.** It depends on uutils' collation under the C
  locale, which was never measured. It also fixes one call site, while the `PATH` prepend
  fixes every later `sort` caller in the login shell.

### Part 2: a doctor arm that checks the outcome

Add `_doctor_check_pyenv_shims` to `lib/helpers.sh` and call it from `run_doctor` directly
after `_doctor_check_gnu_coreutils`.

- It runs only when `PYENV_ROOT` (default `~/.pyenv`) has a `versions/ansible/bin`
  directory. Otherwise it returns 0 and prints nothing, like the RESOLUTE gate on the
  coreutils arm.
- For every executable regular file or symlink in `versions/ansible/bin`, it expects a file
  of the same name in `shims/`. It FAILs once, naming the missing shims, and gives the
  remedy `pyenv rehash` plus a pointer to this spec's cause. When every expected shim is
  present, it PASSes with the count checked, for example `pyenv shims: 147 of 147 ansible
venv binaries shimmed`.
- **No exclusion list.** Measured 2026-09-17 after a rehash with GNU `sort` first on
  `PATH`: every entry in `versions/ansible/bin` had a shim, on both `claude` (143 of 143)
  and `workstation` (144 of 144). An earlier `claude` reading that also lacked
  `python3-config` and `python-config` came from a rehash under uutils `sort`, so it
  measured the defect, not pyenv's own exclusions. If a future pyenv release does skip a
  name on purpose, add it by name, with the measurement, never as a pattern.
- **Seam:** `_OVERRIDE_PYENV_ROOT`. The real `~/.pyenv` exists on every development
  machine, so the check could not be tested without one.

### Part 3: provision the missing tools

**3a. cargo plugins, both platforms.**

- Add `CARGO_TOOLS=( "cargo-audit@0.22.1" … )` to `lib/constants.sh`: the ten rows from
  the table above, alphabetical.
- Add `install_cargo_tools` to `lib/developer.sh`:
  - It returns 0 immediately when `HAS_RUST` is unset.
  - It resolves `cargo` as `${HOME}/.cargo/bin/cargo`, falling back to `command -v cargo`.
    The reason is the same as `_install_ubuntu_rust`'s rustup resolution: `~/.cargo/bin`
    reaches `PATH` only through interactive rc files.
  - It reads `cargo install --list` once. For each pin, it runs `cargo install --locked
<name>@<version>` only when the list lacks that exact `name vversion:` line. A matching
    version is skipped, and a different version is replaced, which is what `cargo install`
    does without `--force`.
  - On Linux, `cargo-tarpaulin` builds with `RUSTFLAGS="-C link-args=-Wl,-rpath,${_brew_lib}"`,
    where `_brew_lib` is `$(brew --prefix)/lib`, resolved once. No other crate gets the flag.
  - The return is tri-state, mirroring `_install_ubuntu_brew_packages`: 0 clean, 2 when some
    crates failed (named on stderr), 1 when `cargo` cannot be resolved at all. One crate
    that fails to compile against a newer toolchain must not abort a bootstrap.
- Call it from `run_setup_or_developer` after the platform package installs. It is advisory
  in the same shape as `install_aws_tools`:
  `install_cargo_tools || log_warn "cargo tools incomplete — see above"`.
- **Not added to `-t update`.** The versions are pins, so bumping one is a `lib/constants.sh`
  edit. Adding to `update` would recompile ten crates weekly to confirm nothing changed.

**3b. `zig` on Linux.** Add `zig` to the `_install_ubuntu_brew_packages` formula loop. On
2026-09-17, `brew install zig` on `claude` installed 0.16.0, the same version as the Studio.

**3c. `tflint` on Linux.**

- Add `_install_ubuntu_tflint` to `lib/linux_ubuntu.sh`, gated on `HAS_DEVTOOLS` and called
  beside the OpenTofu block.
- Pin `TFLINT_VER="0.61.0"` in `lib/constants.sh`, with
  `TFLINT_SHA256_AMD64="ca4e4e8cb7cc3436f2b6979e9c4fd4e2623a66fcca1ad1fe12f8669967636ae2"` and
  `TFLINT_SHA256_ARM64="999c25cfdb5208fe1133dec6b219e666a39fc2a7a0786a781dc9924ea5945ebf"`.
  Both come from the release's `checksums.txt`, fetched 2026-09-17.
- It skips when `tflint --version` already reports `TFLINT_VER`.
- Otherwise it downloads `tflint_linux_${_LINUX_ARCH}.zip` with `curl -fsSL`, verifies it
  with `sha256sum -c`, extracts it, and installs with `sudo install -m 0755` to
  `/usr/local/bin/tflint`.
- It returns 1 on a download or checksum failure: a failed checksum must never install
  anything.
- On 2026-09-17 the amd64 build installed by exactly this route on `claude` was
  byte-identical (sha256 `51ade70d…8a1b`) to `workstation`'s hand-installed
  `/usr/local/bin/tflint`.
- Seams: `_TFLINT_URL`, `_TFLINT_SHA256` and `_TFLINT_BIN_DIR`. They follow the
  `_RUSTUP_INIT_*` pattern: the digest is exposed rather than `sha256sum` being mocked, so
  the real check runs in tests.

### Part 4: `pwsh` installs on a box whose first attempt failed

Rewrite the guard in `_install_ubuntu_powershell`:

1. If `command -v pwsh` resolves, print `pwsh is installed` and return 0.
2. Otherwise, always download the Microsoft config `.deb` for the resolved release
   (`24.04` under `RESOLUTE`, as today) and run `dpkg -i`. Re-running `dpkg -i` on a newer
   config package replaces `microsoft-prod.list`, and that replacement is what repairs a
   stale `resolute` list. The existing `~/software_downloads` path is overwritten.
3. Run `apt update`, then `apt install powershell -y`, and check each exit status.
4. On any failure, `log_warn` with the failing step and return 0. `install_ubuntu_packages`
   calls this function with `|| return 1` as its second step, so a hard failure here would
   abort the whole bootstrap over one upstream repository. Part 5 makes the gap visible
   instead.

**Accepted cost, measured.** Replacing the `26.04` Microsoft config with `24.04` repoints
anything drawn from `microsoft-prod.list` to the noble repository. On `claude` on
2026-09-17, four list files name `packages.microsoft.com`: `microsoft-prod.list`,
azure-cli's own `archive_uri-…-resolute.list`, and two `microsoft-edge` files. The installed
Microsoft-origin packages resolve elsewhere: `azure-cli` comes from its own list, and the
whole `dotnet-*-10.0` family comes from Ubuntu's `resolute-updates`. So nothing installed
today depends on `microsoft-prod.list`. The plan re-checks this with `apt-cache policy` on
the day of rollout.

### Part 5: `doctor` reports the dev tools

Extend `_doctor_check_tools` with a gated devtools list. The existing arms FAIL on a missing
core tool; these WARN, because each install above is advisory:

- `HAS_DEVTOOLS`: `pwsh`, `tflint`, `zig`.
- `HAS_RUST`: each `CARGO_TOOLS` entry, checked against `cargo install --list` so a wrong
  _version_ is reported and not only absence.

This is the consumer for Part 3's and Part 4's advisory failures. Without it, a
`log_warn` scrolls past during a provision and nothing records it afterwards.

## Verification

End-to-end, on the real hosts after merge:

1. On `claude`:
   - `zsh +Z -l -i -c 'sleep 1'`; `test -e ~/.pyenv/shims/pytest`. Expected: present,
     where the same sequence reports absent today.
   - `make test` in a clone of math `fib`. Expected: rc 0, where today it is rc 2 with
     `pytest: No such file`.
2. `setup_env.sh -t doctor` on `claude`:
   - The new pyenv-shims arm PASSes, naming a non-zero count.
   - The devtools arms PASS for `pwsh`, `tflint`, `zig` and all ten crates.
3. Re-run the doctor arm after deleting the `pytest` shim by hand. Expected: FAIL naming
   `pytest`. This is the positive control that the arm can fail, since it would otherwise
   only ever have been observed passing.
4. `setup_env.sh -t developer` on `claude`, which already has every tool. Expected: no
   `cargo install` compiles anything, and `tflint` and `pwsh` report installed. This is the
   idempotency check.
5. On `workstation`: `setup_env.sh -t doctor`. Expected: the Ubuntu 24.04 `.zprofile`
   prepend is inert because the directory is absent, and nothing regresses.

In the suite:

- Every new function gets tests for both branches of each guard, its error paths, and
  idempotency, per `tdd.md`.
- The `sha256sum` mismatch test asserts that nothing was installed, not merely that the
  function returned 1.
- The shim arm has a test in which the fixture's `versions/ansible/bin` is empty. It must
  not PASS with `0 of 0`: a check over an empty set must say it checked nothing.

## Out of scope

- `gitleaks`, `cosign` and `etch`: absent on the Studio as well, so `claude` is at parity.
- `terraform` and `tfsec`: no gate in terraform_ansible invokes them. Its Makefiles use
  `tofu`.
- The Mac cargo plugins' _existing_ hand installs. `install_cargo_tools` adopts them without
  recompiling, because their versions match the pins.
- `USER.md`'s session-placement text, which still names the Studio and `workstation`. That
  is an ai-config docs edit and ships separately.
