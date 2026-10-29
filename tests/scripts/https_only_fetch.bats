#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# A curl that follows redirects (-L) follows them to any protocol curl
# supports, so an https URL answered with a redirect to plain http hands the
# body to anyone on the path. Every redirect-following curl in tracked shell
# code must carry `--proto '=https' --proto-redir '=https'`. Sites whose body
# is sha256- or fingerprint-checked would only fail closed; the ones that are
# not (an apt source list, an executed install script) are the reason for
# the gate, and the rule is kept uniform so a new site cannot pick wrong.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
}

# _curl_redirect_sites FILE... -- one "file:line<TAB>ok|missing" row per
# non-comment command that runs curl, or a variable whose name holds "curl"
# ("${_curl}"), with -L (in any short-option cluster) or --location.
# Backslash-continued lines are joined first and reported at their first line,
# so flags split across lines are still seen. "ok" means both https-only flags
# are on the command. Not seen: options built into an array beforehand.
_curl_redirect_sites() {
  awk '
    function check(file, line, text,   q, ok) {
      if (text ~ /^[[:space:]]*#/) return
      if (text !~ /(^|[^A-Za-z0-9_])(curl|[$][{]?[A-Za-z0-9_]*[Cc][Uu][Rr][Ll][A-Za-z0-9_]*[}]?"?)[[:space:]]/) return
      if (text !~ /[[:space:]]-[A-Za-z]*L[A-Za-z]*([[:space:]]|$)/ && text !~ /--location/) return
      # The value must be quoted: zsh expands an unquoted =https to the path of
      # a command named https (httpie ships one), and a remedy line is pasted
      # into zsh. Octal \047 for the single quote, as POSIX awk specifies.
      q = "[\"\047]"
      ok = (text ~ ("--proto[[:space:]]+" q "=https" q) && text ~ ("--proto-redir[[:space:]]+" q "=https" q))
      printf "%s:%d\t%s\n", file, line, (ok ? "ok" : "missing")
    }
    FNR == 1 && buf != "" { check(bfile, bline, buf); buf = "" }
    {
      if (buf == "") { bfile = FILENAME; bline = FNR }
      l = $0
      if (l ~ /\\$/) { sub(/\\$/, "", l); buf = buf l " "; next }
      check(bfile, bline, buf l)
      buf = ""
    }
    END { if (buf != "") check(bfile, bline, buf) }
  ' "$@"
}

_tracked_shell_outside_tests() {
  (cd "${REPO_ROOT}" && bash scripts/list-shell-files.sh) | tr ' ' '\n' | grep -v '^tests/' | grep .
}

@test "every redirect-following curl in tracked shell code is https-only" {
  local -a _files=()
  local _f
  while IFS= read -r _f; do _files+=("${REPO_ROOT}/${_f}"); done < <(_tracked_shell_outside_tests)
  [ "${#_files[@]}" -gt 0 ]
  run _curl_redirect_sites "${_files[@]}"
  [ "$status" -eq 0 ]
  # A count, not membership: a scanner that silently stops matching must go
  # red here rather than report zero violations over zero sites. 11 sites
  # existed when the gate was added. The floor catches a broken scanner, not
  # a site that was removed or left the shebang scope.
  [ "$(printf '%s\n' "$output" | command grep -c .)" -ge 11 ]
  [[ "$output" != *$'\t'missing* ]]
}

@test "the scanner flags a redirect-following curl without the https-only flags" {
  local _fx="${BATS_TEST_TMPDIR}/fixture.sh"
  cat > "${_fx}" << 'EOF'
#!/usr/bin/env bash
# curl -fsSL https://example.invalid/commented-out
curl -fsSL -o out https://example.invalid/a
curl --proto '=https' --proto-redir '=https' -fsSL -o out https://example.invalid/b
curl --proto '=https' -fsSL https://example.invalid/c
curl -fLo out https://example.invalid/d
curl --location https://example.invalid/e
curl --proto =https --proto-redir =https -fsSL https://example.invalid/unquoted
printf '%s\n' 'paste: curl --proto "=https" --proto-redir "=https" -fsSL https://example.invalid/f'
curl -fsS https://example.invalid/no-redirect
"${_curl}" -fsSL https://example.invalid/var-invoked
local _curl="${_RHN_CURL_BIN:-curl}"
curl --proto '=https' --proto-redir '=https' \
  -fsSL https://example.invalid/continued-ok
curl \
  -fsSL https://example.invalid/continued-missing
echo trailing; curl -fsSL
EOF
  run _curl_redirect_sites "${_fx}"
  [ "$status" -eq 0 ]
  [ "$output" = "${_fx}:3	missing
${_fx}:4	ok
${_fx}:5	missing
${_fx}:6	missing
${_fx}:7	missing
${_fx}:8	missing
${_fx}:9	ok
${_fx}:11	missing
${_fx}:13	ok
${_fx}:15	missing
${_fx}:17	missing" ]
}
