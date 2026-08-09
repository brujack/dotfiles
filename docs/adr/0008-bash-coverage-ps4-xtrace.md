# ADR-0008: Use PS4 Xtrace for Bash Coverage Measurement

- **Date:** 2026-06-01
- **Status:** Accepted (amended 2026-08-07, 2026-08-09 — see Amendments below)

## Context

The dotfiles bash test suite uses BATS (bats-core) to test `setup_env.sh` and its `lib/*.sh` modules. Adding a coverage gate to CI required a mechanism to measure which lines in those shell scripts were executed during the test run.

Three standard approaches were tried and rejected before settling on PS4 xtrace:

1. **kcov (ptrace-based):** kcov works for standalone bash scripts invoked directly, but bats-core forks isolated subshells for each test. Those subshells escape kcov's ptrace attach. Zero coverage data was produced even when kcov was running. Building kcov from source in CI (cmake + libelf + libdw + libiberty) added ~5 minutes to each run with no payoff.

2. **bashcov (LINENO-based):** bashcov is incompatible with bats-core. bats hardcodes a UUID (`608a9069-2672-4fa2-a0e1-2823af783b95`) in its temp file paths; bashcov's LINENO parser chokes on it and produces no output.

3. **BASH_ENV + DEBUG trap:** bats-core overrides the DEBUG trap with its own `bats_debug_trap`. Any custom DEBUG trap set via `BASH_ENV` is replaced at bats startup and never fires.

The PS4 xtrace approach works because bats does not clear `set -x` or redirect `BASH_XTRACEFD`. A tracer script installed via `BASH_ENV` sets `BASH_XTRACEFD=9`, opens a named pipe on fd 9, and a background `grep` process filters the raw trace lines in real time — keeping disk usage at ~200K filtered lines instead of ~33M raw lines. The filtered trace is then parsed post-run to count covered vs coverable lines per file.

**macOS vs Linux runner choice:** The initial CI job ran on `macos-latest` since the xtrace approach was developed locally on macOS. macOS runners queue 30–60+ minutes. PS4 xtrace has no macOS-specific dependencies — `BASH_ENV`, `BASH_XTRACEFD`, and named pipes are standard bash features available on ubuntu-latest. The job was switched to `ubuntu-latest` in the same PR.

## Decision

Use PS4 xtrace (`BASH_XTRACEFD`) as the sole bash coverage mechanism for the dotfiles test suite.

Implementation:

- `scripts/bash-tracer.sh` — installed via `BASH_ENV`; sets `PS4` to emit `BASH_SOURCE:LINENO` and redirects trace to fd 9
- `scripts/run-bash-coverage.sh` — sets up the named pipe, runs `bats --recursive tests/`, drains and parses the trace, reports per-file and overall coverage
- `make bash-coverage` — local measurement target
- `make push-bash-coverage` — measurement + badge push to `coverage-data` branch
- CI `bash-coverage` job on `ubuntu-latest` — runs `make bash-coverage`, fails if overall coverage < 90%, publishes badge JSON

The gate is **90% overall** (not per-file). Per-file floors are defined in `CLAUDE.md` but not yet enforced individually in CI.

Do not attempt kcov, bashcov, or BASH_ENV+DEBUG trap in this repo. All three were confirmed broken with bats-core (see Context above). These dead ends are documented in `CLAUDE.md` to prevent future agents from re-trying them.

## Consequences

**Positive:**

- Coverage measurement works — 92% measured at 726 tests as of 2026-06-01. **The word "accurate" in the original text was wrong and is retracted; see the Amendment below.** That figure was computed over a hand-maintained 13-file subset of 36 tracked shell sources
- CI gate blocks merges when coverage drops below 90%
- Named-pipe filtering keeps trace output manageable without sacrificing accuracy
- `ubuntu-latest` runners avoid the 30–60 min macOS queue delay

**Negative / constraints:**

- Some lines are structurally non-traceable by PS4 xtrace:
  - Lines inside `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` blocks are not traced by subprocess bats invocations (fd 9 not inherited)
  - Multi-line array literals, `usage()` heredoc content, and multi-line curl continuation lines are not emitted by bash xtrace. **The array-literal case is no longer treated as a per-file ceiling — it is excluded from the denominator as of 2026-08-07; see the Amendment.** The heredoc and curl-continuation cases remain unaddressed
  - Function declaration lines (`funcname() {`) are not consistently traced across bash versions
  - The remaining ceilings are documented per-file in `CLAUDE.md` — do not waste time writing tests to exceed them
