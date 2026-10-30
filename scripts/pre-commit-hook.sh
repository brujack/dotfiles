#!/usr/bin/env bash
# pre-commit hook: lint + secrets scan
cd "$(git rev-parse --show-toplevel)" || exit 1

make lint || exit 1

# ggshield is resolved by explicit override, then PATH, then absolute prefixes
# -- deliberately not by `command -v` alone.
#
# A git hook is not an actor of its own: it inherits whoever invoked git. On the
# Linux workstation, Homebrew's prefix reaches PATH only through
# .config/.zshrc.d/6_path.zsh, which INTERACTIVE zsh alone sources. Measured
# 2026-08-21 on that machine -- ggshield is installed and authenticated at
# /home/linuxbrew/.linuxbrew/bin/ggshield, and:
#
#   zsh -i -c            /home/linuxbrew/.linuxbrew/bin/ggshield
#   zsh -l -c            NOT-ON-PATH
#   ssh host 'cmd'       NOT-ON-PATH
#   env -i sh            NOT-ON-PATH
#
# So under the previous bare `command -v` guard the secret scan ran from a
# terminal and silently did not run for cron, editor-spawned git, or
# `ssh host 'git commit'`. The gate was not absent, it was invisible -- which is
# the worse of the two for a security arm, because silence is indistinguishable
# from "scanned and found nothing".
_ggshield=""
if [[ -n "${GGSHIELD_BIN:-}" ]]; then
  # An explicit override that does not resolve is an operator error, not an
  # absent tool: fail rather than degrade into the announce-and-continue path
  # below, which would silently ignore what the operator asked for.
  if [[ ! -x "${GGSHIELD_BIN}" ]]; then
    printf 'pre-commit: GGSHIELD_BIN is set to "%s" but that is not executable\n' \
      "${GGSHIELD_BIN}" >&2
    exit 1
  fi
  _ggshield="${GGSHIELD_BIN}"
else
  _ggshield="$(command -v ggshield 2>/dev/null)"
  if [[ -z "${_ggshield}" ]]; then
    # Word-splitting is the point: this is a space-separated candidate list.
    # It is env-settable so a test can reach the genuinely-not-found branch --
    # on any machine that HAS ggshield the hardcoded prefixes always resolve,
    # which makes that branch otherwise untestable. GGSHIELD_BIN above already
    # grants the same reach and is checked first, so this adds no capability.
    # shellcheck disable=SC2086 # deliberate word-splitting over a path list
    for _candidate in ${GGSHIELD_FALLBACK_PATHS:-/opt/homebrew/bin/ggshield /usr/local/bin/ggshield /home/linuxbrew/.linuxbrew/bin/ggshield}; do
      if [[ -x "${_candidate}" ]]; then
        _ggshield="${_candidate}"
        break
      fi
    done
  fi
fi

if [[ -n "${_ggshield}" ]]; then
  # ggshield 1.56.1 ExitCode (ggshield/core/errors.py): 0 clean, 1 found,
  # 2 usage, 3 auth, 4 server unavailable, 128 unexpected. Measured
  # 2026-10-30 on `secret scan pre-commit`: bad or missing key 3, dead
  # proxy 4 (28 s when blackholed).
  #
  # Only 3 continues: a bad, expired or missing credential persists until
  # someone re-authenticates, so blocking on it blocks every commit and
  # invites a bypass that drops `make lint` too. 4 blocks: it is transient,
  # and when one chunk of a multi-chunk scan times out ggshield discards
  # findings from the chunks that finished (verticals/secret/
  # secret_scanner.py, _collect_results). --fail-on-server-error is pinned
  # so a machine-level `fail_on_server_error: false` cannot turn that into
  # a silent 0. 2 is a usage error, and also a 401 during the scan: a key
  # revoked inside the 300 s auth cache gets 2 once, then 3. 128 includes
  # quota exhaustion. Unknown codes fail closed.
  "${_ggshield}" secret scan pre-commit --fail-on-server-error "$@"
  _scan_rc=$?
  case "${_scan_rc}" in
    0) ;;
    1) exit 1 ;;
    3)
      printf 'pre-commit: ggshield could not authenticate (exit 3) — SECRET SCAN DID NOT RUN\n' >&2
      printf 'pre-commit: fix with: ggshield auth login (or check GITGUARDIAN_API_KEY)\n' >&2
      ;;
    4)
      printf 'pre-commit: GitGuardian unreachable (exit 4) — blocking: a partial scan can discard findings\n' >&2
      printf 'pre-commit: retry the commit when the network is back\n' >&2
      exit 1
      ;;
    *)
      printf 'pre-commit: ggshield failed (exit %s) — unknown failure, blocking\n' "${_scan_rc}" >&2
      if [[ "${_scan_rc}" -eq 2 ]]; then
        printf 'pre-commit: --fail-on-server-error needs ggshield 1.50.0 or later\n' >&2
      fi
      exit 1
      ;;
  esac
else
  # Loud, and on stderr. Never exit non-zero here: a machine that genuinely
  # lacks ggshield must still be able to commit the change that installs it.
  printf 'pre-commit: ggshield could not be resolved — SECRET SCAN DID NOT RUN\n' >&2
  printf 'pre-commit: install with: brew install gitguardian/tap/ggshield && ggshield auth login\n' >&2
fi
