#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  TMPDIR_TEST="$(mktemp -d)"
  export HOME="${TMPDIR_TEST}"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  # This file's 38 run_* invocations each call _dotfiles_run_tmpdir_setup once.
  # bats sets BATS_TEST_TMPDIR but leaves TMPDIR at the system temp dir, so
  # without this every invocation leaks a real dotfiles-run.* dir there.
  export TMPDIR="${BATS_TEST_TMPDIR}"
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
  # _aws_key_make_fixture (below) spawns a real gpg-agent/scdaemon bound to
  # each homedir it creates via --quick-generate-key; kill them here rather
  # than leaking orphans across the suite. Mirrors
  # tests/setup_env/developer.bats' teardown for the identical hazard.
  if [[ -f "${BATS_TEST_TMPDIR}/_gpg_homedirs" ]]; then
    while IFS= read -r _gpg_homedir; do
      gpgconf --homedir "${_gpg_homedir}" --kill all >/dev/null 2>&1
    done < "${BATS_TEST_TMPDIR}/_gpg_homedirs"
  fi
}

# Real gpg is needed to read a fixture key's expiry field; tests/mocks/gpg
# (put on PATH by load_mocks in setup() above) prints nothing and would make
# every expiry unparseable. Mirrors the PATH-scrub idiom in
# tests/setup_env/developer.bats' _gpg_only_path.
_aws_key_gpg_only_path() {
  printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//'
}

# Generates a throwaway ASCII-armored public key in $2 with the gpg expire
# spec in $3 ("30d", "10y", ...), homed in $1. No signing needed -- the
# doctor arm only ever reads the key's own expiration field, never verifies
# a signature against it. Caller must already have PATH pointed at real gpg
# via _aws_key_gpg_only_path.
_aws_key_make_fixture() {
  local _homedir="$1" _pubkey="$2" _expire="$3"
  mkdir -p "${_homedir}"
  chmod 700 "${_homedir}"
  printf 'allow-loopback-pinentry\n' > "${_homedir}/gpg-agent.conf"
  printf '%s\n' "${_homedir}" >> "${BATS_TEST_TMPDIR}/_gpg_homedirs"
  gpg --homedir "${_homedir}" --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "Test AWS Key <t@example.com>" default default "${_expire}" \
    >/dev/null 2>&1
  gpg --homedir "${_homedir}" --batch --armor --export "Test AWS Key <t@example.com>" \
    >"${_pubkey}" 2>/dev/null
}

# ── quiet_which ─────────────────────────────────────────────────────────────

@test "setup isolates HOME from the real developer home" {
  [ "${HOME}" = "${TMPDIR_TEST}" ]
}

@test "quiet_which returns 0 for a command that exists" {
  run quiet_which bash
  [ "$status" -eq 0 ]
}

@test "quiet_which returns 1 for a command that does not exist" {
  run quiet_which __no_such_command_xyz__
  [ "$status" -eq 1 ]
}

@test "quiet_which produces no output" {
  run quiet_which bash
  [ -z "$output" ]
}

# ── app_dir_exists ───────────────────────────────────────────────────────────

@test "app_dir_exists returns 0 when directory exists" {
  run app_dir_exists "${TMPDIR_TEST}"
  [ "$status" -eq 0 ]
}

@test "app_dir_exists returns 1 when directory does not exist" {
  run app_dir_exists "${TMPDIR_TEST}/nonexistent"
  [ "$status" -eq 1 ]
}

@test "app_dir_exists handles paths with escaped spaces" {
  local dir_with_space="${TMPDIR_TEST}/my app"
  mkdir -p "${dir_with_space}"
  run app_dir_exists "${TMPDIR_TEST}/my\\ app"
  [ "$status" -eq 0 ]
}

# ── process_args ────────────────────────────────────────────────────────────

@test "process_args sets SETUP_USER for -t setup_user" {
  process_args -t setup_user
  [ "${SETUP_USER}" -eq 1 ]
}

@test "process_args sets SETUP for -t setup" {
  process_args -t setup
  [ "${SETUP}" -eq 1 ]
}

@test "process_args sets DEVELOPER for -t developer" {
  process_args -t developer
  [ "${DEVELOPER}" -eq 1 ]
}

@test "process_args sets ANSIBLE for -t ansible" {
  process_args -t ansible
  [ "${ANSIBLE}" -eq 1 ]
}

@test "process_args sets RECREATE_VENV for -t recreate-venv" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t recreate-venv
    printf '%s' \"\${RECREATE_VENV}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "process_args sets RECREATE_RUBY for -t recreate-ruby" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t recreate-ruby
    printf '%s' \"\${RECREATE_RUBY}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "process_args sets VENV_NAME from --venv-name flag" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args --venv-name myenv -t recreate-venv
    printf '%s' \"\${VENV_NAME}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "myenv" ]
}

@test "process_args leaves VENV_NAME unset when --venv-name absent" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t recreate-venv
    printf '%s' \"\${VENV_NAME:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "process_args exits non-zero when --venv-name has no value" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args --venv-name
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"--venv-name requires"* ]]
}

@test "process_args sets UPDATE for -t update" {
  process_args -t update
  [ "${UPDATE}" -eq 1 ]
}

@test "process_args sets WORK for -w" {
  process_args -t setup -w
  [ "${WORK}" -eq 1 ]
}

# ── directory constants ──────────────────────────────────────────────────────

@test "AI_CONFIG is set to ai-config" {
  [ "${AI_CONFIG}" = "ai-config" ]
}

@test "AI_CONFIG_DIR is PERSONAL_GITREPOS/ai-config" {
  [ "${AI_CONFIG_DIR}" = "${PERSONAL_GITREPOS}/ai-config" ]
}

# ── version constants ────────────────────────────────────────────────────────

@test "BATS_VER is set and non-empty" {
  [ -n "${BATS_VER}" ]
}

@test "GO_VER is set and non-empty" {
  [ -n "${GO_VER}" ]
}

@test "PYTHON_VER is set and non-empty" {
  [ -n "${PYTHON_VER}" ]
}

@test "RUBY_VER is set and non-empty" {
  [ -n "${RUBY_VER}" ]
}

# ── process_args: doctor ──────────────────────────────────────────────────────

@test "process_args sets DOCTOR for -t doctor" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t doctor
    printf '%s' \"\${DOCTOR}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "process_args sets CHECK_VERSIONS for -t check-versions" {
  process_args -t check-versions
  [ "${CHECK_VERSIONS}" -eq 1 ]
}

@test "process_args prints error for invalid -t type" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t bogus
  "
  # usage() calls exit 0, so the process exits 0; the error message is the signal
  [ "$status" -eq 0 ]
  [[ "$output" == *"Invalid option for -t"* ]]
}

@test "process_args -h exits 0 and prints usage" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -h
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── process_args: --dry-run ───────────────────────────────────────────────────

@test "process_args sets DRY_RUN for --dry-run flag" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args --dry-run -t setup_user
    printf '%s' \"\${DRY_RUN}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "process_args sets SETUP_USER when combined with --dry-run" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args --dry-run -t setup_user
    printf '%s' \"\${SETUP_USER}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "TERRAFORM_VER matches semver pattern" {
  [[ "${TERRAFORM_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "BATS_VER matches semver pattern" {
  [[ "${BATS_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ── usage ────────────────────────────────────────────────────────────────────

@test "usage prints help text and exits 0" {
  run usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"setup_user"* ]]
  [[ "$output" == *"setup"* ]]
  [[ "$output" == *"developer"* ]]
  [[ "$output" == *"ansible"* ]]
  [[ "$output" == *"update"* ]]
  [[ "$output" == *"--brew-install"* ]]
  [[ "$output" == *"--mas-install"* ]]
  [[ "$output" == *"recreate-venv"* ]]
  [[ "$output" == *"--venv-name"* ]]
  [[ "$output" == *"recreate-ruby"* ]]
}

# ── prerequisite check ────────────────────────────────────────────────────────

@test "setup_env.sh exits 1 with error when brew is not found" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew not found"* ]]
}

@test "setup_env.sh prereq error message points to platform bootstrap script" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bootstrap_mac.sh"* ]] || [[ "$output" == *"bootstrap_linux.sh"* ]]
}

