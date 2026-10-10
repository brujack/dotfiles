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
  `python3` prints the first entry with `stable: true` whose `files` include both
  `<version>.linux-amd64.tar.gz` and `<version>.linux-arm64.tar.gz`, minus the leading
  `go`. Requiring both files means `--update` can only write a filename that is published
  for every Linux architecture `_LINUX_ARCH` produces.
- **`_fetch_python_latest [series]`.** Calls curl on the python.org releases URL above.
  `python3` keeps names matching `^Python \d+\.\d+\.\d+$` and prints the highest by
  numeric tuple. With a `series` argument (`3.14`), it prints the highest within that
  series instead.

Neither sends `GITHUB_TOKEN`: neither host is GitHub.

Every failure prints nothing on stdout and returns non-zero: curl failing, a body that is
not JSON or not the expected shape, no qualifying entry, or `python3` not resolvable. An
empty result is what `_check_one_version` already turns into
`[WARN] <tool> could not fetch latest version`, so the existing WARN path and counter are
reused.

### 2. Pin-based verdict for go and python3

A new `_check_one_pin_version <tool> <pinned> <latest-fetcher>` prints the same four line
shapes as `_check_one_version`, minus the `installed=` field and the `[SKIP] not installed`
branch:

```
  [OK]       go           pinned=1.27.2     latest=1.27.2
  [OUTDATED] go           pinned=1.27.1     latest=1.27.2
  [WARN]     python3      could not fetch latest version
```

- **go's pinned value** is the version in `GO_DOWNLOAD_FILENAME` (`go1.27.1.linux-…` →
  `1.27.1`), not `GO_VER`. A filename the pattern cannot parse prints
  `[WARN] go could not parse pinned version`.
- **python3's pinned value** is `PYTHON_VER`.
- There is no `not installed` SKIP. The verdict is about the repo's pin, which exists
  whether or not this machine has the tool.

`_run_cv_check` routes go and python3 through it. Ruby, yq, shellcheck, vagrant and
gitleaks keep `_check_one_version` and `releases/latest`, unchanged.

### 3. Token-refused path

Today a `GITHUB_TOKEN` containing a line break skips all seven `_run_cv_check` calls and
prints `the 7 checks that send it were not run`. After this change go and python3 send no
token, so they run regardless. The skip covers the five GitHub-backed checks and the
message says `5`. The rc 2 precedence over rc 1 is unchanged.

### 4. `--update`

The OUTDATED line still carries `latest=`, which `_run_cv_check` parses as today.

- **go.** `GO_VER` becomes the major.minor of latest, and `GO_DOWNLOAD_FILENAME` becomes
  the full latest version through the existing `_update_url_pins` regex. Latest 1.27.2
  gives `GO_VER="1.27"` and `go1.27.2.linux-…`; latest 1.28.0 gives `"1.28"` and
  `go1.28.0.linux-…`. The prompt names both constants.
- **python3, latest in the pinned series.** Writes `PYTHON_VER` as today, after the
  pyenv guard below.
- **python3, latest in a newer series.** Writes nothing for that version. It prints one
  line: `python3: 3.14 -> 3.15 is a series move: edit requires-python in pyproject.toml,
run uv lock, then bump PYTHON_VER`. Then it fetches the latest patch in the pinned
  series with `_fetch_python_latest <pinned series>`, and if that is newer than the pin
  (3.14.6 → 3.14.8) it offers that bump through the normal prompt. Without this second
  step a stale patch pin could never be offered while a newer series exists. If the
  in-series fetch fails, it prints `python3: could not fetch the latest <series> patch`
  and offers nothing.
- **pyenv guard.** Before writing `PYTHON_VER`, `pyenv install --list` must list the new
  version. If it does not, or `pyenv` is not resolvable, nothing is written and the line
  names the remedy (`brew upgrade pyenv` / update pyenv). A pin pyenv cannot build breaks
  `setup_ansible`; measured 2026-10-10, both machines list 3.14.8 and 3.15.0, so the guard
  matters on the day a release lands before pyenv's build definitions.

Ruby and the GitHub-backed tools keep today's `--update` behaviour.

### 5. Docs

- `CLAUDE.md`'s `check-versions` bullet: the rc 2 sentence says seven checks; it becomes
  five, and the bullet names go and python3 as pin-versus-latest from first-party feeds.
- `lib/constants.sh`'s `GO_VER`/`PYTHON_VER` "read by" comments stay accurate (no new
  readers).

### Out of scope

