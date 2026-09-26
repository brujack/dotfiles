### GPU provisioning as the HAS_* exception (not a capability)

lead: none

- GPU provisioning gates on detected hardware — `_nvidia_gpu_present` matching PCI vendor `10de:` in `lspci -nn` — never a `HAS_*` capability, since `claude` and `workstation` share the `linux_workstation` profile but not a GPU, and WSL2's driver lives Windows-side. Absent `lspci`, default to skip, not attempt.
- Installing the driver does not bind it (nouveau holds the card until reboot), and installing `nvidia-container-toolkit` does not register it with docker — run `nvidia-ctk runtime configure --runtime=docker` after install, and restart docker only when `daemon.json` actually changed, since these boxes run live GitHub runners.
  trigger: editing GPU provisioning | `_install_ubuntu_nvidia`
  covers:
  - a: "Measured on `claude` 2026-09-12 with toolkit 1.20.0 alre"
  - b: "GPU provisioning is the one deliberate exception to that"
  - b: "the systemctl restart docker is conditional on daemon.js"

### zsh -i -c 'exit' after .zshrc changes, and the worktree caveat

lead: none

- After any change to `.zshrc` or `.zshrc.d/`, run `zsh -i -c 'exit'` before committing, to catch a re-source crash before it reaches prod.
- In a worktree that command only proves the main checkout is sane, since `~/.zshrc` symlinks there — source the branch's own files explicitly instead.
  trigger: validating a change | `.zshrc`, `.config/.zshrc.d/`
  covers:
  - b: "After any change to .zshrc or .zshrc.d/ files, run zsh -i"
  - b: "From a worktree, source the branch's own files explicitl"

### $0 resolution in zsh startup files (${0:A:h} pitfall)

lead: none

- `$0` is not a startup file's own path in zsh — its internal startup reader leaves `$0` as the literal `zsh`, so `${0:A:h}` resolves against cwd instead of the file's directory.
- Use `${${(%):-%x}:A:h}` in any file that may be sourced as a startup file — it names the containing file correctly in both actors.
  trigger: resolving a path via `$0` | a zsh startup file
  covers:
  - b: "Use ${${(%):-%x}:A:h} in any file that may be read as a s"

### _UPDATE_SECTION_ORDER coupling

lead: none

- `lib/update_summary.sh`'s `_UPDATE_SECTION_ORDER` array controls which sections print. Add `_update_record_start/end "new-section"` and the array entry together — omitting the entry tracks the section internally but never prints it, with no error.
- Don't audit hardcoded count assertions (`[[ "$output" == *"9 OK"* ]]`) on add/remove — `tests/setup_env/update_summary.bats` seeds sections by name, so an unseeded entry is invisible to the tally by construction.
- The real risk is on **removal**: grep fixtures for a stray reference to the removed name that still seeds it.
  trigger: adding or removing a `run_update` section | `_UPDATE_SECTION_ORDER` in `lib/update_summary.sh`
  covers:
  - a: "Adding _update_record_start/end new-section in run_update"
  - a: "is stale and was measured wrong"
  - a: "the real risk when **removing** a section is a stray refe"
  - b: "this array was named only in the moved lead"

### git-hooks section coupling and _git_hooks_target_dir

lead: none

- The `git-hooks` section carries the same `_UPDATE_SECTION_ORDER` trap as above, one function over — miss the array entry and the section is tracked internally but never printed.
- The sweep's post-condition reads the installed hooks directory, never `scripts/`, so hooks installed by any route (e.g. `ledger init`) still count; only presence and the executable bit are checked, so a stale `cp`-installed hook still passes.
- `install_git_hooks_all_repos` returns 0 clean / 1 hard failure / 2 partial (gaps or a pinned `core.hooksPath`); both `run_update` and `run_setup_user` must branch on all three. `_git_hooks_target_dir` resolves the Makefile target (root, else exactly one `*/Makefile` one level down, else `:ambiguous`/`:unreadable`) rather than assuming root.
  trigger: editing the `git-hooks` section | `_git_hooks_target_dir`
  covers:
  - a: "git-hooks section coupling: same _UPDATE_SECTION_ORDER tr"
  - b: "Both call sites must branch on it: it is install_git_hook"
  - b: "This matters more than a mislabel, because the completen"

### _install_ubuntu_brew_packages tri-state return

lead: none

- `_install_ubuntu_brew_packages` returns 0 clean, 1 hard failure, 2 partial success, with failed packages named on stderr.
- `install_ubuntu_packages` captures that rc rather than using `|| return 1`: only rc 1 aborts, since a bare guard would kill a whole bootstrap over one briefly-unavailable formula, while an unchecked call reports success over packages that never landed.
  trigger: calling | `_install_ubuntu_brew_packages`
  covers:
  - a: "install_ubuntu_packages therefore captures the rc rather "
  - b: "therefore rests on the moved 0/1/2 contract"

