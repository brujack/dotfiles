# HashiCorp apt (PR B) Implementation Plan

> **Status: DONE** — merged as #340 (6ae137af).

spec: docs/superpowers/specs/2026-10-15-hashicorp-apt-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove consul, vault and nomad; install packer and vagrant on Linux from HashiCorp's signed apt repo through a source file only the install step reads; pin-check both in check-versions; move macOS packer to `hashicorp/tap`.

**Architecture:** `_install_ubuntu_hashicorp` (`lib/linux_ubuntu.sh`) is rewritten to the 9-step flow in spec section 2 (migration, decide set without apt, keyring via `_build_pinned_keyring`, source file in `/var/lib/dotfiles`, single-source refresh, glob install, stamp-gated removal). `_install_fetched_binary` loses `--unverified`. check-versions gains a `packer|vagrant)` arm. macOS gets a core-packer guard before the main bundle.

**Tech Stack:** bash, bats, apt-get, gpg, Homebrew.

## Global Constraints

- The spec is authoritative. Each task names the spec sections it implements; read them in full before coding. Messages, argv and paths are copied verbatim from the spec.
- `HASHICORP_GPG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"`.
- Source file: `<_HASHICORP_SOURCE_DIR>/hashicorp.list`, default `/var/lib/dotfiles`. Keyring: `<_APT_KEYRINGS_DIR>/hashicorp-archive-keyring.gpg`, default `/usr/share/keyrings`.
- `_HASHICORP_SOURCE_DIR`, `_HASHICORP_KEY_PATH` and (for this step only) `_APT_KEYRINGS_DIR` are honoured only when `BATS_TEST_TMPDIR` is non-empty (R28).
- No code writes a HashiCorp source under `/etc/apt` (N6); no `apt-mark hold`, no `--allow-change-held-packages` (R24); no Homebrew uninstall (N1); no network fetch of the key (N5); no new doctor check (N4).
- Every sudo apt-get install carries `DEBIAN_FRONTEND=noninteractive` on the sudo line and `"${APT_CONFFILE_OPTS[@]}"` after the verb (`tests/scripts/dpkg_sudo_frontend.bats` must stay green).
- Shell rules: `~/.claude/standards/shell.md`; `|| return 1` in functions, no `set -e`, `printf` not `echo`, `[[ ]]`, no EXIT/RETURN trap in `lib/` (`scripts/check-lib-exit-traps.sh`).
- Tests never touch real `/etc/apt`, `/usr/share/keyrings`, `/var/lib/dotfiles` or `/usr/local/bin` (tdd.md E2): seams at setup scope.
- Per-task gates are `make lint` plus `bats --jobs 24` over the task's own test files (linux_ubuntu.bats runs in ~26 s). The orchestrator runs `make test` once after Task 6 and again after Task 7; that run is the aggregate gate.

## Verification

- Session gate: `make test` exits 0 (orchestrator, after Tasks 6 and 7), and CI green including `bash-coverage` (V3).
- Behaviour: spec V1 on `claude` and `workstation` (`./setup_env.sh -t developer`, `command -v packer vagrant` gives `/usr/bin/*`, no `/etc/apt/sources.list.d/hashicorp.list`, no `/usr/local/bin/{consul,vault,nomad,packer,vagrant}`, second run prints both `up to date` lines, `-t update` leaves `dpkg-query -W packer vagrant` unchanged). V2 on the Studio after the manual brew uninstall. Both run after merge by the operator; Phase 3 states them as post-merge steps.
- Edge cases covered by tests: every case listed in spec section 5.

---

### Task 1: Test harness: apt-get and lsb_release mocks, load_mocks defaults, apt shim split

```yaml-task
id: 1
description: Add the apt-get update/install knobs, a flag-aware lsb_release mock, load_mocks defaults for the new seams, and a glob-safe SHIM_APT_FAIL_PKGS split
role: executor
model: sonnet
tdd: required
requirements: [R28]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats --jobs 24 tests/setup_env/mocks_apt_get.bats tests/setup_env/linux_ubuntu.bats tests/setup_env/linux_shared.bats
    exit_code: 0
max_retries: 3
files_touched: [tests/mocks/apt-get, tests/mocks/lsb_release, tests/helpers/common.bash, tests/setup_env/linux_ubuntu.bats, tests/setup_env/mocks_apt_get.bats]
depends_on: []
```