- **Syncing installed go and python3 across macOS and Linux.** One pinned go on both
  OSes (the mac installing the go.dev tarball instead of `brew "go"`), and `python3`
  outside the venv resolving to the latest Homebrew python on macOS (Apple's 3.9.6 today)
  and something newer than apt's on Linux, per actor. Recorded as its own backlog row
  with the measurements; it changes installers and PATH, not this check.
- **Verifying the go tarball.** `_install_go_from_tarball` runs a bare `wget` with no
  checksum. go.dev's feed carries `sha256` per file. Backlog row.
- **ruby.** `releases/latest` works today. ruby/ruby also publishes maintenance releases
  (`v3_4_11`), so "latest release" could one day be an older series. Not observed; not
  changed.
- **The installed-versus-latest comparison** for the five GitHub-backed tools.

## Testing

Tests run the real `python3` against fixture JSON delivered through `tests/mocks/curl`'s
`MOCK_CURL_STDOUT`. `tests/mocks/pyenv` gains a mock variable for `install --list` output
(a test knob, not a production seam). Tests set `_OVERRIDE_CONSTANTS_PATH` to a per-test copy of
`lib/constants.sh` for every `--update` case.

Positive controls pin an exact derived value, so a fetcher that returns nothing or the
first entry cannot pass:

- go fixture: an unstable `go1.29rc1` first, a stable `go1.28.3` lacking
  `linux-arm64` second, a stable `go1.28.2` with both files third. Result: `1.28.2`.
- python fixture, unsorted: `Python 3.15.0rc1`, `Python install manager 26.4`,
  `Python 3.14.9`, `Python 3.15.1`, `Python 3.10.20`. Result: `3.15.1`; with series
  `3.14`: `3.14.9`.

Failure cases, each asserting the `[WARN]` line and the warned counter: curl exits 22;
body is not JSON; JSON with no qualifying entry; `python3` not resolvable (shim `PATH`
holding everything the check needs except `python3`).

Pin verdict: go `[OK]` and `[OUTDATED]` against `GO_DOWNLOAD_FILENAME`, with a `go` stub
on `PATH` reporting a different version to prove installed is not read; python3 the same
against `PYTHON_VER`; an unparseable `GO_DOWNLOAD_FILENAME` gives the parse WARN.

Token-refused: with a line-break token, go and python3 lines still print, and the summary
reports `5 not checked`.

`--update`, each against the fixture constants file:

- go within the series: `GO_VER` unchanged, filename moves to the new patch.
- go across a minor: `GO_VER` and filename both move.
- python3 within the series, pyenv lists it: `PYTHON_VER` moves.
- python3 within the series, pyenv does not list it: file byte-identical, remedy printed.
- python3 across a series with no newer in-series patch: file byte-identical, series-move
  line printed, no prompt.
- python3 across a series with a newer in-series patch: series-move line printed, then
  the in-series bump is offered and applied.

Mutation controls (run once, recorded in the PR body): replace `_fetch_go_latest`'s
stable filter with "first entry" and confirm the go positive control goes red; drop the
pyenv guard and confirm its case goes red.

## Requirements

- **R1.** `[PR1]` `run_check_versions` gets go's latest version from `https://go.dev/dl/?mode=json`: the first entry with `stable: true` that lists both `<version>.linux-amd64.tar.gz` and `<version>.linux-arm64.tar.gz`, printed without the `go` prefix.
- **R2.** `[PR1]` `run_check_versions` gets python3's latest version from `https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false`, keeping only names matching `^Python \d+\.\d+\.\d+$` and choosing the highest by numeric comparison.
- **R3.** `[PR1]` Neither feed request carries `GITHUB_TOKEN` or any `Authorization` header.
- **R4.** `[PR1]` Each feed curl call passes `--max-time 10`.
- **R5.** `[PR1]` Any feed failure (curl non-zero, unparseable body, no qualifying entry, `python3` unresolvable) produces `[WARN] <tool> could not fetch latest version` and increments the warned counter.
- **R6.** `[PR1]` The go line compares the version embedded in `GO_DOWNLOAD_FILENAME` with latest, never the installed `go`.
- **R7.** `[PR1]` The python3 line compares `PYTHON_VER` with latest, never the installed `python3`.
- **R8.** `[PR1]` The go and python3 lines have no `not installed` SKIP branch.
- **R9.** `[PR1]` With a `GITHUB_TOKEN` containing a line break, go and python3 are still checked, exactly the five GitHub-backed checks are counted as not checked, and the message names 5.
- **R10.** `[PR1]` `--update` on an OUTDATED go sets `GO_VER` to the major.minor of latest and `GO_DOWNLOAD_FILENAME` to the full latest version.
- **R11.** `[PR1]` `--update` on a python3 whose latest is in a newer major.minor series than `PYTHON_VER` does not write that version, and prints a line naming `requires-python`, `uv lock` and `PYTHON_VER`.
- **R12.** `[PR1]` In the R11 case, if the latest release within `PYTHON_VER`'s series is newer than `PYTHON_VER`, `--update` offers that version through the normal prompt.
- **R13.** `[PR1]` `--update` writes `PYTHON_VER` only when `pyenv install --list` lists the new version; otherwise it writes nothing and prints a remedy naming pyenv.
- **R14.** `[PR1]` `CLAUDE.md`'s `check-versions` bullet says five checks for the token-refused case and names go and python3 as pin-versus-latest from first-party feeds.
- **R15.** `[PR1]` Each fetcher has a test pinning an exact non-first, non-empty derived value from a fixture that also contains entries the filter must reject.
- **V1.** On `claude` and the Studio, `./setup_env.sh -t check-versions` prints `[OK]` or `[OUTDATED]` (not `[WARN]`) for both go and python3.
- **V2.** Mutation: replacing the go stable filter with "first entry", and removing the pyenv guard, each turn at least one test red.
- **N1.** No change to the line format, comparison or `--update` behaviour of ruby, yq, shellcheck, vagrant, gitleaks, homebrew-install or the cargo checks.
- **N2.** No change to how go or python3 is installed on any OS, and no `Brewfile`, `pyproject.toml` or `uv.lock` change.
- **N3.** `--update` never writes `PYTHON_VER` to a version in a different major.minor series from its current value.
- **N4.** No new environment-variable seam.
