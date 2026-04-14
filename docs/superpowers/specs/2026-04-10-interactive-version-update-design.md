# Interactive Version Update Design

## Context

`run_check_versions` fetches upstream versions from GitHub and prints `[OUTDATED]` for each stale pin, then exits 1. The user must manually edit `lib/constants.sh` to update pins — and also manually update any URL constants that embed the version (e.g. `GO_DOWNLOAD_FILENAME`, `GO_DOWNLOAD_URL`). This is error-prone and tedious.

## Decision

Add `--update` flag to `check-versions`. When passed, each `[OUTDATED]` result triggers an interactive prompt. On `y`, `lib/constants.sh` is updated in-place: the version var is rewritten and any URL constants that embed that version are reconstructed. Non-interactive (no `--update`) behavior is unchanged — CI pipelines are unaffected.

## Consequences

- One command to discover and apply version updates
- URL constants stay in sync automatically
- Existing CI usage of `-t check-versions` continues to work unchanged
- In-place edit of `lib/constants.sh` produces a ready-to-commit diff

---

## Flag and Dispatch

### `lib/helpers.sh` — `process_args()`

Add `--update` to the long-option loop after `--mas-only`:

```bash
--update)       readonly UPDATE_VERSIONS=1 ;;
```

Update `usage()` to document it under the `check-versions` type:

```
check-versions   Compare pinned versions against GitHub latest.
                 --update   prompt to update each outdated pin in constants.sh
```

### `setup_env.sh`

No change needed — `run_check_versions` is already dispatched when `CHECK_VERSIONS` is set.

---

## `run_check_versions` Changes

`_run_cv_check` currently captures output and counts by tag. With `--update`, after printing an `[OUTDATED]` line it calls `_prompt_version_update`.

### New inner helper: `_prompt_version_update()`

```bash
_prompt_version_update() {
  local _tool="$1" _var="$2" _pinned="$3" _latest="$4"
  local _reply
  printf "  Update %s from %s to %s? [y/N] " "${_tool}" "${_pinned}" "${_latest}"
  read -r _reply
  if [[ "${_reply}" =~ ^[Yy]$ ]]; then
    _update_version_pin "${_tool}" "${_var}" "${_pinned}" "${_latest}"
    printf "  Updated %s → %s\n" "${_var}" "${_latest}"
  fi
}
```

### New helper: `_update_version_pin()`

Updates `lib/constants.sh` in-place. Takes tool name, var name, old version, new version.

```bash
_update_version_pin() {
  local _tool="$1" _var="$2" _old="$3" _new="$4"
  local _constants="${BASH_SOURCE[0]%/*}/../lib/constants.sh"
  # Replace the version var
  sed -i.bak "s|^${_var}=\"${_old}\"|${_var}=\"${_new}\"|" "${_constants}"
  # Update any URL vars that embed the old version string
  _update_url_pins "${_tool}" "${_old}" "${_new}" "${_constants}"
  rm -f "${_constants}.bak"
}
```

### URL update logic: `_update_url_pins()`

Each tool maps to zero or more URL-embedding vars in `constants.sh`:

| Tool         | URL vars to update                        |
| ------------ | ----------------------------------------- |
| `go`         | `GO_DOWNLOAD_FILENAME`, `GO_DOWNLOAD_URL` |
| `vagrant`    | _(none — no URL in constants.sh)_         |
| `python3`    | _(none — pyenv handles downloads)_        |
| `ruby`       | _(none — ruby-install handles downloads)_ |
| `zsh`        | _(none)_                                  |
| `yq`         | `YQ_URL`                                  |
| `shellcheck` | _(none — installed via brew/apt)_         |

```bash
_update_url_pins() {
  local _tool="$1" _old="$2" _new="$3" _constants="$4"

  case "${_tool}" in
    go)
      # GO_DOWNLOAD_FILENAME="go1.26.1.linux-amd64.tar.gz"
      # Note: GO_VER is "1.26" but the filename has the full patch version "1.26.1".
      # We read the current filename and do a full-string replacement.
      local _old_filename _new_filename
      _old_filename=$(grep '^GO_DOWNLOAD_FILENAME=' "${_constants}" | cut -d'"' -f2)
      # Replace "go<anything>." prefix up to first non-version char with "go<new>."
      _new_filename=$(printf '%s' "${_old_filename}" | sed "s|^go[0-9][^.]*\.[0-9][^.]*\.[0-9][^.]*\.|go${_new}.|")
      sed -i.bak "s|^GO_DOWNLOAD_FILENAME=\"${_old_filename}\"|GO_DOWNLOAD_FILENAME=\"${_new_filename}\"|" "${_constants}"
      # GO_DOWNLOAD_URL embeds the filename — replace old filename with new filename throughout
      sed -i.bak "s|${_old_filename}|${_new_filename}|g" "${_constants}"
      rm -f "${_constants}.bak"
      ;;
    yq)
      # YQ_URL embeds the version
      sed -i.bak "s|/v${_old}/|/v${_new}/|g" "${_constants}"
      rm -f "${_constants}.bak"
      ;;
  esac
}
```

