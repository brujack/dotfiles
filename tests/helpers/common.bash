#!/usr/bin/env bash
# Shared BATS test helpers

# Absolute path to repo root (two levels up from tests/helpers/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# A git hook exports GIT_DIR (and from a worktree GIT_INDEX_FILE), and git -C
# does not override it, so a fixture's git init/config/commit would land in
# whatever repo the caller came from. Measured 2026-10-03: whats-new.bats,
# git_hooks.bats, git_sync.bats and workflows.bats wrote commits and a
# user.name into a decoy repo named by an exported GIT_DIR.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

# Prepend tests/mocks/ to PATH so mock executables shadow real ones
load_mocks() {
  # _ai_config_tracked_items needs a git that really answers ls-files, but
  # tests/mocks/git answers it with rc 0 and empty output. Resolve the real git
  # with tests/mocks removed from PATH, before the prepend at the end of this
  # function.
  local _clean_path _real_git _m="${REPO_ROOT}/tests/mocks" _p=":${PATH}:"
  while [[ ${_p} == *":${_m}:"* ]]; do _p="${_p//:"${_m}":/:}"; done
  _p="${_p#:}"; _clean_path="${_p%:}"
  _real_git="$(PATH="${_clean_path}" command -v git)"
  if [[ -z ${_real_git} ]]; then
    printf 'load_mocks: no real git outside tests/mocks on PATH\n' >&2
    return 1
  fi
  export _AI_CONFIG_GIT="${_real_git}"
  # run_setup_user tests reach setup_dotfile_symlinks, which would otherwise read
  # the real-HOME AI_CONFIG_DIR: missing on CI, the real checkout locally. The
  # tracked fixture costs several git spawns, so build it only for a file that
  # sets LOAD_MOCKS_AI_CONFIG=1 (workflows.bats). Otherwise point at a missing
  # path whose name carries the remedy. It stays missing until setup_ai_config's
  # mock clone mkdirs it as an empty non-repo; listing it still fails, so a
  # forgotten opt-in fails loudly via "Cannot list tracked items in <path>".
  # A test needing another layout
  # overrides it and calls track_ai_config_fixture.
  if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
    if [[ ${LOAD_MOCKS_AI_CONFIG:-} == 1 ]]; then
      export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config-default"
      track_ai_config_fixture "${_OVERRIDE_AI_CONFIG_DIR}" || return 1
    else
      export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config-absent--set-LOAD_MOCKS_AI_CONFIG=1"
    fi
  fi
  # Default pyenv-which to the mock python so run_update's pip section never
  # shells out to real python3/pip on dev machines (real pip is slow, hits the
  # network, and mutates the ansible venv). Individual tests may override it.
  export MOCK_PYENV_WHICH_STDOUT="${REPO_ROOT}/tests/mocks/python"
  # install_cargo_tools resolves _CARGO_BIN before ${HOME}/.cargo/bin/cargo or
  # a PATH cargo, so any suite that calls load_mocks gets the mock here and
  # cannot compile crates for real (tdd.md E2). Residual: a test that
  # deliberately unsets _CARGO_BIN (to exercise the other resolution
  # branches) is on its own to keep ${HOME}/.cargo/bin and PATH cargo-free,
  # and a suite that never calls load_mocks at all (e.g.
  # tests/setup_env/git_sync.bats) gets no protection from this seam.
  export _CARGO_BIN="${REPO_ROOT}/tests/mocks/cargo"
  # Every npm call site resolves through _resolve_npm, which tries the real
  # /home/linuxbrew/.linuxbrew/bin/npm (claude, GitHub's ubuntu image) and
  # /opt/homebrew/bin/npm (macOS) by absolute path, where PATH mocking cannot
  # reach. Default to the recording mock, and point the candidate list at a missing
  # path so a test that unsets _NPM_BIN fails rather than finding a real npm
  # (tdd.md E2).
  export _NPM_BIN="${REPO_ROOT}/tests/mocks/npm"
  export _NPM_FALLBACK_PATHS="${BATS_TEST_TMPDIR:-/nonexistent}/no-npm"
  # run_update's pinned-uv section runs install_uv_pinned on any HAS_DEVTOOLS
  # profile, which a developer shell exports and CI does not. Without this
  # default a full run_update test would download uv for real on a dev box
  # (tdd.md E2). Tests of the production path empty BATS_TEST_TMPDIR for the
  # call and stub the function.
  export _UV_PINNED_INSTALLER="${REPO_ROOT}/tests/stubs/uv-pinned-install-stub"
  # update_rust looks for Homebrew's keg-only rustup ahead of PATH, and the
  # real kegs exist on provisioned machines (/opt/homebrew on a mac,
  # /home/linuxbrew on claude), so without this default an update_rust test
  # would run a real `rustup update` (tdd.md E2). Tests that exercise the keg
  # branch point it at a fixture.
  # The azure-cli migration probes the brew az before removing the apt one.
  # tests/mocks/brew prints no prefix by default, so without this default a
  # probe could resolve to the REAL az on a machine with the apt package
  # (tdd.md E2). The stub is a tracked file; tests of the prefix branches
  # unset the variable.
  export _BREW_AZ_BIN="${REPO_ROOT}/tests/stubs/brew-az"
  # Every CI and fleet machine has a real brew at a default fallback path
  # (claude and GitHub's ubuntu image have /home/linuxbrew/.linuxbrew/bin/brew,
  # often on PATH too; the macOS runner has /opt/homebrew/bin/brew), so without these
  # defaults a run_doctor test would run real brew from a fake HOME (37 MB API
  # cache, possible portable-Ruby pour). Both are exported because
  # tests/setup_env/unit.bats reaches the check through a subprocess
  # (`bash setup_env.sh -t doctor`). The stub logs to
  # ${BATS_TEST_TMPDIR:?}/brew-calls, never a ${MOCK_CALLS_FILE:-/tmp/...}
  # fallback.
  export _BREW_BIN="${REPO_ROOT}/tests/stubs/brew-stub"
  export _BREW_FALLBACK_PATHS="${BATS_TEST_TMPDIR:-/nonexistent}/no-brew"
  # inotify step/doctor seams: the real conf, /proc file and sysctl binary must
  # never be reached (tdd.md E2). Live value starts at 1024 so no apply happens
  # unless a test lowers it.
  if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
    # One mkdir for every directory this function needs (a fork per call
    # adds up across the suite); hashicorp-source and apt-keyrings are the
    # directories _HASHICORP_SOURCE_DIR and _APT_KEYRINGS_DIR name below.
    mkdir -p "${BATS_TEST_TMPDIR}/sysctl.d" "${BATS_TEST_TMPDIR}/run-systemd" \
      "${BATS_TEST_TMPDIR}/tmp-mount.d" "${BATS_TEST_TMPDIR}/hashicorp-source" \
      "${BATS_TEST_TMPDIR}/apt-keyrings" "${BATS_TEST_TMPDIR}/tfenv-links" \
      "${BATS_TEST_TMPDIR}/release-bin"
    export _SYSCTL_CONF="${BATS_TEST_TMPDIR}/sysctl.d/90-dotfiles-inotify.conf"
    export _INOTIFY_PROC="${BATS_TEST_TMPDIR}/inotify_max_user_instances"
    printf '1024\n' > "${_INOTIFY_PROC}"
    export _SYSTEMD_RUN_DIR="${BATS_TEST_TMPDIR}/run-systemd"
    export _SYSCTL_BIN="${REPO_ROOT}/tests/stubs/sysctl-stub"
  fi
  # kernel keys step/doctor seams: procs are seeded at the floors (2000 / 500000), so
  # nothing is applied unless a test lowers one; confs start absent, so an absent
  # conf is still written (it persists the floor for the next boot).
  if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
    export _KEYS_MAXKEYS_CONF="${BATS_TEST_TMPDIR}/sysctl.d/90-dotfiles-keys-maxkeys.conf"
    export _KEYS_MAXBYTES_CONF="${BATS_TEST_TMPDIR}/sysctl.d/90-dotfiles-keys-maxbytes.conf"
    export _KEYS_MAXKEYS_PROC="${BATS_TEST_TMPDIR}/keys_maxkeys"
    export _KEYS_MAXBYTES_PROC="${BATS_TEST_TMPDIR}/keys_maxbytes"
    printf '2000\n' > "${_KEYS_MAXKEYS_PROC}"
    printf '500000\n' > "${_KEYS_MAXBYTES_PROC}"
    # perf_event_paranoid step/doctor seams: proc seeded at the ceiling (2), conf absent.
    export _PERF_CONF="${BATS_TEST_TMPDIR}/sysctl.d/90-dotfiles-perf.conf"
    export _PERF_PROC="${BATS_TEST_TMPDIR}/perf_event_paranoid"
    printf '2\n' > "${_PERF_PROC}"
  fi
  # tmp_inodes step seams: the real /etc drop-in, systemctl, findmnt and mount must
  # never be reached (tdd.md E2). The stock unit fixture carries systemd's stock line;
  # the systemctl stub prints it as FragmentPath (MOCK_TMP_FRAGMENT="" means no unit),
  # and the findmnt stub reports a live nr_inodes already at the ceiling
  # (MOCK_TMP_LIVE_INODES overrides); MOCK_SYSTEMCTL_RELOAD_EXIT sets daemon-reload's exit. The tracked tests/mocks/mount (first on PATH) records MOUNT CALLED and exits 1: the step
  # must never run it, and a test asserts that.
  if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
    export _TMP_DROPIN="${BATS_TEST_TMPDIR}/tmp-mount.d/override.conf"
    export _TMP_STOCK_UNIT="${BATS_TEST_TMPDIR}/tmp.mount"
    printf '[Mount]\nWhat=tmpfs\nWhere=/tmp\nType=tmpfs\nOptions=mode=1777,strictatime,nosuid,nodev,size=50%%%%,nr_inodes=1m,x-systemd.graceful-option=usrquota\n' > "${_TMP_STOCK_UNIT}"
    export _SYSTEMCTL_BIN="${REPO_ROOT}/tests/stubs/systemctl-stub"
    export _FINDMNT_BIN="${REPO_ROOT}/tests/stubs/findmnt-stub"
  fi
  # install_repo_sessions / _doctor_check_repo_sessions run real systemctl, loginctl
  # and tmux (and `sudo loginctl enable-linger`, which tests/mocks/sudo execs) and read
  # the operator's real session list unless these seams are set. _SYSTEMCTL_BIN is
  # set above whenever BATS_TEST_TMPDIR is (always, under bats); tests/mocks/loginctl records and defaults to Linger=yes
  # (MOCK_LOGINCTL_LINGER), and /usr/bin/false (present on Ubuntu and macOS) is an inert tmux.
  export _LOGINCTL_BIN="${REPO_ROOT}/tests/mocks/loginctl"
  export _TMUX_BIN="/usr/bin/false"
  export _SYSTEMD_USER_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/systemd-user"
  export REPO_SESSIONS_FILE="${BATS_TEST_TMPDIR:-/nonexistent}/repo-sessions-empty.sh"
  # The whats-new scripts open a PR through gh (scripts/digest-publish.sh); unset,
  # a test reaching main would run the real gh pr create against GitHub.
  export _DIGEST_GH_BIN="${REPO_ROOT}/tests/stubs/gh-stub"
  [[ -z "${BATS_TEST_TMPDIR:-}" ]] || : > "${REPO_SESSIONS_FILE}"
  # claude and workstation have a real /sys/module/nvidia/version, so an unset
  # seam would read the live driver version and make results machine-dependent.
  export _NVIDIA_MODULE_VERSION_FILE="${BATS_TEST_TMPDIR:-/nonexistent}/no-nvidia-version"
  # claude and workstation carry a real libcuda.so.1 link, so an unset seam would read it.
  export _NVIDIA_LIBCUDA="${BATS_TEST_TMPDIR:-/nonexistent}/no-libcuda"
  # Linux hosts and CI runners carry a real package database; the stub reports
  # no packages and no conffiles unless a test feeds it (tests/stubs/dpkg-query-stub).
  export _DPKG_QUERY_BIN="${REPO_ROOT}/tests/stubs/dpkg-query-stub"
  export _OVERRIDE_RUSTUP_BREW_KEGS="${BATS_TEST_TMPDIR:-/nonexistent}/no-rustup-keg"
  # _install_ubuntu_hashicorp writes a source file and a keyring through
  # tests/mocks/sudo, which execs real commands; keep both under the test tmpdir
  # (tdd.md E2). The single mkdir above creates both, so a test that reads
  # them before the step runs sees an empty directory, not a missing one.
  export _HASHICORP_SOURCE_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/hashicorp-source"
  export _APT_KEYRINGS_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/apt-keyrings"
  # The tfenv symlinks and the pinned release binaries land in /usr/local/bin by
  # default, through `ln` and `install` (pass-through mocks) or `sudo` (exec-ing).
  # Both seams are honoured only under bats; a CI runner has no real tfenv link
  # there, so an unset seam attempts the write where `claude` skips it.
  export _TFENV_LINK_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/tfenv-links"
  export _RELEASE_BIN_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/release-bin"
  # _install_ubuntu_nvidia reads and replaces these through sudo (`sudo rm -f
  # <keyring>.new`), which the exec-ing mock runs for real; tests of the nvidia
  # step set their own, but the run_* workflow tests in workflows.bats do not.
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR:-/nonexistent}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR:-/nonexistent}/nvidia-container-toolkit.list"
  # The apt source, trusted-key, edge, docker and daemon.json paths are read and
  # removed as root (`sudo rm -f`, `sudo tee`, `sudo -H cat`) through the same
  # exec-ing sudo mock, so an e2e install path would otherwise name the real /etc
  # and /usr/share/keyrings. Each seam is honoured only under bats. Fixture
  # directories are created lazily by the code under test, except where a test
  # reads them first. assert_no_real_root_paths (teardown) enforces all of this.
  # setup_zsh_as_default_shell reads the account's login shell, then runs
  # `sudo -n chsh` and a bare `chsh`. Default to "already /bin/zsh" so a run_*
  # test never reaches either; a test of the change path sets its own value
  # (and _OVERRIDE_ZSH_PATH). strace of workflows.bats showed the sudo mock
  # never execs chsh anyway (`-n` is not dropped, so it exits 0), but that is
  # an accident of the mock, not a guard.
  export _OVERRIDE_CURRENT_LOGIN_SHELL="/bin/zsh"
  export _APT_SOURCES_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/apt-sources"
  export _APT_TRUSTED_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/apt-trusted"
  export _EDGE_SOURCES_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/edge-sources"
  export _EDGE_BOOTSTRAP_KEYRING="${BATS_TEST_TMPDIR:-/nonexistent}/edge-bootstrap.gpg"
  export _DOCKER_KEYRING="${BATS_TEST_TMPDIR:-/nonexistent}/docker/keyrings/docker.asc"
  export _DOCKER_SOURCES_LIST="${BATS_TEST_TMPDIR:-/nonexistent}/docker/sources.list.d/docker.list"
  export _DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR:-/nonexistent}/docker/daemon.json"
  export _OVERRIDE_DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR:-/nonexistent}/docker/daemon.json"
  # Every run_update/run_setup_user test runs under a redirected HOME with no
  # settings file; point the claude plugin manifest reader at a per-test COPY
  # of the fixture under BATS_TEST_TMPDIR, never the tracked file itself.
  # tests/mocks/claude's MOCK_CLAUDE_EDIT_SETTINGS mode appends to whatever
  # this points at, so pointing it at the tracked fixture would let a test
  # dirty the working tree (`git status` showing `M tests/fixtures/...`).
  cp "${REPO_ROOT}/tests/fixtures/claude-settings.json" "${BATS_TEST_TMPDIR}/claude-settings.json"
  export _OVERRIDE_CLAUDE_SETTINGS="${BATS_TEST_TMPDIR}/claude-settings.json"
  # run_update's claude section prunes the real ~/.claude/plugins/installed_plugins.json
  # unless these point elsewhere; the default file does not exist, so a test
  # that does not care sees "no plugins file". Tests needing records write a
  # fixture and repoint _OVERRIDE_CLAUDE_PLUGINS_FILE.
  export _OVERRIDE_CLAUDE_PLUGINS_FILE="${BATS_TEST_TMPDIR:-/nonexistent}/no-such-installed_plugins.json"
  export _OVERRIDE_CLAUDE_PLUGIN_BACKUP_DIR="${BATS_TEST_TMPDIR:-/nonexistent}/plugin-backups"
  # setup_suite exports one MOCK_CALLS_FILE shared by every file of the run. Give
  # the test its own ledger unless the caller already chose one under the test
  # tmpdir, so assert_no_real_root_paths judges this test's calls alone.
  if [[ -n "${BATS_TEST_TMPDIR:-}" && ${MOCK_CALLS_FILE:-} != "${BATS_TEST_TMPDIR}"/* ]]; then
    export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  fi
  # Keep this the last statement: once tests/mocks leads PATH, chmod/cp/ln/mv/
  # tee/rm resolve to logging mocks, which append to MOCK_CALLS_FILE (default
  # /tmp/mock_calls, outside the test tmpdir) when a test has not set it yet.
  export PATH="${REPO_ROOT}/tests/mocks:${PATH}"
}

# Fail when any recorded mock call names a real root-owned path. tests/mocks/sudo
# and the logging tee/rm/mkdir mocks exec real commands, so such a call either
# touched the host or only failed because the user cannot write there; neither
# is acceptable. Point the seam at a fixture under BATS_TEST_TMPDIR instead.
# Scans every ledger the test could have written to: ${MOCK_CALLS_FILE}, the
# per-test ${BATS_TEST_TMPDIR}/mock_calls load_mocks defaults to, and the
# suite-wide ${_SUITE_MOCK_CALLS_FILE} (setup_suite) that a mock writes to when
# MOCK_CALLS_FILE was never repointed. Prints each offending line and returns 1.
# A test that must record a real path on purpose records it in a ledger of its
# own, which none of these name (linux_ubuntu.bats, "inotify_conf_write: seam
# unset ...").
assert_no_real_root_paths() {
  local _ledger _seen=" " _rc=0
  for _ledger in "${MOCK_CALLS_FILE:-}" "${BATS_TEST_TMPDIR:+${BATS_TEST_TMPDIR}/mock_calls}" "${_SUITE_MOCK_CALLS_FILE:-}"; do
    [[ -n ${_ledger} && ${_seen} != *" ${_ledger} "* ]] || continue
    _seen+="${_ledger} "
    _root_paths_in_ledger "${_ledger}" || _rc=1
  done
  return "${_rc}"
}

# _root_paths_in_ledger <file> -- one ledger's scan for assert_no_real_root_paths.
_root_paths_in_ledger() {
  local _calls="$1" _hits
  [[ -f ${_calls} ]] || return 0
  # Allow-list, each entry a read-only probe or an inert argument the code
  # cannot redirect (no seam exists, and none may be added to production code
  # for a test):
  #  - `awk ... /etc/os-release`: read-only OS-name probe (detect_env, helpers).
  #  - `sudo -H <tmp>/software_downloads/awscli/aws/install --install-dir
  #    /usr/local/aws-cli --bin-dir /usr/local/bin`: the installer is a path in
  #    the test HOME that never exists under the mocked unzip, so tests/mocks/sudo
  #    does not exec it; /usr/local/* are flag values, not read or write targets.
  local _allow='^awk -F= /\^NAME/\{print [$]2\} /etc/os-release$|^sudo -H [^ ]+/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin( --update)?$'
  # A prefix is named when a non-path character (or line start) precedes it and
  # a slash, whitespace or line end follows, which covers `--x=/etc/y`, `[/etc/y`,
  # `>/etc/y`, `-a/etc/y` and a bare `/etc` but not `<tmp>/etc/y` or `/etcetera`.
  local _prefix='(^|[^[:alnum:]_.-]|[[:space:]]-[[:alpha:]])(/etc|/usr/local|/usr/share/keyrings|/opt)(/|$|[[:space:]])'
  local _rc
  # `|| _rc=$?` keeps a no-match rc 1 from tripping the errexit bats runs under.
  _rc=0
  _hits="$(command grep -E "${_prefix}" "${_calls}")" || _rc=$?
  # grep rc 1 is "no match" (clean); anything above 1 is a scan failure, which
  # must not read as clean.
  if (( _rc > 1 )); then
    printf 'assert_no_real_root_paths: scanning %s failed (grep rc %d)\n' "${_calls}" "${_rc}" >&2
    return 1
  fi
  (( _rc == 1 )) && return 0
  _rc=0
  _hits="$(command grep -v -E "${_allow}" <<< "${_hits}")" || _rc=$?
  if (( _rc > 1 )); then
    printf 'assert_no_real_root_paths: allow-list filter failed (grep rc %d)\n' "${_rc}" >&2
    return 1
  fi
  (( _rc == 1 )) && return 0
  printf 'mock calls named real root-owned paths (%s):\n%s\n' "${_calls}" "${_hits}" >&2
  return 1
}

# Assert a pattern is ABSENT from a file.
#
# Use this instead of `! grep -q ...`. A bare `!` only fails a bats test while
# it is the last command in the @test body — anywhere else the negation is
# silently ignored and the assertion cannot fail at all (shellcheck SC2314).
# Six assertions in this suite were inert for exactly that reason, each one the
# first of two consecutive negative checks, and each covering the "skips X"
# half of its test's claim. Failure output names what was actually found,
# which a bare `!` never did.
#
# Extra args are passed through to grep, so `refute_grep 'pat' file -E` works.
refute_grep() {
  local _pattern="$1" _file="$2"
  shift 2
  if grep -q "$@" -- "${_pattern}" "${_file}" 2>/dev/null; then
    printf 'expected no match for %s in %s, found:\n%s\n' \
      "${_pattern}" "${_file}" "$(grep "$@" -- "${_pattern}" "${_file}")" >&2
    return 1
  fi
}

# Write a stub for <name> that logs its argv plus the first line it can read
# from stdin, and print the stub's directory so the caller can prepend it to
# PATH. Pair it with a caller-supplied stdin file carrying a sentinel line:
# `stdin=[]` means the command's stdin was redirected away from the caller's,
# `stdin=[<sentinel>]` means it inherited it. The file is regular, so the read
# reaches EOF rather than blocking on an fd that never closes.
stdin_probe_stub_path() {
  local _name="$1" _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/${_name}" << EOF
#!${_bash_bin}
IFS= read -r _line || true
printf '%s %s stdin=[%s]\n' "${_name}" "\$*" "\${_line}" >> "\${MOCK_CALLS_FILE}"
exit 0
EOF
  chmod +x "${_dir}/${_name}"
  printf '%s' "${_dir}"
}

# Write a stub for <name> that records the DEBIAN_FRONTEND its own process
# environment holds, as `frontend: <name> <argv> DEBIAN_FRONTEND=<value>` in
# MOCK_CALLS_FILE (`<unset>` when absent), and print the stub's directory so the
# caller can prepend it to PATH. This asserts on what the child sees, not on the
# text of the sudo line. A misplaced assignment (`DEBIAN_FRONTEND=x sudo cmd`)
# fails because tests/mocks/sudo scrubs the caller's DEBIAN_FRONTEND, as real
# sudo resets the environment; only a value on the sudo command line survives.
frontend_probe_stub_path() {
  local _name="$1" _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/${_name}" << EOF
#!${_bash_bin}
_all="\$*"
printf 'frontend: %s %s DEBIAN_FRONTEND=%s\n' "${_name}" "\${_all//-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold /}" "\${DEBIAN_FRONTEND:-<unset>}" >> "\${MOCK_CALLS_FILE}"
exit 0
EOF
  chmod +x "${_dir}/${_name}"
  printf '%s' "${_dir}"
}

# Like frontend_probe_stub_path, but records ONE line per invocation with every
# argument bracketed ("argv: <name> [a][b][c]"), so a test can assert the exact
# contiguous argument order and count invocations. Prints the stub directory.
argv_probe_stub_path() {
  local _name="$1" _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/${_name}" << EOF
#!${_bash_bin}
printf 'argv: %s %s\n' "${_name}" "\$(printf '[%s]' "\$@")" >> "\${MOCK_CALLS_FILE}"
# Drain a piped stdin as the real command would, or the writer upstream can
# die of SIGPIPE and a PIPESTATUS check reads that as a failure. Never read a
# non-pipe stdin: an inherited socket would block forever.
[[ -p /dev/stdin ]] && cat > /dev/null
exit 0
EOF
  chmod +x "${_dir}/${_name}"
  printf '%s' "${_dir}"
}

# Source setup_env.sh — the sourcing guard prevents main body execution
load_setup_env() {
  source "${REPO_ROOT}/setup_env.sh"
  # shellcheck disable=SC2317 # NOT dead: setup_env.sh's own
  # `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` guard always returns
  # true here (this call is always a `source`), so control returns to this
  # point every time. shellcheck only reports this when it follows
  # setup_env.sh's body (e.g. `shellcheck -x`, or when setup_env.sh is also
  # passed on the command line) — it can't resolve the guard's BASH_SOURCE
  # condition statically, so it treats setup_env.sh's own unconditional
  # trailing `exit 0` as making everything after this `source` unreachable.
  export BATS_VER  # export so mock scripts can reference it
}

# _brewfile_required_taps -- every non-core tap the real Brewfile needs: its
# `tap` lines plus the owner/repo of each tap-qualified brew or cask entry.
_brewfile_required_taps() {
  {
    sed -En 's/^tap "([^"]*)".*/\1/p' "${REPO_ROOT}/Brewfile"
    sed -En 's/^(brew|cask) "([^"/]+\/[^"/]+)\/[^"]*".*/\2/p' "${REPO_ROOT}/Brewfile"
  } | sort -u
}

