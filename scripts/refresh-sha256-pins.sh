#!/usr/bin/env bash
# Refresh the sha256 pins of kind, yq and shellcheck in lib/constants.sh from the
# digest field of the GitHub releases API, so no release asset is downloaded.
#
# Usage: refresh-sha256-pins.sh [--constants <file>] [--accept-changed] [tool...]
# Exit: 0 written or up to date, 1 failure (target left byte-identical), 2 usage.
#
# Runs as its own process and is never sourced: it sources the target constants
# file exactly once (a second source aborts on a readonly array), then the repo's
# helpers for _github_api_base, _github_auth_header, _sha256_pin_ok and
# _release_asset_url.

_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly _REPO_ROOT

# Temp files this run created; the EXIT trap removes them if a signal or an
# unexpected return skipped the explicit cleanup on the failure paths.
_TMP_FILES=()
_cleanup_tmp() {
  local _f
  for _f in "${_TMP_FILES[@]}"; do
    rm -f "${_f}"
  done
}

_usage() {
  printf "usage: %s [--constants <file>] [--accept-changed] [kind|yq|shellcheck ...]\n" "$(basename "$0")" >&2
}

# Print the API's digest for asset <name> from release JSON file <body>, or nothing.
_digest_from_body() {
  python3 -I -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    for a in data.get("assets", []):
        if a.get("name") == sys.argv[2]:
            print(a.get("digest") or "")
            break
except Exception:
    pass
' "$1" "$2"
}

# _fetch_release <tool> <api-url> <body-file> -- one GET of the release JSON.
_fetch_release() {
  local _tool="$1" _api="$2" _body="$3" _code _rc _hdr
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    _hdr="$(_github_auth_header "${GITHUB_TOKEN}")" || return 1
    _code="$(printf '%s\n' "${_hdr}" | curl -sS --max-time 20 --noproxy 127.0.0.1 -H @- \
      -o "${_body}" -w '%{http_code}' "${_api}")"
    _rc=$?
  else
    _code="$(curl -sS --max-time 20 --noproxy 127.0.0.1 -o "${_body}" -w '%{http_code}' "${_api}")"
    _rc=$?
  fi
  if [[ "${_rc}" -ne 0 ]]; then
    printf "%s: GitHub API request failed (curl rc %s) for %s\n" "${_tool}" "${_rc}" "${_api}" >&2
    return 1
  fi
  if [[ "${_code}" != 200 ]]; then
    printf "%s: GitHub API returned %s for %s" "${_tool}" "${_code}" "${_api}" >&2
    case "${_code}" in
      403 | 429) printf "; set GITHUB_TOKEN (unauthenticated: 60 requests/hour)" >&2 ;;
    esac
    printf "\n" >&2
    return 1
  fi
}