@test "setup_env.sh --brew-install bypasses brew prereq when brew is missing" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --brew-install
  [ "$status" -eq 0 ]
  [[ "$output" != *"Homebrew not found"* ]]
}

@test "setup_env.sh -t doctor bypasses brew prereq when brew is missing" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" -t doctor
  [[ "$output" != *"Homebrew not found"* ]]
}

@test "setup_env.sh -t check-versions bypasses brew prereq when brew is missing" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" -t check-versions
  [[ "$output" != *"Homebrew not found"* ]]
}

@test "setup_env.sh contains bash version prerequisite check" {
  run grep -q 'BASH_VERSINFO' "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 0 ]
}

@test "setup_env.sh exits 1 with bash version error on macOS" {
  load_mocks
  export _OVERRIDE_BASH_MAJOR=4
  export MOCK_UNAME_S=Darwin
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"bash 5+ required"* ]]
  [[ "$output" == *"bootstrap_mac.sh"* ]]
}

@test "setup_env.sh exits 1 with bash version error on Linux" {
  load_mocks
  export _OVERRIDE_BASH_MAJOR=4
  export MOCK_UNAME_S=Linux
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"bash 5+ required"* ]]
  [[ "$output" == *"bootstrap_linux.sh"* ]]
}

@test "setup_env.sh exits 1 with Homebrew error on macOS" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  export MOCK_UNAME_S=Darwin
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew not found"* ]]
  [[ "$output" == *"bootstrap_mac.sh"* ]]
}

@test "setup_env.sh exits 1 with Homebrew error on Linux" {
  load_mocks
  export MOCK_WHICH_MISSING=brew
  export MOCK_UNAME_S=Linux
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh" --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew not found"* ]]
  [[ "$output" == *"bootstrap_linux.sh"* ]]
}

@test "setup_env.sh calls usage when invoked with no arguments" {
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── lib/ source tests ─────────────────────────────────────────────────────────

@test "lib/constants.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/helpers.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/detect_env.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/detect_env.sh'"
  [ "$status" -eq 0 ]
}

# ── detect_env fail-closed on an unloadable identity table ────────────────────
#
# These two use a fixture copy of lib/detect_env.sh (never the tracked
# config/profiles.sh) because T1 makes the fixture's profiles.sh unreadable to
# reach the failing branch, and chmod 000 on the real tracked file would break
# every subsequent login shell on this machine (.zprofile sources it via
# config/profiles.zsh) -- see plan Global Constraints and spec section 1.

@test "detect_env returns 1 and names the cause when config/profiles.sh cannot be sourced" {
  local fixture="${BATS_TEST_TMPDIR}/fixture"
  mkdir -p "${fixture}/lib" "${fixture}/config"
  cp "${REPO_ROOT}/lib/detect_env.sh" "${fixture}/lib/"
  cp "${REPO_ROOT}/config/profiles.sh" "${fixture}/config/"
  chmod 000 "${fixture}/config/profiles.sh"

  # rc-preserving: $status must report detect_env's own exit code, not the
  # trailing printf's -- so the sentinel is captured and printed, then the
  # captured rc is what the subshell actually exits with.
  run bash -c "source '${fixture}/lib/detect_env.sh'
               detect_env; rc=\$?
               printf 'LOADED=%s\n' \"\${_PROFILES_LOADED:-unset}\"
               exit \$rc"
  chmod 644 "${fixture}/config/profiles.sh"

  # rc must be exactly 1, not merely non-zero: a wrong fixture path makes
  # detect_env an unknown command and yields 127, which would falsely satisfy
  # a bare non-zero check.
  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing to continue"* ]]
  # The sentinel must still read 0 after a failed source -- a mutant that
  # hoists _PROFILES_LOADED=1 above the guard and drops the post-source
  # assignment passes rc-exactly-1 and the stderr check above unchanged,
  # because the mutation never touches the `return 1` path. Only this
  # assertion catches the ordering defect.
  [[ "$output" == *"LOADED=0"* ]]
}

@test "detect_env returns 1 when config/profiles.sh sources cleanly but leaves the identity table incomplete" {
  local fixture="${BATS_TEST_TMPDIR}/incomplete-fixture"
  mkdir -p "${fixture}/lib" "${fixture}/config"
  cp "${REPO_ROOT}/lib/detect_env.sh" "${fixture}/lib/"

  # A profiles.sh whose last statement succeeds but never declares PROFILE_MAP.
  # `source` returns the status of its LAST command, so a bare guard on
  # `source`'s own return value cannot see this: rc is 0, yet the table the
  # caller depends on was never built.
  cat > "${fixture}/config/profiles.sh" <<'EOF'
#!/usr/bin/env bash
declare -A PROFILE_CAPS=([mac_workstation]="devtools")
declare -A PROFILE_LEGACY=([studio]="STUDIO")
true
EOF

  run bash -c "source '${fixture}/lib/detect_env.sh'
               detect_env; rc=\$?
               printf 'LOADED=%s\n' \"\${_PROFILES_LOADED:-unset}\"
               exit \$rc"

  [ "$status" -eq 1 ]
  [[ "$output" == *"identity table is incomplete"* ]]
  [[ "$output" == *"LOADED=0"* ]]
}

# ── setup_env.sh full-invocation fail-closed on an unloadable identity table ──
#
# T3/T4 run a full COPY of setup_env.sh, never the tracked repo -- chmod 000
# on the real config/profiles.sh would break every login shell on this
# machine (.zprofile sources it via config/profiles.zsh). setup_env.sh
# sources every lib/*.sh unconditionally at the top, so the fixture needs
# the whole lib/ directory, not just detect_env.sh as the two tests above.