**Spec:** section 5, "Mock seams that do not exist and are added", the `load_mocks` paragraph, and the "packer install fails" case's note on the shim.

- `tests/mocks/apt-get` `update`, in order: (1) `MOCK_APT_GET_SOURCELIST_COPY` set: copy the file named by the `-o Dir::Etc::sourcelist=<path>` argument there; (2) `MOCK_APT_GET_UPDATE_OUTPUT` names a file: print its `W:`/`E:` lines to stderr, the rest to stdout; unset: print `Reading package lists...` to stdout; (3) then the existing `MOCK_APT_FAIL_SUBCMD=update` exit 100. `install`: `MOCK_APT_GET_INSTALL_OUTPUT` file printed (`E:` lines to stderr, rest stdout) before the fail handling; `MOCK_APT_GET_INSTALL_MARK` set: print `<mark> <package arguments>` (non-option args after the verb, `-o` values skipped) on stdout. Keep the call-log line unchanged.
- `tests/mocks/lsb_release`: `-cs` prints `${MOCK_LSB_RELEASE_CS-noble}`; `-rs` prints `${MOCK_LSB_RELEASE_RS:-24.04}` as today.
- `load_mocks`: export `_HASHICORP_SOURCE_DIR` and `_APT_KEYRINGS_DIR` to dirs under `BATS_TEST_TMPDIR`, created (`mkdir -p`).
- `linux_ubuntu.bats` setup: the `SHIM_DIR/apt` wrapper splits `SHIM_APT_FAIL_PKGS` with `read -ra` (no unquoted `for`), so `packer=1.16.1-*` matches literally even when a file `packer=1.16.1-x` exists in cwd. The `apt-get` copy follows.
- New `tests/setup_env/mocks_apt_get.bats` (model on `mocks_sudo.bats`): one test per knob and order (copy happens even when update fails; stderr/stdout split under `run --separate-stderr`; `-cs` unset/empty/set; `-rs` unchanged; load_mocks dirs exist; the shim with a decoy `packer=1.16.1-x` file in cwd still fails only `packer=1.16.1-*`). Each test RED first against the current mocks.

**Produces:** the knobs above for Tasks 3 and 4.

### Task 2: Vendored key and apt fixtures

```yaml-task
id: 2
description: Vendor keys/hashicorp.asc and capture the five apt fixtures with the spec's sandbox recipe (captured real-tool data; no logic, so tdd not-applicable)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'gpg --show-keys --with-colons keys/hashicorp.asc | grep -qx "fpr:::::::::D55C0D1AC78A8D8126CB631CFC9CA96ACA026560:"'
    exit_code: 0
  - cmd: 'grep -q "is not signed" tests/fixtures/apt/update-hashicorp-never-fetched.txt && grep -q "NO_PUBKEY" tests/fixtures/apt/update-hashicorp-stale-rotated.txt && ! grep -q "is not signed" tests/fixtures/apt/update-hashicorp-stale-rotated.txt'
    exit_code: 0
  - cmd: 'grep -q "does not have a Release file" tests/fixtures/apt/update-hashicorp-no-release.txt && grep -q "Could not get lock" tests/fixtures/apt/update-hashicorp-lock.txt && grep -q "was not found" tests/fixtures/apt/install-version-not-found.txt'
    exit_code: 0
  - cmd: '! grep -rqE "/tmp/|/home/" tests/fixtures/apt/'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [keys/hashicorp.asc, tests/fixtures/apt/update-hashicorp-never-fetched.txt, tests/fixtures/apt/update-hashicorp-stale-rotated.txt, tests/fixtures/apt/update-hashicorp-no-release.txt, tests/fixtures/apt/update-hashicorp-lock.txt, tests/fixtures/apt/install-version-not-found.txt]
depends_on: []
```

**Spec:** Measurements (signing key) and section 5 fixtures list and sandbox recipe.

