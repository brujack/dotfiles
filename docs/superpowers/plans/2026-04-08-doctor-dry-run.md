# Doctor Mode and Dry-Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `-t doctor` (print detected environment state without side effects) and `--dry-run` (log mutating symlink/mkdir operations instead of executing them).

**Architecture:** Add `run_cmd()` wrapper to `lib/helpers.sh`; update `safe_link()` to use it; add `DOCTOR` as a valid `-t` type; add `--dry-run` long-option pre-processing in `process_args()`; add `run_doctor()` function; dispatch `DOCTOR` from `setup_env.sh` (or `lib/workflows.sh` if PR A has already landed).

**Tech Stack:** Bash, BATS

---

## File Map

| Action | File |
|---|---|
| Modify | `lib/helpers.sh` |
| Modify | `setup_env.sh` (or `lib/workflows.sh` if workflows extraction is done) |
| Modify | `tests/setup_env/unit.bats` |

---

### Task 1: Add `run_cmd()` and update `safe_link()`

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing tests**

Add to the end of `tests/setup_env/unit.bats`:

```bash
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
  local tmpfile="${TMPDIR_TEST}/should_not_exist"
  run run_cmd touch "${tmpfile}"
  unset DRY_RUN
  [ ! -f "${tmpfile}" ]
}

# ── safe_link dry-run ─────────────────────────────────────────────────────────

@test "safe_link does not create symlink when DRY_RUN is set" {
  export DRY_RUN=1
  local src="${TMPDIR_TEST}/src_file"
  local dest="${TMPDIR_TEST}/dest_link"
  touch "${src}"
  safe_link "${src}" "${dest}"
  unset DRY_RUN
  [ ! -L "${dest}" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit 2>&1 | grep -E "(run_cmd|safe_link dry)"
```

Expected: FAIL (run_cmd not found)

- [ ] **Step 3: Add `run_cmd()` to `lib/helpers.sh`**

Add after the logging helpers block (after `log_error`), before the symlink helpers:

```bash
# ── command wrapper ───────────────────────────────────────────────────────────
run_cmd() {
  if [[ -n ${DRY_RUN:-} ]]; then
    printf "[DRY RUN] %s\n" "$*"
  else
    "$@"
  fi
}
```

- [ ] **Step 4: Update `safe_link()` in `lib/helpers.sh`**

Replace the existing `safe_link()` function with:

```bash
safe_link() {
  local src="$1" dest="$2"
  if [[ -L "${dest}" ]]; then
    return 0
  fi
  if [[ -e "${dest}" ]]; then
    log_warn "Backing up existing file: ${dest} → ${dest}.bak"
    run_cmd mv "${dest}" "${dest}.bak"
  fi
  run_cmd ln -s "${src}" "${dest}"
  log_info "Linked ${dest} → ${src}"
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test-unit 2>&1 | tail -20
```

Expected: all new tests pass; all existing tests pass.

- [ ] **Step 6: Lint**

```bash
make lint
```

Expected: exit 0

- [ ] **Step 7: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add run_cmd() wrapper and update safe_link() for dry-run support

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Add `--dry-run` parsing and `DOCTOR` type to `process_args()`

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── process_args: doctor ──────────────────────────────────────────────────────

@test "process_args sets DOCTOR for -t doctor" {
  process_args -t doctor
  [ "${DOCTOR}" -eq 1 ]
}

# ── process_args: --dry-run ───────────────────────────────────────────────────

@test "process_args sets DRY_RUN for --dry-run flag" {
  process_args --dry-run -t setup_user
  [ "${DRY_RUN}" -eq 1 ]
}

@test "process_args still sets SETUP_USER when --dry-run is combined" {
  process_args --dry-run -t setup_user
  [ "${SETUP_USER}" -eq 1 ]
}
```

Note: `process_args` uses `readonly` internally. Each test runs in a subshell via `run`, so `readonly` vars do not leak between tests. However, tests that call `process_args` directly (not via `run`) will have readonly conflicts on re-call within the same shell. Use `run process_args ...` in these tests to isolate:

```bash
@test "process_args sets DOCTOR for -t doctor" {
  run bash -c "
    source '${REPO_ROOT}/setup_env.sh'
    process_args -t doctor
    [[ \${DOCTOR} -eq 1 ]]
  "
  [ "$status" -eq 0 ]
}

@test "process_args sets DRY_RUN for --dry-run flag" {
  run bash -c "
    source '${REPO_ROOT}/setup_env.sh'
    process_args --dry-run -t setup_user
    [[ \${DRY_RUN} -eq 1 ]]
  "
  [ "$status" -eq 0 ]
}

