# apt Stale-Signer Detection Implementation Plan

spec: docs/superpowers/specs/2026-10-17-apt-stale-signer-detection-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `-t update` WARNs, naming each stale apt source and a per-host remedy, when a source's signing key no longer verifies.

**Architecture:** `nala full-upgrade` gains `--no-update`, so `apt update` is the only refresh. `run_update` parses the `err_apt` file it already writes using `_apt_stale_signer_hosts` (in `lib/linux_shared.sh`). It looks up a remedy for each host with `_apt_signer_remedy`, marks the `apt` section WARN with the existing result kept, and writes one line per host to `detail_apt`. `_hashicorp_rotation_hint_fires` reuses the same parser.

**Tech Stack:** bash, bats, apt 3.2.0 / nala 0.16.0 (resolute), apt 2.7 (noble).

## Global Constraints

- Considered prefixes, case-sensitive: `W:`, `E:`, `Warning:`, `Error:`.
- Tokens: `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`, `KEYEXPIRED`, `REVKEYSIG`, `is not signed`, `is no longer signed`.
- Each list is defined once.
- Detail line: `<host> is not updating: signature check failed (<token>): signer rotated or expired, or a proxy served unsigned data; <remedy>`.
- WARN result: `<existing result>; signer check failed for <hosts, comma-joined> — see detail`.
- N1: `-t update` does not write, fetch or delete any keyring, source file or apt trust setting.
- N2: no doctor check and no keyring-expiry parsing are added.
- N3: the install-time key-fetch guards in `_install_ubuntu_nvidia`, `_install_ubuntu_cloud_tools` and `_install_ubuntu_misc` are unchanged.
- N4: `lib/linux_ubuntu.sh:223` is unchanged.
- N5: a stale signer alone never turns the `apt` section FAIL or the run's exit code non-zero.
- Shell style is set by `~/.claude/standards/shell.md`:
  - `[[ ]]`, `${VAR}` with braces, `printf` rather than `echo`, `|| return 1` in functions;
  - no `set -e`;
  - every new function has a one-line rationale comment.
- Fixtures are real captured output, never hand-typed. Every gate uses `command grep`, because `grep` is a ugrep wrapper in agent sessions.
- Baseline: `make test` exits 0 in 189s with 3202 tests on `claude` (2026-10-17, worktree at `56723d46`). That is under the 600s Bash cap, so sequential code tasks carry `make test` with `timeout: 600000`.

## Verification Planning

- **Whole-change proof:** `make test` exits 0, with the new tests counted in `1..N`. Then, on `claude` after merge (V3), `./setup_env.sh -t update` shows the `apt` row as OK and `detail_apt` has no stale-host line.
- **Detection is proven by fixtures, not by the live box**, since no source is stale today (spec M1). The test with a real stale fixture is the positive control. It must go red under the named mutant (the parser body replaced by `cat > /dev/null`).
- **Edge cases:**
  - clean output;
  - two stale hosts;
  - two URLs on one line;
  - the k8s redirect host;
  - the unknown host;
  - nala failing while a host is stale (FAIL, with the stale line still in the detail);
  - `--no-update` placed after the verb.

---

### Task 1: Capture fixtures and measure V1/V2

```yaml-task
id: 1
description: Capture real apt/nala fixtures and record V1/V2 results (measurement task, no production code, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'command grep -qE "^(W|E|Warning|Error):.*https?://download\.docker\.com.*NO_PUBKEY" tests/fixtures/apt/update-stale-rotated-resolute.txt'
    exit_code: 0
  - cmd: 'command grep -qE "^(W|E|Warning|Error):.*https?://[^ ]+.*NO_PUBKEY" tests/fixtures/apt/update-stale-rotated-noble.txt'
    exit_code: 0
  - cmd: '! command grep -qE "NO_PUBKEY|EXPKEYSIG|EXPSIG|KEYEXPIRED|REVKEYSIG|is not signed|is no longer signed" tests/fixtures/apt/update-clean-resolute.txt'
    exit_code: 0
  - cmd: 'command grep -qE "^## V1" tests/fixtures/apt/README.md && command grep -qE "^## V2" tests/fixtures/apt/README.md'
    exit_code: 0
max_retries: 2
files_touched: [tests/fixtures/apt/update-stale-rotated-resolute.txt, tests/fixtures/apt/update-stale-rotated-noble.txt, tests/fixtures/apt/update-clean-resolute.txt, tests/fixtures/apt/README.md]
depends_on: []
```