### claude plugins install -s user scope flag

lead: none

- `claude plugins install` takes `-s user` and a `plugin@marketplace` id; the flag pins scope (already the CLI's own default) rather than fixing a defect — keep it so a future default change can't silently move installs.
  trigger: changing the plugin install call | `setup_claude_plugins`
  covers:
  - b: "claude plugins install takes -s user and a plugin@market"

### zsh-autosuggestions reported update section

lead: none

- The zsh-autosuggestions guard is `[[ -e ${_zsh_autosug}/.git ]]`, never `git rev-parse --git-dir` — that plumbing command walks upward through parent directories, and `~/.oh-my-zsh` is itself a git checkout, so a non-clone install would silently update oh-my-zsh instead and report a permanent false "no changes".
- Use `-e`, not `-d`: a submodule or linked worktree has `.git` as a file, and `-d` would route that layout to SKIP forever.
  trigger: editing this update section | `lib/workflows.sh`'s zsh-autosuggestions section
  covers:
  - a: "That plumbing command walks upward through parent direct"
  - a: "A future reader will otherwise tighten this to the plumb"
  - b: "-e rather than -d is also deliberate: tightening to -d wo"

### Update summary name column width

lead: none

- The update summary's name-column width is derived, not hardcoded: a test reads the pad width out of `lib/update_summary.sh`'s `printf` format and asserts it stays >= 1 wider than `_UPDATE_SECTION_ORDER`'s longest entry, so a section name of 20+ characters fails the test rather than silently colliding with the reason column.
  trigger: widening a section name | `_UPDATE_SECTION_ORDER`
  covers:
  - a: "The width is not a number to remember and re-check by ha"

### cheat.sh section: both artifacts, both failures FAIL the run

lead: none

- The cheat.sh update section (`lib/workflows.sh`) fetches the binary and the tab-completion file inside one subshell sharing an `_rc`, so either fetch's failure fails the section — it previously ran the completion fetch as a bare statement after the section had already closed, hiding a completion-only failure.
- Progress banners print outside that subshell so they never land in `err_cheat.sh`/`detail_cheat.sh`, which feeds the `tail -10` diagnostic budget.
  trigger: editing this update section | `lib/workflows.sh`'s cheat.sh section
  covers:
  - a: "It previously ran the tab-completion fetch as a bare stat"
  - b: "It is the cheat.sh section, named only in the moved lead"

### .warp/settings.toml Warp-owned symlink and auto_approve_bypasses_command_denylist

lead: none

- `.warp/settings.toml` is Warp-owned and symlinked live (`~/.warp/settings.toml` -> repo); Warp rewrites it on upgrade, so an unexplained diff there is usually a materialized default, not a hand edit.
- `agents.warp_agent.other.auto_approve_bypasses_command_denylist = false` is a deliberate non-default (Warp defaults `true`, which makes `command_denylist` inert under auto-approve). It syncs globally, so a diff flipping it back to `true` is a sync reversion to re-pin, never an upgrade artifact to accept.
  trigger: reviewing a diff | `.warp/settings.toml`
  covers:
  - a: "One value in it is a deliberate non-default, not drift: a"
  - b: "it is .warp/settings.toml, named only in the moved lead"

### Global/system core.hooksPath pin: detection and remedy

lead: none

- `core.hooksPath` set at global/system scope redirects every repo's hooks at once (`git rev-parse --git-path hooks` honors it); empty or whitespace-only counts as a real pin — `git config --get` returns rc 0 with empty stdout and git still disables every hook on the machine.
- Probe with `--includes` (the default `--no-includes` misses a pin reached through an include) and `-z`, consumed via `read -d ''` off a process substitution, never `$(...)`. A key held in an included file needs `git config --file <origin> --unset core.hooksPath`; a scope-level `--unset` there exits 5 and leaves the pin. Output contract is `scope<TAB>remedy<TAB>value`, value last, so a tab in a pinned path can't truncate the remedy.
- `tests/setup_env/git_hooks.bats`'s `setup()` must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, or the suite fails on any machine with a pin — and since `scripts/pre-push` runs `make test`, that developer cannot push.
  trigger: diagnosing dead git hooks, or editing `tests/setup_env/git_hooks.bats` | `_git_hooks_hookspath_offenders`
  covers:
  - a: "An empty or whitespace-only value is a real pin, not an a"
  - a: "The pin probe must read --includes, and the remedy must n"
  - a: "Output contract is `scope<TAB>remedy<TAB>value`"
  - a: "must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`"
  - b: "the value of what? core.hooksPath is introduced only in "

### Homebrew make gnubin prepend (prepend, not append)

lead: none

- The Homebrew `make` gnubin directory must be prepended to `PATH`, never appended (`path+=`) — `.config/.zshrc.d/6_path.zsh`'s existing idiom appends, which would leave `/usr/bin/make` 3.81 ahead and be completely inert.
- Test both Homebrew prefixes for existence (ARM `/opt/homebrew/opt/make/libexec/gnubin`, Intel `/usr/local/opt/make/libexec/gnubin`) rather than calling `brew --prefix`, since `.config/.zshrc.d/6_path.zsh` is what puts `brew` on `PATH`. The linuxbrew coreutils gnubin prepend is gated only on `[[ -d ... ]]`, deliberately not on `RESOLUTE` — the install is release-gated, the `PATH` edit is release-blind.
  trigger: editing the `PATH` prepend | `.config/.zshrc.d/6_path.zsh`
  covers:
  - a: "It must be a prepend, not path+=. Both Homebrew prefixes "
  - b: "It is the gnubin prepend in the moved lead"

### Which make an actor resolves (gnubin/actor table)

lead: none

- Which `make` an actor resolves depends on whether the process sourced `6_path.zsh`: interactive zsh and everything descended from it (tmux, hooks it launches, this harness's own shell) get GNU 4.4.1; cron, launchd, `ssh host '<cmd>'`, and editor-spawned git hooks get `/usr/bin/make` 3.81.
- The split is currently harmless to this repo's gates: `Makefile:1`'s `MAKEFLAGS += --no-print-directory` suppresses on 4.x what 3.81 never printed. Do not reopen this without re-running that comparison (`specs/2026-08-16-system-wide-gnu-make-design.md`, `specs/2026-08-16-hook-make-resolution-design.md`).
  trigger: assuming which `make` resolves | a hook that shells out to `make`
  covers:
  - a: "Because 6_path.zsh is sourced by interactive zsh only, ma"
  - b: "Makefile:1's MAKEFLAGS += --no-print-directory is why; do"

### setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)

lead: none

- `setup_env.sh` gates every workflow on `env which brew`, and `6_path.zsh`'s linuxbrew `PATH` prepend is sourced by interactive zsh only — so no cron job, git hook, CI runner, or agent session can run `setup_env.sh` non-interactively on the Linux workstation; it fails with a misleading "run bootstrap_linux.sh first" even after bootstrap has already run.
- This is the macOS `make`-resolution trap one severity worse: treat a tool path placed in an interactive-only rc file as gating whichever actor sources that file, never as a machine-wide fact. A `PATH` prepend inside a hook shadows `tests/scripts/pre_push.bats`'s own `make` mock (measured: 28 of 36 tests failed) — route any future hook `PATH` edit through `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` instead.
- Workaround for a non-interactive caller: prepend the prefix explicitly rather than re-bootstrapping — `PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}" ./setup_env.sh -t developer`.
  trigger: running it non-interactively on Linux | `setup_env.sh`
  covers:
  - a: "the same defect at two severities"
  - a: "treat a tool path placed in an interactive-only rc file a"
  - b: "A `PATH` prepend inside a hook shadows the test suite's o"
  - b: "Workaround for a non-interactive caller is to prepend the"

### terraform on Linux via tfenv, and the checkout guard

lead: none

- `_install_ubuntu_tfenv` clones `~/.tfenv` if absent, symlinks `tfenv`/`terraform` into `/usr/local/bin` only when neither name already exists as a regular file or a foreign symlink, and installs `TERRAFORM_VER` only when `~/.tfenv/version` is absent — an operator's chosen version is never overwritten.
- The `[[ ! -x "${_root}/bin/tfenv" ]]` guard must run and return before the symlink loop: running the loop first plants two dangling symlinks that the **loop's own** `-L` branch (`[[ -L "${_link}" ]]`, further down) then treats as already repaired on every subsequent run. The remedy for a broken checkout (`rm -rf ${_root}`) belongs in the WARN, not in doctor.
  trigger: editing the tfenv installer | `_install_ubuntu_tfenv`
  covers:
  - a: "It clones ~/.tfenv if absent, symlinks tfenv/terraform in"
  - b: "That ordering is load-bearing: run the loop first and it "

### tflint/tfsec staleness gap; CARGO_TOOLS staleness via crates.io

lead: none

- `tflint`/`tfsec` staleness is not checked by `check-versions` (tracked as a Backlog gap). The eight `CARGO_TOOLS` pins are checked, against crates.io's `max_stable_version`, which needs a `-A "dotfiles check-versions (bjackson@pobox.com)"` header or the request 403s.
  trigger: adding a staleness check | `run_check_versions`
  covers:
  - a: "(none retained; pointer only)"
  - b: "(none listed; verdict complete)"
