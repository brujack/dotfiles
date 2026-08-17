# ADR-0020: Single Identity Table Across bash and zsh

**Date:** 2026-08-17
**Status:** Accepted

## Context

ADR-0003 introduced the profile/capability model: `config/profiles.sh` maps hostnames to
profiles, and profiles to capabilities. It replaced hostname comparisons scattered through
`setup_env.sh` with one table.

That decision covered the **bash** side only. The zsh side — `.zprofile` and
`.config/.zshrc.d/1_init.zsh`, which run on every login and every interactive shell — kept
its own hand-maintained hostname lists and never adopted the model. By 2026-08-16 there were
four independent tables answering "which machine is this", and they had drifted apart in
ways nothing detected:

- `.zprofile` matched `homes`/`homes-1` against a machine actually named `home-1`, so `HOMES`
  was never set there.
- `.zprofile` read `CRUNCHER` at line 21 without ever setting it, making that rbenv guard
  `WORKSTATION`-only in effect.
- `1_init.zsh` never set `OFFICE`, though five zsh sites read it; it survived only because
  `.zprofile` exported it into child processes.
- `lib/detect_env.sh` set five of the eight legacy identity variables and no wireless twins.

The defect that prompted the work was worse than any of those. A `-1` suffix is a machine's
**wireless-interface** hostname, and `hostname -s` returns it when the machine is on wifi.
`PROFILE_MAP` keyed on wired names only, so a machine on wireless resolved `PROFILE=unknown`
with **zero** `HAS_*` capabilities — silently, because `unknown` is a well-formed answer.
Measured: `studio` resolved `mac_workstation` with seven capabilities; `studio-1` resolved
nothing. Downstream, the Brewfile drift check skips every `[HAS_*]`-tagged entry, the
`HAS_SNAP`/`HAS_FLATPAK` branches go dark, and nothing reports it. The laptop is the machine
most often on wifi and therefore the most exposed.

`tests/setup_env/profiles.bats` had 20 tests, all on wired hostnames, and one asserting
`PROFILE=unknown` for an unrecognised hostname — which `studio-1` satisfies. The suite was
derived from the same wired-only table it checked, so it confirmed the defect rather than
catching it.

## Decision

**One table, consumed by both shells, with the legacy variable names derived from it.**

1. `config/profiles.sh` stays the sole data file and gains wireless-interface keys, so both
   spellings of a machine resolve identically. It also gains `ratna`, which was in no bash
   table at all, and drops `[server]` — that profile belonged to a retired mac mini and no
   hostname has mapped to it since. **This amends ADR-0003, whose Decision section still
   lists `server` as a profile.**

2. `config/profiles.zsh` is new: the zsh-side derivation. It sources the shared bash table
   and sets `PROFILE`, `HAS_*`, and the eight legacy identity variables. Both `.zprofile` and
   `1_init.zsh` source it; their own hostname lists are deleted.

3. `lib/detect_env.sh` derives the same eight variables from the table rather than testing
   hostname literals.

4. Read sites that were never identity questions become capability or Homebrew-prefix tests.
   Nine of nineteen hostname reads in `5_general.zsh` were really asking "which Homebrew
   prefix does this machine have"; four were converted, and the rest carry backlog rows.

5. `run_doctor` fails when `PROFILE` is `unknown`, naming the hostname and pointing at
   `config/profiles.sh`. This is the detection half — without it the next unmapped machine
   degrades exactly as silently as the wireless ones did.

Three properties were measured on both development machines and are what make one shared
data file possible:

- zsh sources bash's `declare -A M=( [k]=v )` correctly (zsh 5.9 Linux, 5.9.2 macOS), so no
  generation step or mirror file is needed.
- zsh does **not** word-split unquoted expansions (`SH_WORD_SPLIT` off), so the capability
  string must be split with `${=...}`. The bash idiom silently yields one variable named
  after the whole string.
- `${(%):-%x}` names the containing file in both actors; `${0:A:h}` does **not** work in a
  startup file, because zsh reads `.zprofile` with its internal reader rather than the
  `source` builtin and `$0` stays `zsh`, a relative name that `:A` resolves against the cwd.

## Consequences

**The legacy variable names are kept deliberately.** Roughly nineteen zsh read sites branch
on `LAPTOP`, `STUDIO`, `OFFICE` and friends. Deriving those names from the table rather than
renaming the call sites is what kept the diff proportionate. They are outputs of the model
now, not independent facts.

**`export` in `config/profiles.zsh`, `readonly` in `lib/detect_env.sh`, on purpose.** The zsh
file is sourced twice in one process by a login+interactive shell, and a `readonly`
reassignment makes the second `source` return 126. `detect_env` runs once per bash process.
This reads as an inconsistency and is load-bearing; both files carry a comment saying so,
because "fixing" one to match the other breaks login shells.

**The hostname→legacy-variable mapping is still duplicated**, in `config/profiles.zsh`'s
`case` and the test's expectation helper. Drift between them is now _detected_ by a test
rather than made impossible. The single-table shape would be a third map in
`config/profiles.sh`; it has a backlog row. Note the mapping cannot be _derived_ from the
key — strip-`-1`-and-uppercase turns `home-1` into `HOME`, and `export HOME=1` in a login
shell repoints the user's home directory. The carve-out is load-bearing, so an explicit
table is safer than a derivation.

**Three deliberate behaviour changes**, each documented at its site and covered by a named
test:

- `FZF_BASE` is no longer set on `ratna` or either Linux box. It was previously exported
  unconditionally because `5_general.zsh:18` read `[[ -n {OFFICE} ]]` — no `$` — which zsh
  evaluates as a literal non-empty string. Those machines have no `/opt/homebrew/bin/fzf`;
  `~/.fzf.zsh` is the fallback.
- `home-1` no longer loads a key named `any`. `keychain` has no `any` flag, so the old arm
  was reading it as a nonexistent key name. Recorded as an assumption: if `~/.ssh/any*`
  turns out to be real, the fix is a three-line per-host addition to the key list.
- An unmapped mac now loads the four standard keychain keys where the old chain, having no
  final `else`, loaded none.

**`config/profiles.sh` is now linted by both parsers** — it stays in `SHELL_FILES` for
`bash -n` and shellcheck, and joins `ZSH_FILES` for `zsh -n`. It is the only deliberate
overlap between those sets, and the suite asserts both that it is the only one and that it
is actually present. The pathspec is duplicated at two independent call sites — `Makefile`
and `ci.yml`'s `lint-macos` job — and a test now compares them, because changing one alone
leaves CI checking a stale set.

**Cross-shell equivalence is pinned by a test using a different mechanism than the target.**
Each per-shell suite derives its expectations from `PROFILE_MAP` and checks one resolver, so
both pass if a derivation is right for one shell and wrong for the other.
`tests/zshrc.d/cross_shell.bats` runs both resolvers for every table key and asserts the
`PROFILE`, `HAS_*` set and legacy variable are identical. That is the check the repo did not
have, and it is the one that makes the single-table claim verifiable rather than asserted.

## Related

- ADR-0003 — Profile/capability model for machine detection. Amended: `server` removed from
  the profile list; the model now covers zsh as well as bash.
- ADR-0019 — Shebang-derived shell lint scope. Same class of change as the `ZSH_FILES`
  widening here.
- `docs/superpowers/specs/2026-08-16-zsh-identity-single-table-design.md`
- `docs/superpowers/plans/2026-08-16-zsh-identity-single-table.md`
