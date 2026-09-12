# Add the `claude` Linux workstation to the identity table — Design

## Problem

A new Linux box, hostname `claude`, is joining the fleet as the Claude development machine.
It has no entry in `config/profiles.sh`, so every identity derivation resolves it to the
unmapped case: `PROFILE=unknown`, zero `HAS_*` variables, no legacy identity variable, and
`setup_env.sh -t doctor` fails naming the hostname (`lib/helpers.sh:400`). That is the
designed behaviour for an unknown host, and closing it is this change.

Measured on the box by the ansible session over ssh, 2026-09-11:

| property | value |
| --- | --- |
| `hostname -s` / `hostname -f` | `claude` — no domain suffix |
| `/etc/hostname`, static hostname | `claude` |
| OS | Ubuntu 26.04, `VERSION_CODENAME=resolute`, kernel 7.0.0-31-generic, x86_64 |
| live network | `bond0` over `enp74s0f0` + `enp74s0f1` |
| wireless | `wlo2` exists with `phy80211`, is DOWN, and nothing is configured to bring it up |
| snap | present, snapd 2.76.3+ubuntu26.04 |
| flatpak | absent |
| provisioning state | nothing yet: no docker, no ledger, no make, no `~/.config/dotfiles/machine-id` |

`workstation` stays in the fleet and keeps its entries: it becomes an additional GitHub
runner, so the fleet ends with two runner servers, `workstation` and `claude`. Both are
`linux_workstation`, which already carries `docker`, so running a runner needs nothing from
this change. Ownership is split cleanly — all development setup on `claude` comes from
dotfiles, and ansible provisions exactly one thing there, the GitHub runner.

**This change is a prerequisite for `setup_env.sh` on that box, not the only one.** `claude`
has no Homebrew, and `setup_env.sh:30` exits 1 without it, so `scripts/bootstrap_linux.sh`
runs first. The identity entries are what make the run resolve a profile once it proceeds.

## Scope

In: `config/profiles.sh`, the tests that derive from it, `README.md`, the dotfiles
`CLAUDE.md` statements this change makes false, the ai-config `USER.md` machine list, and an
index row in `docs/superpowers/README.md`.

Out, each with its owner:

- **`acl` and `python3-venv` in `ubuntu_common_packages.txt`** — the ansible session needs
  both for the GitHub runner: `terraform_ansible/.github/workflows/ansible-ci.yml:107` and
  `:176` run `python3 -m venv` in jobs whose `runs-on` is `[self-hosted, linux, ansible]`
  (`:88`, `:123`), verified. Neither is a dotfiles need — `setup_ansible`
  (`lib/developer.sh:464`) builds the venv with `pyenv virtualenv "${PYTHON_VER}" ansible`
  (`:523`, `:549`) and `uv sync --frozen`, and `git grep python3-venv` returns nothing here.
  The ansible session is installing them from its role; a package-list change is the
  operator's own, on their timeline.
- **The GitHub runner on `claude`** — terraform_ansible's `github_runner` role.
- **Session-placement claims in `USER.md`** — deferred until the box actually hosts
  sessions. It is unprovisioned today, so a file saying sessions run there would be false.
- **`lib/legacy_rsync.sh` targets** — studio pushes to `workstation`, `laptop-1` and `ratna`
  and keeps doing so.

## Design

### 1. Identity entries

Two lines in `config/profiles.sh`:

```bash
[claude]="linux_workstation"   # PROFILE_MAP
[claude]="WORKSTATION"         # PROFILE_LEGACY
```