- Coverage measurement runs the full BATS suite; no sub-suite option currently

## Amendment 1 (2026-08-07)

The PS4-xtrace decision stands. Two things this ADR asserted did not.

**The accuracy claim was false when written.** `INCLUDE_FILES` was a hand-maintained
array naming 13 files against 36 tracked `.sh` sources, so "92% accurate" described 36%
of the repo. A literal list cannot fail loudly here: an omitted file is absent from the
numerator _and_ the denominator, so leaving one out does not lower the percentage — it
leaves it unchanged. `lib/git_hooks.sh` was missed exactly that way and only surfaced
because someone noticed its absence from the report by eye; `lib/package_capture.sh`
stayed missing afterwards. The set is now derived at run time from `git ls-files` over
`setup_env.sh`, `config/*.sh`, and `lib/*.sh`, and the script exits non-zero rather than
measuring a short set. The predicate is _reached by the suite_ — `config/` qualifies
because `lib/detect_env.sh` sources `config/profiles.sh` and `lib/git_hooks.sh` sources
`config/hook_repos.sh`.

**The ceiling policy is reversed for two construct classes.** This ADR listed multi-line
array literals among lines "not emitted by bash xtrace" and directed readers not to waste
time testing them. That guidance was correct about the mechanism and wrong about the
remedy: a line no instrument can ever reach does not belong in the denominator at all.
Counting it reports a permanent shortfall as though it were a testing gap, and every
reader who checks the file concludes it is under-tested. Two classes are now excluded,
each verified against real `bash -x` output rather than assumed:

- multi-line `python3 -c "..."` bodies — 54 of `lib/package_capture.sh`'s 107 counted
  lines, which is why that file read 22% against a ceiling it could not reach
- multi-line array literals — `declare -A M=(` … `)` traces as one `M=([a]=1 [b]=2)`
  line; 13 of `config/profiles.sh`'s 15 counted lines and 8 of `lib/helpers.sh`'s

Single-line forms of both are ordinary commands and still count. `usage()` heredoc
content and multi-line curl continuations are the same class and remain **unaddressed** —
two heredoc openers exist in the instrumented set today (`lib/workflows.sh` and
`lib/helpers.sh`), so the residual inflation is small but real.

Post-amendment: 2449/2688 = 91% at 1161 tests. The gate stays at 90%. That the figure
matches the original 91% is a coincidence of two different denominators, not evidence the
old number was right.

## Amendment 2 (2026-08-09)

The PS4-xtrace decision still stands. This amendment closes the two gaps Amendment 1 left
open — `scripts/` outside the instrumented set, and heredoc/curl-continuation inflation —
and corrects two more heuristic mistakes found while closing them.

**The predicate now covers `scripts/`, and the reason it didn't was never measured.**
Amendment 1's set was `setup_env.sh`, `config/*.sh`, `lib/*.sh` — everything reached by the
test suite's own sourcing chain, on the theory that nothing under test sourced `scripts/`
directly. That theory was asserted, not checked. A real run showed all 19 tracked files
under `scripts/` executed by the bats suite between 2 and 29 times each, because the tracer
installs via `BASH_ENV`, which every non-interactive bash subprocess inherits — including
the ones bats forks to run `scripts/*.sh` directly. Those trace lines were being collected
the whole time and then discarded by a predicate that never looked. The predicate is now
`setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh`, and the two
extensionless hooks (`scripts/pre-push`, `scripts/commit-msg`) — 35 files by that
predicate, of which `scripts/bash-tracer.sh` is excluded (below), leaving 34 instrumented.

**`scripts/bash-tracer.sh` is excluded, on the same measured-not-asserted standard.**
`set -x` is its last command, so nothing before it can be traced and nothing follows it to
trace. Verified directly rather than reasoned about:

