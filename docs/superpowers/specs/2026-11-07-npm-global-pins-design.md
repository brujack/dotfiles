# npm global pins: Windows firecrawl-cli, and the firecrawl and context7 MCP servers

- **Status:** Draft
- **Date:** 2026-11-07

## Problem

Two npm-global pin gaps, bundled by operator decision (2026-11-07) because both edit the
same pin set.

1. **Windows installs `firecrawl-cli` unpinned.** `powershell/setup_windows.ps1:103`
   (`Set-NpmGlobalPackages`) runs `npm install -g firecrawl-cli`, and
   `powershell/tests/setup_windows.Tests.ps1:728` asserts that bare call. Bash pins the same
   package as `FIRECRAWL_CLI_VER="1.26.3"` (`lib/constants.sh:26`) at both install sites in
   `lib/workflows.sh`. The Windows box is the backup of last resort, so it is the machine
   least likely to be checked when it floats to a new release. This is backlog row 379
   (`docs/superpowers/README.md`), verified on `9699abe3`.
2. **The firecrawl and context7 MCP servers are not installed binaries.** ai-config is
   moving its MCP wrappers from `npx -y <pkg>` to exec'ing an installed binary, the shape
   `exa-mcp.sh` already uses with `exa-mcp-server`. The first-launch `npx` download is what
   timed out Exa. context7 also moves from HTTP with a header stored in `~/.claude.json` to
   stdio, reading its key from `~/.context7_api` at launch. dotfiles installs
   `exa-mcp-server` but neither `firecrawl-mcp` nor `context7-mcp`. Measured on `claude`,
   2026-11-07: `npm ls -g --depth=0` lists `exa-mcp-server@3.4.2` and
   `firecrawl-cli@1.26.3`, and nothing else MCP-related.

Registry facts, measured with `npm view` on 2026-11-07:

| package | version | `bin` | license |
| --- | --- | --- | --- |
| `firecrawl-mcp` | 3.38.0 | `firecrawl-mcp` | MIT |
| `@upstash/context7-mcp` | 4.4.4 | `context7-mcp` | MIT |

The versions come from the ai-config session. firecrawl-mcp 3.38.0 is the operator's
choice and is what runs on `claude` through `npx`. For context7, 4.4.4 was released
2026-10-19, and 4.5.1 was one day old when requested.

## Premise check: the pin test is blind to scoped packages

`assert_all_npm_globals_pinned` (`tests/setup_env/workflows.bats:2640`) treats a token as
pinned when it matches `*@?*`. `@upstash/context7-mcp` with no version matches that pattern
through its scope `@`. So once the first scoped package is added, the helper would pass an
unpinned install. No scoped package is installed today, which is why this has never
mattered.

## Design

### A. Windows firecrawl-cli: a copy guarded by a drift test

The operator chose this over PowerShell parsing `lib/constants.sh` and over a shared pin
manifest. PowerShell cannot source a bash file, and parsing one ties the `.ps1` to the bash
file's layout.

- `powershell/setup_windows.ps1` defines one script-scope literal after `param()`:
  `$FirecrawlCliVersion = '1.26.3'`. Its comment names `FIRECRAWL_CLI_VER` in
  `lib/constants.sh` and the bats test that keeps the two equal.
  `Set-NpmGlobalPackages` installs `"firecrawl-cli@$FirecrawlCliVersion"`.
- The Pester test at `setup_windows.Tests.ps1:728` asserts that some npm argument matches
  `^firecrawl-cli@\d+\.\d+\.\d+$` and that no argument is the bare `firecrawl-cli`. It does
  not repeat the version, so there is no third copy.
- A new `tests/scripts/windows_npm_pins.bats` extracts the version from each file and
  requires exactly one definition per file, matching `^[0-9]+\.[0-9]+\.[0-9]+$`, with the
  two values equal. A failure names both files and both values.
- The `lib/constants.sh` comment on `FIRECRAWL_CLI_VER` names the `.ps1` copy and the test.

### B. Pin and install firecrawl-mcp and context7-mcp

Treat each package exactly like `EXA_MCP_SERVER_VER`:

- `lib/constants.sh` gains `FIRECRAWL_MCP_VER="3.38.0"` and `CONTEXT7_MCP_VER="4.4.4"`, in
  alphabetical order, each with the standard `# read by` comment.
- `_require_npm_pins` checks both.
- `run_developer_or_ansible` adds one install block for each, after exa:
  `npm install -g "firecrawl-mcp@${FIRECRAWL_MCP_VER}"` and
  `npm install -g "@upstash/context7-mcp@${CONTEXT7_MCP_VER}"`, both `|| return 1`.