**Files:** create the four files above. Do not touch anything outside `tests/fixtures/apt/`. Work in a scratch directory from `mktemp -d`. Write nothing under `/etc` on the host.

**Resolute, unprivileged (no sudo):**

1. `d=$(mktemp -d)`; `mkdir -p "$d"/{lists/partial,cache/archives/partial,parts}`.
2. Copy `/etc/apt/sources.list.d/*.list` and `*.sources` into `"$d/parts"`. Skip `*.orig`.
3. Define `A=(-o Dir::State::Lists="$d/lists" -o Dir::Cache="$d/cache" -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$d/parts" -o Debug::NoLocking=1 -o APT::Sandbox::User="$(id -un)")`.
4. Run `apt "${A[@]}" update > clean.txt 2>&1; echo rc=$?`. This is the clean fixture.
5. In `"$d/parts/docker.list"`, replace the `signed-by=` path with `/etc/apt/keyrings/opentofu-archive-keyring.gpg` (a wrong key).
6. Run step 4's command twice more. The second run is the stale fixture. Both must give rc 0.

**Noble and nala (root in containers, never on the host):**

- In `docker run --rm ubuntu:24.04`, install `ca-certificates curl gpg nala`.
- Add Docker's apt source with its real key, and run `apt update`.
- Swap the source's `signed-by` to a throwaway key you generate.
- Run these, capturing output and rc for each:
  1. `apt update 2>&1`, twice;
  2. `nala full-upgrade -y`;
  3. `nala full-upgrade --no-update -y`.
- Repeat the nala pair in `ubuntu:26.04`, set up the same way.

**V1, expiry, unprivileged:**

1. Generate a key that expires about 2 minutes from now (`gpg --quick-gen-key <uid> default default seconds=120` in a scratch `GNUPGHOME`).
2. Build a one-suite local repo (`apt-ftparchive release`, `gpg --clearsign` → `InRelease`) and serve it with `python3 -m http.server --bind 127.0.0.1`.
3. Fetch it with the sandbox options above, `signed-by` set to the exported key, while the key is still valid.
4. Wait past the expiry with a background `sleep`. Run update twice more.
5. Record whether each run prints a considered line with `EXPKEYSIG` or `KEYEXPIRED` and the `http://127.0.0.1` URL.

**`tests/fixtures/apt/README.md`:** one section per fixture: command, apt and nala versions, rc. Then `## V1`, with the result of each expiry run, and `## V2`, with the rc of every apt and nala run above, per release.

**Stop and report `blocker` if:** any `apt update` or nala run over a stale source exits non-zero, or a stale capture holds no considered line with both the URL and the token. Either one breaks the spec's premise.

### Task 2: Parser and HashiCorp reuse

```yaml-task
id: 2
description: Add _apt_stale_signer_hosts and make _hashicorp_rotation_hint_fires use it
role: executor
model: sonnet
tdd: required
requirements: [R2, R3]
acceptance:
  - cmd: '[ "$(bats --count -f "_apt_stale_signer_hosts" tests/setup_env/linux_shared.bats)" -ge 4 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_shared.sh, lib/linux_ubuntu.sh, tests/setup_env/linux_shared.bats]
depends_on: [1]
```

**Files:** `lib/linux_shared.sh` (new function, plus readonly arrays for the prefixes and tokens), `lib/linux_ubuntu.sh` (`_hashicorp_rotation_hint_fires` body only), `tests/setup_env/linux_shared.bats`.

**Behaviour (R2):**

- Read stdin and consider only lines that start with a Global Constraints prefix and contain a token.
- For every `https?://` URL on such a line, take its authority: strip the scheme, then everything from the first `/`, `'` or space.
- Print `host<TAB>token` once per distinct host, in order of first appearance. The token is the first one found on the first line that named the host.
- Print nothing for a token line with no URL.

**Tests (write each RED first).** First add a stub `_apt_stale_signer_hosts() { cat > /dev/null; }` and confirm every test fails for that reason, not with exit 127:

