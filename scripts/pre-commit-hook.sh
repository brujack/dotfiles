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
  "${_ggshield}" secret scan pre-commit "$@" || exit 1
else
  # Loud, and on stderr. Never exit non-zero here: a machine that genuinely
  # lacks ggshield must still be able to commit the change that installs it.
  printf 'pre-commit: ggshield could not be resolved — SECRET SCAN DID NOT RUN\n' >&2
  printf 'pre-commit: install with: brew install gitguardian/tap/ggshield && ggshield auth login\n' >&2
fi