No `PROFILE_CAPS` change: `linux_workstation` already carries
`gui devtools aws k8s docker rust snap flatpak`, which is the "exact same profile as
workstation" requirement in full. Same profile also means `snap install code slack
--classic` and the Steam flathub install at `lib/linux_ubuntu.sh:431` — the requirement as
given, not a deviation from it. flatpak being absent on the box today is an unprovisioned
box, not a profile difference: `flatpak` is a line in `ubuntu_workstation_packages.txt`,
installed under `HAS_SNAP`.

**Reusing `WORKSTATION` rather than minting a `CLAUDE` variable is the load-bearing
choice.** Two live consumers branch on the legacy variable rather than on a capability:
`.zprofile:10` (`WORKSTATION || CRUNCHER`, rbenv init) and
`.config/.zshrc.d/7_final.zsh:60` (the eight-name list that activates the `ansible` pyenv
venv). Reuse means both work on `claude` with no edit. A new variable would need those two
lines plus every test line enumerating the legacy names by hand — **43 lines across 5
files**, measured with `git grep -cI 'WORKSTATION' -- tests` (`tests/zshrc.d/unit.bats` 23,
`tests/setup_env/profiles.bats` 8, `tests/zshrc.d/profiles.bats` 7,
`tests/zshrc.d/cross_shell.bats` 4, `tests/helpers/legacy_oracle.bash` 1).

The cost, stated rather than discovered later: no consumer can distinguish `claude` from
`workstation` by legacy variable — only by `hostname -s`. Nothing keys on the variable for
anything host-unique: `git grep -nw 'WORKSTATION' -- lib scripts config .config .zprofile`
returns five hits — two comments in `5_general.zsh`, the table row at
`config/profiles.sh:62`, and the two live branches above.

**Where that cost would first bite, so the next reader sees it coming.**
`lib/legacy_rsync.sh:17`, `:19` and `:27` hardcode `bruce@workstation`, `bruce@laptop-1` and
`bruce@ratna` as rsync destinations. Nothing is wrong today — `_is_legacy_sync_host` keys the
*source* on `hostname -s == studio`, so a second `WORKSTATION` host cannot become a target —
but if that destination list were ever driven from the identity table, it would resolve to
whichever host carries `WORKSTATION`. An earlier draft of this section claimed `studio` and
`studio-1` were the only host literals in `lib/`; that was false, and a grep for *quoted*
hostname literals could not see these because they sit inside a quoted ssh destination.

**Ubuntu 26.04 needs nothing.** `detect_env` sets `RESOLUTE` from `lsb_release -rs`, and
`lib/linux_ubuntu.sh` already has the 26.04 arm installing `ubuntu_common_packages.txt` plus
`ubuntu_2604_packages.txt`.

### 2. Wired-only, with the real criterion recorded

`claude` gets one entry per table and no `claude-1` twin, joining `workstation` and
`cruncher`. It also joins the hand-typed `wired_only` set at
`tests/setup_env/profiles.bats:296`, or the twin assertion at `:292` fails — measured below.

**The criterion is how many connections the machine actually uses, and the repo currently
records it wrongly.** A `-1` name is a second DHCP/DNS registration, for a machine that
connects on both a wired and a wireless interface; the bare name is the wired one. `home-1`
is the known exception, where `-1` is part of the name. So the question is not whether
wireless hardware exists.

Measured 2026-09-11, three ways:

| evidence | result |
| --- | --- |
| fleet DNS | `studio-1`, `ratna-1`, `laptop-1` resolve; `workstation-1`, `cruncher-1`, `claude-1` are NXDOMAIN |
| `workstation`, over ssh | `/etc/hostname` and static hostname both `workstation`; wireless `wlp14s0` present; `network-manager 1.46.0` installed; still reports `workstation` |
| `claude`, over ssh | `/etc/hostname` and static hostname both `claude`; `wlo2` DOWN and unconfigured |
| `cruncher` | not verified — sshd refuses connections on that box; DNS agrees (`cruncher` resolves, `cruncher-1` NXDOMAIN). Reported to have wireless hardware, unconfigured; under WSL2 the host's wifi is not exposed as a wireless interface anyway |

`workstation` is the decisive case: it has the wireless hardware *and* NetworkManager, has
run that way for months, and is correctly wired-only — because it never connects on the
second interface. The operator confirms `claude` and `cruncher` are the same shape —
wireless hardware present, unconfigured — so **no host in this table is wired-only for
lack of hardware**, and a rule written in terms of hardware would misclassify all three. That also retires an argument an earlier draft of this spec made, that
`ubuntu_common_packages.txt:46` (`network-manager`) would arrive with the first
`setup_env.sh` and make wired-only unsafe. It arrives, and it changes nothing.

**`README.md:361` is false and gets corrected here**: it says "Machines with no wireless
interface (`workstation`, `cruncher`) take a single key", and `workstation` has one. The
replacement states the connection-count criterion, so the next person adding a Linux box
does not read the hardware and reach the wrong conclusion.

**The condition under which this decision flips, stated so it is checkable:** if `claude`
ever connects on `wlo2` and the fleet registers `claude-1`, the host needs the twin and
loses the `wired_only` entry. `host claude-1` returning an address is the test.

### 3. Tests

The final configuration and every mutation below are measured, not predicted — see
Verification.

- `tests/helpers/legacy_oracle.bash` gains a `claude)` arm returning `WORKSTATION`.
- `tests/setup_env/profiles.bats:296` gains `[claude]=1` in `wired_only`.
- **`tests/zshrc.d/profiles.bats:138` stops swallowing an unknown profile.** Today an
  unmapped `PROFILE_CAPS` key becomes `expected_has=""`, so the expectation is derived from
  the same wrong value production reads — the circular shape `behavior.md` names — and a
  mistyped profile passes. It becomes a failure naming the host and the profile. This is a
  fix at the defect site rather than a second check beside it, and it covers every host.
- **One pinned assertion for `claude`**: its snapshot contains `PROFILE=linux_workstation`
  and exactly 8 `HAS_` names. This is the only thing that catches a *wrong but valid*
  profile value — `[claude]="mac_mini"` satisfies every derived check, because every derived
  check reads the table under test.

Rejected here, having been proposed in an earlier draft: a standalone "every `PROFILE_MAP`
value is a key of `PROFILE_CAPS`" test. The swallow fix covers the same class at the site of
the defect. The one-liner form also returns **rc 0 in bare bash** (a `for` loop's status is
its last iteration), so it would work only under bats' `set -e` — measured.

Everything else is derived from `"${!PROFILE_MAP[@]}"` and covers the new host with no edit.
The `no_legacy` set at `tests/zshrc.d/profiles.bats:120` stays empty, and the set-equality
test at `tests/setup_env/profiles.bats:485` stays green because reuse adds a key, not a
value.

`tests/zshrc.d/profiles.bats` carries three comments describing the table as 13 keys
(`:114`, `:135`, `:346`); the numbers are removed rather than incremented.
`tests/helpers/legacy_oracle.bash:13`'s "All 13 keys remain" is **left alone** — it records
what a mutation experiment did, a frozen reference that `behavior.md`'s document-hygiene
split says to pin rather than update. A note says so.

### 4. Documentation

- **dotfiles `CLAUDE.md`**, Key Conventions (line 849): says `WORKSTATION` and `CRUNCHER`
  "have been removed; use `HAS_*` vars instead". Both are live in `PROFILE_LEGACY` and read
  by `.zprofile:10`. Corrected.
- **dotfiles `CLAUDE.md`**, "Adding a New Machine": says 3 edits across 2 files. True for a
  host with a twin; a wired-only host also needs the `wired_only` exemption, making it **4
  edits across 3 files**. `config/profiles.sh:6` carries the same claim and gets the same
  correction — it is the file someone opens in order to add a machine.
- **`README.md`**: the **Machines column of the profile table is removed**. It duplicates
  `config/profiles.sh`, which is the thing it documents, nothing tests it, and neither
  "Adding a New Machine" section mentions it — so it goes stale silently every time a
  machine is added. The `linux_workstation vs wsl2_workstation` prose at `:343` names
  `workstation` as the hostname and gains `claude`. `:361`'s wired-only sentence is
  corrected per §2.
- **ai-config `USER.md`**: machine list grows to eight, `claude` as a development machine
  carrying all repos; "harness development happens on exactly two" becomes three; "six of
  the seven carry every repo" becomes seven of the eight. That two-machine line was narrowed
  deliberately on 2026-08-11, so it changes knowingly.
- **`docs/superpowers/README.md`**: an All Plans row for this spec and its plan.

## Verification

Measured against a throwaway `git archive` of this branch carrying the final configuration —
entries, `wired_only` exemption, oracle arm, swallow fix, pinned assertion — running
`bats tests/setup_env/profiles.bats tests/zshrc.d/profiles.bats tests/zshrc.d/cross_shell.bats`:

| arm | result |
| --- | --- |
| control | rc 0 — **44 ok, 0 not ok** |
| `[claude]="mac_mini"` (wrong, valid key) | rc 1 — caught **only** by `claude resolves linux_workstation with the full capability set` |
| `[claude]="linux_workstatio"` (garbage) | rc 1 — 3 red: the pinned assertion, the un-swallowed zsh loop, and the bash legacy loop |
| `wired_only` exemption removed | rc 1 — `every wired PROFILE_MAP key has a wireless -1 twin on the same profile` |
| oracle arm removed | rc 1 — 2 red: the bash and zsh per-host legacy loops |

Each edit therefore has a mutation that fires exactly for it, and the correct table produces
no false positive. Earlier drafts of this table described configurations that were later
rejected; these figures are for the design as it now stands. The control row read 45 until the
implementation measured it: that figure came from a scratch copy still carrying the standalone
`PROFILE_CAPS`-key test this design rejected, and the implementer refused to add a fourth test
to satisfy the gate. Measured on the branch: 44.

Still to run, at implementation:

| check | command | expected |
| --- | --- | --- |
| RED first | pinned assertion, before the entries exist | red: `claude` resolves `PROFILE=unknown` |
| full suite | `make test` | rc 0, run by the pre-push hook |
| docs, positive control | `grep -n 'WORKSTATION' CLAUDE.md` around Key Conventions | the corrected sentence is **present** — not merely that the wrong one is absent |
| on the box, after `bootstrap_linux.sh` and `setup_env.sh -t setup` | `setup_env.sh -t doctor` on `claude` | `[PASS] PROFILE (linux_workstation)`. `-t doctor` is brew-gate-exempt (`setup_env.sh:13`), so it runs on a bare box; overall rc is 1 until the rest is provisioned |

The last row is the only check that runs on the machine this change exists for; every other
row runs against an archive on the Studio.

## Rejected alternatives

- **A `claude-1` twin** — carried in a previous revision on the argument that
  `network-manager` arrives with the first `setup_env.sh`. Retired on measurement:
  `workstation` has both the hardware and NetworkManager and still reports `workstation`,
  because the `-1` name is a second DHCP registration for a machine that connects on both
  interfaces. The twin would have been two rows that cannot fire.
- **Mint a `CLAUDE` legacy variable** — costs the two startup-file branches plus 43
  hand-typed lines across 5 files, and buys a distinction nothing needs.
- **No legacy variable, `HAS_*` only** — the cleanest end state, but `.zprofile`'s rbenv init
  and `7_final.zsh`'s venv activation both branch on legacy variables, so the machine would
  silently skip both. Converting those two sites is a separate change.
- **A standalone `PROFILE_CAPS`-key test** — superseded by the swallow fix, which covers the
  same class at the defect site.
- **A `claude`-vs-`workstation` equivalence test** — an equality between two snapshots that
  can both be empty; the pinned assertion asserts the values instead.
- **Fold `acl`/`python3-venv` in** — they apply to every Ubuntu machine, and the ansible
  session's role installs them where the dependency is visible.

## Multi-Lens Review

Reviewed at commit: `aadaf1b4` (round 1) and `d2e7c3e3` (round 2)

### Round 1 — Goal-Fit

Finding: the wired-only premise is falsified by this change's own downstream effect
(`ubuntu_common_packages.txt:46` installs `network-manager`); the proposed equivalence test
is one host wide; `README.md` is a missed doc surface.
Assumption: that `claude` keeps reporting `claude` after provisioning.
Disposition: Addressed, then partly superseded by round 2. The twin was added here and
removed again once `workstation` was measured. `README.md` is in scope. The equivalence test
was replaced.

### Round 1 — Ergonomics

Finding: same `network-manager` falsification, reached independently; the in-code copies at
`config/profiles.sh:6` and `:19` were missed; the verification row pinned no value; three
stale "13" comments, not two, plus a frozen one that must not be updated.
Assumption: same as Goal-Fit's.
Disposition: Addressed. `config/profiles.sh:6` is now corrected in §4, value-pinning is §3's
pinned assertion, and the freeze note is in §3.

### Round 1 — Risk

Finding: the "only host literals in `lib/` are `studio`/`studio-1`" claim is false
(`legacy_rsync.sh:17`, `:19`, `:27`); the equivalence test copied the unguarded precedent;
the `WORKSTATION`-in-tests count is 43 across 5 files, not 42 across 4.
Assumption: that nothing brings `wlo2` up.
Disposition: Addressed. §1 now carries the corrected claim and names where the cost would
bite; counts corrected.

### Round 2 — Goal-Fit

Finding: §3's central measurement was stale by one revision — it described the wired-only
draft, where the exemption bypassed the twin assertion; the RED-first row could not isolate
its own cause; a simpler fix exists at the swallow site; the one-liner names no host, has no
non-vacuity guard, and is correct only under `set -e`.
Assumption: that a Linux host's `hostname -s` can change at all — noting every twin belongs
to a Mac (6 of 6) and neither Linux host has one (2 of 2).
Disposition: Addressed. The measurement table is re-derived for the final design; the
standalone test is replaced by the swallow fix; the one-liner is rejected with its measured
rc 0 in bare bash. The assumption was settled by measurement and by the operator: the twin is
gone.

### Round 2 — Ergonomics

Finding: `workstation` has wireless hardware and NetworkManager and is still correctly
wired-only, so the twin's stated basis was refuted by a machine that already ran the
predicted sequence; `README.md:361`'s criterion is false; the "Measured already" table
validated a rejected configuration; no verification row runs on `claude`; `bootstrap_linux.sh`
is the binding first-run prerequisite, not this change.
Assumption: that `claude` and `workstation` never need to be distinguishable by anything the
identity table derives.
Disposition: Addressed. The twin is removed, §2 records the connection-count criterion with
its three measurements, `README.md:361` is corrected, the measurement table is re-derived, a
`-t doctor` row on the box is added, and the bootstrap prerequisite is named in Problem. On
the assumption: accepted for now — both boxes are `linux_workstation` today and the deferred
session-placement decision is the thing that could change it; `lib/legacy_rsync.sh`'s
hardcoded destinations are named in §1 as where it would first bite.

### Round 2 — Risk

Finding: the derived test does not discriminate a wrong-but-valid profile value — `mac_mini`
for `claude` returns a byte-identical suite verdict; the one-liner is vacuous on an empty
table; nothing committed pins `claude`'s resolved profile after merge; the host count is 15
under the twin, not 14.
Assumption: that the wireless interface would report `claude-1` specifically.
Disposition: Addressed. Reproduced independently — `[claude]="mac_mini"` gave 44 ok / 0 not
ok — and fixed by the pinned assertion, which is now the only check that catches it. The
count question is moot with the twin removed: the table holds 14 keys.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
