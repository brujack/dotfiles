# Design: Doctor Mode and Dry-Run Support

**Date:** 2026-04-08
**Status:** Approved

## Summary

Add two new operational modes to `setup_env.sh`: `-t doctor` (print detected env/profile state without side effects) and `--dry-run` (log mutating operations without executing them). Both improve observability and reduce risk when running setup on unfamiliar machines.

## Motivation

Running `setup_env.sh` on a new machine is a one-shot operation with no preview. If something goes wrong it's hard to diagnose whether the issue is OS detection, profile resolution, or an install path. `doctor` gives instant visibility. `--dry-run` lets you verify what would happen before committing to a full install.

## Changes

### `lib/helpers.sh` — new: `run_cmd()`

A thin wrapper used by all mutating helpers. When `DRY_RUN` is set, it logs the command instead of executing it:

```bash
run_cmd() {
  if [[ -n ${DRY_RUN:-} ]]; then
    printf "[DRY RUN] %s\n" "$*"
  else
    "$@"
  fi
}
```

### `lib/helpers.sh` — update: `safe_link()`

Replace the `ln -s` call with `run_cmd ln -s`. Replace the `mv` (backup) call with `run_cmd mv`:

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

### `lib/helpers.sh` — update: `process_args()`

Add `DOCTOR` as a valid `-t` value. Pre-process `--dry-run` from `$@` before `getopts` (getopts doesn't handle long options):

```bash
process_args() {
  # Pre-process long options
  for _arg in "$@"; do
    [[ "${_arg}" == "--dry-run" ]] && readonly DRY_RUN=1
  done

  local arg OPTARG
  while getopts ":ht:w" arg; do
    case ${arg} in
      t)
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

### `lib/helpers.sh` — update: `usage()`

Add `doctor` and `--dry-run` to the usage text.

### `lib/helpers.sh` — new: `run_doctor()`

Prints detected environment and profile state, with no side effects:

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
  printf "  HOME=%s\n"               "${HOME}"
  printf "  PERSONAL_GITREPOS=%s\n"  "${PERSONAL_GITREPOS:-<unset>}"
  printf "  DOTFILES=%s\n"           "${DOTFILES:-<unset>}"
  printf "  BREWFILE_LOC=%s\n"       "${BREWFILE_LOC:-<unset>}"
  printf "  CURSOR_USER_DIR=%s\n"    "${CURSOR_USER_DIR:-<unset>}"
}
```

### `setup_env.sh` (or `lib/workflows.sh` after PR A)

Add dispatch for `DOCTOR` before other workflow dispatches:

```bash
[[ -n ${DOCTOR:-} ]] && { run_doctor; exit 0; }
```

## Constraints

- `run_doctor` has no side effects — safe to call repeatedly.
- `DRY_RUN` affects only `run_cmd`-wrapped operations. Logging output is always printed.
- `--dry-run` can be combined with any `-t` type; it doesn't need its own `-t` value.
- All existing tests must pass with `DRY_RUN` unset.