- Key: copy `/tmp/claude-1000/-home-bruce-git-repos-personal-dotfiles/cfa82cac-15c7-406a-ac43-0c9d8e6cd020/scratchpad/hc/key.asc` (the file as served 2026-10-14, fingerprint verified) to `keys/hashicorp.asc`. Do not fetch it.
- Fixtures: unprivileged `apt-get` with every `Dir::` path in a scratch dir under that scratchpad, `APT::Sandbox::User=$(id -un)`, `Debug::NoLocking=1` except the lock capture, the step's own command `apt-get update --error-on=any -o Dir::Etc::sourcelist=<f> -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1`. Wrong key = any other key (e.g. `tests/fixtures/albert-obs.asc` dearmored). Stale-rotated: fetch once with the dearmored vendored key, swap the keyring, refresh again. No-release: a codename the repo does not serve (e.g. `bogus`). Lock: hold `lists/lock` with `python3 -c` `fcntl.lockf`. Version-not-found: `apt-get -s install 'vagrant=9.9.9-*'` after a good fetch. Network probes use `python3 -I`/apt only; Bash commands must not contain the words curl or wget.
- Scrub every fixture: the sandbox prefix becomes `/var/lib/apt` (lists/cache paths) and any PID becomes `1234`. No scratch path, username or live PID may remain.

### Task 3: Core hashicorp step, removals, migration, dispatcher test

```yaml-task
id: 3
description: Rewrite _install_ubuntu_hashicorp to the apt flow (spec 2 steps 1-9 minus failure hints and the R30 warning), migration (spec 3), constants and --unverified removal (spec 1, Linux half)
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R19, R21, R22, R23, R24, R25, R26, R28, R29]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats --jobs 24 tests/setup_env/linux_ubuntu.bats tests/setup_env/fetched_binary.bats tests/setup_env/workflows.bats tests/scripts/dpkg_sudo_frontend.bats
    exit_code: 0
  - cmd: '! grep -rnE -- "--unverified|HASHICORP_URL|CONSUL_VER|NOMAD_VER|VAULT_VER|pending HashiCorp apt" lib/ setup_env.sh'
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats, tests/setup_env/fetched_binary.bats]
depends_on: [1, 2]
```

**Spec:** section 1 (Linux items), section 2 steps 1-9 except the refresh-failed line's next-action variants, the rotation hint, the install-failure hints and the step-6 hand-written-source warning (Task 4), section 3, section 5 cases and the dispatcher-test paragraph.

- `lib/constants.sh`: delete `CONSUL_VER`, `NOMAD_VER`, `VAULT_VER`, `HASHICORP_URL` and their comments; add `HASHICORP_GPG_FPR`; add the key path default `${DOTFILES_REPO_ROOT}/keys/hashicorp.asc` (plain assignment, like `_AWS_KEY_PATH`, below `DOTFILES_REPO_ROOT`); `PACKER_VER`'s read-by comment adds `lib/workflows.sh:run_check_versions`.
- `lib/linux_ubuntu.sh`: `_install_fetched_binary` loses `--unverified` (parsing, allow-list, URL-only stamp, not-verified line; update its header comment). `_install_ubuntu_hashicorp` per spec. The refresh in this task prints `_out` and, on non-zero rc, the refresh-failed line ending `; re-run ./setup_env.sh -t developer` and returns 1 with no install; a failed install prints `hashicorp: <tool>: install failed` and `_err`. Task 4 adds the variants.
- Install argv exactly: `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" -o Dir::Etc::sourcelist=<file> --allow-downgrades "<tool>=<VER>-*"` with stdout streamed, stderr captured (`{ _err=$(... 2>&1 1>&3 3>&-); _irc=$?; } 3>&1`).
- Tests: delete `_hc_env`, the five old `_install_ubuntu_hashicorp` tests and the `--unverified` tests in `fetched_binary.bats`; add every section 5 case not listed under Task 4 (clean install argv via `argv_probe_stub_path` + `grep -xF`, source line equality, stale file byte equality, up-to-date absence, `rc`/older status, arm64 skip and its removal failure via `SHIM_DIR` `rm`, empty codename/arch, `install -d`/`tee` failure, wrong key, packer install fails via `SHIM_APT_FAIL_PKGS='packer=1.16.1-*'`, migration cases, refresh argv, `apt-get update` not `apt update`, the R4 fingerprint check of `keys/hashicorp.asc` against `HASHICORP_GPG_FPR`). `_APT_SOURCES_LIST` at setup scope pointing at a missing path. Rewrite the dispatcher test per spec.
- Before deleting a symbol, `grep -rn '<symbol>' lib/ scripts/ tests/` and fix every reader in this task.

