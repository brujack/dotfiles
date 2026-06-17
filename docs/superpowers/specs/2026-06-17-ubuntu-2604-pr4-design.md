# Ubuntu 26.04 PR4: ARM64 Support + Version Bumps — Design

**Date:** 2026-06-17
**Status:** Approved

## Context

PRs 1-3 added Ubuntu 26.04 (Resolute Raccoon) support. All download URLs and APT
stanzas in `lib/constants.sh`, `lib/linux_ubuntu.sh`, and `lib/developer.sh` are
hardcoded to `amd64`/`x86_64`. Ubuntu 26.04 is available for ARM64; this PR fixes
all architecture hardcodes and simultaneously bumps all pinned tool versions to latest.

## Scope

Two changes bundled:

1. **ARM64 URL and APT stanza support** — replace hardcoded arch tokens with dynamic
   variables derived from `uname -m` or `dpkg --print-architecture`.
2. **Version bumps** — update all stale pins in `lib/constants.sh` to latest stable.

## Design

### Central Architecture Variable (`lib/constants.sh`)

Add near the start of the Linux-specific section:

```bash
_LINUX_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
```

Converts kernel convention (`x86_64`/`aarch64`) to Debian/GitHub-release convention
(`amd64`/`arm64`). Used by all Debian-packaged tools and GitHub release assets.

Not used by AWS CLI (which uses kernel convention directly) or APT `deb [arch=]`
stanzas (which use `dpkg --print-architecture`).

### `lib/constants.sh` — URL Arch Tokens

Replace every hardcoded `amd64` in download URL variables with `${_LINUX_ARCH}`:

| Variable               | Change                                     |
| ---------------------- | ------------------------------------------ |
| `GO_DOWNLOAD_FILENAME` | `go${GO_VER}.linux-${_LINUX_ARCH}.tar.gz`  |
| `CF_TERRAFORMING_URL`  | `..._linux_${_LINUX_ARCH}.tar.gz`          |
| `KIND_URL`             | `kind-linux-${_LINUX_ARCH}`                |
| `TELEPRESENCE_URL`     | `linux/${_LINUX_ARCH}/latest/telepresence` |
| `TFLINT_URL`           | `tflint_linux_${_LINUX_ARCH}.zip`          |
| `TFSEC_URL`            | `tfsec-linux-${_LINUX_ARCH}`               |
| `YQ_URL`               | `yq_linux_${_LINUX_ARCH}`                  |

**Exception:** `VAGRANT_VER` — HashiCorp Vagrant has no ARM64 Linux release.
Keep `amd64` hardcode; add comment: `# amd64 only — no ARM64 Linux build`.

### `lib/developer.sh` — AWS CLI

AWS CLI uses kernel arch naming directly (`x86_64`/`aarch64`), not Debian naming.
Replace both occurrences of `x86_64` with `$(uname -m)`:

- Line ~30 (`update_aws`): `awscli-exe-linux-x86_64.zip` → `awscli-exe-linux-$(uname -m).zip`
- Line ~77 (`install_aws_tools`): same substitution

### `lib/linux_ubuntu.sh` — Hashicorp ZIP URLs + APT Stanzas

**HashiCorp tools** (consul, vault, nomad, packer) all use `_linux_amd64.zip` pattern
via `${HASHICORP_URL}`. Replace `amd64` with `${_LINUX_ARCH}` in each download function.
All four tools confirmed to have ARM64 releases.

**APT stanzas:**

| Tool           | Change                                                                                                 |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| azure-cli      | `[arch=amd64]` → `[arch=$(dpkg --print-architecture)]` — MS repo confirmed ships amd64 + arm64 + armhf |
| virtualbox     | Keep `[arch=amd64]` — no ARM64 Linux build. Add comment.                                               |
| microsoft-edge | Keep `[arch=amd64]` — no ARM64 Linux build. Add comment.                                               |

### Version Bumps (`lib/constants.sh`)

All versions verified via GitHub releases API and official release pages (2026-06-17):

| Variable               | Pinned   | Latest   | Notes                           |
| ---------------------- | -------- | -------- | ------------------------------- |
| `BATS_VER`             | 1.11.0   | 1.13.0   |                                 |
| `GIT_VER`              | 2.53.0   | 2.54.0   |                                 |
| `GITLEAKS_VER`         | 8.21.2   | 8.30.1   |                                 |
| `CF_TERRAFORMING_VER`  | 0.16.1   | 0.27.0   |                                 |
| `CONSUL_VER`           | 1.16.0   | 2.0.0    | major — HashiCorp CE 2.0 stable |
| `DOCKER_COMPOSE_VER`   | v2.20.2  | v5.1.4   | major — Compose v5 stable       |
| `GO_DOWNLOAD_FILENAME` | go1.26.1 | go1.26.4 | patch; `GO_VER` stays "1.26"    |
| `KIND_VER`             | 0.31.0   | 0.32.0   |                                 |
| `NOMAD_VER`            | 1.6.1    | 2.0.3    | major — HashiCorp CE 2.0 stable |
| `PACKER_VER`           | 1.15.1   | 1.15.4   |                                 |
| `RUBY_INSTALL_VER`     | 0.9.1    | 0.10.2   |                                 |
| `TERRAFORM_VER`        | 1.3.5    | 1.15.6   |                                 |
| `TFLINT_VER`           | 0.61.0   | 0.63.1   |                                 |
| `TFSEC_VER`            | 1.28.4   | 1.28.14  |                                 |
| `VAULT_VER`            | 1.14.1   | 2.0.2    | major — HashiCorp CE 2.0 stable |
| `YQ_VER`               | 4.52.5   | 4.53.3   |                                 |
| `KUBERNETES_VER`       | v1.35    | v1.36    | minor pin only                  |

**No change:** CHRUBY_VER 0.3.9, PYTHON_VER 3.14.6, RUBY_VER 4.0.5,
SHELLCHECK_VER 0.11.0, VAGRANT_VER 2.4.9 already at latest.

**ZSH_VER unchanged:** Currently pinned at "5.10" but zsh.org latest is 5.9.1.
Since 5.10 > 5.9.1 and it may be an anticipated release, leave as-is.

## Testing

### ARM64 Tests

BATS tests for each modified function asserting correct arch token substitution:

- Mock `uname` to return `aarch64` → assert download URL contains `arm64`
- Mock `uname` to return `x86_64` → assert download URL contains `amd64`
- Mock `dpkg --print-architecture` to return `arm64` → assert azure-cli APT stanza uses `arm64`
- Vagrant function: assert URL always contains `amd64` regardless of arch

### Version Bump Tests

No new BATS tests needed for version bumps — existing tests pass the version constant
through; updating the constant is sufficient. The `check-versions` workflow validates
the pins against installed versions at runtime.

## Files Changed

- `lib/constants.sh` — `_LINUX_ARCH` variable, all arch tokens in URLs, all version bumps
- `lib/developer.sh` — AWS CLI arch tokens (2 occurrences)
- `lib/linux_ubuntu.sh` — Hashicorp ZIP arch tokens, azure-cli APT arch, comments on VirtualBox/Edge
- `tests/setup_env/install_guards.bats` — new arch-conditional tests for each modified function
- `tests/setup_env/install_functions.bats` — existing tests updated as needed