# _assert_trust_covers_brewfile -- the recorded `brew trust` call names every
# tap _brewfile_required_taps lists, and never the retired go-task/tap.
_assert_trust_covers_brewfile() {
  local _trust _tap
  _trust="$(grep '^brew trust ' "${MOCK_CALLS_FILE}")"
  [[ -n ${_trust} ]]
  [[ "$(_brewfile_required_taps | wc -l)" -gt 0 ]]
  while IFS= read -r _tap; do
    [[ " ${_trust} " == *" ${_tap} "* ]] || { printf 'not trusted: %s\n' "${_tap}" >&2; return 1; }
  done < <(_brewfile_required_taps)
  [[ " ${_trust} " != *" go-task/tap "* ]]
}

# setup_run_update_linux -- environment for run_update tests that exercise the Linux
# package sections (apt, snap, flatpak) against mocks and a scratch HOME-less tree.
setup_run_update_linux() {
  unset MACOS HAS_AWS PYENV_ROOT
  export LINUX=1 UBUNTU=1 NOBLE=1 UPDATE_PKGS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  export _OVERRIDE_PYENV_ROOT="${BATS_TEST_TMPDIR}/pyenv"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  export TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
}

# track_ai_config_fixture <dir> -- make <dir> a git repo whose index holds a
# minimal ai-config layout (.claude/settings.json, .cursor/rules/.gitkeep) plus
# every file already there. Empty directories get a .gitkeep, since git cannot
# track them. No commit: CI has no user.name. Uses the real git load_mocks
# resolved into _AI_CONFIG_GIT.
track_ai_config_fixture() {
  local _dir="$1" _d
  local -a _git=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "${_AI_CONFIG_GIT}" -C "${_dir}")
  mkdir -p "${_dir}/.claude" "${_dir}/.cursor/rules" || return 1
  [[ -e ${_dir}/.claude/settings.json ]] || : > "${_dir}/.claude/settings.json" || return 1
  [[ -e ${_dir}/.cursor/rules/.gitkeep ]] || : > "${_dir}/.cursor/rules/.gitkeep" || return 1
  while IFS= read -r -d '' _d; do
    : > "${_d}/.gitkeep" || return 1
  done < <(find "${_dir}/.claude" "${_dir}/.cursor" -type d -empty -print0)
  "${_git[@]}" init -q || return 1
  "${_git[@]}" add -A || return 1
}

# link_real_tool <target> <link> -- symlink a real binary into a shim directory.
# Plain `ln` resolves to tests/mocks/ln once load_mocks ran, which records its
# argv in MOCK_CALLS_FILE; on a macOS runner the real git, sleep and timeout live
# under /opt/homebrew, so the record would name a real root-owned path and trip
# assert_no_real_root_paths. The absolute /bin/ln skips PATH and the mock; unlike
# `command -p ln` it leaves bash's command hash alone, which would otherwise send
# every later plain `ln` in the test to the real binary and bypass the mock.
link_real_tool() {
  /bin/ln -sf "$1" "$2"
}

# refusing_sudo_path <dirs> -- echo <dirs> with the suite's refusing sudo stub
# (tests/helpers/suite_isolation.bash) first. A test that replaces PATH with
# system directories would otherwise reach the real, passwordless /usr/bin/sudo.
# Fails closed when the stub is missing.
refusing_sudo_path() {
  local _d="${_BATS_NOSUDO_DIR:-}"
  if [[ -z ${_d} || ! -x ${_d}/sudo ]]; then
    printf 'refusing_sudo_path: no refusing sudo stub (suite setup did not run)\n' >&2
    return 1
  fi
  printf '%s:%s' "${_d}" "$1"
}
