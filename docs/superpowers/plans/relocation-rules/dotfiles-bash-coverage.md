### Instrumented set: git ls-files derivation and the scripts/ history

lead: none

- Derive the instrumented set from `git ls-files`, never a glob — `config/local.sh` is git-ignored and machine-local, so a glob would diverge from CI. Set: `setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh` and the two extensionless hooks, less `scripts/bash-tracer.sh`. The predicate is "reached by the suite" via `BASH_ENV` tracing, not "lives in a directory" — a directory-only predicate silently discards already-collected trace lines, which is how `scripts/` was wrongly excluded, on a claim that was asserted, never measured.
- Check the current set: `bash scripts/run-bash-coverage.sh --list-sources`.

trigger: editing the instrumented file set | scripts/run-bash-coverage.sh, scripts/bash-tracer.sh

covers:

- a: "The tracer enables tracing through `BASH_ENV`, whi"
- b: "**`git ls-files` rather than a filesystem glob is "

### Denominator counts commands, not source lines (heredocs, python -c, arrays, continuations)

lead: none

- The denominator counts commands, not source lines — bash xtrace emits one line per command. Exclude: heredoc bodies/terminators (any interpreter); multi-line `python3 -c "..."` bodies; multi-line array literals (trace as one line — cost `config/profiles.sh` 13 of its 15 lines and `lib/helpers.sh` 8); and pure-argument backslash continuations (only more arguments — **not** excluded if it begins or contains `||`, `&&`, `|`, or `;`). A one-line instance of any of the four is still counted normally.
- Never add a function-declaration exclusion — tried and removed on evidence: a real trace showed `lib/detect_env.sh` line 4 traced twice (source, then re-source under an active `set -x`), so the assumption was wrong, not just too broad.

trigger: editing coverable-line exclusions | scripts/run-bash-coverage.sh

covers:

- a: "That was 13 of `config/profiles.sh`'s 15 lines and"

### Denominator is the union of the heuristic and the real trace

lead: none

- The coverable-line denominator is the union of the static heuristic's count and whatever the real trace actually contains — never the heuristic alone — so `covered <= coverable` holds by construction: a wrongly-excluded line raises the denominator (and numerator) rather than lowering the percentage. Each run prints every union-added line as a heuristic-disagreement count; read that count beside the ratio from the same run, never a ratio from a different one.
- Treat `covered > coverable` as a hard, loud non-zero exit, never a silent clamp — it means an exclusion heuristic over-matched, and the run must fail rather than report a number nobody can trust.
- Inspect a file's denominator or a run's coverage against a real trace: `bash scripts/run-bash-coverage.sh --count-coverable <file>` and `--file-coverage <file> <trace>`.

trigger: editing coverable/covered accounting | scripts/run-bash-coverage.sh

covers:

- a: "**The denominator is the union of the static heuri"
- b: "**Read it beside the ratio from the same run, neve"

### covered > coverable is now a hard exit; publishing and reading the figure

lead: none

- Publish CI's bash coverage figure in the PR body once CI has run (`gh pr edit <n>`); a local run is a preview and must be labelled as one.

trigger: publishing or reading a bash coverage figure | scripts/run-bash-coverage.sh

covers:

- b: "Publish CI's bash coverage figure in the PR body o"
