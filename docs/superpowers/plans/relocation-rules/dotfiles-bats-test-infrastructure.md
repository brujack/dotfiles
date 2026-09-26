### Mock Pattern full reference pointer (superseded by this section)

lead: none

- The full `MOCK_*` env var reference table and the general mock usage pattern live in `dotfiles-bats-test-infrastructure.md` — this group's own suffix target, not a `CLAUDE.md` section.
  trigger: read | `tests/mocks/*`, `MOCK_*` env vars
  covers:
  - a: (none — nothing retained beyond the pointer itself)
  - b: (none — verdict: complete)

### Mock Pattern: pass-through mocks (ln, chmod, mv, cp, tee)

lead: none

- `tests/mocks/ln`, `chmod`, `mv`, `cp` and `tee` pass through to the real binary (`/bin/cmd "$@" 2>/dev/null || true`), so a test asserting real filesystem state gets a real result.
- Set the mock's exit-code variable to a non-zero value to simulate a failure instead of calling through.
  trigger: edit | tests/mocks/ln, tests/mocks/chmod, tests/mocks/mv, tests/mocks/cp, tests/mocks/tee
  covers:
  - a: (none — nothing retained beyond the pointer itself)
  - b: "Set the corresponding exit var to a non-zero value to simula"

### Mock Pattern: env -i strips PATH (pyenv mock placement) -- CLAUDE.md addendum

lead: none

- `env -i` strips `PATH`, so a `PATH`-injected pyenv mock is invisible to `setup_ansible()`'s pyenv calls — place the mock binary at the absolute path `${HOME}/.pyenv/bin/pyenv` instead.
  trigger: edit | lib/developer.sh:setup_ansible, tests/mocks/pyenv
  covers:
  - a: (none — nothing retained beyond the pointer itself)
  - b: "**`env -i` subprocess strips PATH** — `setup_ansible()`'s pye"

### Mock Pattern: tests/mocks/curl short-option cluster parsing

lead: none

- Recognize any `-[a-zA-Z]+` short-option cluster in `tests/mocks/curl`'s arg loop, not just bare `-o`/`--fail`: an `f` anywhere sets fail-mode, a cluster ending in `o` takes the next arg as the `-o` target (production passes `-fsS -o` and `-fLo`, `developer.sh:105`).
- Gate `MOCK_CURL_HTTP_STATUS` on all three: `MOCK_CURL_EXIT` unset, an f-bearing form passed, and the value matching `^[0-9]+$` before comparing `>= 400` (numeric check first, per `shell.md`). `MOCK_CURL_EXIT` always wins when set.
  trigger: edit | tests/mocks/curl
  covers:
  - a: "Production calls curl as `-fsS -o <file> <url>` and `-fLo <fi"
  - b: (none — verdict: complete)

### Mock Pattern: tests/mocks/curl -o write ordering (deferred success write)

lead: none

- `tests/mocks/curl`'s `-o` write is deferred until **after** the exit code is decided, a deliberate deviation from real curl: a simulated failure (`MOCK_CURL_HTTP_STATUS >= 400` or a nonzero `MOCK_CURL_EXIT`) leaves a pre-seeded target file completely unchanged.
- On success it writes `MOCK_CURL_STDOUT` to the target file AND still emits it on stdout — keep the dual emission: `whats-new*.sh`, `_fetch_github_latest` (`lib/workflows.sh`) and `install_homebrew` (`lib/macos.sh`) never pass `-o` and need the stdout copy from this mock.
- Before removing it, verify no current caller both passes `-o` and consumes stdout.
  trigger: edit | tests/mocks/curl
  covers:
  - a: "`-o`'s write is now deferred until after the exit code is "
  - a: "leaves a pre-seeded target file completely unchanged"
  - b: "On success, the mock writes `MOCK_CURL_STDOUT` to the target "

### MAKEFLAGS: --no-print-directory directive and its GNU Make version limit

lead: none

- `Makefile:1`'s `MAKEFLAGS += --no-print-directory` suppresses `Entering`/`Leaving directory` only for a child `make` that inherits it, and only on GNU Make 4.0+ (macOS's 3.81 never prints them).
- It does not cover a direct `make -C` on GNU Make 4.3 (`ubuntu-latest`) — that line prints before the Makefile parses, so an in-file directive is too late. The load-bearing protection is the per-call flag plus the partition below, never this directive alone.
  trigger: edit | Makefile
  covers:
  - a: (none — nothing retained beyond the pointer itself)
  - b: "**The load-bearing protection is the per-call flag and the p"

### MAKEFLAGS: exported env var; guarded vs measuring test partition

lead: none

- `MAKEFLAGS` is an exported env var every spawned `make` inherits — a test capturing `make` output must be guarded or measuring, never neither.
- Guarded: per-call `--no-print-directory` flag, for an exact output-shape assertion.
- Measuring: `env -u MAKEFLAGS` prefix, only to observe directory lines — on GNU Make 4.3 it strips the one working suppression, so never use it for a guarded assertion. Both categories must exist in the suite.
  trigger: edit | tests/*.bats calling make -C
  covers:
  - a: "tests fall into two categories: Use it only for that — on 4."
  - b: "- **Guarded:** Per-call `--no-print-directory` flag (override"

### MAKEFLAGS: partition enforcement test and the git ls-files domain

lead: none

- `tests/scripts/makefile_lint_scope.bats` enforces the partition mechanically: it scans every stdout-capturing `make -C` invocation in its domain and requires each in exactly one category, both sets non-empty.
- Derive that domain from `git ls-files` (the same four-variable `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip), never a hardcoded list — an earlier two-file array excluded the one real violation and still reported clean.
  trigger: edit | tests/scripts/makefile_lint_scope.bats
  covers:
  - a: (none — nothing retained beyond the pointer itself)
  - b: (none — verdict: complete)

### MAKEFLAGS: known gap -- recursive sub-make and -w invisible to the scanner

lead: none

- The partition scanner sees only the invoking line, so it is blind to recursive `$(MAKE)` calls and to `-w`/`--print-directory` — both print `Entering`/`Leaving` with no `-C` on the line that triggers them.
- Not exploitable today (the root `Makefile` has no `$(MAKE)` recipes), but `powershell/Makefile` sits outside this scanner's domain entirely — treat this as an accepted boundary, not a defect to silently fix.
  trigger: read | Makefile, powershell/Makefile
  covers:
  - a: "A line scanner can only see what is on the invoking line."
  - b: (none — verdict: complete)