**Produces:** `_install_ubuntu_hashicorp` with clear points for Task 4 to add the next-action variants, rotation hint, install hints and the step-6 warning.

### Task 4: Failure diagnostics and the hand-written-source warning

```yaml-task
id: 4
description: Add the refresh-failed next-action variants, rotation hint, install-failure hints and the R30 hand-written-source warning, with the fixture-driven cases
role: executor
model: sonnet
tdd: required
requirements: [R7, R19, R20, R30]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats --jobs 24 tests/setup_env/linux_ubuntu.bats
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [3]
```

**Spec:** section 2 step 6 (warning, refresh-failed line, rotation hint, stderr order) and step 7 (install hints and default), section 5 cases for: never-fetched, stale-rotated, no-release, lock, unset fixture, install-version-not-found, install output streams, Signed-By conflict, neither-hint default, held package (`Held packages were changed` gives `(<tool> is held: run sudo apt-mark unhold <tool>, then re-run)`), and hand-written source (live/inert files, `.list`/`.sources`, `uris:` lowercase, `.save`/`.distUpgrade` ignored, `_APT_SOURCES_LIST`).

- Order on failure, all stderr: `_out`, refresh-failed line, rotation hint. One case asserts under `run --separate-stderr` that the hint is the line after the refresh-failed line.
- `<install set>` joined with " and ".
- Every case RED first: run it against Task 3's code and confirm it fails for the missing message, not a usage error.

### Task 5: macOS Brewfile, core-packer guard, tap trust, zsh completions

```yaml-task
id: 5
description: Brewfile drops consul/nomad/vault and moves packer to hashicorp/tap, install_macos_casks refuses on core packer, both brew trust lists gain hashicorp/tap, and the vault/consul/nomad completion block goes
role: executor
model: sonnet
tdd: required
requirements: [R13, R14, R15, R17]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats --jobs 24 tests/setup_env/macos.bats tests/setup_env/install_guards.bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: '! grep -nE "^brew \"(consul|nomad|vault|packer)\"|^#brew \"vault\"" Brewfile && ! grep -q "complete -o nospace -C /usr/local/bin" .config/.zshrc.d/5_general.zsh'
    exit_code: 0
max_retries: 3
files_touched: [Brewfile, lib/macos.sh, lib/helpers.sh, .config/.zshrc.d/5_general.zsh, tests/setup_env/macos.bats]
depends_on: []
```

**Spec:** section 1 (Brewfile, zsh items), section 4 (Brewfile, core-packer guard, tap trust), section 5 mac case.

- Brewfile: `tap "hashicorp/tap", trusted: true` and `brew "hashicorp/tap/packer"`, both `# [HAS_DEVTOOLS]`, in alphabetical position; delete the four lines.
- `install_macos_casks`: before the main bundle, if `brew list --formula --full-name` has a line exactly `packer`, print `homebrew-core packer conflicts with hashicorp/tap/packer: run 'brew uninstall packer consul vault nomad', then re-run` and `return 1` with no bundle.
- Add `hashicorp/tap` to the `brew trust` calls in `lib/macos.sh:install_macos_casks` and `lib/helpers.sh` (not the Linux one in `lib/linux_ubuntu.sh`).
- Tests: the guard fires on bare `packer` (rc 1, no `brew bundle` in the call log) and not on `hashicorp/tap/packer` alone; both trust lists contain `hashicorp/tap`.

### Task 6: check-versions for packer and vagrant