1. `update-stale-rotated-resolute.txt` → output is exactly `download.docker.com<TAB>NO_PUBKEY`.
2. `update-clean-resolute.txt` → empty output.
3. The resolute and noble stale fixtures concatenated → two lines, resolute's host first. If both name the same host, concatenate the noble fixture with `update-hashicorp-stale-rotated.txt` instead, so there are two distinct hosts.
4. A line built by `sed` from the first considered line of the resolute stale fixture, inserting ` https://second.example/x` after its URL → both hosts. The line is derived from real output and is not hand-typed.
5. `_hashicorp_rotation_hint_fires`: the existing tests in `tests/setup_env/linux_ubuntu.bats` pass unchanged (R3, test 9). Its new body:
   `printf '%s\n' "$1" | _apt_stale_signer_hosts | cut -f1 | command grep -qxF apt.releases.hashicorp.com`.

**Interfaces:** produces `_apt_stale_signer_hosts` (reads stdin, prints `host\ttoken` lines, rc 0).

### Task 3: Remedy routing

```yaml-task
id: 3
description: Add _apt_signer_remedy mapping each host apt prints to its remedy text
role: executor
model: sonnet
tdd: required
requirements: [R4]
acceptance:
  - cmd: '[ "$(bats --count -f "_apt_signer_remedy" tests/setup_env/linux_shared.bats)" -ge 7 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_shared.sh, tests/setup_env/linux_shared.bats]
depends_on: [2]
```

**Behaviour:** a `case` on the host returns the text from the spec's Design §3 table, verbatim in substance. Above the `case`, a comment names `_install_ubuntu_nvidia`, `_install_ubuntu_cloud_tools` and `_install_ubuntu_misc` as the guards the remedies depend on.

**Tests:** one per row, asserting the substance:

- `download.docker.com` and `prod-cdn.packages.k8s.io` → `-t developer` and the "persists … publisher's own key" clause;
- `nvidia.github.io` → `nvidia-container-toolkit-keyring.gpg`;
- `packages.cloud.google.com` → `google-cloud-sdk.list`;
- `packages.opentofu.org` → `mktemp -d`, `gpg --show-keys` and `.gpg.new`;
- `packages.microsoft.com` → `MS_GPG_FPR`;
- `download.opensuse.org` → `ALBERT_GPG_FPR`;
- `example.invalid` → `no remedy for this host`.

**Interfaces:** produces `_apt_signer_remedy <host>` (prints one line, rc 0).

### Task 4: nala `--no-update`

```yaml-task
id: 4
description: Pass --no-update to nala full-upgrade after the verb, and update the exact-argv test
role: executor
model: sonnet
tdd: required
requirements: [R1]
acceptance:
  - cmd: 'command grep -qE "nala full-upgrade --no-update " lib/linux_shared.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_shared.sh, tests/setup_env/linux_shared.bats]
depends_on: [3]
```

**Change:** `sudo -H DEBIAN_FRONTEND=noninteractive nala full-upgrade --no-update "${APT_CONFFILE_OPTS[@]}" -y`. Add one comment line explaining why: `apt update` has just refreshed, and nala's own refresh would print a second copy of every signer error. Nothing else in `update_apt_packages` changes.

**Tests (RED first):**

- Edit `linux_shared.bats:127`'s `grep -qxF` to `argv: nala [full-upgrade][--no-update][-o][Dpkg::Options::=--force-confdef][-o][Dpkg::Options::=--force-confold][-y]`. This is the planned edit the spec names. It goes RED before the code change.
- Add a test asserting that the mock call log matches `^nala full-upgrade --no-update` (test 8, order-sensitive).

### Task 5: `run_update` wiring and the apt mock

```yaml-task
id: 5
description: Parse err_apt in run_update, WARN with kept result and per-host detail; add MOCK_APT_STDOUT_FILE
role: executor
model: sonnet
tdd: required
requirements: [R5, R6, R7, R8]
acceptance:
  - cmd: '[ "$(bats --count -f "run_update apt section" tests/setup_env/update_apt.bats 2>/dev/null || printf 0)" -ge 4 ]'
    exit_code: 0
  - cmd: 'command grep -q MOCK_APT_STDOUT_FILE tests/mocks/apt'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/mocks/apt, tests/helpers/common.bash, tests/setup_env/flatpak.bats, tests/setup_env/update_apt.bats]
depends_on: [4]
```

