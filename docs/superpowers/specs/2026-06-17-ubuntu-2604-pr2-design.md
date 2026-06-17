# PR2: Ubuntu 26.04 — Docker cgroup v2, passlib, glances via apt

## Context

Follow-up to PR #143 (PR1: detection + package files). Fixes three platform-level
breakages that affect every fresh Ubuntu 26.04 setup:

- **P0-5** Docker `daemon.json` missing — cgroup v1 gone in systemd 259 / kernel 7.0
- **P0-6** `passlib` absent from ansible venv — Python 3.13 removes stdlib `crypt` module
- **P1-2** `python -m pip install glances` — PEP 668 externally-managed error on 26.04

## Design

### 1. Docker daemon.json (P0-5)

**File:** `lib/linux_ubuntu.sh:_install_ubuntu_docker`

After the Docker package installs, add an idempotent write:

```bash
local _daemon_json="${_DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}"
if [[ ! -f ${_daemon_json} ]]; then
  printf "Configuring Docker for cgroup v2\n"
  printf '{"exec-opts": ["native.cgroupdriver=systemd"]}\n' | \
    sudo tee "${_daemon_json}" > /dev/null
fi
```

`_DOCKER_DAEMON_JSON` is a test seam variable following the `_OVERRIDE_ZSH_PATH` pattern
in `helpers.sh`. Tests set it to a `BATS_TEST_TMPDIR` path; production leaves it unset.

Runs on all Ubuntu (Noble + Resolute) — harmless on Noble, required on Resolute.
Never overwrites an existing `daemon.json` (user may have custom config).

**Tests** (`tests/setup_env/linux_ubuntu.bats`):

1. HAS_DOCKER=1, no pre-existing daemon.json → assert `tee` called with daemon.json path
2. HAS_DOCKER=1, daemon.json already exists → assert `tee` NOT called
3. HAS_DOCKER unset → existing test still passes (no-op)

### 2. passlib in ansible venv (P0-6)

**File:** `lib/developer.sh`

Add `passlib` to `_pip_pkgs` in both install sites (lines ~197 and ~227):

```bash
local _pip_pkgs=(ansible ansible-lint certbot certbot-dns-cloudflare checkov \
  boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli \
  wheel shell-gpt pyright cosmic-ray hypothesis passlib)
```

`passlib` is a pure-Python drop-in for stdlib `crypt`, zero risk to add. Preempts any
transitive dependency that still imports `crypt` on Python 3.13.

**Tests** (`tests/setup_env/developer.bats`): update the existing `setup_ansible` pip
install test to assert `passlib` appears in the `pip install` call.

### 3. Glances via apt (P1-2)

**Two changes:**

**`ubuntu_common_packages.txt`** — add `glances` (available in Ubuntu universe on Noble
and Resolute; confirmed present via packages.ubuntu.com at time of audit):

```
...
glances
...
```

**`lib/linux_ubuntu.sh:_install_ubuntu_misc`** — remove the `python -m pip install
glances` block (3 lines):

```bash
# REMOVE:
python -m pip install glances
if [[ -x $(command -v glances) ]]; then
  printf "glances is installed\n"
fi
```

**Tests** (`tests/setup_env/linux_ubuntu.bats`): add new regression test:

```bash
@test "_install_ubuntu_misc: does not pip install glances" {
  run _install_ubuntu_misc
  run grep "pip.*glances" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}
```

No existing glances test to update — this is a new regression guard.

## Files Changed

| File                                | Change                                                                                                |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `lib/linux_ubuntu.sh`               | Add daemon.json write in `_install_ubuntu_docker`; remove glances pip block in `_install_ubuntu_misc` |
| `lib/developer.sh`                  | Add `passlib` to `_pip_pkgs` in two locations                                                         |
| `ubuntu_common_packages.txt`        | Add `glances`                                                                                         |
| `tests/setup_env/linux_ubuntu.bats` | 2 new docker daemon.json tests; update misc test                                                      |
| `tests/setup_env/developer.bats`    | Update setup_ansible test to assert passlib                                                           |

## Acceptance Criteria

- `_install_ubuntu_docker` with `HAS_DOCKER=1` and no daemon.json → writes `daemon.json`
- `_install_ubuntu_docker` with `HAS_DOCKER=1` and existing daemon.json → leaves it alone
- `setup_ansible` pip install call includes `passlib`
- `_install_ubuntu_misc` no longer calls `pip install glances`
- `glances` in `ubuntu_common_packages.txt`
- `make test` passes, coverage ≥90%
