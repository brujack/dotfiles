#!/usr/bin/env bash
# Emit every tracked file whose FIRST line is a bash/sh shebang, one per line.
#
# Content-derived rather than name-derived, because the set must be correct in
# BOTH directions: a pathspec cannot express "every tracked shell script" (so
# extensionless hooks and mocks fall out of scope silently), and a directory
# glob added to compensate cannot express "only the shell ones" (so a README
# dropped into tests/mocks/ enters shellcheck's argv and reddens the gate).
set -o pipefail
_root="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
           git rev-parse --show-toplevel 2>/dev/null)" || exit 1
cd "${_root}" || exit 1
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  git ls-files -z | while IFS= read -r -d '' f; do
    [[ -f "${f}" ]] || continue
    first=
    # `read` returns 1 at EOF-without-delimiter while STILL populating the
    # variable, so a bare `|| continue` discards a single-line file whose only
    # line is an unterminated shebang.
    #
    # 2>/dev/null MUST precede the input redirect: bash applies redirections
    # left to right, so a failing `< "${f}"` on an unreadable file reports to
    # the not-yet-redirected stderr. With the order reversed, an unreadable
    # tracked file prints `Permission denied` at every make parse.
    IFS= read -r first 2>/dev/null < "${f}" || [[ -n "${first}" ]] || continue
    case "${first}" in
      '#!'*/bash|'#!'*/bash\ *|'#!'*env\ bash|'#!'*env\ bash\ *|\
      '#!'*/sh|'#!'*/sh\ *|'#!'*env\ sh|'#!'*env\ sh\ *) printf '%s\n' "${f}" ;;
    esac
  done
