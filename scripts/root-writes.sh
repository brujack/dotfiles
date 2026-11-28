#!/usr/bin/env bash
# root-writes.sh mark <marker> | check <marker> -- detect bats-suite writes to
# real host paths by walking the filesystem, not by reading mock-call ledgers.
#
#   mark  <marker>  create the marker file the walk compares against.
#   check <marker>  list every path under the roots created, modified,
#                   chmodded or chowned after the marker, plus the directory of
#                   every entry deleted after it. Exit 0 when none, 1 otherwise
#                   or when the scan cannot be trusted (see the failure cases).
#
# ci.yml runs `mark` before the bats work and `check` after it. No Makefile
# target runs the scan (it is a CI measurement, not a local gate), and the scan
# never writes, moves or deletes anything under its roots.
#
# Seams (honoured only under bats, via _bats_seam; an exported value must never
# steer a real scan): ROOT_WRITES_ROOTS (whitespace-separated roots),
# ROOT_WRITES_SUDO (default sudo), ROOT_WRITES_PRUNE (whitespace-separated
# paths replacing the chosen per-OS prune list).

_RW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
# shellcheck source=lib/helpers.sh
source "${_RW_DIR}/../lib/helpers.sh" || exit 1

# Per-OS prune lists. A prune enters only by spec amendment, each entry with a
# comment citing the measurement that produced it. No entry may equal or
# contain a directory lib/ installs into (/etc/apt, /etc/docker,
# /etc/sysctl.d, /usr/share/keyrings, /usr/local/bin, /opt/homebrew and the
# macOS /private/etc equivalents); tests/scripts/root_writes.bats enforces it.
# /opt/hca: the hosted runner's own agent log (hosted-compute-agent.log), a
# background writer on both OSes: rollout CI run 46103860810 (test-shard 1 and 2,
# test-macos-shard 2 and 3) and null-window run 46103849102 (macos 9).
ROOT_WRITES_PRUNE_LINUX=(/opt/hca)
ROOT_WRITES_PRUNE_DARWIN=(/opt/hca)

# _rw_roots -- print the roots to scan, one per line.
_rw_roots() {
  local _roots _split=() _r
  _roots="$(_bats_seam "${ROOT_WRITES_ROOTS:-}" '/etc /usr/local /usr/share/keyrings /opt')"
  # Roots are whitespace-separated.
  read -ra _split <<< "${_roots}"
  for _r in "${_split[@]}"; do
    printf '%s\n' "${_r}"
  done
}

# _rw_sudo_cmd -- print the sudo command; the override counts only under bats.
_rw_sudo_cmd() {
  _bats_seam "${ROOT_WRITES_SUDO:-}" sudo
}

