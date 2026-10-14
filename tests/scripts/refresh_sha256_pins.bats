#!/usr/bin/env bats
#
# Tests for scripts/refresh-sha256-pins.sh. The script runs as its own process
# against a COPY of lib/constants.sh and talks to a one-shot local listener
# standing in for the GitHub releases API, so no test reads the real constants
# file for writing or reaches the network. The listener serves one request per
# start, so every case makes at most one API call.

bats_require_minimum_version 1.5.0

DA="1111111111111111111111111111111111111111111111111111111111111111"
DB="2222222222222222222222222222222222222222222222222222222222222222"
OLD="3333333333333333333333333333333333333333333333333333333333333333"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/refresh-sha256-pins.sh"
  source "${REPO_ROOT}/tests/helpers/http_listener.bash"
  C="${BATS_TEST_TMPDIR}/constants.sh"
  sed -E 's/^(KIND|YQ|SHELLCHECK)_VER=.*/\1_VER="1.2.3"/' "${REPO_ROOT}/lib/constants.sh" >"${C}"
  export GITHUB_TOKEN=""
  unset _REFRESH_ASSET_URL HTTP_LISTENER_STATUS
  export HTTP_LISTENER_BODY_FILE="${BATS_TEST_TMPDIR}/release.json"
  _release_json kind-linux-amd64 "sha256:${DA}" kind-linux-arm64 "sha256:${DB}"
}

teardown() {
  stop_http_listener
}

# _release_json <name> <digest> [<name> <digest>...] -- "-" omits the digest field.
_release_json() {
  python3 -I - "${HTTP_LISTENER_BODY_FILE}" "$@" <<'PY'
import json, sys
out, rest = sys.argv[1], sys.argv[2:]
assets = []
for name, digest in zip(rest[0::2], rest[1::2]):
    a = {"name": name}
    if digest != "-":
        a["digest"] = digest
    assets.append(a)
json.dump({"assets": assets}, open(out, "w"))
PY
}

_listen() {
  start_http_listener "${BATS_TEST_TMPDIR}"
  export _GITHUB_API="${HTTP_LISTENER_URL}"
}

_val() { # <VAR> -- value of VAR="..." in the constants copy
  sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "${C}"
}

_snapshot() { cp -p "${C}" "${BATS_TEST_TMPDIR}/before"; }
_unchanged() { cmp "${C}" "${BATS_TEST_TMPDIR}/before"; }

@test "stale tool: writes both arch digests and _FOR_VER to the right variables" {
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  [ "$(_val KIND_SHA256_AMD64)" = "${DA}" ]
  [ "$(_val KIND_SHA256_ARM64)" = "${DB}" ]
  [ "$(_val KIND_SHA256_FOR_VER)" = "1.2.3" ]
  [[ "$output" == *"querying https://github.com/kubernetes-sigs/kind/releases/download/v1.2.3/kind-linux-amd64"* ]]
  [[ "$output" == *"querying https://github.com/kubernetes-sigs/kind/releases/download/v1.2.3/kind-linux-arm64"* ]]
  [[ "$output" == *"KIND_SHA256_AMD64 "*" -> ${DA}"* ]]
  [[ "$output" == *"KIND_SHA256_FOR_VER  -> 1.2.3"* ]]
  [ "$(<"${HTTP_LISTENER_PATHS}")" = "/repos/kubernetes-sigs/kind/releases/tags/v1.2.3" ]
}

@test "write leaves the other lines of the file untouched and keeps the mode" {
  _listen
  chmod 640 "${C}"
  cp -p "${C}" "${BATS_TEST_TMPDIR}/before"
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  [ "$(diff "${BATS_TEST_TMPDIR}/before" "${C}" | grep -c '^>')" -eq 3 ]
  [ "$(stat -c %a "${C}" 2>/dev/null || stat -f %Lp "${C}")" = 640 ]
  run ! compgen -G "${BATS_TEST_TMPDIR}/.refresh-pins.*" >/dev/null
}

@test "a second run is a no-op: pins up to date, no request, file unchanged" {
  sed -i.bak 's/^YQ_SHA256_FOR_VER=.*/YQ_SHA256_FOR_VER="1.2.3"/; s/^SHELLCHECK_SHA256_FOR_VER=.*/SHELLCHECK_SHA256_FOR_VER="1.2.3"/' "${C}"
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  _snapshot
  rm -f "${HTTP_LISTENER_PATHS}"
  run "${SCRIPT}" --constants "${C}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pins up to date"* ]]
  [ ! -e "${HTTP_LISTENER_PATHS}" ]
  _unchanged
}