# _resolve_pins <tool> -- appends "tool|arch|VAR|new" lines to _UPDATES for
# every pin and _FOR_VER whose value differs. rc 1 on any failure.
_resolve_pins() {
  local _tool="$1" _up="${1^^}" _ver_var _ver _for_var _for _arch _url _var _old
  local _owner _repo _tag _asset _api _body _raw _hex _first="" _o2 _r2 _t2 _a2
  local _re='^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/]+)$'
  local -a _assets=() _news=() _arches=() _vars=()
  _ver_var="${_up}_VER"
  _ver="${!_ver_var}"
  _for_var="${_up}_SHA256_FOR_VER"
  _for="${!_for_var}"
  _body="$(mktemp "${TMPDIR:-/tmp}/refresh-pins-body.XXXXXXXX")" || {
    printf "%s: cannot create a temp file\n" "${_tool}" >&2
    return 1
  }
  _TMP_FILES+=("${_body}")

  for _arch in amd64 arm64; do
    _url="$(_release_asset_url "${_tool}" "${_arch}")" || {
      printf "%s: %s: no release asset URL\n" "${_tool}" "${_arch}" >&2
      rm -f "${_body}"
      return 1
    }
    if [[ -n "${BATS_TEST_TMPDIR:-}" && -n "${_REFRESH_ASSET_URL:-}" ]]; then
      _url="${_REFRESH_ASSET_URL}"
    fi
    if [[ ! "${_url}" =~ ${_re} ]]; then
      printf "%s: %s is not a GitHub release asset URL\n" "${_tool}" "${_url}" >&2
      rm -f "${_body}"
      return 1
    fi
    _o2="${BASH_REMATCH[1]}" _r2="${BASH_REMATCH[2]}" _t2="${BASH_REMATCH[3]}" _a2="${BASH_REMATCH[4]}"
    if [[ -z "${_first}" ]]; then
      _first=1 _owner="${_o2}" _repo="${_r2}" _tag="${_t2}"
    elif [[ "${_o2}/${_r2}/${_t2}" != "${_owner}/${_repo}/${_tag}" ]]; then
      printf "%s: %s and the amd64 asset are not in the same release\n" "${_tool}" "${_arch}" >&2
      rm -f "${_body}"
      return 1
    fi
    printf "querying %s\n" "${_url}"
    _arches+=("${_arch}")
    _assets+=("${_a2}")
    _vars+=("$(_release_asset_sha "${_tool}" "${_arch}" | cut -d' ' -f1)")
  done

  _api="$(_github_api_base)/repos/${_owner}/${_repo}/releases/tags/${_tag}"
  _fetch_release "${_tool}" "${_api}" "${_body}" || {
    rm -f "${_body}"
    return 1
  }

  local _i
  for _i in 0 1; do
    _arch="${_arches[_i]}" _asset="${_assets[_i]}" _var="${_vars[_i]}"
    _raw="$(_digest_from_body "${_body}" "${_asset}")"
    _hex="${_raw#sha256:}"
    if [[ "${_raw}" != sha256:* ]] || ! _sha256_pin_ok "${_hex}"; then
      printf "%s: %s: no usable sha256 digest for %s (got '%s')\n" "${_tool}" "${_arch}" "${_asset}" "${_raw}" >&2
      rm -f "${_body}"
      return 1
    fi
    _old="${!_var}"
    if [[ "${_for}" == "${_ver}" && "${_old}" != "${_hex}" ]] && [[ "${_ACCEPT_CHANGED}" -eq 0 ]]; then
      printf "%s: %s asset changed at unchanged version %s: pin %s, API %s\n" \
        "${_tool}" "${_arch}" "${_ver}" "${_old}" "${_hex}" >&2
      rm -f "${_body}"
      return 1
    fi
    _news+=("${_hex}")
  done
  rm -f "${_body}"

  for _i in 0 1; do
    _var="${_vars[_i]}"
    [[ "${!_var}" == "${_news[_i]}" ]] || _UPDATES+=("${_tool}|${_arches[_i]}|${_var}|${_news[_i]}")
  done
  [[ "${_for}" == "${_ver}" ]] || _UPDATES+=("${_tool}|-|${_for_var}|${_ver}")
  return 0
}

# _validate_tool <tool> <file> -- version set and every pin line present, before any request.
_validate_tool() {
  local _tool="$1" _file="$2" _up="${1^^}" _v
  local _ver_var="${_up}_VER"
  if [[ -z "${!_ver_var}" ]]; then
    printf "%s: %s is empty in %s\n" "${_tool}" "${_ver_var}" "${_file}" >&2
    return 1
  fi
  for _v in "${_up}_SHA256_AMD64" "${_up}_SHA256_ARM64" "${_up}_SHA256_FOR_VER"; do
    if ! grep -q "^${_v}=" "${_file}"; then
      printf "%s: %s line missing in %s; add it, then re-run\n" "${_tool}" "${_v}" "${_file}" >&2
      return 1
    fi
  done
  if [[ ! "${!_ver_var}" =~ ^[[:alnum:].+-]+$ ]]; then
    printf "%s: %s has characters outside [A-Za-z0-9.+-] in %s\n" "${_tool}" "${_ver_var}" "${_file}" >&2
    return 1
  fi
}

