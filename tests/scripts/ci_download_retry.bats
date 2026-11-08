#!/usr/bin/env bats
# Every third-party download in .github/workflows/ci.yml retries.
#
# The pinned downloads are correct by construction (exact version, `-f`, then
# `sha256sum -c` before anything runs), and that same construction made each
# one a hard dependency on the CDN answering at that instant: on dotfiles#207 a
# single `curl: (22) ... error: 503` failed the `test` job in 12 seconds,
# before any test ran. `--retry 3 --retry-all-errors` buys the availability
# back without touching integrity, since the checksum still gates execution.
#
# Downloads use curl only. wget's retry flags treat HTTP errors differently
# (`--tries` alone does not retry a 503), so one tool keeps one rule.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${REPO_ROOT}/.github/workflows/ci.yml"
}

# _downloads <workflow>: print one line per download command as
# `<job>:<line>:<tool>:OK` or `<job>:<line>:<tool>:MISSING <what>`.
# A download is a command whose first word (after an optional sudo) is curl or
# wget, at the start of a line or after `run:`, `;`, `&`, `|` or `(` (which
# covers `$(`). A trailing backslash joins the next line into the same
# command, so a flag on a continuation line counts. A `#` after whitespace
# starts a comment, so indented comment lines and trailing ` # ...` are
# ignored: a flag written only in a comment does not count.
_downloads() {
  awk '
    function finish(   miss) {
      if (tool == "wget") {
        miss = "use curl"
      } else {
        if (cmd !~ /--retry[ =][1-9]/) miss = miss " --retry<n>"
        if (cmd !~ /--retry-all-errors/) miss = miss " --retry-all-errors"
        if (cmd !~ /(^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--fail)([[:space:]]|$)/) miss = miss " -f"
        sub(/^ /, "", miss)
      }
      printf "%s:%d:%s:%s\n", job, start, tool, (miss == "" ? "OK" : "MISSING " miss)
      cont = 0
    }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); next }
    {
      line = $0
      sub(/[[:space:]]#.*$/, "", line)
      if (cont) {
        cmd = cmd " " line
      } else if (match(line, /(^|run:|[;&|(])[[:space:]]*(sudo[[:space:]]+)?(curl|wget)([[:space:]]|$)/)) {
        cmd = line; start = NR
        tool = (substr(line, RSTART, RLENGTH) ~ /wget/) ? "wget" : "curl"
      } else {
        next
      }
      if (line ~ /\\[[:space:]]*$/) { cont = 1 } else { finish() }
    }
  ' "$1"
}

@test "every download in ci.yml is curl with -f, --retry and --retry-all-errors" {
  run _downloads "${WF}"
  [ "$status" -eq 0 ]
  # Count, not membership: a parser that silently matched nothing would
  # otherwise pass. Six is the count when this test was written (2026-11-07);
  # removing a download is fine, so the floor only catches a broken parse.
  [ "$(printf '%s\n' "${output}" | command grep -c .)" -ge 6 ]
  local bad
  bad="$(printf '%s\n' "${output}" | command grep -v ':OK$' || true)"
  [ -z "${bad}" ] || { printf 'download without retry:\n%s\n' "${bad}"; false; }
}

@test "_downloads classifies a fixture: flags, continuation, wget, comments, non-downloads" {
  local fx="${BATS_TEST_TMPDIR}/wf.yml"
  cat > "${fx}" <<'YAML'
jobs:
  bare:
    steps:
      - run: |
          curl -fsSL -o /tmp/a "https://example.invalid/a"
  continued:
    steps:
      - run: |
          curl -fsSL -o /tmp/b \
            --retry 3 --retry-all-errors \
            "https://example.invalid/b"
  wgetjob:
    steps:
      - run: |
          wget -qO /tmp/c "https://example.invalid/c"
  notdownloads:
    steps:
      - run: |
          sudo apt-get install -y wget curl
          # curl -fsSL "https://example.invalid/commented"
  nofail:
    steps:
      - run: curl -sSL --retry 3 --retry-all-errors -o /tmp/d "https://example.invalid/d"
  subst:
    steps:
      - run: |
          X="$(curl -fsS --retry=2 --retry-all-errors "https://example.invalid/e")"
  zero:
    steps:
      - run: |
          sudo curl -fsSL --retry 0 --retry-all-errors -o /tmp/f "https://example.invalid/f"
  commented:
    steps:
      - run: |
          curl -fsSL -o /tmp/g "https://example.invalid/g" # --retry 3 --retry-all-errors
  chained:
    steps:
      - run: |
          apt-get update && curl -fsSL -o /tmp/h "https://example.invalid/h"
          true; curl -fsSL -o /tmp/i "https://example.invalid/i"
          printf x | curl -fsSL -K - -o /tmp/j "https://example.invalid/j"
YAML
  run _downloads "${fx}"
  [ "$status" -eq 0 ]
  printf '%s\n' "${output}"
  [ "${output}" = "bare:5:curl:MISSING --retry<n> --retry-all-errors
continued:9:curl:OK
wgetjob:15:wget:MISSING use curl
nofail:23:curl:MISSING -f
subst:27:curl:OK
zero:31:curl:MISSING --retry<n>
commented:35:curl:MISSING --retry<n> --retry-all-errors
chained:39:curl:MISSING --retry<n> --retry-all-errors
chained:40:curl:MISSING --retry<n> --retry-all-errors
chained:41:curl:MISSING --retry<n> --retry-all-errors" ]
}
