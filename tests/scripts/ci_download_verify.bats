#!/usr/bin/env bats
# Every third-party download in .github/workflows/ci.yml is verified, in the
# same step, before anything uses it.
#
# ci-002: a direct download is pinned and checksum-verified before it runs.
# The steps fetching shellcheck and uv always were; the secret-scan step
# extracted and ran gitleaks unverified, and the powershell job `dpkg -i`d
# packages-microsoft-prod.deb -- Microsoft's apt signing key, installed as root
# -- unverified. A verifier is `sha256sum -c` (`shasum -a 256 -c` on the macOS
# jobs), scripts/verify-release-asset.sh or scripts/verify-ms-deb.sh, on a later line
# of the same step: a verifier in the next step runs after the step that used
# the file has already finished.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${REPO_ROOT}/.github/workflows/ci.yml"
}

# _verified <workflow>: one line per download, `<job>:<line>:VERIFIED <n>` with
# the line of the first verifier after it in the same step, or
# `<job>:<line>:UNVERIFIED`. A step starts at a `      - ` line; a job at a
# two-space key. Downloads are found as in ci_download_retry.bats.
_verified() {
  awk '
    function flush(   i) {
      for (i = 1; i <= n; i++) {
        printf "%s:%d:%s\n", djob[i], dline[i], (vline[i] ? "VERIFIED " vline[i] : "UNVERIFIED")
      }
      n = 0
    }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); next }
    /^      - / { flush() }
    {
      line = $0
      sub(/[[:space:]]#.*$/, "", line)
      if (line ~ /sha256sum -c|shasum -a 256 -c|scripts\/verify-release-asset\.sh|scripts\/verify-ms-deb\.sh/) {
        for (i = 1; i <= n; i++) if (!vline[i]) vline[i] = NR
      }
      if (line ~ /(^|run:|[;&|(])[[:space:]]*(sudo[[:space:]]+)?(curl|wget)([[:space:]]|$)/) {
        n++; djob[n] = job; dline[n] = NR; vline[n] = 0
      }
    }
    END { flush() }
  ' "$1"
}

@test "every download in ci.yml is verified later in its own step" {
  run _verified "${WF}"
  [ "$status" -eq 0 ]
  # Count, not membership: a parser that matched nothing would otherwise pass.
  [ "$(printf '%s\n' "${output}" | command grep -c .)" -ge 6 ]
  local bad
  bad="$(printf '%s\n' "${output}" | command grep ':UNVERIFIED$' || true)"
  [ -z "${bad}" ] || { printf 'download used unverified:\n%s\n' "${bad}"; false; }
}

@test "gitleaks is verified against its pin and the Microsoft .deb by signature" {
  # The two verifiers this suite exists for, named so a generic sha256sum -c
  # line cannot stand in for either.
  run awk '/- name: Install gitleaks/,/sudo mv/' "${WF}"
  [[ "$output" == *"bash scripts/verify-release-asset.sh gitleaks amd64 /tmp/gitleaks.tar.gz"* ]]
  run awk '/- name: Install PowerShell/,/apt-get install -y powershell/' "${WF}"
  [[ "$output" == *"bash scripts/verify-ms-deb.sh packages-microsoft-prod.deb"* ]]
  # and the verifier precedes the dpkg -i that installs the key
  local v d
  v="$(command grep -n 'scripts/verify-ms-deb.sh' "${WF}" | cut -d: -f1)"
  d="$(command grep -n 'dpkg -i packages-microsoft-prod.deb' "${WF}" | cut -d: -f1)"
  [ -n "${v}" ] && [ -n "${d}" ] && [ "${v}" -lt "${d}" ]
}

@test "_verified classifies a fixture: same step, order, step and job boundaries" {
  local fx="${BATS_TEST_TMPDIR}/wf.yml"
  cat >"${fx}" <<'YAML'
jobs:
  good:
    steps:
      - run: |
          curl -fsSL -o /tmp/a "https://example.invalid/a"
          echo "x  /tmp/a" | sha256sum -c -
  before:
    steps:
      - run: |
          echo "x  /tmp/b" | sha256sum -c -
          curl -fsSL -o /tmp/b "https://example.invalid/b"
  nextstep:
    steps:
      - run: curl -fsSL -o /tmp/c "https://example.invalid/c"
      - run: bash scripts/verify-release-asset.sh kind amd64 /tmp/c
  msdeb:
    steps:
      - run: |
          curl -fsSL -O "https://example.invalid/d.deb"
          bash scripts/verify-ms-deb.sh d.deb # verified
  commented:
    steps:
      - run: |
          curl -fsSL -o /tmp/e "https://example.invalid/e"
          tar -xzf /tmp/e # sha256sum -c is not here
  nextjob:
    steps:
      - run: |
          curl -fsSL -o /tmp/f "https://example.invalid/f"
  verifier:
    steps:
      - run: |
          echo "x  /tmp/f" | sha256sum -c -
  macos:
    steps:
      - run: |
          curl -fsSL -o /tmp/g "https://example.invalid/g"
          echo "x  /tmp/g" | shasum -a 256 -c -
YAML
  run _verified "${fx}"
  [ "$status" -eq 0 ]
  printf '%s\n' "${output}"
  [ "${output}" = "good:5:VERIFIED 6
before:11:UNVERIFIED
nextstep:14:UNVERIFIED
msdeb:19:VERIFIED 20
commented:24:UNVERIFIED
nextjob:29:UNVERIFIED
macos:37:VERIFIED 38" ]
}
