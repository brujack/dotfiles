# ADR-0058: Pin uv for the requirements renderings and the lock check

**Date:** 2026-11-19
**Status:** Accepted

## Context

`make check-requirements-ci` renders the five `requirements-ci*.txt` files from `uv.lock`
and compares them with the committed copies; `make check-lock` runs `uv lock --check`.
Both used whatever `uv` was first on `PATH`. CI installs a pinned, checksum-verified uv
0.13.0. Developer machines get `brew "uv"` unpinned, and `-t update` runs
`brew upgrade --yes`, so the local tool drifts from CI's on brew's schedule.

`specs/2026-08-20-brewfile-uv-design.md` chose unpinned brew uv and rejected a pinned
binary "for now", because nothing yet consumed uv. It predicted that skew would first
appear as a lockfile disagreement. It did: on 2026-11-19 brew uv 0.13.9 rendered
`pywinpty`'s environment marker differently from 0.13.0, so `check-requirements-ci`
reported `DRIFT: requirements-runtime-ci.txt` on a correct tree. The pre-push hook runs
`make test`, so every dotfiles push from `claude` failed. Under a bare environment the
drift reproduced, so it came from the uv version, not local config.

Alternatives weighed in the spec and rejected:

- **Bump CI's pin to 0.13.9.** Fixes today's skew; the next `brew upgrade` brings it back.
- **A version guard only.** Turns a misleading DRIFT into an honest refusal, but every push
  stays blocked and the fix stays manual.
- **Fetch the pinned uv inside the check.** Puts the network inside `make test` and breaks
  offline pushes.
- **`brew pin uv`.** A `Brewfile` cannot express a pin, and pin state is machine-local and
  untracked (the 2026-08-20 spec's own reason).
- **uv as a PyPI package in `uv.lock`.** The weekly `uv-lock-refresh` would move the
  renderer, a rendering would gain a `uv` line that ai-config and state-ledger then
  install, the check would depend on the ansible venv's health, and the lock would pin its
  own renderer.

## Decision

The renderings (`check-requirements-ci`, `sync-requirements-ci`) and `check-lock` run only
a pinned uv, never the uv on `PATH`:

- `UV_VER` and per-asset sha256 pins (`UV_SHA256_LINUX_AMD64`, `UV_SHA256_DARWIN_ARM64`)
  live in `lib/constants.sh`, refreshed by `scripts/refresh-sha256-pins.sh uv`.
- The binary installs to `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv`: versioned,
  user-owned, not on `PATH`. Setup installs it under `HAS_DEVTOOLS`, `-t update` has a
  `pinned-uv` section, and `make install-pinned-uv` installs it on demand from the
  checkout's own `UV_VER`.
- `resolve_pinned_uv` (`lib/helpers.sh`) reads only `${PINNED_UV_BIN:-<that path>}` and
  accepts it only when its `--version` matches `^uv <UV_VER>( |$)`.
- Absent, non-executable or wrong-version uv fails closed with the remedy
  `make install-pinned-uv`, locally and in CI alike; there is no `REQUIRE_TOOLS` skip.
- CI's three uv-installing jobs set `PINNED_UV_BIN: /usr/local/bin/uv`, and
  `tests/scripts/ci_uv_pin.bats` keeps each job's `UV_VER`/`UV_SHA256` equal to
  `lib/constants.sh`, per job.

Brew's uv stays for everyday use, and the venv `uv sync` callers keep `resolve_uv`.

## Consequences

- Local and CI renderings come from the same uv, so a brew upgrade can no longer turn a
  correct tree red or a drifted one green.
- A uv bump is one change: `UV_VER` plus `refresh-sha256-pins.sh uv`, the three CI blocks
  (the equality test fails until they match), then `make install-pinned-uv` on each
  machine. The versioned path lets branches on either side of a bump coexist on one box.
- Every machine that pushes dotfiles needs the pinned uv once; until then pushes fail with
  the remedy named. It was installed by hand on claude, studio, workstation and laptop
  before this merged.
- Superseded versions stay on disk (about 50 MB each); nothing prunes them.
- Accepted risk: a future brew uv may write a `uv.lock` that 0.13.0 rejects. CI's pinned
  0.13.0 would reject it too, so that forces a pin bump either way. Measured 2026-11-19, a
  brew-0.13.9 lock passed 0.13.0's `lock --check` for both a constraint change and a newly
  added marker-bearing dependency.
- Test-only seams `_UV_PINNED_URL`, `_UV_PINNED_SHA256` and `_UV_PINNED_INSTALLER` are
  honoured only when `BATS_TEST_TMPDIR` is non-empty, so a stray export cannot replace the
  in-repo digest or the installer on a real run.

## Related

- [Spec: pinned uv for the requirements renderings and the lock check](../superpowers/specs/2026-11-19-pinned-uv-renderings-design.md)
- [Plan](../superpowers/plans/2026-11-19-pinned-uv-renderings.md)
- [Spec: brewfile uv (the reversed deferral)](../superpowers/specs/2026-08-20-brewfile-uv-design.md)
- [ADR-0056: weekly uv.lock refresh](0056-weekly-uv-lock-refresh-workflow.md)
- ai-config `docs/knowledge/dotfiles-test-seams.md` § `pinned uv seam`