@test "process_args sets SETUP_USER when combined with --dry-run" {
  run bash -c "
    source '${REPO_ROOT}/setup_env.sh'
    process_args --dry-run -t setup_user
    [[ \${SETUP_USER} -eq 1 ]]
  "
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit 2>&1 | grep -E "(DOCTOR|DRY_RUN)"
```

Expected: FAIL

- [ ] **Step 3: Update `process_args()` in `lib/helpers.sh`**

Replace the existing `process_args()` function with:

```bash
process_args() {
  # Pre-process long options before getopts (getopts only handles short options)
  for _arg in "$@"; do
    [[ "${_arg}" == "--dry-run" ]] && readonly DRY_RUN=1
  done

  local arg OPTARG
  while getopts ":ht:w" arg; do
    # shellcheck disable=SC2317 # exit after usage() is intentional redundancy
    case ${arg} in
      t)
        # shellcheck disable=SC2317 # exit after usage() is intentional redundancy
        case ${OPTARG} in
          setup_user) readonly SETUP_USER=1 ;;
          setup)      readonly SETUP=1 ;;
          developer)  readonly DEVELOPER=1 ;;
          ansible)    readonly ANSIBLE=1 ;;
          update)     readonly UPDATE=1 ;;
          doctor)     readonly DOCTOR=1 ;;
          *) echo "Invalid option for -t"; usage; exit 1 ;;
        esac
        ;;
      w) readonly WORK=1 ;;
      h | *) usage; exit 0 ;;
    esac
  done
}
```

- [ ] **Step 4: Update `usage()` in `lib/helpers.sh`**

Replace the existing `usage()` function with:

```bash
usage() {
  cat << EOF
Usage: $0 -t <type> [--dry-run] [-w]
Types:
  setup_user : Sets up a basic user environment for the current user
  setup      : Runs a full machine and developer setup
  developer  : Runs a developer setup with packages and python virtual environment for running ansible
  ansible    : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  update     : Does a system update of packages including brew packages
  doctor     : Prints detected OS, profile, capabilities, and key paths (no side effects)
Options:
  --dry-run  : Log mutating operations (symlinks, installs, mkdir) without executing them
  -w         : Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
EOF
  exit 0
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test-unit 2>&1 | tail -20
```

Expected: all new and existing tests pass.

- [ ] **Step 6: Lint**

```bash
make lint
```

Expected: exit 0

- [ ] **Step 7: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add --dry-run flag and -t doctor type to process_args

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add `run_doctor()` and dispatch from `setup_env.sh`

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `setup_env.sh` (or `lib/workflows.sh` if PR A is merged)
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing test**

Add to `tests/setup_env/unit.bats`:

```bash
# ── run_doctor ────────────────────────────────────────────────────────────────

@test "run_doctor prints Doctor Report header" {
  run run_doctor
  [ "$status" -eq 0 ]
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit 2>&1 | grep "run_doctor"
```

Expected: FAIL (run_doctor not found)

- [ ] **Step 3: Add `run_doctor()` to `lib/helpers.sh`**

Add after the `usage()` function, before `process_args()`:

```bash
run_doctor() {
  printf "=== Doctor Report ===\n"
  printf "\nOS Detection:\n"
  printf "  MACOS=%s  LINUX=%s\n" "${MACOS:-<unset>}" "${LINUX:-<unset>}"
  printf "  UBUNTU=%s  REDHAT=%s  FEDORA=%s  CENTOS=%s\n" \
    "${UBUNTU:-<unset>}" "${REDHAT:-<unset>}" "${FEDORA:-<unset>}" "${CENTOS:-<unset>}"
  printf "  FOCAL=%s  JAMMY=%s  NOBLE=%s\n" \
    "${FOCAL:-<unset>}" "${JAMMY:-<unset>}" "${NOBLE:-<unset>}"
  printf "\nProfile:\n"
  printf "  PROFILE=%s\n" "${PROFILE:-unknown}"
  printf "\nCapabilities:\n"
  printf "  HAS_GUI=%s\n"      "${HAS_GUI:-<unset>}"
  printf "  HAS_DEVTOOLS=%s\n" "${HAS_DEVTOOLS:-<unset>}"
  printf "  HAS_AWS=%s\n"      "${HAS_AWS:-<unset>}"
  printf "  HAS_K8S=%s\n"      "${HAS_K8S:-<unset>}"
  printf "  HAS_DOCKER=%s\n"   "${HAS_DOCKER:-<unset>}"
  printf "  HAS_RUST=%s\n"     "${HAS_RUST:-<unset>}"
  printf "  HAS_SNAP=%s\n"     "${HAS_SNAP:-<unset>}"
  printf "  HAS_PRINTING=%s\n" "${HAS_PRINTING:-<unset>}"
  printf "\nKey Paths:\n"
  printf "  HOME=%s\n"              "${HOME}"
  printf "  PERSONAL_GITREPOS=%s\n" "${PERSONAL_GITREPOS:-<unset>}"
  printf "  DOTFILES=%s\n"          "${DOTFILES:-<unset>}"
  printf "  BREWFILE_LOC=%s\n"      "${BREWFILE_LOC:-<unset>}"
  printf "  CHRUBY_LOC=%s\n"        "${CHRUBY_LOC:-<unset>}"
}
```

- [ ] **Step 4: Add doctor dispatch to `setup_env.sh`**

In `setup_env.sh`, after `detect_env` and before the workflow dispatch calls, add:

```bash
[[ -n ${DOCTOR:-} ]] && { run_doctor; exit 0; }
```

If PR A (workflows extraction) has been merged, this line goes in `lib/workflows.sh` just before the other dispatch lines. If not, add it to `setup_env.sh` just after `detect_env`.

- [ ] **Step 5: Run full test suite**

```bash
make test
```

Expected: exit 0

- [ ] **Step 6: Commit**

```bash
git add lib/helpers.sh setup_env.sh tests/setup_env/unit.bats
git commit -m "feat: add run_doctor() function and dispatch -t doctor from setup_env.sh

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Update `CLAUDE.md`

- [ ] **Step 1: Update `CLAUDE.md` Entry Points table**

Add `doctor` to the `-t` types table:

```markdown
| `doctor` | Print OS, profile, capabilities, and key paths (no side effects) |
```

Add `--dry-run` to the table as an option:

```markdown
**Options:**
- `--dry-run` — log mutating operations (symlinks, installs, mkdir) without executing
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add doctor and dry-run to CLAUDE.md entry points

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
