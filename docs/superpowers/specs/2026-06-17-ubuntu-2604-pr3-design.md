# Ubuntu 26.04 PR3: Package + Ruby + Go PPA Cleanup

**PR title:** `fix(packages): nala, ruby, Go PPA cleanup`
**Items:** P1-1, P1-3, P1-4, P1-5, P2-4
**Depends on:** PR1 (RESOLUTE detection), PR2 (Docker/Python fixes) — both merged

---

## Context

PRs 1 and 2 landed core 26.04 detection and the two P0 runtime blockers. PR3 addresses five
high-probability failure points in package management, Ruby toolchain setup, and Go installation
that would corrupt or silently skip work on a fresh 26.04 machine.

---

## Changes

### P1-1 — Nala: version-branch install (`lib/helpers.sh`)

**Problem:** `check_and_install_nala()` fetches a 2022-era volian archive `.deb` unconditionally.
Nala is in the Ubuntu 26.04 universe repo — the volian bootstrap is unnecessary and the hardcoded
URL may rot.

**Fix:** Branch on `RESOLUTE`:

- `RESOLUTE` → `sudo apt install nala -y` (direct apt install, idempotent via `command -v nala` guard)
- `NOBLE` (or unset) → existing volian wget path unchanged

**Idempotency:** existing `command -v nala` guard already gates the whole function; no change needed
there.

**Tests:**

- `RESOLUTE=1` → mock `apt`; assert nala installed via apt, volian wget NOT called
- `NOBLE=1` → mock `wget`; assert volian wget called, apt nala NOT called

---

### P1-3 — Remove `ruby-full` from common packages (`ubuntu_common_packages.txt`)

**Problem:** `ruby-full` installs system Ruby 3.4+ alongside rbenv. The system Ruby shadows rbenv's
Ruby until `rbenv global` is explicitly set — setup completes silently with wrong Ruby version
active.

**Fix:** Remove the `ruby-full` line. rbenv is the sole Ruby manager on Linux (`lib/developer.sh`
installs it); no other code path needs system Ruby.

**Tests:** None — package list change, no BATS logic involved. Verified by absence of `ruby-full`
in file.

---

### P1-4 — rbenv install guard (`lib/developer.sh`)

**Problem:** `rbenv install ${RUBY_VER}` with `RUBY_VER="4.0.5"` — Ruby 4 definitions lag behind
`ruby-build` releases on new LTS cycles. No guard; `rbenv install` exits non-zero if the
definition is missing, causing `install_ruby()` to return an error and halting developer setup.

**Fix:** Before `rbenv install`, check:

```bash
if ! rbenv install --list 2>/dev/null | grep -q "^ ${RUBY_VER}$"; then
  log_warn "ruby-build has no definition for Ruby ${RUBY_VER} — skipping rbenv install"
  log_warn "Run 'rbenv install ${RUBY_VER}' manually once ruby-build is updated"
  return 0
fi
```

Skip is non-fatal (`return 0`) — missing a Ruby version on setup day does not block the rest of
developer tooling.

**Tests:**

- `rbenv install --list` includes version → `rbenv install` called
- `rbenv install --list` excludes version → `log_warn` called, `rbenv install` NOT called, returns 0

---

### P1-5 — Remove Go PPA path (`lib/linux_ubuntu.sh`)

**Problem:** `_install_ubuntu_go()` (around line 97) has an `if [[ ${_minor} -lt 21 ]]` branch
that installs Go via `ppa:longsleep/golang-backports`. With `GO_VER="1.26"`, `_minor=26 ≥ 21` —
the PPA branch is dead code. The PPA is also slow to publish definitions for new LTS releases.

**Fix:** Remove the entire `if/elif/else` conditional. Keep only the tarball download path
(the current `else` branch). The `_minor` local variable and the PPA `add-apt-repository` call are
removed entirely.

**Tests:**

- `_install_ubuntu_go` calls tarball wget (existing test pattern)
- No call to `add-apt-repository` or `longsleep` in any mock call log

---

### P2-4 — Package list cleanup (`ubuntu_common_packages.txt`)

**Problem:**

- `xinetd` — removed from Ubuntu universe in 26.04; `apt install` fails
- `ruby-full` — already removed by P1-3 (same file, handled there)
- `python3-pip` — PEP 668 prevents `pip install --user` without `--break-system-packages`;
  users who run pip after setup hit a confusing error

**Fix:**

- Remove `xinetd`
- Add comment above `python3-pip`: `# PEP 668: use pipx or a pyenv venv — pip install --user is blocked on 26.04`

**Tests:** None — package list change. Verified by file inspection.

---

## Acceptance Criteria

1. `make test` passes (lint + all BATS tests, ≥753 tests)
2. `check_and_install_nala`: on `RESOLUTE`, uses apt; on `NOBLE`, uses volian wget
3. `ubuntu_common_packages.txt` contains neither `ruby-full` nor `xinetd`
4. `install_ruby()`: when `ruby-build` lacks the version, logs warning and returns 0 without calling `rbenv install`
5. `_install_ubuntu_go()`: no PPA branch, tarball path only
6. Coverage ≥ 90% (bash-coverage CI gate)

---

## Files Touched

| File                         | Change                                                             |
| ---------------------------- | ------------------------------------------------------------------ |
| `lib/helpers.sh`             | P1-1: branch nala install on `RESOLUTE` vs `NOBLE`                 |
| `lib/developer.sh`           | P1-4: add rbenv version guard before `rbenv install`               |
| `lib/linux_ubuntu.sh`        | P1-5: remove Go PPA branch, tarball-only                           |
| `ubuntu_common_packages.txt` | P1-3 + P2-4: remove `ruby-full`, `xinetd`; annotate `python3-pip`  |
| `tests/setup_env/unit.bats`  | Tests for P1-1 (nala branching), P1-4 (rbenv guard), P1-5 (no PPA) |
