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

# Known blind spots (not detected by either checker):
#   - os.path.join / joinpath / multi-segment `/` joins (REPO / "tests" / "x.md"
#     is not seen; only ROOT / "x.md" and ROOT/x.md single-join forms are)
#   - Path(__file__).parents[N] and $(dirname "$BATS_TEST_FILENAME") forms
#   - `cd "$ROOT" && cat X.md` and globs
#   - tests/mocks/ is not scanned (only *.bats, *.py and helpers/*)
#   - reads done by scripts a test invokes, e.g. sync-agent-guidance.sh defaults
#     to the real CLAUDE.md when _OVERRIDE_CLAUDE_MD_PATH is unset
#   - BATS_TEST_DIRNAME inside a tests/helpers/ file: the scanner resolves it
#     against the helper's own directory, while at run time it is the calling
#     test's directory
#   - a recipe that builds a .md path from a variable is not seen
#
# The recipe scan is deliberately fail-closed rather than a parser: any .md
# named in a test-chain recipe fails (even `echo "see README.md"`), and any
# sub-make ($(MAKE), ${MAKE}, or make as a command word) fails whatever its
# flags or targets, because a sub-make has to be reviewed by hand for .md reads.

# awk regex for the text after `target:` that is a variable assignment
# (`t: VAR = x`, `t: VAR := x`, `t := x`) rather than a prerequisite list.
_ASSIGN_RE='^[ \t]*([^ \t:]+[ \t]*)?[:+?!]?='

# awk function shared by _rule_prereqs and _rule_recipe so both parse a rule
# line identically. rule_rest(line, target) returns the text after `target:` or
# `target::` and sets matched=1; for any other line it sets matched=0.
_AWK_RULE_FN='
  function rule_rest(line, t,   n, rest) {
    n = length(t)
    matched = 0
    if (substr(line, 1, n) != t) return ""
    rest = substr(line, n + 1)
    if (substr(rest, 1, 2) == "::") rest = substr(rest, 3)
    else if (substr(rest, 1, 1) == ":") rest = substr(rest, 2)
    else return ""
    matched = 1
    return rest
  }'

# Prints the prerequisites of every rule for target $2 in the make database
# dump $1. Order-only prerequisites (after |) are included: they still run.
# Handles `t::`, and skips variable assignments (`t: VAR = x`, `t := x`).
_rule_prereqs() {
  local _db="${1}" _target="${2}"
  printf '%s\n' "${_db}" | awk -v t="${_target}" -v asg="${_ASSIGN_RE}" "${_AWK_RULE_FN}"'
    {
      rest = rule_rest($0, t)
      if (!matched) next
      if (rest ~ asg) next
      gsub(/\|/, " ", rest)
      print rest
    }'
}