```yaml-task
id: 6
description: Check packer and vagrant pin-against-latest via _run_cv_pinned_release and add the packer|vagrant arm of _prompt_version_update
role: executor
model: sonnet
tdd: required
requirements: [R16, R27]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats --jobs 24 tests/setup_env/workflows.bats tests/setup_env/check_versions_feeds.bats
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/workflows.bats, tests/setup_env/check_versions_feeds.bats]
depends_on: [3]
```

**Spec:** section 4 check-versions bullet; section 5 check-versions case; R27.

- Replace vagrant's `_run_cv_check` line with `_run_cv_pinned_release "vagrant" "${VAGRANT_VER}" "hashicorp/vagrant" "VAGRANT_VER"` and add `_run_cv_pinned_release "packer" "${PACKER_VER}" "hashicorp/packer" "PACKER_VER"`.
- `packer|vagrant)` arm: refuse non-`X.Y.Z` latest (rc 1, no write); edit only the `*_VER` line of `_release_pin_constants_path`; read back with `grep -Fqx`; on miss print a read-back failure and return 1; else print `Updated <VAR> → <version>`, then `<tool>: commit lib/constants.sh and merge the PR, then run ./setup_env.sh -t developer on each Linux box to install <version>` and `  if it reports <version> not found in apt.releases.hashicorp.com, HashiCorp has not published it to apt yet: wait and re-run`.
- Tests call `_prompt_version_update` directly (`<<< "y"`) and assert rc 0/1, output and file; update the existing vagrant test at `workflows.bats` (`Updated VAGRANT_VER → 2.5.0`) to the new arm's output. The token-gated count in the GITHUB_TOKEN warning stays derived from the gated calls.
- Self-check before reporting: grep `CLAUDE.md` for the check-versions paragraph; Task 7 edits it, not this task.

### Task 7: ADR amendment, README backlog, CLAUDE.md

```yaml-task
id: 7
description: Docs only (ADR-0046 amendment, backlog rows, CLAUDE.md seams and check-versions paragraph); no behaviour change, so tdd not-applicable
role: executor
model: sonnet
tdd: not-applicable
requirements: [R18]
acceptance:
  - cmd: 'grep -q "2026-10-1[0-9]" docs/adr/0046-release-asset-pins-from-the-github-api-digest.md && grep -qi "apt" docs/adr/0046-release-asset-pins-from-the-github-api-digest.md'
    exit_code: 0
  - cmd: '! grep -q "HashiCorp tools are installed without a checksum" docs/superpowers/README.md && ! grep -q -- "--unverified" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "_HASHICORP_SOURCE_DIR" CLAUDE.md && grep -q "MOCK_LSB_RELEASE_CS" CLAUDE.md && grep -q "brew uninstall packer consul vault nomad" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [docs/adr/0046-release-asset-pins-from-the-github-api-digest.md, docs/superpowers/README.md, CLAUDE.md]
depends_on: [3, 4, 5, 6]
```

**Spec:** section 4 ADR, README and CLAUDE.md bullets. Cite functions by name, not `file:line`. Add the ADR amendment as a dated section; edit existing CLAUDE.md bullets in place (release-asset-pins, `_APT_SOURCES_DIR`/... bullet, check-versions entry-point paragraph) and add the seams and knobs to Test Seams. Do not restate measured figures.

## Orchestrator steps

- [ ] After Task 6: `make test < /dev/null` from the worktree; exit 0 required.
- [ ] After Task 7: `make test < /dev/null` again, then Phase 3 (`finishing-a-development-branch`). V1/V2 are post-merge operator steps named in the PR body.

## Non-goal check

One fresh reviewer, plan at the commit that adds this section: N1 through N6 all CLEAR (0 CONFLICT, 0 UNCLEAR).

- N1: Task 5's guard only prints the `brew uninstall` command; it runs none.
- N2: the arm64 vagrant removal is the stamp-gated removal of spec section 3 (Task 3).
- N5: Task 2 copies the vendored key from the scratchpad; its network use is the one-time fixture capture, never install time.
- N6: the source file is in `/var/lib/dotfiles`, the keyring in `/usr/share/keyrings`, fixtures in a scratch `Dir::` tree.

No plan revision or amendment needed.
