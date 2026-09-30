#!/usr/bin/env bats

# scripts/auto-merge-gate.sh decides whether ci.yml's auto-merge job may merge
# a green PR. It writes merge=true|false to GITHUB_OUTPUT and exits 1 when it
# cannot decide, so a broken query can never fall through to a merge. `gh` is
# a fake that prints FAKE_GH_JSON (the `gh pr view --json` payload) and exits
# FAKE_GH_EXIT.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  GATE="${REPO_ROOT}/scripts/auto-merge-gate.sh"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s' "${FAKE_GH_JSON:-}"
exit "${FAKE_GH_EXIT:-0}"
GH
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
  : > "${GITHUB_OUTPUT}"
}

# _pr <author> <labels-json> <files-json> [changedFiles]
_pr() {
  local _n
  _n="${4:-$(printf '%s' "$3" | jq 'length')}"
  export FAKE_GH_JSON
  FAKE_GH_JSON="$(jq -cn --arg a "$1" --argjson l "$2" --argjson f "$3" --argjson n "${_n}" \
    '{author:{login:$a}, labels:($l|map({name:.})), files:($f|map({path:.})), changedFiles:$n}')"
}

@test "a human PR with ordinary files is cleared to merge" {
  _pr "brujack" '[]' '["lib/workflows.sh","tests/x.bats"]'
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=true" ]
}

@test "a Renovate PR with automerge-ok is cleared to merge" {
  _pr "app/renovate" '["automerge-ok"]' '[".github/workflows/ci.yml"]'
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=true" ]
}

@test "a Renovate PR without automerge-ok is held" {
  _pr "app/renovate" '["dependencies"]' '[".github/workflows/ci.yml"]'
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=false" ]
}

@test "uv.lock changed without pyproject.toml is held, whoever the author" {
  local _author
  for _author in brujack app/dependabot app/renovate; do
    : > "${GITHUB_OUTPUT}"
    _pr "${_author}" '["automerge-ok"]' '["uv.lock","requirements-ci.txt"]'
    run bash "${GATE}" 1
    [ "$status" -eq 0 ] || { printf '%s: status %s\n' "${_author}" "$status" >&3; return 1; }
    [ "$(cat "${GITHUB_OUTPUT}")" = "merge=false" ] || { printf '%s: not held\n' "${_author}" >&3; return 1; }
    [[ "$output" == *"uv.lock"* ]]
  done
}

@test "uv.lock changed together with pyproject.toml is cleared to merge" {
  _pr "brujack" '[]' '["pyproject.toml","uv.lock","requirements-ci.txt"]'
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=true" ]
}

@test "a pyproject.toml in a subdirectory does not count as the manifest" {
  _pr "brujack" '[]' '["uv.lock","docs/pyproject.toml"]'
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=false" ]
}

@test "a filename containing a newline cannot pose as pyproject.toml" {
  export FAKE_GH_JSON='{"author":{"login":"brujack"},"labels":[],"files":[{"path":"uv.lock"},{"path":"x\npyproject.toml"}],"changedFiles":2}'
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=false" ]
}

@test "a payload missing changedFiles exits 1 rather than skipping the truncation check" {
  export FAKE_GH_JSON='{"author":{"login":"brujack"},"labels":[],"files":[{"path":"lib/a.sh"}]}'
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "a payload with a null author exits 1" {
  export FAKE_GH_JSON='{"author":null,"labels":[],"files":[{"path":"lib/a.sh"}],"changedFiles":1}'
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "a files field that is not an array exits 1" {
  export FAKE_GH_JSON='{"author":{"login":"brujack"},"labels":[],"files":{"x":{"path":"lib/a.sh"}},"changedFiles":1}'
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "a null labels field exits 1 even for a human PR" {
  export FAKE_GH_JSON='{"author":{"login":"brujack"},"labels":null,"files":[{"path":"lib/a.sh"}],"changedFiles":1}'
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "a nested uv.lock alone is cleared, since only the root lock pins the venv" {
  _pr "brujack" '[]' '["vendor/tool/uv.lock"]'
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=true" ]
}

@test "an empty gh payload with exit 0 exits 1 and writes no merge decision" {
  export FAKE_GH_JSON="" FAKE_GH_EXIT=0
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [[ "$output" == *"unexpected gate verdict"* ]]
}

@test "two concatenated gh payloads exit 1 and write no merge decision" {
  _pr "brujack" '[]' '["lib/a.sh"]'
  export FAKE_GH_JSON="${FAKE_GH_JSON}${FAKE_GH_JSON}" FAKE_GH_EXIT=0
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "a valid payload followed by a malformed one exits 1 rather than merging" {
  _pr "brujack" '[]' '["lib/a.sh"]'
  export FAKE_GH_JSON="${FAKE_GH_JSON}"'{"author":null}' FAKE_GH_EXIT=0
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
  [[ "$output" == *"cannot read"* ]]
}

@test "a PR whose file list is truncated is held, since uv.lock could be hidden" {
  _pr "brujack" '[]' '["lib/a.sh"]' 150
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=false" ]
}

@test "a file list one short of changedFiles is held (gh lists 100 of a 101-file PR)" {
  _pr "brujack" '[]' '["lib/a.sh"]' 2
  run bash "${GATE}" 1
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_OUTPUT}")" = "merge=false" ]
}

@test "a failed gh query exits 1 and writes no merge decision" {
  export FAKE_GH_JSON="" FAKE_GH_EXIT=1
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "a failed gh query exits 1 even when it printed a valid payload" {
  # The exit status is what says the query failed; a payload that happens to
  # parse must not be trusted over it.
  _pr "brujack" '[]' '["lib/a.sh"]'
  export FAKE_GH_EXIT=1
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "an unparseable gh payload exits 1 and writes no merge decision" {
  export FAKE_GH_JSON="not json"
  run bash "${GATE}" 1
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}

@test "a missing PR number exits 1 and writes no merge decision" {
  _pr "brujack" '[]' '["lib/a.sh"]'
  run bash "${GATE}"
  [ "$status" -eq 1 ]
  [ ! -s "${GITHUB_OUTPUT}" ]
}
