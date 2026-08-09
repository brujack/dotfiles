#!/usr/bin/env bats

# Tests for scripts/html2ascii.sh
#
# tests/scripts/unit.bats already covers the happy-path tag/entity stripping,
# stdin vs file-argument input, -h/--help, and the nonexistent-file error
# path. This file adds the mandatory boundary, error-path, and
# state-transition categories that unit.bats does not exercise: empty input,
# malformed/unterminated tags (the exact case the sed patterns on lines 30
# and 41 are written to handle), the embedded-apostrophe-vs-leading/trailing-
# quote distinction called out in the script's own comment, a directory
# passed as the file argument (a different `cat` failure mode than
# nonexistent-file), and idempotency (running the tool's own output back
# through itself is a no-op, since no HTML remains after the first pass).

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

# ── boundary: empty input ────────────────────────────────────────────────────

@test "html2ascii.sh: empty stdin produces empty output and exits 0" {
  run bash -c "printf '' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [ -z "${output}" ]
}

# ── boundary: malformed / unterminated tags ──────────────────────────────────
# The tag-stripping sed has three patterns specifically for boundary cases:
# a normal <tag>, an unterminated tag at end of input (<[^>]*$), and a
# dangling close with no opener at start of input (^[^>]*>). None of the
# existing tests exercise the latter two.

@test "html2ascii.sh: strips a tag left unterminated at end of input" {
  run bash -c "printf 'before <div class=x' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"before"* ]]
  [[ "${output}" != *"<div"* ]]
}

@test "html2ascii.sh: strips a dangling close tag at start of input" {
  run bash -c "printf 'span> after text' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"after"* ]]
  [[ "${output}" != *"span>"* ]]
}

@test "html2ascii.sh: strips multiple sequential tags in one line" {
  run bash -c "printf '<b><i>word</i></b>\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"word"* ]]
  [[ "${output}" != *"<"* ]]
  [[ "${output}" != *">"* ]]
}

# ── boundary: quote / apostrophe handling ────────────────────────────────────
# The script's own comment (lines 39-40) distinguishes stray leading/trailing
# quote characters (stripped) from an apostrophe embedded mid-word, e.g.
# "John's" (preserved). Neither unit.bats nor the tests above exercise this.

@test "html2ascii.sh: strips a leading quote from a token" {
  run bash -c "printf '\"quoted word\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"quoted"* ]]
  [[ "${output}" != *'"'* ]]
}

@test "html2ascii.sh: preserves an apostrophe embedded mid-word" {
  run bash -c "printf \"John's book\\n\" | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"John's"* ]]
}

# ── error path: directory passed as the file argument ───────────────────────
# unit.bats covers a nonexistent file ("No such file or directory"). A
# directory is a different `cat` failure mode ("Is a directory") that still
# must not crash or hang the script.

@test "html2ascii.sh: a directory argument exits 0, surfacing cat's error" {
  run bash "${REPO_ROOT}/scripts/html2ascii.sh" "${BATS_TEST_TMPDIR}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Is a directory"* ]]
}

# ── state transition: idempotency ────────────────────────────────────────────
# Property: once HTML tags/entities are stripped and the result is tokenized,
# feeding that output back through the script a second time must be a no-op —
# there is no more markup left to strip or entities left to replace.

@test "html2ascii.sh: running its own output back through itself is idempotent" {
  local _first _second
  _first="$(printf '<p>a&auml;b</p>\n' | bash "${REPO_ROOT}/scripts/html2ascii.sh")"
  _second="$(printf '%s' "${_first}" | bash "${REPO_ROOT}/scripts/html2ascii.sh")"
  [ "${_first}" = "${_second}" ]
}