# _write_updates <file> -- apply _UPDATES to a same-directory copy, read every line
# back, then mv it over the target. The target is untouched on any failure.
_write_updates() {
  local _file="$1" _tmp _entry _tool _arch _var _new _old
  local -a _sedargs=()
  _tmp="$(mktemp "$(dirname "${_file}")/.refresh-pins.XXXXXXXX")" || {
    printf "cannot create a temp copy next to %s\n" "${_file}" >&2
    return 1
  }
  _TMP_FILES+=("${_tmp}")
  cp -p "${_file}" "${_tmp}" || {
    printf "cannot copy %s\n" "${_file}" >&2
    rm -f "${_tmp}"
    return 1
  }
  for _entry in "${_UPDATES[@]}"; do
    IFS='|' read -r _tool _arch _var _new <<<"${_entry}"
    _sedargs+=(-e "s|^${_var}=\".*\"\$|${_var}=\"${_new}\"|")
  done
  sed "${_sedargs[@]}" "${_file}" >"${_tmp}" || {
    printf "sed failed on %s\n" "${_file}" >&2
    rm -f "${_tmp}"
    return 1
  }
  for _entry in "${_UPDATES[@]}"; do
    IFS='|' read -r _tool _arch _var _new <<<"${_entry}"
    if ! grep -Fqx "${_var}=\"${_new}\"" "${_tmp}"; then
      printf "%s: %s: read-back failed for %s\n" "${_tool}" "${_arch}" "${_var}" >&2
      rm -f "${_tmp}"
      return 1
    fi
  done
  mv -f "${_tmp}" "${_file}" || {
    printf "cannot replace %s\n" "${_file}" >&2
    rm -f "${_tmp}"
    return 1
  }
  for _entry in "${_UPDATES[@]}"; do
    IFS='|' read -r _tool _arch _var _new <<<"${_entry}"
    _old="${_OLD_VALUES[${_var}]}"
    printf "%s %s -> %s\n" "${_var}" "${_old}" "${_new}"
  done
}

main() {
  local _constants="${_REPO_ROOT}/lib/constants.sh" _tool _up _for_var _ver_var _entry _var
  local -a _tools=()
  _ACCEPT_CHANGED=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --constants)
        [[ $# -ge 2 ]] || {
          _usage
          return 2
        }
        _constants="$2"
        shift 2
        ;;
      --accept-changed)
        _ACCEPT_CHANGED=1
        shift
        ;;
      kind | yq | shellcheck)
        case " ${_tools[*]:-} " in
          *" $1 "*) ;;
          *) _tools+=("$1") ;;
        esac
        shift
        ;;
      *)
        _usage
        return 2
        ;;
    esac
  done
  [[ -f "${_constants}" ]] || {
    printf "%s: no such file\n" "${_constants}" >&2
    return 1
  }
  if [[ -L "${_constants}" ]]; then
    printf "%s is a symlink; pass the real file\n" "${_constants}" >&2
    return 1
  fi
  command -v python3 >/dev/null 2>&1 || {
    printf "python3 not found; it parses the GitHub API response\n" >&2
    return 1
  }
  trap _cleanup_tmp EXIT

  # shellcheck source=/dev/null # the target is a runtime argument
  source "${_constants}" || return 1
  # shellcheck source=lib/helpers.sh
  source "${_REPO_ROOT}/lib/helpers.sh" || return 1
  # shellcheck source=lib/linux_ubuntu.sh
  source "${_REPO_ROOT}/lib/linux_ubuntu.sh" || return 1

  if [[ "${#_tools[@]}" -eq 0 ]]; then
    for _tool in kind yq shellcheck; do
      _up="${_tool^^}"
      _for_var="${_up}_SHA256_FOR_VER"
      _ver_var="${_up}_VER"
      [[ "${!_for_var:-}" == "${!_ver_var:-}" ]] || _tools+=("${_tool}")
    done
    if [[ "${#_tools[@]}" -eq 0 ]]; then
      printf "pins up to date\n"
      return 0
    fi
  fi

  for _tool in "${_tools[@]}"; do
    _validate_tool "${_tool}" "${_constants}" || return 1
  done

  _UPDATES=()
  for _tool in "${_tools[@]}"; do
    _resolve_pins "${_tool}" || return 1
  done

  if [[ "${#_UPDATES[@]}" -eq 0 ]]; then
    printf "pins up to date\n"
    return 0
  fi
  declare -gA _OLD_VALUES=()
  for _entry in "${_UPDATES[@]}"; do
    _var="$(cut -d'|' -f3 <<<"${_entry}")"
    _OLD_VALUES["${_var}"]="${!_var}"
  done
  _write_updates "${_constants}"
}

main "$@"
