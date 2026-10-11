# check-versions: go and python3 from vendor feeds

- **Status:** Draft
- **Backlog row:** `-t check-versions` go and python3 WARN on every run (P2 — bugs and security)

## Problem

`./setup_env.sh -t check-versions` prints `[WARN] could not fetch latest version` for
go and python3 on every run (measured 2026-10-08 on `claude`).

Cause, measured 2026-10-10 against the live API, unauthenticated:

| repo             | `releases/latest` | `releases` | `tags` (first page)                         |
| ---------------- | ----------------- | ---------- | ------------------------------------------- |
| `golang/go`      | 404               | `[]`       | `weekly.2012-03-27`, `weekly.2012-03-22`, … |
| `python/cpython` | 404               | `[]`       | `v3.15.0`, `v3.15.0rc3`, `v3.15.0rc2`, …    |
| `ruby/ruby`      | 200 → `v4.0.7`    | 3          | `v4.0.7`, …                                 |

`_fetch_github_latest` (`lib/workflows.sh`) reads only `releases/latest`, so neither
project can ever answer. This is the same never-worked class as the oh-my-zsh check
deleted in #321. The `/tags` endpoint is not a substitute: go's first page is sorted by
name and starts at 2012.

Each project publishes a first-party feed that does answer. Measured the same day:

| feed                                                                                   | answer                                                                                                          |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `https://go.dev/dl/?mode=json`                                                         | first entry `go1.27.2`, `stable: true`, lists `go1.27.2.linux-amd64.tar.gz`, each file carries `sha256`         |
| `https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false` | 275 rows; filtered to `^Python \d+\.\d+\.\d+$` and sorted numerically, the top three are 3.14.7, 3.14.8, 3.15.0 |

Two independent derivations agree with these: `git ls-remote --tags` on cpython and
`go.googlesource.com/go`, filtered to final-release tags, gave the same 3.15.0 and 1.27.2.

### The write path this fix turns on

Fixing the fetch makes `--update` reachable for go and python3 for the first time. As
written today it would do the wrong thing for both:

- **go.** `_update_version_pin` would rewrite `GO_VER="1.27"` to `"1.27.2"`. `GO_VER` is
  deliberately a series (`lib/constants.sh:39`, `lib/linux_ubuntu.sh:547`); the patch pin
  is `GO_DOWNLOAD_FILENAME`.
- **python3.** `pyproject.toml:14` is `requires-python = "==3.14.*"`. Writing
  `PYTHON_VER="3.15.0"` makes the next venv build run `pyenv virtualenv 3.15.0 ansible`
  followed by `uv sync --frozen` against a lock that admits only 3.14, so the ansible
  venv build fails.

### What the go and python3 lines compare

Today every line compares the **installed** version with latest. For go and python3 that
measures the wrong thing:

- **go.** On macOS `Brewfile:40` installs an unversioned `brew "go"`; on Linux
  `_install_ubuntu_go` installs exactly `GO_DOWNLOAD_FILENAME`. Measured 2026-10-10: the
  Studio runs brew's 1.27.2 and `claude` runs the pinned 1.27.1. An installed-version
  verdict on a mac describes brew, while `--update` writes a Linux pin.
