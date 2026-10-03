#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Direct pushes of .md files to master skip the test suite (scripts/pre-push).
# That is safe only while nothing `make test` runs reads a tracked .md outside
# tests/. This file turns that premise into a gate.

# Recorded closure of `make test` prerequisites, measured against the real
# Makefile. Adding a target here is a claim that it reads no tracked .md.
ALLOWED_TEST_PREREQS=(lint check-lock check-requirements-ci test-python)

# "<file>|<reason>" entries for tests allowed to read a tracked .md outside
# tests/. Empty today. tests/test_relocation_check.py needs no entry: it reads
# CLAUDE.md through `git show` at a pinned SHA, not from the working tree.
ALLOWED_MD_READERS=()

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  CLEAN_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  export PATH="${CLEAN_PATH}"
}

# Prints the prerequisites of every rule for target $2 in the make database
# dump $1. Order-only prerequisites (after |) are included: they still run.
_rule_prereqs() {
  local _db="${1}" _target="${2}"
  printf '%s\n' "${_db}" | awk -v t="${_target}" '
    index($0, t ":") == 1 && substr($0, length(t) + 2, 1) != "=" {
      line = substr($0, length(t) + 2)
      gsub(/\|/, " ", line)
      print line
    }'
}

# _check_prereqs <root>: fail if the `make test` closure differs from
# ALLOWED_TEST_PREREQS. Parses stdout only; -q makes make exit 1 by design.
_check_prereqs() {
  local _root="${1}" _db _queue=() _seen=" " _t _p _extra=() _a _ok
  # -q exits 1 by design; parse stdout, never branch on the status
  _db="$(make --no-print-directory -C "${_root}" -pnq test 2>/dev/null || true)"
  # shellcheck disable=SC2207 # word-splitting is the point: one name per token
  _queue=($(_rule_prereqs "${_db}" test))
  while [[ ${#_queue[@]} -gt 0 ]]; do
    _t="${_queue[0]}"
    _queue=("${_queue[@]:1}")
    [[ "${_seen}" == *" ${_t} "* ]] && continue
    [[ -e "${_root}/${_t}" ]] && continue
    _seen+="${_t} "
    # shellcheck disable=SC2207 # word-splitting is the point
    for _p in $(_rule_prereqs "${_db}" "${_t}"); do
      _queue+=("${_p}")
    done
  done
  if [[ "${_seen}" == " " ]]; then
    printf 'FAIL: empty make test prerequisite closure; the parse found nothing\n' >&2
    return 1
  fi
  for _t in ${_seen}; do
    _ok=0
    for _a in "${ALLOWED_TEST_PREREQS[@]}"; do
      [[ "${_t}" == "${_a}" ]] && _ok=1
    done
    [[ "${_ok}" -eq 0 ]] && _extra+=("${_t}")
  done
  if [[ ${#_extra[@]} -gt 0 ]]; then
    printf 'FAIL: make test gained prerequisite(s) not in ALLOWED_TEST_PREREQS: %s\n' "${_extra[*]}" >&2
    printf 'Check whether each reads a tracked .md; if not, add it to ALLOWED_TEST_PREREQS.\n' >&2
    printf 'check-agent-guidance is the known reader (it reads CLAUDE.md), so it must not be a prerequisite.\n' >&2
    return 1
  fi
  return 0
}

# _check_readers <root>: fail if a file under <root>/tests builds a path from a
# root variable that ends in .md and is not under tests/.
# docs_inert_premise.bats is excluded: its own source names these patterns.
_check_readers() {
  local _root="${1}" _files _f _hit _rel _bad=0 _entry _allowed _n=0
  local _re='(^|[^A-Za-z0-9_])(REPO_ROOT|ROOT|repo_root|BATS_TEST_DIRNAME/\.\./\.\.)\}?["'"'"']?[[:space:]]*/?[[:space:]]*["'"'"']?/?[A-Za-z0-9_./-]+\.md'
  _files="$(find "${_root}/tests" -type f \( -name '*.bats' -o -name '*.py' -o -path '*/helpers/*' \) | sort)"
  while IFS= read -r _f; do
    [[ -z "${_f}" ]] && continue
    [[ "$(basename "${_f}")" == "docs_inert_premise.bats" ]] && continue
    _n=$((_n + 1))
    _rel="${_f#"${_root}"/}"
    while IFS= read -r _hit; do
      [[ -z "${_hit}" ]] && continue
      # strip the root-variable prefix, leaving the path it is joined to
      _path="$(printf '%s' "${_hit#*:}" | sed -E 's/^[^A-Za-z0-9_]?(REPO_ROOT|ROOT|repo_root|BATS_TEST_DIRNAME\/\.\.\/\.\.)\}?["'"'"']?[[:space:]]*\/?[[:space:]]*["'"'"']?\/?//')"
      [[ "${_path}" == tests/* ]] && continue
      _allowed=0
      for _entry in "${ALLOWED_MD_READERS[@]}"; do
        [[ "${_entry%%|*}" == "${_rel}" ]] && _allowed=1
      done
      [[ "${_allowed}" -eq 1 ]] && continue
      printf 'FAIL: %s:%s reads tracked .md outside tests/: %s\n' "${_rel}" "${_hit%%:*}" "${_path}" >&2
      _bad=1
    done < <(grep -noE "${_re}" "${_f}" 2>/dev/null | sed -E 's/^([0-9]+):/\1:/')
  done <<<"${_files}"
  if [[ "${_n}" -eq 0 ]]; then
    printf 'FAIL: scanned zero test files under %s/tests\n' "${_root}" >&2
    return 1
  fi
  return "${_bad}"
}

_fixture_makefile() {
  local _dir="${1}" _test_line="${2}"
  mkdir -p "${_dir}"
  {
    printf '%s\n' "${_test_line}"
    printf 'lint:\n\t@true\n'
    printf 'check-agent-guidance:\n\t@true\n'
  } >"${_dir}/Makefile"
}

@test "real repo: make test prerequisite closure matches the recorded set" {
  run -0 _check_prereqs "${REPO_ROOT}"
}

@test "positive control: the real closure parse is non-empty and contains lint" {
  local _db
  # -q exits 1 by design; the database on stdout is what matters
  _db="$(make --no-print-directory -C "${REPO_ROOT}" -pnq test 2>/dev/null || true)"
  run _rule_prereqs "${_db}" test
  [ "${status}" -eq 0 ]
  [[ "${output}" == *lint* ]]
}

@test "fixture: test depending on check-agent-guidance fails naming it" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint check-agent-guidance"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *check-agent-guidance* ]]
}

@test "fixture: test depending only on recorded targets passes" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: transitive prerequisite is found through a recorded target" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint"
  printf 'lint: check-agent-guidance\n' >>"${BATS_TEST_TMPDIR}/fx/Makefile"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *check-agent-guidance* ]]
}

@test "fixture: a Makefile with no test rule fails rather than passing vacuously" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx"
  printf 'lint:\n\t@true\n' >"${BATS_TEST_TMPDIR}/fx/Makefile"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "real repo: no test reads a tracked .md outside tests/" {
  run -0 _check_readers "${REPO_ROOT}"
}

@test "fixture: bats file reading README.md via REPO_ROOT fails naming the file" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${REPO_ROOT}/README.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/x.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/x.bats* ]]
}

@test "fixture: python file reading CLAUDE.md via REPO_ROOT fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'p = REPO_ROOT / "CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/y.py"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/y.py* ]]
}

@test "fixture: reading a .md under tests/ passes" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${REPO_ROOT}/tests/fixtures/a.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/z.bats"
  run -0 _check_readers "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: a tests directory with no scannable files fails rather than passing vacuously" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
}