@test "default selects only the stale tool" {
  sed -i.bak 's/^YQ_SHA256_FOR_VER=.*/YQ_SHA256_FOR_VER="1.2.3"/; s/^SHELLCHECK_SHA256_FOR_VER=.*/SHELLCHECK_SHA256_FOR_VER="1.2.3"/' "${C}"
  _listen
  run "${SCRIPT}" --constants "${C}"
  [ "$status" -eq 0 ]
  [ "$(<"${HTTP_LISTENER_PATHS}")" = "/repos/kubernetes-sigs/kind/releases/tags/v1.2.3" ]
  [[ "$output" != *"mikefarah"* ]]
  [[ "$output" != *"koalaman"* ]]
}

@test "yq and shellcheck URLs and asset names are looked up" {
  _release_json yq_linux_amd64 "sha256:${DA}" yq_linux_arm64 "sha256:${DB}"
  _listen
  run "${SCRIPT}" --constants "${C}" yq
  [ "$status" -eq 0 ]
  [ "$(_val YQ_SHA256_AMD64)" = "${DA}" ]
  [ "$(<"${HTTP_LISTENER_PATHS}")" = "/repos/mikefarah/yq/releases/tags/v1.2.3" ]
}

@test "shellcheck resolves its tar.xz asset names per arch" {
  _release_json shellcheck-v1.2.3.linux.x86_64.tar.xz "sha256:${DA}" shellcheck-v1.2.3.linux.aarch64.tar.xz "sha256:${DB}"
  _listen
  run "${SCRIPT}" --constants "${C}" shellcheck
  [ "$status" -eq 0 ]
  [ "$(_val SHELLCHECK_SHA256_AMD64)" = "${DA}" ]
  [ "$(_val SHELLCHECK_SHA256_ARM64)" = "${DB}" ]
}

@test "changed digest at an unchanged version is refused and writes nothing" {
  sed -i.bak "s/^KIND_SHA256_FOR_VER=.*/KIND_SHA256_FOR_VER=\"1.2.3\"/; s/^KIND_SHA256_AMD64=.*/KIND_SHA256_AMD64=\"${OLD}\"/" "${C}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: amd64 asset changed at unchanged version 1.2.3: pin ${OLD}, API ${DA}"* ]]
  _unchanged
}

@test "--accept-changed lets a changed digest at an unchanged version through" {
  sed -i.bak "s/^KIND_SHA256_FOR_VER=.*/KIND_SHA256_FOR_VER=\"1.2.3\"/; s/^KIND_SHA256_AMD64=.*/KIND_SHA256_AMD64=\"${OLD}\"/" "${C}"
  _listen
  run "${SCRIPT}" --constants "${C}" --accept-changed kind
  [ "$status" -eq 0 ]
  [ "$(_val KIND_SHA256_AMD64)" = "${DA}" ]
}

@test "an unchanged digest at an unchanged version is not a refusal" {
  sed -i.bak "s/^KIND_SHA256_FOR_VER=.*/KIND_SHA256_FOR_VER=\"1.2.3\"/; s/^KIND_SHA256_AMD64=.*/KIND_SHA256_AMD64=\"${DA}\"/; s/^KIND_SHA256_ARM64=.*/KIND_SHA256_ARM64=\"${DB}\"/" "${C}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  _unchanged
}

@test "missing pin line: names the variable, never appends, no request" {
  sed -i.bak '/^KIND_SHA256_ARM64=/d' "${C}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: KIND_SHA256_ARM64 line missing in ${C}; add it, then re-run"* ]]
  _unchanged
  [ ! -e "${HTTP_LISTENER_PATHS}" ]
}

@test "empty *_VER is refused before any request" {
  sed -i.bak 's/^KIND_VER=.*/KIND_VER=""/' "${C}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: KIND_VER is empty in ${C}"* ]]
  _unchanged
  [ ! -e "${HTTP_LISTENER_PATHS}" ]
}

@test "a URL that is not a GitHub release asset is refused" {
  _snapshot
  _listen
  _REFRESH_ASSET_URL="https://example.invalid/x" run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: https://example.invalid/x is not a GitHub release asset URL"* ]]
  _unchanged
}

@test "the URL override is ignored outside bats" {
  _listen
  run env -u BATS_TEST_TMPDIR _REFRESH_ASSET_URL="https://example.invalid/x" "${SCRIPT}" --constants "${C}" kind
  [[ "$output" != *"example.invalid"* ]]
  [[ "$output" == *"querying https://github.com/kubernetes-sigs/kind/"* ]]
}