- **python3.** The interpreter depends on the actor. With `PYENV_VERSION=ansible` both
  machines resolve the venv's 3.14.6. Without it, measured 2026-10-10, `/usr/bin/python3`
  is 3.14.4 on `claude` and 3.9.6 (Apple's) on the Studio, and `pyenv global` is unset on
  both. The same command reports different verdicts depending on who runs it.

The pin is what `--update` can change and what every machine shares, so for these two
tools the verdict compares the pin.

## Design

### 1. Feed fetchers

Two new functions in `lib/workflows.sh`, beside `_fetch_github_latest`:

- **`_fetch_go_latest`.** Calls `curl -sf --max-time 10 'https://go.dev/dl/?mode=json'`.
  Among entries with `stable: true` whose `files` include both
  `<version>.linux-amd64.tar.gz` and `<version>.linux-arm64.tar.gz`, `python3` prints the
  **highest** version by numeric tuple, minus the leading `go`. Taking the maximum rather
  than the first entry removes any dependence on the feed's order: go.dev does not promise
  newest-first, and a 1.26.x security patch listed ahead of 1.27.x would otherwise read as
  latest and make `--update` downgrade. Requiring both files means `--update` can only
  write a filename published for every Linux architecture `_LINUX_ARCH` produces.
- **`_fetch_python_latest [series]`.** Calls curl on the python.org releases URL above.
  The body must be a JSON **list**; a dict (the shape a paginated API returns) is a
  failure, because the newest release might then be on a page never read. Measured
  2026-10-10: a bare list of 275 rows back to Python 2.0.1, `limit`/`offset` ignored, no
  `Link` header. `python3` keeps names matching `^Python \d+\.\d+\.\d+$` and prints the
  highest by numeric tuple, or the highest within `series` (`3.14`) when one is given.

Neither sends `GITHUB_TOKEN`: neither host is GitHub.

The parsing runs under whichever `python3` the caller resolves, which outside the venv is
Apple's 3.9.6 on the Studio (measured 2026-10-10). The fetchers' header comment states a
**Python 3.9 floor**: `json`, `re` and tuple comparison only, no `match`, no 3.10+ syntax.
Running them under the venv's interpreter instead would make `check-versions` depend on the
venv existing, so that is rejected.

Every failure prints nothing on stdout and returns non-zero: curl failing, a body that is
not JSON or not the expected shape, no qualifying entry, or `python3` not resolvable.
The caller checks `python3` first and reports it with its own line,
`[WARN] <tool> python3 not found; cannot read the release feed`, so a missing interpreter
is not reported as a feed problem.

### 2. Pin-based verdict for go and python3

A new `_check_one_pin_version` prints the `[OK]`/`[OUTDATED]`/`[WARN]` line shapes of
`_check_one_version`, minus the `installed=` field and the `[SKIP] not installed` branch.
The verdict is about the repo's pin, which exists whether or not this machine has the
tool. An empty fetch result prints `[WARN] <tool> could not fetch latest version` and
counts as a warning, as today.

- **go.** Pinned value: the version in `GO_DOWNLOAD_FILENAME` (`go1.27.1.linux-…` →
  `1.27.1`), not `GO_VER`; an unparseable filename prints
  `[WARN] go could not parse pinned version`. Compared with go's latest across all series.
- **python3.** Pinned value: `PYTHON_VER`. Compared with the latest **within
  `PYTHON_VER`'s major.minor series** (`_fetch_python_latest 3.14`). When the latest
  overall is in a newer series, one extra line follows, not counted in any total and not
  affecting the exit code:

  ```
    [OUTDATED] python3      pinned=3.14.6     latest=3.14.8
    [INFO]     python3      3.15 series available (series move: requires-python, uv lock)
  ```

  **Why go and python3 differ:** `--update` can move go across a minor on its own, so go's
  verdict tracks the latest series. A python series move needs `requires-python` edited
  and `uv lock` re-resolved first (`pyproject.toml:14`), which `--update` deliberately does
  not do. Judging python against a series nothing can reach would leave the line
  `[OUTDATED]` and the command at rc 1 on every run, which is the noise this change exists
  to remove.

`_run_cv_check` routes go and python3 through it. Ruby, yq, shellcheck, vagrant and
gitleaks keep `_check_one_version` and `releases/latest`, unchanged.

### 3. Token-refused path

Today a `GITHUB_TOKEN` containing a line break skips all seven `_run_cv_check` calls and
prints `the 7 checks that send it were not run`. After this change go and python3 send no
token, so they run regardless. The skip covers the five GitHub-backed checks and the
message says `5`. The rc 2 precedence over rc 1 is unchanged.

### 4. `--update`

The OUTDATED line still carries `latest=`, which `_run_cv_check` parses as today.

**Every go and python3 write reports its own result.** Today `_prompt_version_update`
prints `Updated <var> → <new>` whenever the writer returns, without reading its status,
and `sed -i` exits 0 when its pattern matches nothing. For go and python3 the writer
returns non-zero on any refusal or failed read-back, and `Updated` is printed only when it
returned 0. The other tools' writers keep today's behaviour (N1).

- **go: a dedicated writer.** `_update_version_pin` cannot do this. With `pinned=` now
  the filename version, its `s|^GO_VER="1.27.1"|…|` matches nothing, `sed -i` exits 0,
  and only the filename moves. A new `_update_go_pin <latest>` sets `GO_VER` to latest's
  major.minor and `GO_DOWNLOAD_FILENAME` to the full version (latest 1.27.2 → `"1.27"` +
  `go1.27.2.linux-…`; 1.28.0 → `"1.28"` + `go1.28.0.linux-…`).
  It then reads both lines back from the constants file and compares them with the
  **literal source text**, unexpanded:
  `GO_VER="1.28"` and `GO_DOWNLOAD_FILENAME="go1.28.0.linux-${_LINUX_ARCH}.tar.gz"`.
  The file holds `${_LINUX_ARCH}` as text, so comparing against an expanded value would
  reject every correct write. On a mismatch it prints
  `go: pin update failed: <constant> is not <expected>` and returns 1.
- **go: next step and local-series warning.** After a successful write it prints
  `go: next, on macOS run brew upgrade go; on Linux run ./setup_env.sh -t developer`.
  The Linux installer's stamp compares the download URL, so it reinstalls on its own.
  If this machine's `go version` is outside the new `GO_VER` series, it also prints
  `go: this machine runs <installed>, outside the new <GO_VER> series; doctor fails here until go is upgraded`.
  Brew has shipped every go release from 1.25.7 to 1.27.2, both minors included, within
  0–1 days of go.dev (homebrew-core `Formula/g/go.rb` commits against go.dev's release
  history, measured 2026-10-10), so on a mac the gap lasts until the next `brew upgrade`,
  not until brew catches up.
- **python3.** The verdict is already in-series (section 2), so `latest=` is always in
  `PYTHON_VER`'s series and a cross-series write cannot be reached. The writer applies the
  pyenv guard, writes `PYTHON_VER`, reads the line back as literal text
  (`PYTHON_VER="3.14.8"`), and returns 1 with a `pin update failed` line on a mismatch.
- **python3: next step.** After a successful write it prints
  `python3: next, on every machine run brew upgrade pyenv, then pyenv install 3.14.8 && ./setup_env.sh -t ansible`.
  The `&&` matters. `-t ansible` (`setup_ansible`) does not check its own
  `pyenv install`, and when the venv's readlink no longer matches it runs
  `pyenv virtualenv-delete -f ansible` before building the replacement. A failed build
  would leave no venv. `-t recreate-venv` is worse: it deletes first and never installs
  the interpreter (`lib/developer.sh:637,640`), so with a new `PYTHON_VER` it always ends
  with no venv. Installing the interpreter first, and only then running `-t ansible`, is
  the order that keeps the old venv when the build fails. Both installer defects are
  backlog rows; fixing them is an installer change (N2).
- **pyenv guard.** Before writing `PYTHON_VER`, the new version must appear in
  `pyenv install --list` as an exact line, matched as `^[[:space:]]*<version>$` with the
  dots literal. The list also prints free-threaded builds (`3.14.8t`), which must not
  satisfy it. If the version is absent or `pyenv` is not resolvable, nothing is written,
  it prints `python3: pyenv on this machine cannot build <version>; run brew upgrade pyenv`,
  and it returns 1. The guard checks **this machine only**. Both machines get pyenv from
  Homebrew (2.8.9 on each, measured 2026-10-10) but upgrade it on their own schedules,
  which is why the next-step line names every machine.

Ruby and the GitHub-backed tools keep today's `--update` behaviour.

### 5. Docs

- `CLAUDE.md`'s `check-versions` bullet: the rc 2 sentence says seven checks; it becomes
  five. The bullet names go (pin versus latest) and python3 (pin versus latest in its
  series, newer series as `[INFO]`) and their first-party feeds.
- `lib/constants.sh`: the verification comment above `GO_DOWNLOAD_FILENAME` names a
  specific version and goes stale on the first bump; reword it to say what must hold
  (both Linux tarballs published), not which version was checked.

### Out of scope

- **Syncing installed go and python3 across macOS and Linux.** One pinned go on both
  OSes (the mac installing the go.dev tarball instead of `brew "go"`), and `python3`
  outside the venv resolving to the latest Homebrew python on macOS (Apple's 3.9.6 today)
  and something newer than apt's on Linux, per actor. Its own backlog row with the
  measurements; it changes installers and PATH, not this check. It is also what removes
  the Studio doctor failure the go local-series warning names.
- **Verifying the go tarball.** `_install_go_from_tarball` runs a bare `wget` with no
  checksum. go.dev's feed carries `sha256` per file. Backlog row.
- **ruby.** `releases/latest` works today. ruby/ruby also publishes maintenance releases
  (`v3_4_11`), so "latest release" could one day be an older series. Not observed; not
  changed.
- **The installed-versus-latest comparison** for the five GitHub-backed tools.

## Testing

Tests run the real `python3` against fixture JSON delivered through `tests/mocks/curl`'s
`MOCK_CURL_STDOUT`. `tests/mocks/pyenv` gains a mock variable for `install --list` output
(a test knob, not a production seam). Every `--update` case sets
`_OVERRIDE_CONSTANTS_PATH` to a per-test copy of `lib/constants.sh`.

Positive controls pin an exact derived value, so a fetcher that returns nothing, the first
entry, or the last entry cannot pass:

- go fixture, in this order: unstable `go1.29rc1`; stable `go1.26.9`; stable `go1.28.3`
  lacking `linux-arm64`; stable `go1.28.2` with both files; stable `go1.27.5`. Result:
  `1.28.2` (not first, not last, not the highest stable overall).
- python fixture, unsorted: `Python 3.15.0rc1`, `Python install manager 26.4`,
  `Python 3.14.9`, `Python 3.15.1`, `Python 3.10.20`, `Python 3.14.10`. Result:
  `3.15.1`; with series `3.14`: `3.14.10` (numeric, not string, comparison).

Failure cases, each asserting the `[WARN]` line and the warned counter: curl exits 22;
body is not JSON; python body is a JSON dict; no qualifying entry. `python3` not
resolvable (shim `PATH` holding everything the check needs except `python3`) asserts the
`python3 not found` text and the absence of `could not fetch`.

Existing assertions that change: `tests/setup_env/workflows.bats` stubs
`_check_one_version` and asserts totals over seven tools (`7 skipped`, `7 OK`,
`7 outdated`, `runs all seven`, `7 not checked`). go and python3 no longer pass through
that function, so those become five, and the go and python3 lines get their own fixtures.
The existing `16 warnings` case stays green whether or not the fetchers work, so it is
not evidence for them; R19's positive controls are.

Pin verdict:

- go `[OK]` and `[OUTDATED]` against `GO_DOWNLOAD_FILENAME`, with a `go` stub on `PATH`
  reporting a different version, to prove installed is not read; an unparseable filename
  gives the parse WARN.
- python3 with pin 3.14.6, in-series latest 3.14.8, overall 3.15.1: `[OUTDATED]` plus
  `[INFO] … 3.15 series available`, outdated counter 1.
- python3 with pin 3.14.8 (newest in series) and overall 3.15.1: `[OK]` plus `[INFO]`,
  outdated counter 0, function rc 0. This is the steady state the lenses flagged.
- python3 with pin equal to the overall latest: `[OK]`, no `[INFO]` line.

Token-refused: with a line-break token, go and python3 lines still print, and the summary
reports `5 not checked`.

`--update`, each against the fixture constants file:

- go within the series: `GO_VER` unchanged, filename moves to the new patch.
- go across a minor: `GO_VER` and filename both move.
- go write read-back failure (fixture constants file with `GO_VER` missing): rc 1, the
  `pin update failed` line printed, no `Updated` line.
- go read-back on a fixture holding the real unexpanded
  `go1.27.1.linux-${_LINUX_ARCH}.tar.gz`: write succeeds, `Updated` printed, next-step
  line printed. Guards against comparing the expanded value.
- go local-series warning: `go` stub reporting 1.27.1, update to 1.28.0, warning printed;
  stub reporting 1.28.0, no warning.
- python3 write read-back failure (fixture with no `PYTHON_VER=` line): rc 1,
  `pin update failed` printed, no `Updated` line.
- python3, pyenv lists the version: `PYTHON_VER` moves, `Updated` printed, and the
  next-step line printed containing `pyenv install 3.14.8 && ./setup_env.sh -t ansible`
  and not `recreate-venv`.
- python3, pyenv lists only `3.14.8t`: file byte-identical **and** the `cannot build` line
  printed **and** no `Updated` line **and** the pyenv mock recorded an `install --list`
  call, so inert code cannot pass.
- python3, pyenv not resolvable: file byte-identical, the `cannot build` line printed, no
  `Updated` line.

Mutation controls (run once, recorded in the PR body): replace the go max with "first
qualifying entry", drop the arm64 requirement, unanchor the pyenv match, and route go back
through `_update_version_pin`, make the go read-back compare the expanded filename, and
print `Updated` regardless of the writer's status. Each must turn at least one test red.

## Requirements

- **R1.** `[PR1]` `run_check_versions` gets go's latest version from `https://go.dev/dl/?mode=json`: the highest version by numeric comparison among entries with `stable: true` that list both `<version>.linux-amd64.tar.gz` and `<version>.linux-arm64.tar.gz`, printed without the `go` prefix.
- **R2.** `[PR1]` `run_check_versions` gets python3 versions from `https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false`, keeping only names matching `^Python \d+\.\d+\.\d+$` and comparing numerically.
- **R3.** `[PR1]` A python.org body that is not a JSON list is a fetch failure.
- **R4.** `[PR1]` Neither feed request carries `GITHUB_TOKEN` or any `Authorization` header.
- **R5.** `[PR1]` Each feed curl call passes `--max-time 10`.
- **R6.** `[PR1]` Any feed failure (curl non-zero, unparseable body, wrong shape, no qualifying entry) produces `[WARN] <tool> could not fetch latest version` and increments the warned counter; an unresolvable `python3` instead produces `[WARN] <tool> python3 not found; cannot read the release feed` and increments the warned counter.
- **R7.** `[PR1]` The go line compares the version embedded in `GO_DOWNLOAD_FILENAME` with go's latest across all series, never the installed `go`.
- **R8.** `[PR1]` The python3 line compares `PYTHON_VER` with the latest release in `PYTHON_VER`'s major.minor series, never the installed `python3`.
- **R9.** `[PR1]` When python3's latest overall is in a newer series than `PYTHON_VER`, an `[INFO]` line names that series; it increments no counter and does not change the exit code.
- **R10.** `[PR1]` The go and python3 lines have no `not installed` SKIP branch.
- **R11.** `[PR1]` With a `GITHUB_TOKEN` containing a line break, go and python3 are still checked, exactly the five GitHub-backed checks are counted as not checked, and the message names 5.
- **R12.** `[PR1]` `--update` on an OUTDATED go sets `GO_VER` to the major.minor of latest and `GO_DOWNLOAD_FILENAME` to the full latest version, through a go-specific writer that does not call `_update_version_pin`.
- **R13.** `[PR1]` After writing, the go writer reads both constants back and compares them with the literal unexpanded source text (`GO_DOWNLOAD_FILENAME="go<ver>.linux-${_LINUX_ARCH}.tar.gz"`); if either differs it prints a `pin update failed` line naming the constant and returns 1.
- **R14.** `[PR1]` After a successful go write, `--update` prints a next-step line naming `brew upgrade go` for macOS and `./setup_env.sh -t developer` for Linux, plus a warning when this machine's `go version` is outside the new `GO_VER` series and none when it is inside.
- **R15.** `[PR1]` `--update` writes `PYTHON_VER` only when `pyenv install --list` has a line matching `^[[:space:]]*<version>$` with literal dots; otherwise, including when `pyenv` is unresolvable, it writes nothing, prints a line naming `brew upgrade pyenv`, and the writer returns 1.
- **R16.** `[PR1]` After writing `PYTHON_VER`, `--update` prints a next-step line naming `brew upgrade pyenv` on every machine and `pyenv install <version> && ./setup_env.sh -t ansible`; it never names `recreate-venv`.
- **R17.** `[PR1]` The fetchers' header comment states a Python 3.9 floor for their parsing code.
- **R18.** `[PR1]` `CLAUDE.md`'s `check-versions` bullet says five checks for the token-refused case and names go (pin versus latest) and python3 (pin versus latest in its series, newer series as `[INFO]`) and their feeds.
- **R19.** `[PR1]` Each fetcher has a test pinning an exact derived value that is neither the first nor the last qualifying entry of a fixture that also contains entries the filter must reject.
- **R20.** `[PR1]` A test covers python3 pinned at the newest patch of its series while a newer series exists, asserting `[OK]`, the `[INFO]` line, an outdated count of 0 and rc 0.
- **R21.** `[PR1]` The python3 writer reads `PYTHON_VER` back as literal text after writing; on a mismatch it prints a `pin update failed` line and returns 1.
- **R22.** `[PR1]` For go and python3, `--update` prints `Updated <var> → <new>` only when the writer returned 0.
- **V1.** On `claude` and the Studio, `./setup_env.sh -t check-versions` prints `[OK]` or `[OUTDATED]` (not `[WARN]`) for both go and python3, and exits 0 when every pin is current.
- **V2.** Both fetchers return the expected value when run under the Studio's `/usr/bin/python3` (3.9.6) via `env -i`.
- **V3.** Mutation: go max replaced with first qualifying entry, arm64 requirement dropped, pyenv match unanchored, go routed through `_update_version_pin` — each turns at least one test red.
- **N1.** No change to the line format, comparison or `--update` behaviour of ruby, yq, shellcheck, vagrant, gitleaks, homebrew-install or the cargo checks.
- **N2.** No change to how go or python3 is installed on any OS, and no `Brewfile`, `pyproject.toml` or `uv.lock` change.
- **N3.** `--update` never writes `PYTHON_VER` to a version in a different major.minor series from its current value.
- **N4.** No new environment-variable seam.
- **N5.** The `[INFO]` line never increments the outdated, warned, skipped or OK counters.

## Multi-Lens Review

Reviewed at commit: `bd9b9def` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The python3 verdict (R2, latest across all series) replaces a permanent WARN with a permanent `[OUTDATED] python3 pinned=3.14.x latest=3.15.0` and a permanent rc 1, because the series move is deliberately outside `--update` (R11). Reads-it test: the line changes no decision and has no durable consumer, so it is decoration that costs rc 1. Fix already in the spec, in the wrong layer: make the in-series latest the verdict and report a newer series on a non-failing line. Simpler path: make go and python3 report-only (like homebrew-install) and drop R10-R13 — pin bumps are rare (4 commits since 2026-05). V1 cannot catch the always-OUTDATED state.
Assumption: the python.org v2 endpoint returns every release unpaginated. Checked by orchestrator 2026-10-10: bare list, 275 rows back to 2.0.1, `limit`/`offset` ignored, no `Link` header — holds today; a dict-shaped body would be the paginated tell.
Disposition: Addressed (operator, 2026-10-10) — python3 verdict is now the latest in `PYTHON_VER`'s series with a non-counted `[INFO]` line for a newer series (R8, R9, N5); the go/python asymmetry is stated in Design §2. Report-only alternative rejected: the operator wants `--update` to pull latest, and a go series move is the case it automates. python.org shape guard added (R3).

### Ergonomics

Finding: Same as Goal-Fit, found independently: python3 OUTDATED on every run while 3.15 exists, `check-versions` exits 1 daily, training the operator to skip the report and the next real go patch with it. Fix: judge python3 within its series; print a newer series as a non-counted `[INFO]` line. Secondary: after `--update` bumps `PYTHON_VER`, doctor reports drift until the venv is rebuilt; print the next step (`-t recreate-venv`). Missing test: pin at newest in-series patch while a newer series exists.
Assumption: the python.org `/api/v2/downloads/release/` endpoint is a stable public interface; it is pydotorg's site API with no documented compatibility promise.
Disposition: Addressed (operator, 2026-10-10) — same verdict change; post-bump next-step line naming `-t recreate-venv` (R16); steady-state test added (R20).

### Risk

Finding: (1) The go write cannot use today's `_update_version_pin`: with `pinned=` now the filename version, `s|^GO_VER="1.27.1"|…|` matches nothing, `sed -i` exits 0, the helper prints "Updated", and the filename moves alone — `GO_VER="1.27"` beside a 1.28.0 tarball, so the installer warns and doctor fails. Passing GO_VER's values instead writes `go1.28.linux-…`, a 404. Specify a go-specific two-value writer that reads both lines back and fails loudly. (2) The pyenv guard's match is unspecified; `pyenv install --list` also prints `3.14.8t`, so an unanchored grep passes on only the free-threaded build. Require an anchored literal match plus a `t`-only fixture. (3) The Studio's doctor FAILs whenever `GO_VER` and brew's go are in different series; state it or backlog it. Tests: "file byte-identical" cases are satisfied by inert code (tdd.md E5) and need a positive companion.
Assumption: go.dev's feed is ordered newest-version-first; nothing guarantees it. A 1.26.x patch published after 1.27.x would be picked as latest, or make `--update` downgrade. Taking the maximum stable version removes the dependency.
Disposition: Addressed (operator, 2026-10-10) — go-specific writer with read-back and loud failure (R12, R13); go latest is the maximum stable version, not the first entry (R1); anchored literal pyenv match and a `3.14.8t`-only fixture (R15); byte-identical tests gain a positive companion; Studio doctor consequence gets a local-series warning (R14) plus the sync backlog row. Peer review (operator's architect session) added: guard is local-only, stated, with a every-machine next step (R16); Python 3.9 parser floor (R17, V2).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `92268a84` (all three lenses re-run: the round-1 revision changed design substance)

- **Goal-Fit.** Finding: §4 (`--update`) is out of proportion to its value — no `check-versions --update` in shell history, four hand bumps in PRs since 2026-06, and a constants edit lands as a PR regardless; report-only (the `homebrew-install` precedent) keeps most of the value. Assumption: pins will be bumped through `--update` rather than by hand. Disposition: Accepted, reason: operator chose to keep the writers (option B over report-only, 2026-10-10).
- **Ergonomics.** Finding: blocker — R16's `-t recreate-venv` deletes the venv then runs `pyenv virtualenv` on an uninstalled interpreter (`lib/developer.sh:637,640`), ending with no venv; the pyenv guard proves buildable, not installed. Assumption: the documented next step finishes non-interactively on `claude`. Disposition: Addressed — next step is `pyenv install <ver> && ./setup_env.sh -t ansible` (R16); orchestrator measured `setup_ansible`'s unchecked install and the missing linuxbrew `pyenv update`, both backlogged.
- **Risk.** Finding: python3 refusals could still print `Updated` (`_prompt_version_update` ignores the writer's status); python write never read back; go read-back must compare the unexpanded `${_LINUX_ARCH}` text; missing `python3` misreported as a feed failure; existing `7 …` assertions become 5. Assumption: brew's go tracks go.dev closely — orchestrator measured 0–1 day lag across 12 releases (1.25.7–1.27.2). Disposition: Addressed — R6, R13, R21, R22, test list updated.