```bash
_COV_TRACE_FILE=$PWD/tr.txt BASH_ENV=scripts/bash-tracer.sh bash -c 'x=1; y=2'
grep -c 'bash-tracer.sh' tr.txt   # -> 0
```

**The heredoc/curl-continuation gap this ADR called unaddressed is now closed, and the
underlying rule is broader than "curl continuations."** Any pure-argument backslash
continuation — a continuation line whose only content is more arguments to the command the
backslash opened — is excluded, matching how bash actually traces it: one xtrace line for
the whole logical command, attributed to the opening line, never to the continuation lines.
The rule does **not** exclude a continuation that itself begins or contains `||`, `&&`,
`|`, or `;` — bash starts tracing a new command at that boundary regardless of the trailing
backslash, so that class is counted like any other command. Heredoc bodies and their
terminator lines are excluded in any form (`<<` or `<<-`, any interpreter, not just bash's
own `usage()` blocks) — a heredoc body can contain arbitrary text, including lines that
would otherwise parse as commands, comments, or continuations in their own right, so a
line-by-line heuristic cannot safely look inside one at all.

**A function-declaration exclusion was tried while implementing the above, and withdrawn on
evidence rather than kept as a hedge.** This ADR's own Consequences section listed
`funcname() {` lines as "not consistently traced across bash versions," and Amendment 1
repeated that framing implicitly by not touching it. A real tracer run over the bats suite
showed roughly 150 counterexamples: `lib/detect_env.sh` line 4, `detect_env() {`, was
traced **twice** in one run — once when the file is sourced directly, once when a caller
re-sources it under an already-active `set -x`. The rule was deleted outright, not
narrowed, because the premise it was built on was false, not merely imprecise.

**The denominator is now the union of the static heuristic's coverable-line count and
whatever the trace file actually contains for that file — not the heuristic's count alone.**
This is the structural fix that makes the invariant `covered <= coverable` hold by
construction instead of by the heuristic happening to be right: every line the trace hits
is, by definition, coverable, so folding traced lines into the denominator means no
possible heuristic mistake can push `covered` past it. The previous approach — clamp
`covered` down to `coverable` if it ever exceeded it — didn't fix the heuristic error, it
hid it: `lib/detect_env.sh` read 24/24 = 100% while the trace emitted 25 distinct lines for
it, and the clamp silently absorbed the missing line rather than reporting the mismatch.
`covered > coverable` is now a hard, loud non-zero exit instead of a clamp, and under the
union rule it can only fire when an exclusion heuristic has genuinely double-counted or
otherwise over-matched — a real bug in the tool, not a normal run.

A side effect worth stating plainly: because the union folds in whatever a given run
traced, the denominator is now run-dependent — a file whose covering tests are later
deleted loses those union-added lines and its denominator can shrink back down. That is an
accepted trade, not an oversight: coverage would have genuinely dropped either way, and the
alternative (a denominator that only the heuristic controls) is what let the clamp hide a
real bug for as long as it did. Every union-added line is printed as a **heuristic
disagreement** for exactly this reason — so a systematically wrong exclusion rule stays
visible run over run instead of being quietly absorbed into a bigger denominator. The
current run reports 15 disagreements, down from 192 before the heredoc and continuation
rules landed. Fifteen is a to-do against the heuristic, not a failure of the gate — the
union means none of them can be inflating the published percentage.

**What genuinely remains unaddressed:** nothing in the four excluded classes above is
still open. The heuristic disagreement count (15) is the honest remainder — real
constructs the static heuristic has not yet been taught to recognize, surfaced every run
rather than hidden, and guaranteed by the union not to distort the published figure either
direction in the meantime.

Post-amendment: 3060/3326 = 92% at 1257 tests, 34 of 35 tracked shell files (by the widened
predicate) instrumented. The gate moves to 92% in the same change — see `CLAUDE.md`
§Testing > Coverage > Bash for the full current-state table.

## Related

- ADR-0001: Use BATS for shell testing
- ADR-0006: Shell script testability conventions
- `scripts/run-bash-coverage.sh` — implementation
- `scripts/bash-tracer.sh` — PS4 tracer
- `CLAUDE.md` §Testing > Coverage > Bash — per-file floors, ceilings, and structural non-traceables
- `memory/project_bash_coverage.md` — current coverage state and history
