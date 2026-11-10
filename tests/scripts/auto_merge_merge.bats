#!/usr/bin/env bats

# scripts/auto-merge-merge.sh runs the auto-merge job's one `gh pr merge` and
# retries only GitHub's "base branch policy prohibits the merge" refusal, which
# can precede the required-check state reaching the merge API. `gh` and `sleep`
# are fakes: FAKE_GH_SEQ holds one "<exit><TAB><message>" line per expected
# call; a non-zero exit prints its message on stderr only, as real gh does.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/auto-merge-merge.sh"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/gh" <<'GH'
#!/usr/bin/env bash
_calls="${BATS_TEST_TMPDIR}/calls"
_n=$(( $(cat "${_calls}" 2>/dev/null || printf 0) + 1 ))
printf '%s' "${_n}" > "${_calls}"
for _a in "$@"; do printf '%s\n' "${_a}"; done >> "${BATS_TEST_TMPDIR}/argv"
printf -- '--\n' >> "${BATS_TEST_TMPDIR}/argv"
_line="$(sed -n "${_n}p" "${FAKE_GH_SEQ}")"
_rc="${_line%%$'\t'*}"
_msg="${_line#*$'\t'}"
if [[ "${_rc}" -eq 0 ]]; then
  [[ -n "${_msg}" ]] && printf '%s\n' "${_msg}"
else
  [[ -n "${_msg}" ]] && printf '%s\n' "${_msg}" >&2
fi
exit "${_rc}"
GH
  cat > "${BATS_TEST_TMPDIR}/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${BATS_TEST_TMPDIR}/sleeps"
exit 0
SLEEP
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh" "${BATS_TEST_TMPDIR}/bin/sleep"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  export BATS_TEST_TMPDIR
  FAKE_GH_SEQ="${BATS_TEST_TMPDIR}/seq"
  export FAKE_GH_SEQ
  unset AUTO_MERGE_RETRY_DELAY
  REFUSED='X Pull request brujack/dotfiles#354 is not mergeable: the base branch policy prohibits the merge.'
  MODIFIED='GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)'
  CONFLICT='X Pull request brujack/dotfiles#354 is not mergeable: the merge commit cannot be cleanly created.'
}

# _seq <exit> <message> ... : one fake-gh response line per pair.
_seq() {
  : > "${FAKE_GH_SEQ}"
  while [[ $# -ge 2 ]]; do
    printf '%s\t%s\n' "$1" "$2" >> "${FAKE_GH_SEQ}"
    shift 2
  done
}

_gh_calls() { cat "${BATS_TEST_TMPDIR}/calls" 2>/dev/null || printf 0; }

@test "merged on the first call makes one call and never sleeps" {
  _seq 0 "merged"
  run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 0 ]
  [ "$(_gh_calls)" -eq 1 ]
  [ ! -e "${BATS_TEST_TMPDIR}/sleeps" ]
}

@test "a refusal then success retries once after the configured delay" {
  _seq 1 "${REFUSED}" 0 "merged"
  AUTO_MERGE_RETRY_DELAY=5 run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 0 ]
  [ "$(_gh_calls)" -eq 2 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/sleeps")" = "5" ]
}

@test "three refusals stop after three attempts with the default delay and a remedy line" {
  _seq 1 "${REFUSED}" 1 "${REFUSED}" 1 "${REFUSED}"
  run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 3 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/sleeps")" = "$(printf '30\n30')" ]
  [[ "$output" == *"merge by hand with gh pr merge 354 --squash --match-head-commit abc123"* ]]
  _n="$(printf '%s\n' "$output" | grep -cE '^attempt [1-3]/3 at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')"
  [ "${_n}" -eq 3 ]
}

@test "a head-modified error is not retried" {
  _seq 1 "${MODIFIED}"
  run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 1 ]
  [[ "$output" == *"Head branch was modified"* ]]
}

@test "a refusal then a head-modified error stops at the second call" {
  _seq 1 "${REFUSED}" 1 "${MODIFIED}"
  run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 2 ]
}

@test "gh failing with no output is not retried" {
  _seq 1 ""
  run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 1 ]
}

@test "a pr number without a head sha prints usage and makes no gh call" {
  _seq 0 "merged"
  run bash "${SCRIPT}" 354
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "no arguments makes no gh call" {
  _seq 0 "merged"
  run bash "${SCRIPT}"
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 0 ]
}

@test "gh receives exactly the squash merge argv pinned to the head sha" {
  _seq 0 "merged"
  run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/argv")" = "$(printf 'pr\nmerge\n354\n--squash\n--match-head-commit\nabc123\n--')" ]
}

@test "a non-numeric retry delay prints usage and makes no gh call" {
  _seq 0 "merged"
  AUTO_MERGE_RETRY_DELAY=abc run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "a not-mergeable conflict is not retried" {
  # shares "is not mergeable:" with the policy refusal, so only a match on the
  # full refusal text keeps it out of the retry
  _seq 1 "${CONFLICT}" 0 "merged"
  run bash "${SCRIPT}" 354 abc123
  [ "$status" -eq 1 ]
  [ "$(_gh_calls)" -eq 1 ]
  [[ "$output" == *"cannot be cleanly created"* ]]
}