@test "asset with no digest field is refused" {
  _release_json kind-linux-amd64 - kind-linux-arm64 "sha256:${DB}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: amd64: no usable sha256 digest for kind-linux-amd64 (got '')"* ]]
  _unchanged
}

@test "asset missing from the release is refused" {
  _release_json other-asset "sha256:${DA}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"no usable sha256 digest for kind-linux-amd64"* ]]
  _unchanged
}

@test "a non-sha256 digest is refused" {
  _release_json kind-linux-amd64 "md5:${DA}" kind-linux-arm64 "sha256:${DB}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"(got 'md5:${DA}')"* ]]
  _unchanged
}

@test "a sha256 digest that is not 64 hex is refused" {
  _release_json kind-linux-amd64 "sha256:abc" kind-linux-arm64 "sha256:${DB}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"(got 'sha256:abc')"* ]]
  _unchanged
}

@test "a body that is not JSON is refused as no usable digest" {
  printf 'not json' >"${HTTP_LISTENER_BODY_FILE}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"no usable sha256 digest"* ]]
  _unchanged
}

@test "API 403 names the status, the URL and the token hint" {
  export HTTP_LISTENER_STATUS=403
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: GitHub API returned 403 for ${HTTP_LISTENER_URL}/repos/kubernetes-sigs/kind/releases/tags/v1.2.3"* ]]
  [[ "$output" == *"set GITHUB_TOKEN (unauthenticated: 60 requests/hour)"* ]]
  _unchanged
}

@test "API 404 carries no token hint" {
  export HTTP_LISTENER_STATUS=404
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub API returned 404"* ]]
  [[ "$output" != *"GITHUB_TOKEN"* ]]
  _unchanged
}

@test "GITHUB_TOKEN is sent as a bearer header, not on argv" {
  export GITHUB_TOKEN="tok-abc123"
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  grep -q 'Authorization: Bearer tok-abc123' "${HTTP_LISTENER_HEADERS}"
}

@test "no GITHUB_TOKEN sends no Authorization header" {
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  run ! grep -qi '^Authorization:' "${HTTP_LISTENER_HEADERS}"
}

@test "a token with a line break is refused and nothing is requested" {
  export GITHUB_TOKEN=$'tok\nX-Evil: 1'
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"line break"* ]]
  _unchanged
  [ ! -e "${HTTP_LISTENER_PATHS}" ]
}

@test "read-back failure: names the variable, removes its copy, target unchanged" {
  sed -i.bak "s/^KIND_SHA256_AMD64=.*/KIND_SHA256_AMD64='${OLD}'/" "${C}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: amd64: read-back failed for KIND_SHA256_AMD64"* ]]
  _unchanged
  run ! compgen -G "${BATS_TEST_TMPDIR}/.refresh-pins.*" >/dev/null
}

@test "unknown option and unknown tool exit 2 with usage" {
  run "${SCRIPT}" --constants "${C}" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  run "${SCRIPT}" --constants "${C}" vagrant
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "--constants without a value, or a missing file, fails without writing" {
  run "${SCRIPT}" --constants
  [ "$status" -eq 2 ]
  run "${SCRIPT}" --constants "${BATS_TEST_TMPDIR}/nope.sh" kind
  [ "$status" -eq 1 ]
}

@test "a *_VER with characters outside the safe set is refused before any request" {
  sed -i.bak 's/^KIND_VER=.*/KIND_VER="1.2.3\&x"/' "${C}"
  _snapshot
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"kind: KIND_VER has characters outside [A-Za-z0-9.+-] in ${C}"* ]]
  _unchanged
  [ ! -e "${HTTP_LISTENER_PATHS}" ]
}

# _curl_shim -- puts a curl on PATH that logs its argv, then execs the real one.
_curl_shim() {
  local _real shim="${BATS_TEST_TMPDIR}/shim"
  _real="$(command -v curl)"
  mkdir -p "${shim}"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >>"%s"\nexec "%s" "$@"\n' \
    "${BATS_TEST_TMPDIR}/curl-argv" "${_real}" >"${shim}/curl"
  chmod +x "${shim}/curl"
  PATH="${shim}:${PATH}"
}

@test "the token reaches curl on stdin only: absent from argv, present in the header" {
  export GITHUB_TOKEN="tok-secret-777"
  _curl_shim
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  # Positive control: the shim really saw the call.
  grep -q 'releases/tags/v1.2.3' "${BATS_TEST_TMPDIR}/curl-argv"
  run ! grep -q 'tok-secret-777' "${BATS_TEST_TMPDIR}/curl-argv"
  grep -q 'Authorization: Bearer tok-secret-777' "${HTTP_LISTENER_HEADERS}"
}