# _rw_show <path> -- print one reported path on one line; a name holding a
# newline is shown in printf %q form (the only case that changes the text).
_rw_show() {
  if [[ $1 == *$'\n'* ]]; then
    printf '%q\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

# _rw_prune_list -- print the prune paths for this OS, one per line.
_rw_prune_list() {
  local _override _split=() _p
  _override="$(_bats_seam "${ROOT_WRITES_PRUNE:-}" '')"
  if [[ -n ${_override} ]]; then
    read -ra _split <<< "${_override}"
    for _p in "${_split[@]}"; do
      printf '%s\n' "${_p}"
    done
    return 0
  fi
  if [[ "$(uname -s)" == Darwin ]]; then
    for _p in "${ROOT_WRITES_PRUNE_DARWIN[@]}"; do printf '%s\n' "${_p}"; done
  else
    for _p in "${ROOT_WRITES_PRUNE_LINUX[@]}"; do printf '%s\n' "${_p}"; done
  fi
  return 0
}

# root_writes_mark <marker>
root_writes_mark() {
  local _marker="${1:-}"
  if [[ -z ${_marker} ]]; then
    printf 'root-writes: mark needs a marker path\n' >&2
    return 1
  fi
  if ! : > "${_marker}"; then
    printf 'root-writes: cannot create marker %s\n' "${_marker}" >&2
    return 1
  fi
  return 0
}

# _rw_denied_dirs <stderr-file> -- print the directory of each `Permission
# denied` line; return 1 when any line ends otherwise (or the file is empty).
_rw_denied_dirs() {
  local _line _dir _seen=0
  while IFS= read -r _line; do
    [[ ${_line} == *"Permission denied" ]] || return 1
    _dir="${_line#find: }"
    _dir="${_dir%: Permission denied}"
    # GNU find quotes the path (‘x’ or 'x'); BSD find does not.
    _dir="${_dir#[\'‘]}"
    _dir="${_dir%[\'’]}"
    printf '%s\n' "${_dir}"
    _seen=1
  done < "$1"
  (( _seen == 1 )) || return 1
  return 0
}

# _rw_scan_root <root> <marker> -- scan one root. Appends to the globals
# _RW_HITS, _RW_NOTES, _RW_COUNTS and _RW_FAILS (arrays); never exits.
_rw_scan_root() {
  local _root="$1" _marker="$2" _resolved _listing _lrc=0 _out _err _frc=0
  local _p _line _prev _total=0 _dir
  local _prunes=()
  if [[ ! -d ${_root} ]]; then
    _RW_NOTES+=("skipped: ${_root} (missing)")
    return 0
  fi
  if ! _resolved="$(cd "${_root}/." && pwd -P)"; then
    _RW_FAILS+=("cannot resolve root ${_root}")
    return 0
  fi

  # Emptiness is decided apart from the walk, with the walk's privilege, so a
  # walk that never descended cannot pass for an empty root.
  _listing="$("${_RW_PRIV[@]}" ls -A "${_root}/." 2> /dev/null)" || _lrc=$?
  if (( _lrc != 0 )); then
    _RW_FAILS+=("listing of ${_root} refused (status ${_lrc})")
    return 0
  fi
  if [[ -z ${_listing} ]]; then
    _RW_NOTES+=("empty: ${_root}")
    return 0
  fi

  while IFS= read -r _p; do
    [[ -n ${_p} ]] && _prunes+=(-path "${_p}" -prune -o)
  done < <(_rw_prune_list)

  _out="${_RW_TMP}/out.$$.${#_RW_COUNTS[@]}"
  _err="${_RW_TMP}/err.$$.${#_RW_COUNTS[@]}"
  # Every entry prints once, NUL-terminated so a name holding a newline cannot
  # split (the count of entries visited); an entry changed after the marker
  # prints a second time straight after, which marks it a hit.
  "${_RW_PRIV[@]}" find "${_resolved}" -xdev "${_prunes[@]}" -print0 \
    \( \( -newer "${_marker}" -o -cnewer "${_marker}" \) -print0 \) \
    > "${_out}" 2> "${_err}" || _frc=$?

  if (( _frc != 0 )); then
    if (( ${#_RW_PRIV[@]} > 0 )); then
      _RW_FAILS+=("find under sudo failed on ${_root} (status ${_frc})")
      return 0
    fi
    if (( _frc != 1 )) || ! _dir="$(_rw_denied_dirs "${_err}")"; then
      _RW_FAILS+=("find failed on ${_root} (status ${_frc}): $(head -n 3 "${_err}" | tr '\n' ' ')")
      return 0
    fi
    while IFS= read -r _line; do
      _RW_NOTES+=("not scanned: ${_line}")
    done <<< "${_dir}"
  elif [[ -s ${_err} ]]; then
    _RW_FAILS+=("find wrote to stderr on ${_root}: $(head -n 3 "${_err}" | tr '\n' ' ')")
    return 0
  fi

  _prev=""
  while IFS= read -r -d '' _line; do
    if [[ -n ${_prev} && ${_line} == "${_prev}" ]]; then
      _RW_HITS+=("${_line}")
    else
      _total=$((_total + 1))
    fi
    _prev="${_line}"
  done < "${_out}"
  # find prints its starting point itself, so entries below the root = total - 1.
  _total=$((_total - 1))
  if (( _total < 1 )); then
    _RW_FAILS+=("walk of ${_root} visited nothing below it though its listing is not empty")
    return 0
  fi
  _RW_COUNTS+=("${_root} ${_total}")
  return 0
}

# root_writes_check <marker>
root_writes_check() {
  local _marker="${1:-}" _sudo _root _entry _joined="" _f _nroots=0
  if [[ -z ${_marker} || ! -f ${_marker} ]]; then
    printf 'root-writes: marker %s is missing\n' "${_marker}" >&2
    return 1
  fi
  _RW_HITS=()
  _RW_NOTES=()
  _RW_COUNTS=()
  _RW_FAILS=()
  _RW_PRIV=()
  _sudo="$(_rw_sudo_cmd)"
  if "${_sudo}" -n true < /dev/null > /dev/null 2>&1; then
    _RW_PRIV=("${_sudo}" -n)
  fi
  _RW_TMP="$(mktemp -d "${TMPDIR:-/tmp}/root-writes.XXXXXX")" || {
    printf 'root-writes: cannot create a temporary directory\n' >&2
    return 1
  }
  while IFS= read -r _root; do
    _nroots=$((_nroots + 1))
    _rw_scan_root "${_root}" "${_marker}"
  done < <(_rw_roots)
  if (( _nroots == 0 )); then
    rm -rf "${_RW_TMP}"
    printf 'root-writes: the roots list is empty\n' >&2
    return 1
  fi
  rm -rf "${_RW_TMP}"

  for _f in ${_RW_NOTES[@]+"${_RW_NOTES[@]}"}; do printf '%s\n' "${_f}"; done
  if (( ${#_RW_FAILS[@]} > 0 )); then
    for _f in "${_RW_FAILS[@]}"; do printf 'root-writes: %s\n' "${_f}" >&2; done
    if (( ${#_RW_HITS[@]} > 0 )); then
      printf 'root-writes: the suite changed real host paths:\n'
      for _f in "${_RW_HITS[@]}"; do _rw_show "${_f}"; done
    fi
    return 1
  fi
  if (( ${#_RW_HITS[@]} > 0 )); then
    printf 'root-writes: the suite changed real host paths:\n'
    for _f in "${_RW_HITS[@]}"; do _rw_show "${_f}"; done
    return 1
  fi
  for _entry in ${_RW_COUNTS[@]+"${_RW_COUNTS[@]}"}; do
    _joined+="${_joined:+, }${_entry}"
  done
  printf 'root-writes: none (%s)\n' "${_joined}"
  return 0
}

root_writes_main() {
  case "${1:-}" in
    mark) root_writes_mark "${2:-}" ;;
    check) root_writes_check "${2:-}" ;;
    *)
      printf 'usage: root-writes.sh mark|check <marker>\n' >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
root_writes_main "$@"
exit $?