@test "setup_env.sh -t update aborts before any workflow runs when the identity table did not load" {
  # run_update reaches brew_update then a real 'sudo softwareupdate' before
  # the git sync (lib/workflows.sh:325-334). If PATH ever resolved away from
  # tests/mocks, this test would not merely assert wrongly -- it would
  # perform a real machine update. Refuse rather than risk it.
  [[ "$(command -v brew)" == "${REPO_ROOT}/tests/mocks/brew" ]] \
    || { echo "refusing to run: tests/mocks not on PATH" >&2; return 1; }

  local fixture="${BATS_TEST_TMPDIR}/update-fixture"
  mkdir -p "${fixture}/lib" "${fixture}/config"
  cp "${REPO_ROOT}/setup_env.sh" "${fixture}/"
  cp "${REPO_ROOT}"/lib/*.sh "${fixture}/lib/"
  cp "${REPO_ROOT}/config/profiles.sh" "${fixture}/config/"
  chmod 000 "${fixture}/config/profiles.sh"

  # run_update's only durable side effect reachable this early is its own
  # log file (lib/update_summary.sh:588), appended once at the very end of
  # the workflow. Its absence is evidence the workflow's body never started
  # -- not merely that some later step inside it failed.
  local marker="${TMPDIR_TEST}/.dotfiles-update.log"
  rm -f "${marker}"

  run bash "${fixture}/setup_env.sh" -t update
  chmod 644 "${fixture}/config/profiles.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing to continue"* ]]
  [ ! -f "${marker}" ]
}

@test "setup_env.sh -t doctor continues to run_doctor when the identity table did not load" {
  local fixture="${BATS_TEST_TMPDIR}/doctor-fixture"
  mkdir -p "${fixture}/lib" "${fixture}/config"
  cp "${REPO_ROOT}/setup_env.sh" "${fixture}/"
  cp "${REPO_ROOT}"/lib/*.sh "${fixture}/lib/"
  cp "${REPO_ROOT}/config/profiles.sh" "${fixture}/config/"
  chmod 000 "${fixture}/config/profiles.sh"

  run bash "${fixture}/setup_env.sh" -t doctor
  chmod 644 "${fixture}/config/profiles.sh"

  # Both assertions are required, and the first is the one that makes this
  # test about the carve-out rather than about doctor printing a banner.
  # "=== Checks ===" has two producers: the carve-out let doctor run despite
  # a failed table (intended), or the table loaded fine and doctor ran
  # normally (alternate). Only the chmod 000 above distinguishes them, and
  # nothing here asserted it took effect -- mutation-confirmed: deleting the
  # chmod left this test green. "Refusing to continue" is emitted solely by
  # detect_env's failure branch, so it pins the alternate out.
  [[ "$output" == *"Refusing to continue"* ]]
  [[ "$output" == *"=== Checks ==="* ]]
}

@test "detect_env returns 0 for an unmapped hostname so setup_env does not abort a new machine" {
  # setup_env.sh:61 turned detect_env's exit status into a gate for the first
  # time -- before this branch it was discarded, so nothing depended on it.
  # detect_env's terminal statement is a no-else `if` on MACOS/LINUX, which
  # bash evaluates to 0; the line directly above it,
  # `[[ -n ${legacy} ]] && readonly "${legacy}=1"`, returns 1 whenever the
  # hostname has no PROFILE_LEGACY entry. Swap those two and every unmapped
  # machine's `-t setup` and `-t update` abort at :61 -- an unmapped host is
  # supposed to reach doctor and be told to add a row, not be locked out.
  # Both arms are asserted because the two branches assign CHRUBY_LOC from
  # different sides of the conditional.
  unset "${!HAS_@}" PROFILE

  run bash -c "
    export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
    export MOCK_HOSTNAME_OUTPUT='totally-unmapped-host'
    export MOCK_UNAME_S='Darwin'
    source '${REPO_ROOT}/lib/detect_env.sh'
    detect_env; printf 'rc=%s PROFILE=%s\n' \"\$?\" \"\${PROFILE}\"
  "
  [[ "$output" == *"rc=0"* ]]
  [[ "$output" == *"PROFILE=unknown"* ]]

  run bash -c "
    export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
    export MOCK_HOSTNAME_OUTPUT='totally-unmapped-host'
    export MOCK_UNAME_S='Linux'
    source '${REPO_ROOT}/lib/detect_env.sh'
    detect_env; printf 'rc=%s PROFILE=%s\n' \"\$?\" \"\${PROFILE}\"
  "
  [[ "$output" == *"rc=0"* ]]
  [[ "$output" == *"PROFILE=unknown"* ]]
}

@test "detect_env sets PROFILE, the legacy variable, and _PROFILES_LOADED=1 on success" {
  # Load-bearing, not boilerplate: config/profiles.zsh exports PROFILE, every
  # HAS_* and the legacy identity variable into every child of a login
  # shell. Without this unset, PROFILE=mac_workstation and STUDIO=1 are
  # inherited from the parent on any dev machine and two of the three
  # assertions below pass vacuously regardless of what detect_env does.
  unset "${!HAS_@}" PROFILE STUDIO

  run bash -c "
    export PATH='${REPO_ROOT}/tests/mocks:${PATH}'
    export MOCK_HOSTNAME_OUTPUT='studio'
    export MOCK_UNAME_S='Darwin'
    source '${REPO_ROOT}/lib/detect_env.sh'
    detect_env
    printf 'PROFILE=%s\n' \"\${PROFILE}\"
    printf 'STUDIO=%s\n' \"\${STUDIO}\"
    printf 'LOADED=%s\n' \"\${_PROFILES_LOADED}\"
  "

  [ "$status" -eq 0 ]
  [[ "$output" == *"PROFILE=mac_workstation"* ]]
  [[ "$output" == *"STUDIO=1"* ]]
  [[ "$output" == *"LOADED=1"* ]]
}

@test "lib/macos.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/macos.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/linux_shared.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/linux_shared.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/linux_ubuntu.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/linux_shared.sh'; source '${REPO_ROOT}/lib/linux_ubuntu.sh'"
  [ "$status" -eq 0 ]
}

@test "lib/developer.sh sources without error" {
  run bash -c "source '${REPO_ROOT}/lib/constants.sh'; source '${REPO_ROOT}/lib/helpers.sh'; source '${REPO_ROOT}/lib/developer.sh'"
  [ "$status" -eq 0 ]
}

# ── logging helpers ───────────────────────────────────────────────────────────
@test "log_info output contains [INFO] prefix" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_info 'test message'"
  [[ "${output}" == *"[INFO]"* ]]
}

@test "log_info output contains the message" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_info 'hello world'"
  [[ "${output}" == *"hello world"* ]]
}

@test "log_warn output contains [WARN] prefix" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_warn 'test warning' 2>&1"
  [[ "${output}" == *"[WARN]"* ]]
}

@test "log_error output contains [ERROR] prefix" {
  run bash -c "source '${REPO_ROOT}/lib/helpers.sh'; log_error 'test error' 2>&1"
  [[ "${output}" == *"[ERROR]"* ]]
}

# ── workflows ────────────────────────────────────────────────────────────────

@test "run_setup_user is defined after sourcing setup_env" {
  declare -f run_setup_user &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_setup_or_developer is defined after sourcing setup_env" {
  declare -f run_setup_or_developer &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_developer_or_ansible is defined after sourcing setup_env" {
  declare -f run_developer_or_ansible &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_recreate_venv is defined after sourcing setup_env" {
  declare -f run_recreate_venv &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_recreate_venv calls recreate_python_venv with ansible when VENV_NAME unset" {
  recreate_python_venv() { printf "recreate_python_venv %s\n" "$1"; }
  run run_recreate_venv
  [[ "$output" == *"recreate_python_venv ansible"* ]]
}

@test "run_recreate_venv calls recreate_python_venv with VENV_NAME when set" {
  recreate_python_venv() { printf "recreate_python_venv %s\n" "$1"; }
  # shellcheck disable=SC2034 # read by run_recreate_venv after source; shellcheck cannot see the consumer
  VENV_NAME="myenv"
  run run_recreate_venv
  [[ "$output" == *"recreate_python_venv myenv"* ]]
}

@test "run_recreate_ruby is defined after sourcing setup_env" {
  declare -f run_recreate_ruby &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_recreate_ruby calls recreate_ruby" {
  recreate_ruby() { printf "recreate_ruby called\n"; }
  run run_recreate_ruby
  [[ "$output" == *"recreate_ruby called"* ]]
}

@test "run_recreate_ruby returns non-zero when recreate_ruby fails" {
  recreate_ruby() { return 1; }
  run run_recreate_ruby
  [ "$status" -ne 0 ]
}

@test "recreate_ruby on Linux returns non-zero when install_ruby soft-fails" {
  export LINUX=1; unset MACOS
  export HOME="${BATS_TEST_TMPDIR}/recreate_ruby_fail_home"
  mkdir -p "${HOME}"
  # install_ruby returns 0 without creating the rbenv version dir — simulates rbenv soft-fail
  install_ruby() { return 0; }
  local _mock_bin="${BATS_TEST_TMPDIR}/mock_rbenv_softfail"
  mkdir -p "${_mock_bin}"
  # rbenv init - must emit a valid shell snippet; uninstall/other cmds succeed silently
  printf '#!/usr/bin/env bash\n[[ "$1" == "init" ]] && printf ": \n" || true\n' \
    > "${_mock_bin}/rbenv"
  chmod +x "${_mock_bin}/rbenv"
  export PATH="${_mock_bin}:${PATH}"
  run recreate_ruby
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found after install"* ]]
}

@test "recreate_ruby on Linux returns zero when install_ruby succeeds" {
  export LINUX=1; unset MACOS
  export HOME="${BATS_TEST_TMPDIR}/recreate_ruby_pass_home"
  mkdir -p "${HOME}/.rbenv/versions/${RUBY_VER}"
  # install_ruby returns 0 and the version dir already exists (mock rbenv doesn't uninstall)
  install_ruby() { return 0; }
  local _mock_bin="${BATS_TEST_TMPDIR}/mock_rbenv_pass"
  mkdir -p "${_mock_bin}"
  printf '#!/usr/bin/env bash\n[[ "$1" == "init" ]] && printf ": \n" || true\n' \
    > "${_mock_bin}/rbenv"
  chmod +x "${_mock_bin}/rbenv"
  export PATH="${_mock_bin}:${PATH}"
  run recreate_ruby
  [ "$status" -eq 0 ]
}

@test "run_update is defined after sourcing setup_env" {
  declare -f run_update &>/dev/null
  [ "$?" -eq 0 ]
}

# ── run_cmd ──────────────────────────────────────────────────────────────────

@test "run_cmd executes command when DRY_RUN is unset" {
  unset DRY_RUN
  run run_cmd printf "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "run_cmd prints dry-run message when DRY_RUN is set" {
  export DRY_RUN=1
  run run_cmd ln -s /src /dest
  unset DRY_RUN
  [ "$status" -eq 0 ]
  [[ "$output" == "[DRY RUN]"* ]]
}

@test "run_cmd dry-run does not execute the command" {
  export DRY_RUN=1
  local tmpfile="${BATS_TEST_TMPDIR}/should_not_exist"
  run run_cmd touch "${tmpfile}"
  unset DRY_RUN
  [ ! -f "${tmpfile}" ]
}

# ── safe_link error handling ──────────────────────────────────────────────────

@test "safe_link restores backup when ln fails" {
  export MOCK_LN_EXIT=1
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_file"
  touch "${src}" "${dest}"
  run safe_link "${src}" "${dest}"
  unset MOCK_LN_EXIT
  [ "$status" -ne 0 ]
  [ -f "${dest}" ]
  [ ! -L "${dest}" ]
}

@test "safe_link returns 1 when ln fails with no pre-existing file" {
  export MOCK_LN_EXIT=1
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  run safe_link "${src}" "${dest}"
  unset MOCK_LN_EXIT
  [ "$status" -ne 0 ]
}

# ── process_args double-invocation safety ─────────────────────────────────────

@test "process_args does not crash when called twice with --dry-run" {
  process_args --dry-run -t setup_user
  run process_args --dry-run -t setup_user
  [ "$status" -eq 0 ]
}

@test "process_args does not crash when called twice with --brew-only" {
  process_args -t update --brew-only
  run process_args -t update --brew-only
  [ "$status" -eq 0 ]
}

# ── safe_link dry-run ─────────────────────────────────────────────────────────

@test "safe_link does not create symlink when DRY_RUN is set" {
  export DRY_RUN=1
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  safe_link "${src}" "${dest}"
  unset DRY_RUN
  [ ! -L "${dest}" ]
}

# ── run_doctor ────────────────────────────────────────────────────────────────

@test "run_doctor prints Doctor Report header" {
  run run_doctor
  [[ "$output" == *"Doctor Report"* ]]
}

@test "run_doctor prints PROFILE line" {
  run run_doctor
  [[ "$output" == *"PROFILE="* ]]
}

@test "run_doctor prints HAS_GUI line" {
  run run_doctor
  [[ "$output" == *"HAS_GUI="* ]]
}

@test "run_doctor calls _doctor_check_github_mcp" {
  local _called=0
  _doctor_check_github_mcp() { _called=1; }
  # Stub all other sub-checks to avoid side effects
  _doctor_check_profile()       { :; }
  _doctor_check_symlinks()      { :; }
  _doctor_check_symlink_roots() { :; }
  _doctor_check_tools()         { :; }
  _doctor_check_cred_dirs()     { :; }
  _doctor_check_hooks_path()    { :; }
  _doctor_check_versions()      { :; }
  _doctor_check_aws_key_expiry() { :; }
  run_doctor
  [ "${_called}" -eq 1 ]
}

@test "run_doctor summary includes warnings count" {
  _doctor_check_profile()       { :; }
  _doctor_check_symlinks()      { :; }
  _doctor_check_symlink_roots() { :; }
  _doctor_check_tools()         { :; }
  _doctor_check_cred_dirs()     { :; }
  _doctor_check_hooks_path()    { :; }
  _doctor_check_versions()      { :; }
  _doctor_check_aws_key_expiry() { :; }
  _doctor_check_github_mcp()    { doctor_warn "test" "a warning"; }
  run run_doctor
  [[ "$output" == *"1 warnings"* ]]
}

# ── run_check_versions ────────────────────────────────────────────────────────

@test "run_check_versions exits 0 when all pinned versions match latest" {
  run_check_versions() {
    local _outdated=0
    local _latest _installed
    _latest="${YQ_VER}"
    _installed="${YQ_VER}"
    if [[ "${_installed}" == "${_latest}" ]]; then
      printf "  [OK]      yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
    else
      printf "  [OUTDATED] yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
      _outdated=1
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
}

@test "run_check_versions exits 1 when a pinned version is outdated" {
  run_check_versions() {
    local _outdated=0
    local _latest _installed
    _latest="99.99.99"
    _installed="${YQ_VER}"
    if [[ "${_installed}" == "${_latest}" ]]; then
      printf "  [OK]      yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
    else
      printf "  [OUTDATED] yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
      _outdated=1
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 1 ]
}

@test "run_check_versions soft-fails when curl returns error for one tool" {
  run_check_versions() {
    local _outdated=0
    local _latest
    _latest=""
    if [[ -z "${_latest}" ]]; then
      printf "  [WARN]    yq  could not fetch latest version\n"
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
}

@test "run_check_versions skips tool when not installed" {
  run_check_versions() {
    local _outdated=0
    if ! command -v __no_such_tool_xyz__ &>/dev/null; then
      printf "  [SKIP]    __no_such_tool_xyz__  not installed\n"
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SKIP]"* ]]
}

# ── local overrides ───────────────────────────────────────────────────────────

@test ".gitignore contains config/local.sh" {
  grep -q '^config/local\.sh$' "${REPO_ROOT}/.gitignore"
}

@test "config/local.sh is sourced when present" {
  local local_cfg="${BATS_TEST_TMPDIR}/local.sh"
  printf '#!/usr/bin/env bash\nLOCAL_SENTINEL=42\n' > "${local_cfg}"
  run bash -c "
    _LOCAL_CFG='${local_cfg}'
    [[ -f \"\${_LOCAL_CFG}\" ]] && source \"\${_LOCAL_CFG}\"
    unset _LOCAL_CFG
    [[ \${LOCAL_SENTINEL} -eq 42 ]]
  "
  [ "$status" -eq 0 ]
}

@test "config/local.sh absence does not cause errors" {
  local local_cfg="${BATS_TEST_TMPDIR}/local.sh"
  run bash -c "
    _LOCAL_CFG='${local_cfg}'
    [[ -f \"\${_LOCAL_CFG}\" ]] && source \"\${_LOCAL_CFG}\"
    unset _LOCAL_CFG
  "
  [ "$status" -eq 0 ]
}

# ── _any_update_flag ──────────────────────────────────────────────────────────

@test "_any_update_flag returns 1 when no flags set" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run _any_update_flag
  [ "$status" -eq 1 ]
}

@test "_any_update_flag returns 0 when UPDATE_BREW is set" {
  export UPDATE_BREW=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

@test "_any_update_flag returns 0 when UPDATE_PIP is set" {
  export UPDATE_PIP=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

@test "_any_update_flag returns 0 when multiple flags are set" {
  export UPDATE_PIP=1
  export UPDATE_GEMS=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

# ── process_args granular update flags ───────────────────────────────────────

@test "process_args sets UPDATE_BREW for --brew-only" {
  process_args -t update --brew-only
  [ "${UPDATE_BREW}" -eq 1 ]
}

@test "process_args sets UPDATE_PIP for --pip-only" {
  process_args -t update --pip-only
  [ "${UPDATE_PIP}" -eq 1 ]
}

@test "process_args sets UPDATE_GEMS for --gems-only" {
  process_args -t update --gems-only
  [ "${UPDATE_GEMS}" -eq 1 ]
}

@test "process_args sets UPDATE_MAS for --mas-only" {
  process_args -t update --mas-only
  [ "${UPDATE_MAS}" -eq 1 ]
}

@test "process_args sets UPDATE_CLAUDE for --claude-only" {
  process_args -t update --claude-only
  [ "${UPDATE_CLAUDE}" -eq 1 ]
}

@test "process_args sets multiple UPDATE flags when multiple flags given" {
  process_args -t update --brew-only --pip-only
  [ "${UPDATE_BREW}" -eq 1 ]
  [ "${UPDATE_PIP}" -eq 1 ]
}

@test "process_args sets SETUP_BREW for --brew-install" {
  process_args -t setup --brew-install
  [ "${SETUP_BREW}" -eq 1 ]
}

@test "process_args sets SETUP_MAS for --mas-install" {
  process_args -t setup --mas-install
  [ "${SETUP_MAS}" -eq 1 ]
}

@test "process_args sets both SETUP_BREW and SETUP_MAS when both flags given" {
  process_args -t setup --brew-install --mas-install
  [ "${SETUP_BREW}" -eq 1 ]
  [ "${SETUP_MAS}" -eq 1 ]
}

@test "process_args --update sets UPDATE_VERSIONS" {
  process_args --update -t check-versions
  [[ -n ${UPDATE_VERSIONS:-} ]]
}

# ── run_update flag dispatch ───────────────────────────────────────────────────

@test "run_update with --brew-only calls brew subsystem and skips gems" {
  load_mocks
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  export UPDATE_BREW=1
  unset UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run run_update
  [ "$status" -eq 0 ]
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  ! grep -q "gem update" "${MOCK_CALLS_FILE}"
}

@test "run_update with no flags calls brew and gem subsystems" {
  load_mocks
  export HOME="${TMPDIR_TEST}"
  export _OVERRIDE_AI_CONFIG_DIR="${TMPDIR_TEST}/ai-config"
  mkdir -p "${TMPDIR_TEST}/ai-config"
  setup_ai_config() { true; }
  update_aws_cli() { true; }
  update_rust() { true; }
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run run_update
  [ "$status" -eq 0 ]
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  grep -q "gem update" "${MOCK_CALLS_FILE}"
}

@test "run_update --gems-only: calls gem update and skips brew" {
  export HOME="${TMPDIR_TEST}"
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  export UPDATE_GEMS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run run_update
  [ "$status" -eq 0 ]
  grep -q "gem update" "${MOCK_CALLS_FILE}"
  ! grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_update --mas-only on MACOS: calls mas upgrade and skips brew" {
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  export UPDATE_MAS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_CLAUDE UPDATE_PKGS
  run run_update
  [ "$status" -eq 0 ]
  grep -q "mas upgrade" "${MOCK_CALLS_FILE}"
  ! grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_update --brew-only on LINUX: calls brew update and skips gems" {
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export LINUX=1
  unset MACOS
  export UPDATE_BREW=1
  unset UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run run_update
  [ "$status" -eq 0 ]
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  ! grep -q "gem update" "${MOCK_CALLS_FILE}"
}

@test "run_update --claude-only: calls claude plugins update and skips brew" {
  export HOME="${TMPDIR_TEST}"
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  export UPDATE_CLAUDE=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_PKGS
  run run_update
  [ "$status" -eq 0 ]
  grep -q "claude plugins update" "${MOCK_CALLS_FILE}"
  ! grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_update --pkgs-only on LINUX: calls nala and skips brew and gems" {
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export LINUX=1
  export MOCK_UNAME_S="Linux"
  unset MACOS
  export UPDATE_PKGS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run run_update
  [ "$status" -eq 0 ]
  grep -q "nala" "${MOCK_CALLS_FILE}"
  refute_grep "brew update" "${MOCK_CALLS_FILE}"
  refute_grep "gem update" "${MOCK_CALLS_FILE}"
}

# ── doctor_pass / doctor_fail ─────────────────────────────────────────────────

@test "doctor_pass increments _DOCTOR_PASS" {
  _DOCTOR_PASS=0
  doctor_pass "some check"
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "doctor_pass prints [PASS] and label" {
  _DOCTOR_PASS=0
  run doctor_pass "my label"
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"my label"* ]]
}

@test "doctor_fail increments _DOCTOR_FAIL and sets _DOCTOR_FAILED" {
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  doctor_fail "broken thing" "it is missing"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "doctor_fail prints [FAIL] with label and detail" {
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  run doctor_fail "broken thing" "it is missing"
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"broken thing"* ]]
  [[ "$output" == *"it is missing"* ]]
}

# ── doctor_warn ──────────────────────────────────────────────────────────────

@test "doctor_warn increments _DOCTOR_WARN" {
  _DOCTOR_WARN=0
  doctor_warn "some check" "a warning"
  [ "${_DOCTOR_WARN}" -eq 1 ]
}

@test "doctor_warn does not set _DOCTOR_FAILED" {
  _DOCTOR_FAILED=0
  _DOCTOR_WARN=0
  doctor_warn "some check" "a warning"
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "doctor_warn prints [WARN] with label and detail" {
  _DOCTOR_WARN=0
  run doctor_warn "my label" "my detail"
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"my label"* ]]
  [[ "$output" == *"my detail"* ]]
}

# ── run_doctor exit code ──────────────────────────────────────────────────────

@test "run_doctor exits 0 when _DOCTOR_FAILED is 0" {
  run_doctor() {
    _DOCTOR_PASS=5
    _DOCTOR_FAIL=0
    _DOCTOR_FAILED=0
    [[ ${_DOCTOR_FAILED} -eq 0 ]]
  }
  run run_doctor
  [ "$status" -eq 0 ]
}

@test "run_doctor exits 1 when _DOCTOR_FAILED is 1" {
  run_doctor() {
    _DOCTOR_PASS=3
    _DOCTOR_FAIL=1
    _DOCTOR_FAILED=1
    [[ ${_DOCTOR_FAILED} -eq 0 ]]
  }
  run run_doctor
  [ "$status" -eq 1 ]
}

# ── _doctor_check_profile ─────────────────────────────────────────────────────
#
# load_setup_env() (tests/helpers/common.bash) sources setup_env.sh, whose own
# sourcing guard returns before detect_env runs -- so _PROFILES_LOADED is unset
# in every test in this file unless a test sets it. The three tests below set
# it at function scope (never export it, never call detect_env) because
# detect_env assigns PROFILE unconditionally and would clobber the PROFILE
# fixture these tests control. T5 below is the one test in this file that
# calls the real detect_env, deliberately, for the opposite reason.

@test "_doctor_check_profile passes for a mapped profile" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export PROFILE="mac_workstation"
  _PROFILES_LOADED=1
  _doctor_check_profile
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_profile fails for an unmapped profile and names the hostname" {
  export PROFILE="unknown"
  export MOCK_HOSTNAME_OUTPUT="totally-unmapped-host"
  _PROFILES_LOADED=1
  run _doctor_check_profile
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"totally-unmapped-host"* ]]
  [[ "$output" == *"config/profiles.sh"* ]]
}

@test "run_doctor exit code reflects an unmapped profile" {
  _doctor_check_symlinks()      { :; }
  _doctor_check_symlink_roots() { :; }
  _doctor_check_tools()         { :; }
  _doctor_check_cred_dirs()     { :; }
  _doctor_check_hooks_path()    { :; }
  _doctor_check_versions()      { :; }
  _doctor_check_github_mcp()    { :; }
  export PROFILE="unknown"
  _PROFILES_LOADED=1
  run run_doctor
  [ "$status" -eq 1 ]
}

@test "run_doctor reports the identity table did not load rather than a stale inherited PROFILE" {
  # T5 -- the regression pin. detect_env.sh:31 assigns PROFILE unconditionally
  # on master, so an inherited value never survives a failed table load there.
  # Task 1's early return skips that assignment, so a value config/profiles.zsh
  # exported at login (simulated here by `export PROFILE` before the table
  # ever loads) can survive into doctor's report. This is the one test in the
  # file that drives the sentinel through a REAL detect_env call rather than
  # injecting it -- an injected _PROFILES_LOADED exercises only
  # _doctor_check_profile's branch and is invariant under a sentinel-ordering
  # defect inside detect_env itself.
  local fixture="${BATS_TEST_TMPDIR}/t5-fixture"
  mkdir -p "${fixture}/lib" "${fixture}/config"
  cp "${REPO_ROOT}/setup_env.sh" "${fixture}/"
  cp "${REPO_ROOT}"/lib/*.sh "${fixture}/lib/"
  cp "${REPO_ROOT}/config/profiles.sh" "${fixture}/config/"
  chmod 000 "${fixture}/config/profiles.sh"

  export PROFILE="mac_workstation"
  run bash "${fixture}/setup_env.sh" -t doctor
  chmod 644 "${fixture}/config/profiles.sh"

  # doctor_pass/doctor_fail's printf template puts an ANSI reset escape
  # between "[PASS]"/"[FAIL]" and the label that follows, so a plain
  # substring spanning both never matches -- strip escapes before asserting.
  local stripped
  stripped="$(printf '%s' "$output" | sed -E $'s/\x1b\\[[0-9;]*m//g')"
  [[ "${stripped}" != *"[PASS] PROFILE ("* ]]
  [[ "${stripped}" == *"[FAIL] PROFILE: config/profiles.sh did not load this run"* ]]
}

@test "_doctor_check_profile produces three distinct verdict/message pairs across loaded+mapped, loaded+unmapped, and not-loaded" {
  export PROFILE="mac_workstation"
  _PROFILES_LOADED=1
  run _doctor_check_profile
  local loaded_mapped="$output"

  export PROFILE="unknown"
  export MOCK_HOSTNAME_OUTPUT="totally-unmapped-host"
  _PROFILES_LOADED=1
  run _doctor_check_profile
  local loaded_unmapped="$output"

  export PROFILE="mac_workstation"
  _PROFILES_LOADED=0
  run _doctor_check_profile
  local not_loaded="$output"

  [[ "${loaded_mapped}" != "${loaded_unmapped}" ]]
  [[ "${loaded_mapped}" != "${not_loaded}" ]]
  [[ "${loaded_unmapped}" != "${not_loaded}" ]]

  [[ "${loaded_mapped}" == *"[PASS]"* ]]
  [[ "${loaded_unmapped}" == *"[FAIL]"* ]]
  [[ "${loaded_unmapped}" == *"unmapped hostname"* ]]
  [[ "${not_loaded}" == *"[FAIL]"* ]]
  [[ "${not_loaded}" == *"did not load"* ]]
}

@test "_doctor_check_profile PASSes when the environment supplies _PROFILES_LOADED=1 without detect_env running" {
  # T7 -- negative control. Pins that an environment-supplied sentinel DOES
  # defeat the read, so the reader knows protection comes from detect_env's
  # unconditional _PROFILES_LOADED=0 on entry, not from the variable being
  # non-exported. If this test ever starts failing, the mechanism changed and
  # the comment in lib/detect_env.sh describing it is stale.
  export PROFILE="mac_workstation"
  export _PROFILES_LOADED=1
  run _doctor_check_profile
  # A non-empty [PASS] line, not merely "no FAIL" -- an empty result would
  # satisfy the weaker check. "[PASS]" and "PROFILE (" are separated by an
  # ANSI reset escape in doctor_pass's printf template, so they are asserted
  # separately rather than as one spanning substring.
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"PROFILE (mac_workstation)"* ]]
}

# ── _doctor_check_symlinks ────────────────────────────────────────────────────

@test "_doctor_check_symlinks passes when all symlinks exist and resolve" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  export MACOS=1
  unset LINUX
  mkdir -p "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.config"
  # Create a real file for each expected link target, then symlink it
  local _links=(
    ".zshrc" ".zprofile" ".vimrc" ".tmux.conf" ".gitconfig"
  )
  local _f
  for _f in "${_links[@]}"; do
    touch "${TMPDIR_TEST}/src_${_f}"
    ln -s "${TMPDIR_TEST}/src_${_f}" "${TMPDIR_TEST}/${_f}"
  done
  touch "${TMPDIR_TEST}/src_ssh_config"
  ln -s "${TMPDIR_TEST}/src_ssh_config" "${TMPDIR_TEST}/.ssh/config"
  touch "${TMPDIR_TEST}/src_starship"
  ln -s "${TMPDIR_TEST}/src_starship" "${TMPDIR_TEST}/.config/starship.toml"
  mkdir -p "${TMPDIR_TEST}/src_zshrc_d"
  ln -s "${TMPDIR_TEST}/src_zshrc_d" "${TMPDIR_TEST}/.config/.zshrc.d"
  _doctor_check_symlinks
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_symlinks fails when symlinks are missing" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  export MACOS=1
  unset LINUX
  # Do not create any symlinks
  _doctor_check_symlinks
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "_doctor_check_symlinks fails when symlink is broken" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  export MACOS=1
  unset LINUX
  mkdir -p "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.config"
  # Create broken symlink for .zshrc (target does not exist)
  ln -s "${TMPDIR_TEST}/nonexistent" "${TMPDIR_TEST}/.zshrc"
  _doctor_check_symlinks
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

# ── _doctor_check_tools ───────────────────────────────────────────────────────

@test "_doctor_check_tools passes for a tool that is installed" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export MACOS=1
  unset LINUX
  # Override tool list to just bash — always present
  _doctor_check_tools() {
    printf "\nTools:\n"
    if command -v bash &>/dev/null; then
      doctor_pass "bash"
    else
      doctor_fail "bash" "not found"
    fi
  }
  _doctor_check_tools
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_tools fails for a tool that is missing" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  # Override tool list to a clearly non-existent command
  _doctor_check_tools() {
    printf "\nTools:\n"
    if command -v __no_such_tool_xyz__ &>/dev/null; then
      doctor_pass "__no_such_tool_xyz__"
    else
      doctor_fail "__no_such_tool_xyz__" "not found"
    fi
  }
  _doctor_check_tools
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "_doctor_check_tools passes apt-get when found on Ubuntu" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export LINUX=1; export UBUNTU=1; unset MACOS
  _doctor_check_tools
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_tools fails when apt-get is missing on Ubuntu" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export LINUX=1; export UBUNTU=1; unset MACOS
  local _saved_path="$PATH"
  local _mocks_dir; _mocks_dir="$(cd "${BATS_TEST_DIRNAME}/../mocks" && pwd)"
  local _tmp="${BATS_TEST_TMPDIR}/mocks_no_apt"
  mkdir -p "${_tmp}"
  for f in "${_mocks_dir}/"*; do
    [[ "$(basename "$f")" == "apt-get" ]] && continue
    ln -sf "$f" "${_tmp}/$(basename "$f")"
  done
  export PATH="${_tmp}"
  _doctor_check_tools
  export PATH="${_saved_path}"
  [ "${_DOCTOR_FAILED}" -ge 1 ]
}

@test "_doctor_check_tools real: fails when brew is missing on macOS" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export MACOS=1; unset LINUX UBUNTU
  local _saved_path="$PATH"
  local _mocks_dir; _mocks_dir="$(cd "${BATS_TEST_DIRNAME}/../mocks" && pwd)"
  local _tmp="${BATS_TEST_TMPDIR}/mocks_no_brew"
  mkdir -p "${_tmp}"
  for f in "${_mocks_dir}/"*; do
    [[ "$(basename "$f")" == "brew" ]] && continue
    ln -sf "$f" "${_tmp}/$(basename "$f")"
  done
  export PATH="${_tmp}"
  _doctor_check_tools
  export PATH="${_saved_path}"
  [ "${_DOCTOR_FAILED}" -ge 1 ]
}

# ── _doctor_check_cred_dirs ───────────────────────────────────────────────────

@test "_doctor_check_cred_dirs passes when dir exists with mode 700" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  mkdir -p "${TMPDIR_TEST}/.aws"
  chmod 700 "${TMPDIR_TEST}/.aws"
  # Override to check only .aws so test is isolated from other missing dirs
  _doctor_check_cred_dirs() {
    printf "\nCredential directories:\n"
    local _dir="${HOME}/.aws"
    local _perms
    if [[ ! -d "${_dir}" ]]; then
      # shellcheck disable=SC2088  # display label for the operator, not a path
      doctor_fail "~/.aws" "missing"
      return
    fi
    if [[ "$(uname -s)" == "Darwin" ]]; then
      _perms=$(stat -f '%OLp' "${_dir}")
    else
      _perms=$(stat -c '%a' "${_dir}")
    fi
    if [[ "${_perms}" == "700" ]]; then
      # shellcheck disable=SC2088  # display label, see above
      doctor_pass "~/.aws (700)"
    else
      # shellcheck disable=SC2088  # display label, see above
      doctor_fail "~/.aws" "expected 700, got ${_perms}"
    fi
  }
  _doctor_check_cred_dirs
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_cred_dirs fails when dir is missing" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  # Do not create ~/.aws
  _doctor_check_cred_dirs() {
    printf "\nCredential directories:\n"
    local _dir="${HOME}/.aws"
    if [[ ! -d "${_dir}" ]]; then
      # shellcheck disable=SC2088  # display label for the operator, not a path
      doctor_fail "~/.aws" "missing"
      return
    fi
  }
  _doctor_check_cred_dirs
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "_doctor_check_cred_dirs real: fails when all credential dirs are missing" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export HOME="${TMPDIR_TEST}"
  # No dirs created — all four dirs are absent
  _doctor_check_cred_dirs
  [ "${_DOCTOR_FAIL}" -ge 4 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "_doctor_check_cred_dirs real: passes when all dirs have correct 700 perms" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export HOME="${TMPDIR_TEST}"
  mkdir -p "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.tsh"
  chmod 700 "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.tsh"
  _doctor_check_cred_dirs
  [ "${_DOCTOR_PASS}" -eq 4 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_cred_dirs real: fails when a dir has wrong perms" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export HOME="${TMPDIR_TEST}"
  mkdir -p "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.tsh"
  chmod 700 "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.tsh"
  chmod 755 "${TMPDIR_TEST}/.ssh"
  _doctor_check_cred_dirs
  [ "${_DOCTOR_FAIL}" -ge 1 ]
  [ "${_DOCTOR_PASS}" -ge 3 ]
}

# ── _doctor_check_hooks_path ──────────────────────────────────────────────────

# _doctor_check_hooks_path shells out to real `git config --get`, relying on
# its genuine unset (rc 1) vs set-including-empty (rc 0) semantics. This
# file's setup() calls load_mocks, which prepends tests/mocks/git — a mock
# that always exits 0 regardless of args — ahead of the real binary on PATH.
# That flattens the exact unset/empty distinction these tests exist to check,
# so every test in this section resolves a mock-free PATH first.
_unmocked_path() {
  printf '%s' "${PATH}" | tr ':' '\n' | grep -vxF "${REPO_ROOT}/tests/mocks" | tr '\n' ':' | sed 's/:$//'
}

@test "_doctor_check_hooks_path passes both scopes when neither pins core.hooksPath" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc" _out="${TMPDIR_TEST}/hp_out"
  : > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  # Deliberately NOT `run` here: `run` forks a subshell, so mutations
  # _doctor_check_hooks_path makes to _DOCTOR_PASS would never reach this
  # test's scope. Redirect output to a file instead so both the text and
  # the counter can be asserted on the same invocation.
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" _doctor_check_hooks_path > "${_out}"
  local _rc=$?
  [ "${_rc}" -eq 0 ]
  grep -q "Git hooksPath:" "${_out}"
  grep -q "\[PASS\]" "${_out}"
  # Both scopes (system AND global) must report PASS on the clean path --
  # a mutation that drops one scope from the report loop (e.g. `for _scope
  # in system` instead of `for _scope in system global`) leaves every
  # other assertion in this test passing while silently under-reporting.
  [ "${_DOCTOR_PASS}" -eq 2 ]
}

@test "_doctor_check_hooks_path fails on a global pin and names the --global remedy" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  # doctor_fail's own ANSI reset sits between "[FAIL]" and the label, so a
  # combined "[FAIL] global" pattern never matches -- assert the marker and
  # the label as separate fragments, per the existing convention at
  # "doctor_fail prints [FAIL] with label and detail" above.
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"global: pinned to /tmp/mine"* ]]
  [[ "$output" == *"git config --global --unset core.hooksPath"* ]]
  # the other scope still reports
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"system: unset"* ]]
}

@test "_doctor_check_hooks_path fails on an include-borne pin and names the --file remedy" {
  # Before the --includes read, this shape rendered "[PASS] global: unset"
  # while the pin was live -- doctor's whole job here, inverted.
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc" _inc="${TMPDIR_TEST}/inc.cfg"
  printf '[core]\n\thooksPath = /tmp/via-include\n' > "${_inc}"
  printf '[include]\n\tpath = %s\n' "${_inc}" > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"global: pinned to /tmp/via-include"* ]]
  [[ "$output" == *"git config --file ${_inc} --unset core.hooksPath"* ]]
  [[ "$output" != *"global: unset"* ]]
  # the unpinned scope still reports independently
  [[ "$output" == *"system: unset"* ]]
}

@test "_doctor_check_hooks_path sets _DOCTOR_FAILED on an include-borne pin" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc" _inc="${TMPDIR_TEST}/inc.cfg"
  printf '[core]\n\thooksPath = /tmp/via-include\n' > "${_inc}"
  printf '[include]\n\tpath = %s\n' "${_inc}" > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" _doctor_check_hooks_path > /dev/null
  [ "${_DOCTOR_FAILED}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "_doctor_check_hooks_path sets _DOCTOR_FAILED on a pin" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" _doctor_check_hooks_path > /dev/null
  [ "${_DOCTOR_FAILED}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 1 ]
}

@test "_doctor_check_hooks_path reports both pins without either masking the other" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"
  printf '[core]\n\thooksPath = /etc/hooks\n' > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"global: pinned to /tmp/mine"* ]]
  [[ "$output" == *"system: pinned to /etc/hooks"* ]]
  [[ "$output" != *"[PASS]"* ]]
}

@test "_doctor_check_hooks_path fails on a pin whose directory does not exist" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc"
  printf '[core]\n\thooksPath = /nonexistent/nope\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"global: pinned to /nonexistent/nope"* ]]
}

@test "_doctor_check_hooks_path fails on a scope pinned to an empty value and renders it (empty)" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc"
  printf '[core]\n\thooksPath =\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"global: pinned to (empty)"* ]]
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"system: unset"* ]]
}

@test "_doctor_check_hooks_path renders a whitespace-only hooksPath pin as (empty)" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc"
  printf '[core]\n\thooksPath = " "\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"global: pinned to (empty)"* ]]
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"system: unset"* ]]
}

@test "run_doctor invokes the hooksPath check" {
  local _g="${TMPDIR_TEST}/gc" _s="${TMPDIR_TEST}/sc"
  : > "${_g}"; : > "${_s}"
  PATH="$(_unmocked_path)" GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run run_doctor
  [[ "$output" == *"Git hooksPath:"* ]]
}

# ── _doctor_check_versions ────────────────────────────────────────────────────

@test "_doctor_check_versions passes when installed version matches pinned" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  _doctor_check_versions() {
    printf "\nVersions:\n"
    local _pinned="${PYTHON_VER}"
    local _installed="${PYTHON_VER}"
    if [[ "${_installed}" == "${_pinned}"* ]]; then
      doctor_pass "python3 (${_installed})"
    else
      doctor_fail "python3" "installed ${_installed}, pinned ${_pinned}"
    fi
  }
  _doctor_check_versions
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_versions fails when installed version differs from pinned" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  _doctor_check_versions() {
    printf "\nVersions:\n"
    local _pinned="${PYTHON_VER}"
    local _installed="2.7.0"
    if [[ "${_installed}" == "${_pinned}"* ]]; then
      doctor_pass "python3 (${_installed})"
    else
      doctor_fail "python3" "installed ${_installed}, pinned ${_pinned}"
    fi
  }
  _doctor_check_versions
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "_doctor_check_versions real: warns when tools are not installed" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  local _saved_path="$PATH"
  local _empty="${BATS_TEST_TMPDIR}/empty_tools"
  mkdir -p "${_empty}"
  export PATH="${_empty}"  # no binaries here — command -v go/python3/ruby/zsh all fail
  local _rc=0
  _doctor_check_versions 2>&1 || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_versions real: warns when version output cannot be parsed" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  local _tmp="${BATS_TEST_TMPDIR}/version_tools"
  mkdir -p "${_tmp}"
  # go: returns unparseable output — exercises the empty _installed path
  printf '#!/usr/bin/env bash\nprintf "go: totally unparseable output\n"\n' > "${_tmp}/go"
  chmod +x "${_tmp}/go"
  # python3/ruby/zsh: absent so they take the "not installed" (warn, non-fatal) path
  local _saved_path="$PATH"
  export PATH="${_tmp}"
  local _rc=0
  _doctor_check_versions 2>&1 || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

# ── _doctor_check_symlink_roots ───────────────────────────────────────────────

@test "_doctor_check_symlink_roots passes when dotfiles repo directory exists" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export PERSONAL_GITREPOS="${TMPDIR_TEST}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  _doctor_check_symlink_roots
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_symlink_roots fails when dotfiles repo directory is missing" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export PERSONAL_GITREPOS="${TMPDIR_TEST}/git-repos/personal"
  export DOTFILES="dotfiles"
  # Do not create the directory
  _doctor_check_symlink_roots
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

# ── _doctor_check_aws_key_expiry ──────────────────────────────────────────────

@test "_doctor_check_aws_key_expiry is silent when HAS_AWS is unset (e.g. mac_mini)" {
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_WARN=0
  unset HAS_AWS
  run _doctor_check_aws_key_expiry
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_aws_key_expiry warns on a near-expiry key" {
  export PATH
  PATH="$(_aws_key_gpg_only_path)"
  if ! command -v gpg >/dev/null 2>&1; then
    skip "real gpg not on PATH outside tests/mocks"
  fi
  export HAS_AWS=1
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_WARN=0
  local _homedir="${BATS_TEST_TMPDIR}/near" _pub="${BATS_TEST_TMPDIR}/near.asc"
  _aws_key_make_fixture "${_homedir}" "${_pub}" "30d"
  [ -s "${_pub}" ]
  local _AWS_KEY_PATH="${_pub}"
  run _doctor_check_aws_key_expiry
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"AWS CLI signing key"* ]]
}

@test "_doctor_check_aws_key_expiry does not warn on a far-future key" {
  export PATH
  PATH="$(_aws_key_gpg_only_path)"
  if ! command -v gpg >/dev/null 2>&1; then
    skip "real gpg not on PATH outside tests/mocks"
  fi
  export HAS_AWS=1
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_WARN=0
  local _homedir="${BATS_TEST_TMPDIR}/far" _pub="${BATS_TEST_TMPDIR}/far.asc"
  _aws_key_make_fixture "${_homedir}" "${_pub}" "10y"
  [ -s "${_pub}" ]
  local _AWS_KEY_PATH="${_pub}"
  run _doctor_check_aws_key_expiry
  [[ "$output" != *"WARN"* ]]
  [ "${_DOCTOR_WARN}" -eq 0 ]
}

@test "_doctor_check_aws_key_expiry warns rather than fails on a near-expiry key" {
  export PATH
  PATH="$(_aws_key_gpg_only_path)"
  if ! command -v gpg >/dev/null 2>&1; then
    skip "real gpg not on PATH outside tests/mocks"
  fi
  export HAS_AWS=1
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_WARN=0
  local _homedir="${BATS_TEST_TMPDIR}/near2" _pub="${BATS_TEST_TMPDIR}/near2.asc"
  _aws_key_make_fixture "${_homedir}" "${_pub}" "30d"
  [ -s "${_pub}" ]
  local _AWS_KEY_PATH="${_pub}"
  _doctor_check_aws_key_expiry
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

# ── _doctor_check_github_mcp ─────────────────────────────────────────────────

@test "_doctor_check_github_mcp fails when ~/.claude/mcp.json is missing" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  unset GITHUB_PAT GITHUB_PAT_EXPIRY
  # HOME is BATS_TEST_TMPDIR — no .claude/mcp.json exists
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "_doctor_check_github_mcp fails when mcp.json is a broken symlink" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  unset GITHUB_PAT GITHUB_PAT_EXPIRY
  local _saved_home="${HOME}"
  export HOME="${BATS_TEST_TMPDIR}/symlink_home"
  mkdir -p "${HOME}/.claude"
  ln -s "${HOME}/.claude/nonexistent_target" "${HOME}/.claude/mcp.json"
  _doctor_check_github_mcp
  export HOME="${_saved_home}"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "_doctor_check_github_mcp fails when GITHUB_PAT is unset" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  unset GITHUB_PAT GITHUB_PAT_EXPIRY
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAIL}" -eq 1 ]
}

@test "_doctor_check_github_mcp fails when curl exits 22 (invalid token)" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  unset GITHUB_PAT_EXPIRY
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=22
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAIL}" -eq 1 ]
}

@test "_doctor_check_github_mcp warns when curl exits 28 (timeout)" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  unset GITHUB_PAT_EXPIRY
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=28
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -ge 1 ]
}

@test "_doctor_check_github_mcp warns when curl exits 6 (DNS failure)" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  unset GITHUB_PAT_EXPIRY
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=6
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -ge 1 ]
}

@test "_doctor_check_github_mcp warns for other curl errors" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  unset GITHUB_PAT_EXPIRY
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=7  # CURLE_COULDNT_CONNECT — not 22/28/6, hits the catch-all warn branch
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -ge 1 ]
}

@test "_doctor_check_github_mcp warns when GITHUB_PAT_EXPIRY within 30 days" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=0
  # Set expiry to 5 days from now (within 30-day warning window)
  if [[ -n "${MACOS:-}" ]]; then
    GITHUB_PAT_EXPIRY=$(date -v+5d +%Y-%m-%d)
    export GITHUB_PAT_EXPIRY
  else
    GITHUB_PAT_EXPIRY=$(date -d "+5 days" +%Y-%m-%d)
    export GITHUB_PAT_EXPIRY
  fi
  _doctor_check_github_mcp
  [ "${_DOCTOR_WARN}" -ge 1 ]
}

@test "_doctor_check_github_mcp prints INFO when GITHUB_PAT_EXPIRY not set" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  unset GITHUB_PAT_EXPIRY
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=0
  run _doctor_check_github_mcp
  [[ "$output" == *"GITHUB_PAT_EXPIRY"* ]]
}

@test "_doctor_check_github_mcp passes when all checks pass" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=0
  # Set expiry 90 days out (outside warning window)
  if [[ -n "${MACOS:-}" ]]; then
    GITHUB_PAT_EXPIRY=$(date -v+90d +%Y-%m-%d)
    export GITHUB_PAT_EXPIRY
  else
    GITHUB_PAT_EXPIRY=$(date -d "+90 days" +%Y-%m-%d)
    export GITHUB_PAT_EXPIRY
  fi
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_github_mcp warns when GITHUB_PAT_EXPIRY cannot be parsed" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=0
  export GITHUB_PAT_EXPIRY="not-a-date"
  _doctor_check_github_mcp
  [ "${_DOCTOR_WARN}" -ge 1 ]
}

@test "_doctor_check_github_mcp fails when GITHUB_PAT has expired" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=0
  export GITHUB_PAT_EXPIRY="2020-01-01"
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAILED}" -ge 1 ]
}

# ── _update_record_start legacy-rsync ─────────────────────────────────────────

@test "_update_record_start legacy-rsync case skips via _update_skip when not studio" {
  export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}"
  _is_legacy_sync_host() { return 1; }
  export -f _is_legacy_sync_host
  _update_record_start "legacy-rsync"
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_legacy-rsync")" = "SKIP" ]
}

@test "_update_record_start legacy-rsync case does not skip on studio" {
  export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}"
  _is_legacy_sync_host() { return 0; }
  export -f _is_legacy_sync_host
  _update_record_start "legacy-rsync"
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/status_legacy-rsync" ]
}