@test "proxy environment variables do not divert the loopback API call" {
  unset no_proxy NO_PROXY
  export http_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9
  export https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  [ "$(<"${HTTP_LISTENER_PATHS}")" = "/repos/kubernetes-sigs/kind/releases/tags/v1.2.3" ]
}

@test "proxy environment variables do not divert the token-bearing API call" {
  unset no_proxy NO_PROXY
  export http_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9
  export https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9
  export GITHUB_TOKEN="tok-proxy-555"
  _listen
  run "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 0 ]
  [ "$(<"${HTTP_LISTENER_PATHS}")" = "/repos/kubernetes-sigs/kind/releases/tags/v1.2.3" ]
  grep -q 'Authorization: Bearer tok-proxy-555' "${HTTP_LISTENER_HEADERS}"
}

@test "a symlinked --constants target is refused and left alone" {
  local real="${BATS_TEST_TMPDIR}/real.sh" link="${BATS_TEST_TMPDIR}/link.sh"
  mv "${C}" "${real}"
  ln -s "${real}" "${link}"
  cp -p "${real}" "${BATS_TEST_TMPDIR}/before"
  _listen
  run "${SCRIPT}" --constants "${link}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"${link} is a symlink; pass the real file"* ]]
  [ -L "${link}" ]
  cmp "${real}" "${BATS_TEST_TMPDIR}/before"
  [ ! -e "${HTTP_LISTENER_PATHS}" ]
}

@test "missing python3 is reported as such, before any request" {
  local shim="${BATS_TEST_TMPDIR}/nopy" b p
  mkdir -p "${shim}"
  for b in bash env sed grep cp mv rm mktemp dirname basename cut curl cat tr sort uname date head tail awk ls chmod mkdir sleep stat; do
    p="$(command -v "${b}" 2>/dev/null)" || continue
    [[ "${p}" == /* ]] && ln -sf "${p}" "${shim}/${b}"
  done
  [ ! -e "${shim}/python3" ]
  _snapshot
  _listen
  run env PATH="${shim}" "${SCRIPT}" --constants "${C}" kind
  [ "$status" -eq 1 ]
  [[ "$output" == *"python3 not found; it parses the GitHub API response"* ]]
  _unchanged
  [ ! -e "${HTTP_LISTENER_PATHS}" ]
}

@test "a tool named twice is processed once" {
  _listen
  run "${SCRIPT}" --constants "${C}" kind kind
  [ "$status" -eq 0 ]
  [ "$(wc -l <"${HTTP_LISTENER_PATHS}" | tr -d ' ')" -eq 1 ]
}

@test "SIGTERM mid-request: exits 143 and leaves no temp file once curl has finished" {
  local tmpd="${BATS_TEST_TMPDIR}/tmpd" shim="${BATS_TEST_TMPDIR}/slow" real pid rc=0
  mkdir -p "${tmpd}" "${shim}"
  real="$(command -v curl)"
  # The shim signals readiness through a file, then lingers so the signal lands
  # while the request is in flight; its exec'd curl then writes the body file.
  printf '#!/usr/bin/env bash\ntouch "%s/ready"\nsleep 1\nexec "%s" "$@"\n' "${BATS_TEST_TMPDIR}" "${real}" >"${shim}/curl"
  chmod +x "${shim}/curl"
  _listen
  TMPDIR="${tmpd}" PATH="${shim}:${PATH}" "${SCRIPT}" --constants "${C}" kind >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 200); do
    [[ -e "${BATS_TEST_TMPDIR}/ready" ]] && break
    sleep 0.05
  done
  # Positive controls: the request was in flight and its body file existed.
  [ -e "${BATS_TEST_TMPDIR}/ready" ]
  compgen -G "${tmpd}/refresh-pins-body.*" >/dev/null
  kill -TERM "${pid}"
  wait "${pid}" || rc=$?
  [ "${rc}" -eq 143 ]
  # The orphaned curl may outlive the script; wait for every process of this test.
  for _ in $(seq 200); do
    pgrep -f "${BATS_TEST_TMPDIR}/(tmpd|slow)" >/dev/null || break
    sleep 0.05
  done
  run ! pgrep -f "${BATS_TEST_TMPDIR}/(tmpd|slow)"
  run ! compgen -G "${tmpd}/refresh-pins-body.*"
  run ! compgen -G "${tmpd}/.refresh-pins.*"
}