- The single `npm install -g` call in `run_update`'s npm section lists both.
- Windows is out of scope: `setup_windows.ps1` does not install exa either, and the
  ai-config wrappers are bash scripts that are not linked on native Windows (the CLAUDE.md
  "Hooks gap").

### C. Fix the pin assertion for scoped names

`assert_all_npm_globals_pinned` judges a token pinned only when a non-empty version
follows the last `@`, and that `@` is not at position 0. In other words the token is
`<name>@<ver>` or `@<scope>/<name>@<ver>`, and `@<scope>/<name>` with no version fails.

### Tests (bats, `tests/setup_env/workflows.bats`)

- "pins every npm global package" also greps `firecrawl-mcp@3.38.0` and
  `@upstash/context7-mcp@4.4.4`.
- The `run_update` pinned test also greps both, anchored at line start. The stale comment
  about "all three packages" becomes count-free.
- "names every missing pin" also blanks the two new pins and asserts both names appear.
- A new test checks `assert_all_npm_globals_pinned` against four tokens: unpinned scoped
  `@upstash/context7-mcp` (rc 1), pinned scoped (rc 0), bare unscoped (rc 1), and
  `pkg@` with an empty version (rc 1).

### Docs

- Backlog row 379 is deleted, because A resolves it.
- Backlog row 378 (npm pin bump path) stops counting pins ("three npm pins"). It names the
  hand-bumped set by pointing at `lib/constants.sh` and notes that a `FIRECRAWL_CLI_VER`
  bump also needs the `.ps1` copy, which the drift test enforces.
- The CLAUDE.md line on `setup_windows.ps1 -update` says the `firecrawl-cli` install is
  pinned and names the drift test.

### Rollout

**This PR must merge before ai-config's wrapper PR, and the binaries must be installed
before that PR lands.** `~/.claude/scripts` is a symlink into ai-config's main checkout, so
the moment ai-config's PR merges, its firecrawl wrapper execs `firecrawl-mcp`. On any
machine without that binary, firecrawl is then down. The ai-config session corrected its
earlier "safe to land first" on 2026-11-07, and is holding its PR.

The binaries are installed by `./setup_env.sh -t developer` or by `-t update` with the npm
section (a full run, or `UPDATE_CLAUDE`). `-t setup_user` does not run the npm installs, so
it is not the step to use.

## Requirements

- **R1.** `[A]` `powershell/setup_windows.ps1` installs `firecrawl-cli` only as `firecrawl-cli@$FirecrawlCliVersion`, where `$FirecrawlCliVersion` is a single literal `'1.26.3'`.
- **R2.** `[A]` The Pester test fails if `Set-NpmGlobalPackages` passes a bare `firecrawl-cli`, and passes on any `firecrawl-cli@X.Y.Z`.
- **R3.** `[A]` `tests/scripts/windows_npm_pins.bats` fails when the `.ps1` version differs from `FIRECRAWL_CLI_VER`, when either file has zero or more than one definition, or when either value is not `X.Y.Z`.
- **R4.** `[B]` `lib/constants.sh` defines `FIRECRAWL_MCP_VER="3.38.0"` and `CONTEXT7_MCP_VER="4.4.4"`.
- **R5.** `[B]` `_require_npm_pins` returns non-zero and names `FIRECRAWL_MCP_VER` or `CONTEXT7_MCP_VER` when either is unset or empty.
- **R6.** `[B]` `run_developer_or_ansible` installs `firecrawl-mcp@${FIRECRAWL_MCP_VER}` and `@upstash/context7-mcp@${CONTEXT7_MCP_VER}`, and `run_update`'s npm section installs both in its single `npm install -g` call.
- **R7.** `[C]` `assert_all_npm_globals_pinned` rejects `@upstash/context7-mcp` and `pkg@`, and accepts `@upstash/context7-mcp@4.4.4` and `pkg@1.2.3`.
- **R8.** `[Docs]` Backlog row 379 is removed, row 378 carries no pin count, and the CLAUDE.md `setup_windows.ps1 -update` line says the install is pinned.
- **V1.** `make test` exits 0 with 0 `not ok`. Changing one of the two firecrawl-cli literals turns `windows_npm_pins.bats` red. Reverting R7's helper change turns the new scoped-token test red.
- **V2.** The CI `powershell` job passes, since Pester is not installed on `claude`.
- **V3.** After merge, `./setup_env.sh -t update` with the npm section on `claude` leaves `firecrawl-mcp` and `context7-mcp` on `PATH` at the pinned versions.
- **N1.** No PowerShell code reads `lib/constants.sh`, and no shared pin manifest is introduced.
- **N2.** No MCP server package is installed on native Windows.
- **N3.** No other npm pin changes value, and `firecrawl-cli` stays installed on every platform.