**Mock:** when `MOCK_APT_STDOUT_FILE` is set, `tests/mocks/apt` `cat`s that file to stdout before exiting.

**Helper:** move `_setup_run_update` from `tests/setup_env/flatpak.bats` into `tests/helpers/common.bash` as `setup_run_update_linux`, and have `flatpak.bats` call it. The new file needs the same helper, and a copy would duplicate 11 lines.

**Wiring (`lib/workflows.sh`, apt section):** after `_update_record_end "apt" "${PIPESTATUS[0]}"`, keep the rc and run `_apt_stale_signer_hosts < "${_DOTFILES_RUN_TMPDIR}/err_apt"`. Then:

- **rc 0 and hosts present:**
  1. Read `result_apt` and call `_update_warn "apt" "<that>; signer check failed for <hosts joined by ', '> — see detail"`.
  2. Write `detail_apt` with `>`, one Global-Constraints detail line per host, using `_apt_signer_remedy`.
- **rc ≠ 0 and hosts present:** append the same lines to `detail_apt` with `>>`.

**Tests, new file `tests/setup_env/update_apt.bats`, names prefixed `run_update apt section:`, written RED first:**

1. Stale fixture through the real `update_apt_packages`:
   - status `WARN`;
   - result contains `no changes` or `package(s)`, and `download.docker.com`;
   - `detail_apt` contains `download.docker.com is not updating` and `-t developer`.
2. The same run exits 0 (R7).
3. Stale fixture plus `MOCK_APT_FAIL_SUBCMD=full-upgrade` on the nala mock:
   - status `FAIL`;
   - `detail_apt` holds the error tail, and the stale line after it (R6).
4. Clean fixture → status `OK`, and `detail_apt` absent or free of `is not updating`.

### Task 6: Documentation

```yaml-task
id: 6
description: Document the apt stale-signer WARN and MOCK_APT_STDOUT_FILE in CLAUDE.md (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'command grep -q "MOCK_APT_STDOUT_FILE" CLAUDE.md && command grep -q "signer check failed" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md]
depends_on: [5]
```

**Edits:**

- In the `update` entry, after the flatpak sentence, add one sentence: `-t update` parses `err_apt` for signer failures and WARNs the `apt` row with `signer check failed for <hosts>`, keeping the package result; `detail_apt` names each host's remedy (`_apt_signer_remedy`); `nala full-upgrade` runs `--no-update`.
- In the `tests/mocks/apt-get` knobs bullet, add `MOCK_APT_STDOUT_FILE` (`tests/mocks/apt`: a file printed to stdout).

No suite reads `CLAUDE.md`, so this task's gate is `make lint` plus the grep. The orchestrator's final `make test` covers the branch.

## Orchestrator steps

- [ ] After Task 1: copy the README's V1 and V2 results into the spec as a `## Verification results` section, and commit it on `master`, docs-only. If V1 shows expiry is silent, amend spec §5 and add a P2 backlog row for the doctor expiry check in the same commit.
- [ ] After Task 6: run `make test < /dev/null` once, then Phase 3 (`finishing-a-development-branch`).
- [ ] After merge: V3 on `claude`, and run `-t update` for real.

## Non-goal check

One fresh reviewer-role subagent, `writing-plans/nongoal-check.md`, 2026-10-17. Result: CLEAR 5,
CONFLICT 0, UNCLEAR 0. No plan revision or amendment was needed.

- **N1 CLEAR:** Task 1's `signed-by` swap edits a copy of `docker.list` in a `mktemp -d` scratch
  directory during fixture capture. Neither `-t update` nor `/etc` is touched.
- **N2 CLEAR:** matching `EXPKEYSIG`/`KEYEXPIRED` in apt output is not keyring-expiry parsing. The
  doctor expiry item is only a conditional backlog row.
- **N3 CLEAR:** Task 3 only adds a comment naming the three guards.
- **N4 CLEAR:** Task 2's `lib/linux_ubuntu.sh` edit may shift line numbers, but the base step's
  `apt update` call and message stay unchanged.
- **N5 CLEAR:** a stale signer at rc 0 is WARN and test 2 asserts exit 0. FAIL happens only when
  nala itself fails.