# Prints the recipe lines of every rule for target $2 in the database dump $1.
# Separate from _rule_prereqs because it is a stateful scan (recipe lines follow
# their rule line) while _rule_prereqs is a stateless per-line filter.
_rule_recipe() {
  local _db="${1}" _target="${2}"
  printf '%s\n' "${_db}" | awk -v t="${_target}" -v asg="${_ASSIGN_RE}" "${_AWK_RULE_FN}"'
    {
      rest = rule_rest($0, t)
      if (matched) {
        if (rest ~ asg) { in_r = 0; next }
        in_r = 1
        next
      }
      if (in_r && substr($0, 1, 1) == "\t") { print; next }
      if ($0 ~ /^#/) next
      in_r = 0
    }'
}

# _make_db <root>: print make's database dump for the test target. -q makes
# make exit 1 by design, so 0 and 1 are both a successful parse; 2 or more is
# a Makefile error and fails loudly with make's own message.
_make_db() {
  local _root="${1}" _out _rc _err="${BATS_TEST_TMPDIR}/make.err"
  _out="$(make --no-print-directory -C "${_root}" -pnq test 2>"${_err}")" && _rc=0 || _rc=$?
  if [[ "${_rc}" -ge 2 ]]; then
    printf 'FAIL: make exited %s reading %s/Makefile: %s\n' "${_rc}" "${_root}" "$(head -3 "${_err}" | tr '\n' ' ')" >&2
    return 1
  fi
  printf '%s\n' "${_out}"
}

# _recipe_violations <db> <target>: print one line per recipe problem. Fail
# closed: any .md named in the recipe, and any sub-make, whatever its flags.
_recipe_violations() {
  local _db="${1}" _t="${2}" _line
  local _md_re='\.md([^A-Za-z0-9]|$)'
  local _make_re='(^|[;&|])[[:space:]]*[@+-]*[[:space:]]*make([[:space:]]|$)'
  while IFS= read -r _line; do
    [[ -z "${_line}" ]] && continue
    if [[ "${_line}" =~ ${_md_re} ]]; then
      printf 'recipe of %s names a .md path: %s\n' "${_t}" "${_line}"
    fi
    if [[ "${_line}" == *'$(MAKE)'* || "${_line}" == *'${MAKE}'* || "${_line}" =~ ${_make_re} ]]; then
      printf 'recipe of %s runs a sub-make, which must be reviewed by hand for .md reads: %s\n' "${_t}" "${_line}"
    fi
  done < <(_rule_recipe "${_db}" "${_t}")
}

# _check_prereqs <root>: fail if the `make test` closure differs from
# ALLOWED_TEST_PREREQS, names a .md file, or has a recipe problem. File
# prerequisites are followed when they have their own rule.
_check_prereqs() {
  local _root="${1}" _db _queue=() _seen=" " _t _p _extra=() _fail=0 _v _a _ok
  _db="$(_make_db "${_root}")" || return 1
  # shellcheck disable=SC2207 # word-splitting is the point: one name per token
  _queue=($(_rule_prereqs "${_db}" test))
  _queue+=(test)
  while [[ ${#_queue[@]} -gt 0 ]]; do
    _t="${_queue[0]}"
    _queue=("${_queue[@]:1}")
    [[ "${_seen}" == *" ${_t} "* ]] && continue
    _seen+="${_t} "
    if [[ "${_t}" =~ \.md$ && "${_t}" != tests/* ]]; then
      printf 'FAIL: make test depends on the .md file %s\n' "${_t}" >&2
      _fail=1
    fi
    # shellcheck disable=SC2207 # word-splitting is the point
    for _p in $(_rule_prereqs "${_db}" "${_t}"); do
      _queue+=("${_p}")
    done
    while IFS= read -r _v; do
      [[ -z "${_v}" ]] && continue
      printf 'FAIL: %s\n' "${_v}" >&2
      _fail=1
    done < <(_recipe_violations "${_db}" "${_t}")
    [[ "${_t}" == test ]] && continue
    [[ -e "${_root}/${_t}" ]] && continue
    _ok=0
    for _a in "${ALLOWED_TEST_PREREQS[@]}"; do
      [[ "${_t}" == "${_a}" ]] && _ok=1
    done
    [[ "${_ok}" -eq 1 ]] || _extra+=("${_t}")
  done
  if [[ "${_seen}" == " test " ]]; then
    printf 'FAIL: empty make test prerequisite closure; the parse found nothing\n' >&2
    return 1
  fi
  if [[ ${#_extra[@]} -gt 0 ]]; then
    printf 'FAIL: make test gained prerequisite(s) not in ALLOWED_TEST_PREREQS: %s\n' "${_extra[*]}" >&2
    printf 'Check whether each reads a tracked .md; if not, add it to ALLOWED_TEST_PREREQS.\n' >&2
    printf 'check-agent-guidance is the known reader (it reads CLAUDE.md), so it must not be a prerequisite.\n' >&2
    _fail=1
  fi
  return "${_fail}"
}

# Pieces of the reader scanner's regexes (ERE). Each shows a string it matches.
_RE_BOUNDARY='(^|[^A-Za-z0-9_])\$?\{?'                       # ` "${` before a variable name
_RE_ROOT_VARS='_{0,2}(REPO_ROOT|REPO|ROOT|repo_root|REPO_DIR)' # _REPO, REPO_ROOT
_RE_VAR_END="\\}?[\"']?"                                       # `}"` closing the variable
_RE_AFTER_SLASH="[[:space:]]*[\"']?"                           # ` "` between the slash and the path
_RE_SEP="[[:space:]]*/${_RE_AFTER_SLASH}"                      # `/` or ` / "`
_RE_PATH_CHARS='[A-Za-z0-9_./-]'                               # a path character: `docs/x`
_RE_MD='\.md'                                                  # the .md suffix

# _normalize_path <a/b/../c>: collapse . and .. segments; a path that climbs
# above its start keeps a leading ../ so it can never read as under tests/.
_normalize_path() {
  local IFS=/ _seg _out=() _n
  for _seg in ${1}; do
    case "${_seg}" in
      '' | .) ;;
      ..)
        _n=${#_out[@]}
        if [[ "${_n}" -gt 0 && "${_out[$((_n - 1))]}" != .. ]]; then
          unset "_out[$((_n - 1))]"
          _out=("${_out[@]}")
        else
          _out+=(..)
        fi
        ;;
      *) _out+=("${_seg}") ;;
    esac
  done
  printf '%s' "${_out[*]}"
}

# _check_readers <root>: fail if a file under <root>/tests builds a path from a
# root variable that ends in .md and does not resolve under tests/.
# docs_inert_premise.bats is excluded: its own source names these patterns.
_check_readers() {
  local _root="${1}" _files _f _hits _grc _hit _rel _bad=0 _entry _allowed _n=0 _path _base _resolved
  local _re_root="${_RE_BOUNDARY}${_RE_ROOT_VARS}${_RE_VAR_END}${_RE_SEP}${_RE_PATH_CHARS}+${_RE_MD}"
  local _re_bats="${_RE_BOUNDARY}BATS_TEST_DIRNAME${_RE_VAR_END}/${_RE_PATH_CHARS}*${_RE_MD}"
  _files="$(find "${_root}/tests" -type f \( -name '*.bats' -o -name '*.py' -o -path '*/helpers/*' \) | sort)"
  while IFS= read -r _f; do
    [[ -z "${_f}" ]] && continue
    [[ "$(basename "${_f}")" == "docs_inert_premise.bats" ]] && continue
    _n=$((_n + 1))
    _rel="${_f#"${_root}"/}"
    _hits="$(grep -noE -e "${_re_root}" -e "${_re_bats}" "${_f}")" && _grc=0 || _grc=$?
    if [[ "${_grc}" -ge 2 ]]; then
      printf 'FAIL: could not scan %s (grep exit %s)\n' "${_rel}" "${_grc}" >&2
      _bad=1
      continue
    fi
    while IFS= read -r _hit; do
      [[ -z "${_hit}" ]] && continue
      # drop "LINE:" and everything up to the first "/", which follows the root variable
      _path="${_hit#*:}"
      _path="$(printf '%s' "${_path}" | sed -E "s/^[^/]*\/${_RE_AFTER_SLASH}//")"
      _base=""
      [[ "${_hit}" == *BATS_TEST_DIRNAME* ]] && _base="$(dirname "${_rel}")/"
      _resolved="$(_normalize_path "${_base}${_path}")"
      [[ "${_resolved}" == tests/* ]] && continue
      _allowed=0
      for _entry in "${ALLOWED_MD_READERS[@]}"; do
        [[ "${_entry%%|*}" == "${_rel}" ]] && _allowed=1
      done
      [[ "${_allowed}" -eq 1 ]] && continue
      printf 'FAIL: %s:%s reads tracked .md outside tests/: %s\n' "${_rel}" "${_hit%%:*}" "${_resolved}" >&2
      _bad=1
    done <<<"${_hits}"
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
  _db="$(_make_db "${REPO_ROOT}")"
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

@test "fixture: braced BATS_TEST_DIRNAME two levels up to CLAUDE.md fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests/scripts"
  printf 'cat "${BATS_TEST_DIRNAME}/../../CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/scripts/q.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/scripts/q.bats* ]]
}

@test "fixture: BATS_TEST_DIRNAME one level up from tests/ itself to README.md fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${BATS_TEST_DIRNAME}/../README.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/q.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/q.bats* ]]
}

@test "fixture: BATS_TEST_DIRNAME one level up from tests/scripts to a tests/ fixture passes" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests/scripts"
  printf 'cat "${BATS_TEST_DIRNAME}/../fixtures/a.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/scripts/q.bats"
  run -0 _check_readers "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: python _REPO / CLAUDE.md fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf '_X = _REPO / "CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/w.py"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/w.py* ]]
}

@test "fixture: root variable REPO reading CLAUDE.md fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${REPO}/CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/rv.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/rv.bats* ]]
}

@test "fixture: root variable ROOT reading CLAUDE.md fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${ROOT}/CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/rv.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/rv.bats* ]]
}

@test "fixture: root variable repo_root reading CLAUDE.md fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${repo_root}/CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/rv.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/rv.bats* ]]
}

@test "fixture: root variable REPO_DIR reading CLAUDE.md fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${REPO_DIR}/CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/rv.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/rv.bats* ]]
}

@test "fixture: a hyphenated path outside tests/ fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${REPO_ROOT}/docs/a-b.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/hy.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/hy.bats* ]]
}

@test "fixture: a path that climbs out of tests/ through .. fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'cat "${REPO_ROOT}/tests/../CLAUDE.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/v.bats"
  run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/v.bats* ]]
}

@test "fixture: DOTFILES_ROOT (a temp fixture dir, not the repo) is not a root variable" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests"
  printf 'OUT="${DOTFILES_ROOT}/features.md"\n' >"${BATS_TEST_TMPDIR}/fx/tests/u.bats"
  run -0 _check_readers "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: an unreadable test file fails loudly instead of hiding the read" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests" "${BATS_TEST_TMPDIR}/shim"
  printf 'true\n' >"${BATS_TEST_TMPDIR}/fx/tests/t.bats"
  printf '#!/bin/sh\nexit 2\n' >"${BATS_TEST_TMPDIR}/shim/grep"
  chmod +x "${BATS_TEST_TMPDIR}/shim/grep"
  PATH="${BATS_TEST_TMPDIR}/shim:${PATH}" run -1 _check_readers "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *tests/t.bats* ]]
}

@test "fixture: a .md prerequisite fails naming it" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint README.md"
  printf 'x\n' >"${BATS_TEST_TMPDIR}/fx/README.md"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *README.md* ]]
}

@test "fixture: a file prerequisite with its own rule is followed" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint stamp.txt"
  printf 'stamp.txt: check-agent-guidance\n' >>"${BATS_TEST_TMPDIR}/fx/Makefile"
  printf 'x\n' >"${BATS_TEST_TMPDIR}/fx/stamp.txt"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *check-agent-guidance* ]]
}

@test "fixture: a recipe invoking a sub-make on an unrecorded target fails" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@$(MAKE) check-agent-guidance')"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *check-agent-guidance* ]]
}

@test "fixture: a recipe invoking a sub-make on a recorded target fails" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@$(MAKE) lint')"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: a recipe naming a .md path fails" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@cat CLAUDE.md')"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *CLAUDE.md* ]]
}

@test "fixture: a Makefile that does not parse fails loudly" {
  mkdir -p "${BATS_TEST_TMPDIR}/fx"
  printf 'ifeq (a,a)\ntest: lint\nlint:\n\t@true\n' >"${BATS_TEST_TMPDIR}/fx/Makefile"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *"make exited"* ]]
}

@test "fixture: a target-specific variable on test is not a prerequisite" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint"
  printf 'test: JOBS = 5\n' >>"${BATS_TEST_TMPDIR}/fx/Makefile"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: a double-colon test rule is parsed and names the real prerequisite" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test:: lint check-agent-guidance"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *check-agent-guidance* ]]
  [[ "${output}" != *JOBS* && "${output}" != *"= "* ]]
}

@test "fixture: chained sub-makes in a recipe fail" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@$(MAKE) lint && $(MAKE) check-agent-guidance')"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *"sub-make"* ]]
}

@test "fixture: a sub-make on a recorded target fails too, whatever its flags" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@$(MAKE) -j 4 lint')"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *"sub-make"* ]]
}

@test "fixture: make as a bare command word after a separator fails" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@true; -make lint')"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *"sub-make"* ]]
}

@test "fixture: the word make inside a quoted string is not a sub-make" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@printf "make lint failed\\\\n"')"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: a recipe naming x.mdc is not a .md read" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@cat rules/x.mdc')"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: a recipe merely mentioning README.md fails (deliberately fail-closed)" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "$(printf 'test: lint\n\t@echo "see README.md"')"
  run -1 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
  [[ "${output}" == *README.md* ]]
}

@test "fixture: a .md prerequisite under tests/ is exempt" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint tests/fixtures/a.md"
  mkdir -p "${BATS_TEST_TMPDIR}/fx/tests/fixtures"
  printf 'x\n' >"${BATS_TEST_TMPDIR}/fx/tests/fixtures/a.md"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: an x.mdc prerequisite is not a .md file" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint x.mdc"
  printf 'x\n' >"${BATS_TEST_TMPDIR}/fx/x.mdc"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: a double-colon test rule with only recorded prerequisites passes" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test:: lint"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}

@test "fixture: a prerequisite that exists as a plain file is not an unrecorded target" {
  _fixture_makefile "${BATS_TEST_TMPDIR}/fx" "test: lint Makefile"
  run -0 _check_prereqs "${BATS_TEST_TMPDIR}/fx"
}
