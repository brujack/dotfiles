# ADR-0013: Replace curl|bash Installers with Verified Package Manager Installs

**Date:** 2026-06-22
**Status:** Accepted

## Context

Several tool installations in the dotfiles Linux setup path used the curl|bash
anti-pattern: download a shell script from the internet and pipe it directly to
`bash` without any integrity verification. Affected tools: pyenv (pyenv.run),
helm (get-helm-3 script), kustomize (install_kustomize.sh), cargo-nextest
(get.nexte.st), rustup (sh.rustup.rs), and oh-my-zsh (raw GitHub tools/install.sh).
The Homebrew installer in three files (lib/macos.sh, scripts/bootstrap_linux.sh,
scripts/bootstrap_mac.sh) fetched from a floating `/HEAD/` URL.

Risks:

- **Supply chain substitution:** A compromised CDN or GitHub account can silently
  swap the script between the fetch and execution. No hash or signature is verified.
- **Reproducibility:** The same URL can serve different content on different days
  (floating HEAD refs, rolling releases).
- **Privilege escalation surface:** Several of these scripts run as root or install
  to system paths; an injected payload would execute with elevated privilege.

Alternatives considered:

- **Checksum verification before exec:** Download to tmpfile, verify SHA-256 against
  a pinned digest in constants.sh, then execute. Viable for one-off scripts but still
  requires running untrusted code and maintaining digests per platform/arch.
- **Vendoring scripts:** Copy installers into the repo. Eliminates download risk but
  creates ongoing maintenance burden and bloats repo size.
- **Package manager installs (chosen):** Homebrew formulas, APT with GPG-verified
  signing keys, and git clone are already the standard for reproducible installs.
  Homebrew verifies checksums internally; APT verifies signatures against a keyring.

## Decision

All new tool installations in dotfiles must use one of the following verified methods:

1. **Homebrew formula** (`brew_install_formula <name>`) — preferred for all tools
   available in Homebrew on both macOS and Linux. Homebrew verifies bottle checksums.
2. **APT with explicit GPG keyring** — for Linux tools distributed via Debian
   repositories. Fetch the signing key with curl and write to
   `/etc/apt/keyrings/<tool>-archive-keyring.gpg`; configure the signed-by source;
   then install via `apt-get install`. Use `DEBIAN_FRONTEND=noninteractive` on all
   apt/nala calls.
3. **SHA-pinned content-addressable URL** — for bootstrap scripts that must be
   fetched before a package manager is available. Pin the GitHub commit SHA in
   `lib/constants.sh` (constant name `<TOOL>_INSTALL_SHA`); reference
   `raw.githubusercontent.com/<org>/<repo>/<SHA>/path`. Add an update check via
   `_check_cv_<tool>` in `lib/workflows.sh` and call it from `run_check_versions()`.
4. **`git clone --depth 1 --branch <REF>`** — for projects distributed as a git
   repository (e.g. oh-my-zsh). The branch ref is pinned in constants.sh as
   `<TOOL>_VER`.

**curl|bash is banned.** No new code may pipe a curl download directly to `bash`,
`sh`, or any other interpreter without integrity verification. If a tool's only
install method is a piped script, the preferred resolution is to request a Homebrew
formula or APT package from the upstream maintainer.

## Consequences

**Easier:**

- Reproducible installs: the same constants.sh values produce the same installed
  version on every machine.
- Supply chain auditability: every install path can be traced to a specific artifact
  version (formula version, package version, commit SHA, or branch ref).
- Update tracking: the check-versions framework (`./setup_env.sh -t check-versions`)
  covers all pinned values including SHA-pinned bootstrap scripts and branch refs.

**Harder / required going forward:**

- New tool installs must be researched for Homebrew or APT availability before
  falling back to other methods.
- SHA-pinned bootstrap scripts require periodic updates via check-versions; outdated
  SHAs don't fail at install time, only at audit time.
- BATS tests for brew formula installs must mock `brew_install_formula` rather than
  asserting on curl calls — the mock pattern is established in `tests/mocks/`.

## Related

- PR #162 — implementation that introduced this guardrail
- [docs/superpowers/plans/2026-06-21-secure-curl-installs.md](../superpowers/plans/2026-06-21-secure-curl-installs.md)
- [ADR-0005](0005-require-secrets-guarding-in-all-personal-repos.md) — related security guardrail (secrets scanning)
- `lib/constants.sh` — canonical location for all version/SHA pins
- `lib/workflows.sh` — `run_check_versions()` and `_check_cv_*` helpers
