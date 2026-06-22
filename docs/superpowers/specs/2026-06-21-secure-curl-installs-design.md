# Secure curl-based Software Installs

## Context

Several tools in this dotfiles repo are installed by piping a remote script into bash
(`curl https://... | bash`) or fetching an install script and running it unverified. This
is a supply chain risk: a compromised CDN, a DNS hijack, or a MITM can silently replace
the installer with malicious code.

The scope is **Linux-only**. On macOS every tool already flows through Homebrew, which
verifies SHA-256 checksums for all bottles and source tarballs. The Linux paths are where
the exposure exists.

Three patterns were evaluated:

1. **SHA-pin content** — download, verify against a hardcoded SHA-256, then execute.
   Rejected: requires updating the SHA on every upstream release, and the SHA must itself
   be fetched from a trusted channel (otherwise you're pinning a compromise).

2. **URL commit-SHA pinning** — replace `HEAD`/`latest` URLs with
   `raw.githubusercontent.com/org/repo/{COMMIT_SHA}/path`. TLS + fixed commit SHA is
   content-addressable. No separate checksum file needed. Update via `check-versions --update`.

3. **Package manager migration** — move tools to `brew_install_formula` in
   `_install_ubuntu_brew_packages()`. Homebrew verifies checksums for every install;
   this is the strongest guarantee and eliminates the curl entirely.

**Decision: combination of 2 and 3.** Move to brew when a good Homebrew formula exists
with up-to-date versions. Use URL commit-SHA pinning for the remaining unavoidable scripts.

---

## Section 1: Linux brew migrations (curl removed entirely)

Five tools move from curl installs to `brew_install_formula` calls in
`_install_ubuntu_brew_packages()`. Install order within that function does not matter.

| Tool                  | Old location                                                | Change                                                                                                                                                  |
| --------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pyenv`               | `_install_ubuntu_pyenv()` — `pyenv.run` curl                | Remove function; add `brew_install_formula pyenv` + `brew_install_formula pyenv-virtualenv`                                                             |
| `pyenv-virtualenv`    | same function                                               | same                                                                                                                                                    |
| `helm` (no-snap path) | `_install_ubuntu_k8s_tools()` — `get-helm-3` curl           | Remove curl block; add `brew_install_formula helm`                                                                                                      |
| `kustomize`           | `_install_ubuntu_k8s_tools()` — `install_kustomize.sh` curl | Remove entire block; add `brew_install_formula kustomize`                                                                                               |
| `cargo-nextest`       | `_install_ubuntu_rust()` + `update_rust()`                  | Remove both curl blocks; add `brew_install_formula cargo-nextest`                                                                                       |
| `rustup` (initial)    | `_install_ubuntu_rust()` — `sh.rustup.rs`                   | Remove curl; brew already installs rustup; function becomes configure-only: `rustup self update`, `rustup update`, `rustup component add rust-analyzer` |

`install_ubuntu_packages()` removes the `_install_ubuntu_pyenv` call from its
orchestration sequence.

---

## Section 2: Remaining curl removals

### opentofu — replace piped install script with manual apt setup

Current: `curl https://get.opentofu.org/install-opentofu.sh | sudo sh`

Replacement — manual apt source setup, matching the pattern already used for
Docker, Kubernetes, Cloudflare, etc.:

```bash
curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey \
  | sudo gpg --dearmor -o /etc/apt/keyrings/opentofu-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/opentofu-archive-keyring.gpg] \
  https://packages.opentofu.org/opentofu/tofu/any/ any main" \
  | sudo DEBIAN_FRONTEND=noninteractive tee /etc/apt/sources.list.d/opentofu.list

sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y opentofu
```

Idempotency guard: `[[ -x "$(command -v tofu)" ]]` skip check.

### oh-my-zsh — replace curl|bash with git clone at pinned tag

Current: `sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`

Replacement:

```bash
git clone --depth 1 --branch "${OH_MY_ZSH_VER}" \
  https://github.com/ohmyzsh/ohmyzsh.git "${HOME}/.oh-my-zsh"
```

`OH_MY_ZSH_VER` pinned in `lib/constants.sh` (resolved at implementation time from
`https://api.github.com/repos/ohmyzsh/ohmyzsh/releases/latest`).

Idempotency guard: `[[ -d "${HOME}/.oh-my-zsh" ]]` (already present in code).
Oh-my-zsh auto-updates itself via `omz update` — the clone is bootstrap-only.

### Homebrew installer — pin to commit SHA

Current: fetches `https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`
in three places: `lib/macos.sh`, `scripts/bootstrap_linux.sh`, `scripts/bootstrap_mac.sh`.

Replacement: replace `HEAD` with `${HOMEBREW_INSTALL_SHA}` in all three files.
`HOMEBREW_INSTALL_SHA` pinned in `lib/constants.sh` (resolved at implementation time from
`https://api.github.com/repos/Homebrew/install/commits/master` — `sha` field of first
result).

`raw.githubusercontent.com` at a fixed commit SHA is content-addressable: TLS + commit
SHA guarantees the bytes cannot change without changing the URL.

---

## Section 3: check-versions integration

Two new helper functions added to `lib/workflows.sh`, following the existing
`_check_version_helm` pattern:

```bash
_check_version_oh_my_zsh() {
  local _latest
  _latest=$(curl -fsSL "https://api.github.com/repos/ohmyzsh/ohmyzsh/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4)
  _compare_version "OH_MY_ZSH_VER" "${OH_MY_ZSH_VER}" "${_latest}"
}

_check_version_homebrew_install() {
  local _latest
  _latest=$(curl -fsSL "https://api.github.com/repos/Homebrew/install/commits/master" \
    | grep '"sha"' | head -1 | cut -d'"' -f4)
  _compare_version "HOMEBREW_INSTALL_SHA" "${HOMEBREW_INSTALL_SHA}" "${_latest}"
}
```

`--update` flag: same in-place `sed` on `lib/constants.sh` used by existing pins.
Display shows first 12 chars of SHAs for readability; full SHA stored in constants.

---

## Section 4: New constants in `lib/constants.sh`

```bash
# oh-my-zsh bootstrap tag
OH_MY_ZSH_VER="<resolved at implementation time>"

# Homebrew install script — commit SHA for content-addressable fetch
HOMEBREW_INSTALL_SHA="<resolved at implementation time>"
```

No constants are removed; nextest had no version pin in `constants.sh` (it used a
`latest` URL).

---

## Section 5: Testing strategy

### Files touched

| File                                     | Change                                                                                                                                                      |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/constants.sh`                       | Add `OH_MY_ZSH_VER`, `HOMEBREW_INSTALL_SHA`                                                                                                                 |
| `lib/linux_ubuntu.sh`                    | Remove `_install_ubuntu_pyenv`; remove curl blocks from `_install_ubuntu_k8s_tools`, `_install_ubuntu_rust`; add opentofu apt setup; add brew formula calls |
| `lib/macos.sh`                           | Pin Homebrew installer URL to `HOMEBREW_INSTALL_SHA`                                                                                                        |
| `lib/helpers.sh`                         | Replace oh-my-zsh `curl\|bash` with `git clone --depth 1 --branch` (line 616)                                                                               |
| `lib/workflows.sh`                       | Remove `_install_ubuntu_pyenv` call; add `_check_version_oh_my_zsh`, `_check_version_homebrew_install`                                                      |
| `scripts/bootstrap_linux.sh`             | Pin Homebrew installer URL to `HOMEBREW_INSTALL_SHA`                                                                                                        |
| `scripts/bootstrap_mac.sh`               | Pin Homebrew installer URL to `HOMEBREW_INSTALL_SHA`                                                                                                        |
| `tests/setup_env/linux_ubuntu.bats`      | Tests for opentofu apt setup; brew migration calls                                                                                                          |
| `tests/setup_env/install_functions.bats` | Tests for oh-my-zsh git clone, Homebrew SHA pin                                                                                                             |
| `tests/setup_env/unit.bats`              | Tests for `_check_version_oh_my_zsh`, `_check_version_homebrew_install`                                                                                     |

### Test approach per change

**Brew migrations** (pyenv, helm, kustomize, nextest):

- Assert `grep -q "brew_install_formula <tool>" "${MOCK_CALLS_FILE}"`
- Assert old curl command absent from mock calls
- Test idempotency: formula already installed → skip

**opentofu apt setup**:

- Assert `grep -q "DEBIAN_FRONTEND=noninteractive.*apt-get install.*opentofu"` in mock calls
- Test idempotency: `tofu` already on PATH → function skips entire block

**oh-my-zsh git clone**:

- Mock `git`; assert `grep -q "clone.*${OH_MY_ZSH_VER}.*ohmyzsh"` in mock calls
- Test skip: `~/.oh-my-zsh` exists → no clone

**Homebrew SHA pin**:

- Assert URL passed to curl in `install_homebrew` contains `${HOMEBREW_INSTALL_SHA}`
- Assert URL does not contain `/HEAD/`

**check-versions**:

- Mock curl to return a newer tag / different SHA
- Assert `_check_version_oh_my_zsh` emits "outdated" output
- Assert `_check_version_homebrew_install` emits "outdated" output

TDD order: one RED→GREEN cycle per change, committed separately. All existing tests
remain green throughout.
