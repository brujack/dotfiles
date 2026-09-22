# Phrase manifest -- fragment D (gap-fill: the 10 content paragraphs left
# unclassified by fragments A, B, and C -- see docs/superpowers/plans/phrases-{a,b,c}.md)
#
# class | phrase | counterpart-file | counterpart-symbol | note

# ---- Language Standards ----

# ---- Testing (venv snapshot rollback) ----
HAZARD | "$(pyenv which python)" -m pip install --no-deps -r ~/.local/share/dotfiles/venv-snapshots/ansible-<UTC>.txt | - | - | The `--no-deps` flag is not stylistic -- the surrounding prose states the pre-sync venv state is provably unsatisfiable via ordinary pip dependency resolution (pip reached it incrementally; the cumulative set has no single consistent resolution). An operator restoring from a snapshot without this exact flag gets a resolver failure and may conclude the snapshot is corrupt rather than that the flag was dropped.

# ---- PowerShell Testing ----
REFERENCE | make test   # runs PSScriptAnalyzer lint then Pester tests | - | - | Mechanical command reference for running the PowerShell suite from the `powershell/` subdirectory; the recipe itself is discoverable by reading `powershell/Makefile`.
REFERENCE | Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0 | - | - | One-time prerequisite install command for the Pester/PSScriptAnalyzer toolchain; plain scaffolding, no hidden consequence beyond what running it shows.

# ---- Coverage (Bash) ----
REFERENCE | bash scripts/run-bash-coverage.sh --count-coverable lib/helpers.sh | - | - | Example CLI invocation for inspecting one file's coverage denominator without running the full bats suite; mechanical, discoverable by reading `scripts/run-bash-coverage.sh --help`-equivalent usage.

# ---- Key Conventions: "Which `make` an actor resolves" (5-paragraph argument; p215 is the
# measured evidence for the HAZARD claimed in p214, and both sit downstream of the RECORD/
# DUPLICATE pair at p209/p210 that establish the actor table itself. A deletion pass must
# keep p214+p215 together -- the HAZARD without its evidence is an unverified assertion. ----
RECORD | all measured 2026-08-16 on the Studio: | - | - | Dated re-measurement notice introducing the 4-row actor table (p210): "not the two this file used to describe" is a self-correction of this same file's earlier, coarser account. Checked against ~/.claude/standards/behavior.md's own re-measurement of the identical underlying fact (also dated 2026-08-16, around its "Re-measured 2026-08-16, that is false:" passage) -- wording differs entirely (0-byte overlap for this exact sentence, confirmed by grep), so this is RECORD rather than DUPLICATE: the same underlying finding, independently worded in each file.
DUPLICATE | `6_path.zsh` / `.zprofile` | ~/.claude/standards/behavior.md | "A boundary can be an actor, not a place" section, actor table, interactive-zsh row's PATH-source cell | Verified by direct whitespace-normalised substring search: the literal cell value `` `6_path.zsh` / `.zprofile` `` occurs exactly once in dotfiles/CLAUDE.md (this table's own interactive-zsh row) and exactly once in behavior.md's own actor table (its interactive-zsh row), byte-identical including backticks and the single spaces around the slash. Both tables assert the same fact for the same actor; the surrounding table structure differs (behavior.md collapses cron/launchd/ssh into one row and has no separate `resolves`/`version` columns), so only this one cell is a genuine duplicate, not the whole table.
AMBIGUOUS | because both cost real work and neither is obvious: | - | - | Bare connector sentence introducing the two /usr/local/bin and PATH-shadowing traps that follow; matches the established house style for introductory sentences (fragment C's "Three properties are load-bearing and none is obvious from the shape:" and siblings) -- fits none of the four classes on its own.
HAZARD | a human at a prompt and not for anything else | - | - | Standing operational hazard, not merely historical: because `6_path.zsh` (which puts Homebrew's brew on PATH) is sourced by interactive zsh only, `setup_env.sh`'s `env which brew` prerequisite check means no cron job, git hook, CI runner, or non-interactive agent session can run this entry point on the Linux workstation at all -- it dies in seconds with advice ("run bootstrap_linux.sh") that is actively wrong for a machine already bootstrapped. Checked against behavior.md and shell.md for the same claim about this specific script; not found -- this is dotfiles-specific narrative, not a cross-file duplicate.
HAZARD | non-interactive bash : ABSENT | - | - | This is the measured evidence for the HAZARD immediately above (p214): the two-line probe output proving the actor split is real on this exact machine, not asserted. Deleting this block without the claim it supports turns a measured finding back into an unverified assertion; deleting the claim without this block strands a bare command transcript with no stated consequence. The two rows must be treated as one unit in any later pruning pass.

# EXEMPT p51 `@~/.claude/standards/powershell.md` — no row is possible. The bare path
# occurs 3 times in CLAUDE.md, so uniqueness requires the leading `@`; the `@` sits
# immediately after a sentence-ending period, so every unique candidate is
# sentence-initial and the tool rejects it. Exhaustive search under the tool's own
# match_phrase predicate confirms 2 such paragraphs in 249: this and `CI requirements:`.