### Updated `_run_cv_check` inner helper

```bash
_run_cv_check() {
  local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5" _var="$6"
  local _out _latest
  _out=$(_check_one_version "${_tool}" "${_pinned}" "${_repo}" "${_cmd}" "${_regex}" 2>&1)
  printf '%s\n' "${_out}"
  if [[ "${_out}" == *"[SKIP]"* ]];       then _skipped=$(( _skipped + 1 ))
  elif [[ "${_out}" == *"[WARN]"* ]];     then _warned=$(( _warned + 1 ))
  elif [[ "${_out}" == *"[OK]"* ]];       then _ok=$(( _ok + 1 ))
  elif [[ "${_out}" == *"[OUTDATED]"* ]]; then
    _outdated=$(( _outdated + 1 ))
    if [[ -n ${UPDATE_VERSIONS:-} ]]; then
      _latest=$(printf '%s' "${_out}" | grep -oE 'latest=[^ ]+' | cut -d= -f2)
      _prompt_version_update "${_tool}" "${_var}" "${_pinned}" "${_latest}"
    fi
  fi
}
```

Each `_run_cv_check` call gains a sixth arg — the var name in `constants.sh`:

```bash
_run_cv_check "go"         "${GO_VER}"         "golang/go"           "go version"           "[0-9]+\.[0-9]+(\.[0-9]+)?" "GO_VER"
_run_cv_check "python3"    "${PYTHON_VER}"      "python/cpython"      "python3 --version"    "[0-9]+\.[0-9]+\.[0-9]+"    "PYTHON_VER"
_run_cv_check "ruby"       "${RUBY_VER}"        "ruby/ruby"           "ruby --version"       "[0-9]+\.[0-9]+\.[0-9]+"    "RUBY_VER"
_run_cv_check "zsh"        "${ZSH_VER}"         "zsh-users/zsh"       "zsh --version"        "[0-9]+\.[0-9]+(\.[0-9]+)?" "ZSH_VER"
_run_cv_check "yq"         "${YQ_VER}"          "mikefarah/yq"        "yq --version"         "[0-9]+\.[0-9]+\.[0-9]+"    "YQ_VER"
_run_cv_check "shellcheck" "${SHELLCHECK_VER}"  "koalaman/shellcheck" "shellcheck --version" "[0-9]+\.[0-9]+\.[0-9]+"    "SHELLCHECK_VER"
_run_cv_check "vagrant"    "${VAGRANT_VER}"     "hashicorp/vagrant"   "vagrant --version"    "[0-9]+\.[0-9]+\.[0-9]+"    "VAGRANT_VER"
```

---

## Testing

### `tests/setup_env/unit.bats`

- `process_args --update` sets `UPDATE_VERSIONS`
- `process_args check-versions` without `--update` does not set `UPDATE_VERSIONS`

### `tests/setup_env/workflows.bats`

**`_update_version_pin` tests** (use a temp copy of `lib/constants.sh`):

- Updates the named var (e.g. `GO_VER`) from old to new value
- Does not modify other vars
- Removes `.bak` file after update

**`_update_url_pins` tests** (use a temp copy of `lib/constants.sh`):

- Updates `GO_DOWNLOAD_FILENAME` when tool is `go`
- Updates `GO_DOWNLOAD_URL` (embeds filename) when tool is `go`
- Updates `YQ_URL` when tool is `yq`
- Leaves all vars unchanged for tools with no URL vars (vagrant, python3, ruby, zsh, shellcheck)

---

## Related

- `lib/helpers.sh` — `process_args()`, `usage()`
- `lib/workflows.sh` — `run_check_versions`, `_check_one_version`, `_run_cv_check`
- `lib/constants.sh` — updated in-place by `_update_version_pin`
- `tests/setup_env/unit.bats`, `tests/setup_env/workflows.bats`
