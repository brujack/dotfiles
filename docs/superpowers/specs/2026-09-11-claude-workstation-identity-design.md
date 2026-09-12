# Add the `claude` Linux workstation to the identity table — Design

## Problem

A new Linux box, hostname `claude`, is joining the fleet as the Claude development machine.
It has no entry in `config/profiles.sh`, so every identity derivation resolves it to the
unmapped case: `PROFILE=unknown`, zero `HAS_*` variables, no legacy identity variable, and
`setup_env.sh -t doctor` fails naming the hostname (`lib/helpers.sh:400`). That is the
designed behaviour for an unknown host, not a bug — it is what this change closes. This
change is also the prerequisite for running `setup_env.sh` on the box at all.

Measured on the box by the ansible session over ssh, 2026-09-11:

| property | value |
| --- | --- |
| `hostname -s` / `hostname -f` | `claude` — no domain suffix |
| OS | Ubuntu 26.04, `VERSION_CODENAME=resolute`, kernel 7.0.0-31-generic, x86_64 |
| live network | `bond0` over `enp74s0f0` + `enp74s0f1` |
| wireless | `wlo2` exists with `phy80211`, is DOWN; `iw` and `nmcli` not installed **today** |
| snap | present, snapd 2.76.3+ubuntu26.04 |
| flatpak | absent |
| provisioning state | nothing yet: no docker, no ledger, no make, no `~/.config/dotfiles/machine-id` |

`workstation` stays in the fleet and keeps its entries: it becomes an additional GitHub
runner, so the fleet ends with two runner servers, `workstation` and `claude`. Both are
`linux_workstation`, which already carries `docker`, so running a runner needs nothing from
this change. Ownership is split cleanly: all development setup on `claude` comes from
dotfiles, and ansible provisions exactly one thing there, the GitHub runner.

## Scope

In: `config/profiles.sh`, the tests that derive from it, `README.md`, the dotfiles
`CLAUDE.md` statement this change makes false, and the ai-config `USER.md` machine list.

Out, each with its owner:

- **`acl` and `python3-venv` in `ubuntu_common_packages.txt`** — requested by the ansible
  session for its runner role. Their own change, by the operator's decision. `python3-venv`
  is additionally not a dotfiles need: `setup_ansible` (`lib/developer.sh:464`) creates the
  venv with `pyenv virtualenv "${PYTHON_VER}" ansible` (`:523`, `:549`) and installs with
  `uv sync --frozen`; `git grep python3-venv` returns nothing in this repo.
- **The GitHub runner on `claude`** — terraform_ansible's `github_runner` role, already
  adding the host on that side.
- **Session-placement claims in `USER.md`** — deferred until the box actually hosts
  sessions. It is unprovisioned today, so a file saying sessions run there would be false.
- **`lib/legacy_rsync.sh` targets** — studio pushes to `workstation`, `laptop-1` and `ratna`
  and keeps doing so.

## Design

### 1. Identity entries

Four lines in `config/profiles.sh` — wired and wireless in both tables:

```bash
[claude]="linux_workstation"   [claude-1]="linux_workstation"   # PROFILE_MAP
[claude]="WORKSTATION"         [claude-1]="WORKSTATION"         # PROFILE_LEGACY
```

No `PROFILE_CAPS` change: `linux_workstation` already carries
`gui devtools aws k8s docker rust snap flatpak`, which is the "exact same profile as
workstation" requirement in full.

**Reusing `WORKSTATION` rather than minting a `CLAUDE` variable is the load-bearing
choice.** Two live consumers branch on the legacy variable rather than on a capability:
`.zprofile:10` (`WORKSTATION || CRUNCHER`, rbenv init) and
`.config/.zshrc.d/7_final.zsh:60` (the eight-name list that activates the `ansible` pyenv
venv). Reuse means both work on `claude` with no edit. A new variable would need those two
lines plus every test line that enumerates the legacy names by hand — **43 lines across 5
files**, measured with `git grep -cI 'WORKSTATION' -- tests` (`tests/zshrc.d/unit.bats` 23,
`tests/setup_env/profiles.bats` 8, `tests/zshrc.d/profiles.bats` 7,
`tests/zshrc.d/cross_shell.bats` 4, `tests/helpers/legacy_oracle.bash` 1) — or the new
variable leaks between tests and those two branches silently skip on the new machine.

**Reuse also closes a logged backlog row rather than merely being cheap.**
`docs/superpowers/README.md:180` records that `.zprofile:10` duplicates the rbenv init
`5_general.zsh` now gates by capability, and that the next Linux devtools host added to
`PROFILE_MAP` would get rbenv interactively but not at login. That host is `claude`.

The cost, stated rather than discovered later: no consumer can distinguish `claude` from
`workstation` by legacy variable — only by `hostname -s`. Nothing keys on the variable for
anything host-unique: `git grep -nw 'WORKSTATION' -- lib scripts config .config .zprofile`
returns five hits, being two comments in `5_general.zsh`, the table row at
`config/profiles.sh:62`, and the two live branches above.

**An earlier draft of that sentence was wrong and the correction is worth keeping.** It
claimed the only host-keyed literals in `lib/` were `studio` and `studio-1`. There are three
more — `bruce@workstation`, `bruce@laptop-1` and `bruce@ratna` at `lib/legacy_rsync.sh:17`,
`:19` and `:27` — which a grep for *quoted* hostname literals cannot see, because they sit
inside a quoted ssh destination. They do not change the conclusion (`_is_legacy_sync_host`
keys the *source* on `hostname -s == studio`, so a second `WORKSTATION` host cannot become
an rsync target) but they are exactly where the indistinguishability would acquire teeth if
that destination list were ever driven from the identity table.

**Ubuntu 26.04 needs nothing.** `detect_env` sets `RESOLUTE` from `lsb_release -rs`, and
`lib/linux_ubuntu.sh` already has the 26.04 arm installing `ubuntu_common_packages.txt` plus
`ubuntu_2604_packages.txt`.

**flatpak being absent is an unprovisioned box, not a profile difference.** `flatpak` is a
line in `ubuntu_workstation_packages.txt`, which installs under `HAS_SNAP`
(`lib/linux_ubuntu.sh:39-46`); `HAS_FLATPAK` gates only the Steam flathub install at `:431`.
Same profile also means `snap install code slack --classic`: that is the requirement as
given, not a deviation from it.

### 2. The twin, and why wired-only was rejected

`claude` gets a `claude-1` twin. An earlier draft had it wired-only, matching `workstation`
and `cruncher`, on the ansible session's measurement that nothing manages `wlo2`.

**That basis does not survive this change's own first run.** `ubuntu_common_packages.txt:46`
is `network-manager`, and the 26.04 arm installs that list on this machine. So the first
`setup_env.sh -t setup` on `claude` installs the very tooling whose absence justified the
exemption. Whether NetworkManager then associates `wlo2` and the fleet's DHCP/DNS hands back
`claude-1` is not established either way — but the *stated reason* would be false from the
moment the change ships, and the failure it guards is total: `PROFILE=unknown`, zero
`HAS_*`, with `.zprofile:10` and `7_final.zsh:60` both silently skipping, on the machine
every session is supposed to run on.

The twin is also **cheaper than the exemption it replaces**. A wired-only host must join the
hand-typed `wired_only` set at `tests/setup_env/profiles.bats:296`, or the twin assertion at
`:292` fails. With a twin there is nothing to exempt, so the change stays at **3 edits
across 2 files** — which is exactly what `config/profiles.sh:6` and `CLAUDE.md`'s "Adding a
New Machine" already claim. Neither needs correcting, and `config/profiles.sh:19`'s
"`workstation` and `cruncher` are wired-only by design" stays true, because `claude` is no
longer in that class.

### 3. Tests

- `tests/helpers/legacy_oracle.bash` gains one arm, `claude | claude-1)`, returning
  `WORKSTATION`. The oracle is hand-typed on purpose (ADR-0021) and its `*)` arm fails
  loudly, so a host added to `PROFILE_MAP` without an arm here turns the suite red.
- **A new derived test: every `PROFILE_MAP` value is a key of `PROFILE_CAPS`.** This closes
  a measured hole, and it is not the test an earlier draft proposed.

  Measured against a throwaway archive of this branch: with `[claude]` mistyped as
  `"linux_workstatio"`, `bats tests/setup_env/profiles.bats tests/zshrc.d/profiles.bats
  tests/zshrc.d/cross_shell.bats` returns **rc 0, 43 ok, 0 not ok**. Nothing catches it. The
  derived per-host loops take `expected_profile="${PROFILE_MAP[${hn}]}"` from the table under
  test, so a bad value makes the expectation wrong in the same direction as production — the
  circular-check shape `behavior.md` names — and `tests/zshrc.d/profiles.bats:137` turns the
  resulting unknown profile into `expected_has=""` rather than an error.

  The check is one line over the whole table and covers all 14 hosts plus every future one:

  ```bash
  for k in "${!PROFILE_MAP[@]}"; do [ -n "${PROFILE_CAPS[${PROFILE_MAP[$k]}]:-}" ]; done
  ```

  An earlier draft proposed a `claude`-vs-`workstation` equivalence test instead. It is one
  host wide, and every other failure it would catch is already caught: a missing
  `PROFILE_LEGACY` entry at `:432`, a missing oracle arm by the oracle's own `*)` arm, a
  missing twin at `:292`. `tests/setup_env/profiles.bats:292`'s own comment makes this
  argument against hand-picked pairs.
- **If an equivalence test is kept anyway, it must pin values, not just compare.**
  `_profile_snapshot` (`tests/setup_env/profiles.bats:46`) guards an empty `PROFILE` with
  `exit 1` but ends its capability arm with `compgen -v | grep '^HAS_' | sort` and `exit 0`,
  so two capability-less snapshots compare equal. Assert `PROFILE=linux_workstation`,
  `LEGACY=WORKSTATION`, and a `HAS_` count of 8 before asserting equality.
  `tests/zshrc.d/cross_shell.bats:143-152` already carries the non-emptiness guard and a
  comment naming this exact failure. Note also that the helper hardcodes
  `MOCK_UNAME_S='Darwin'`, so it certifies a Linux host under a mac uname.
- `tests/zshrc.d/profiles.bats` carries **three** comments describing the table as 13 keys
  (`:114`, `:135`, `:346`). All three describe present state and go stale at 14; the numbers
  are removed rather than incremented.
- `tests/helpers/legacy_oracle.bash:13` also says "All 13 keys remain" and is **left
  alone**. It records what a mutation experiment did, not what the table holds — a frozen
  reference, which `behavior.md`'s document-hygiene split says to pin rather than update. A
  note says so, so the next reader does not "fix" it.

Everything else is already derived from `"${!PROFILE_MAP[@]}"` and covers the new host with
no edit — measured, not assumed (see Verification). The `no_legacy` exception set at
`tests/zshrc.d/profiles.bats:120` stays empty, because `claude` has a legacy variable, and
the set-equality test at `tests/setup_env/profiles.bats:485` stays green because reusing
`WORKSTATION` adds keys, not values.

### 4. Documentation

- **dotfiles `CLAUDE.md`**, Key Conventions (line 849 at `aadaf1b4`): it says `WORKSTATION`
  and `CRUNCHER` "have been removed; use `HAS_*` vars instead". Both are live in
  `PROFILE_LEGACY` (`config/profiles.sh:62-63`) and read by `.zprofile:10`. Corrected to
  describe the table as it is. Nothing else in that file needs changing: the wired-only
  sentence and the "3 edits across 2 files" count both stay true under the twin decision.
- **`README.md`**: its profile table names `workstation` as the only `linux_workstation`
  host (line 340), and the prose at line 343 says "hostname: `workstation`". Both gain
  `claude`. Line 361's wired-only sentence is unchanged for the same reason as above.
- **ai-config `USER.md`**: the machine list grows to eight, with `claude` as a development
  machine carrying all repos. "Harness development happens on exactly two" becomes three,
  and "six of the seven carry every repo" becomes seven of the eight. That two-machine line
  was deliberately narrowed on 2026-08-11, so it changes knowingly. The Session-placement
  paragraph and `workstation`'s role are left alone until the box hosts sessions.
- **`docs/superpowers/README.md`**: an All Plans row for this spec and its plan.

## Verification

Measured already, against a throwaway `git archive` of `aadaf1b4` with entries added:

| arm | result |
| --- | --- |
| entries only, no oracle arm, no exemption | rc 1 — 32 ok, 2 not ok: the twin assertion and `every PROFILE_MAP hostname sets the right legacy identity variable in bash` |
| plus `wired_only` exemption and oracle arm | rc 0 — 34 ok, 0 not ok |
| zsh side, same state | rc 0 — 9 ok, 0 not ok across `tests/zshrc.d/profiles.bats` and `cross_shell.bats` |
| `PROFILE_MAP[claude]` mistyped as `linux_workstatio` | **rc 0 — 43 ok, 0 not ok.** The hole §3's derived test closes |

Still to run, at implementation:

| check | command | expected |
| --- | --- | --- |
| RED first | the new derived `PROFILE_CAPS`-key test, against a mistyped value | red, naming the offending host |
| twin resolves | `_profile_snapshot claude` vs `_profile_snapshot claude-1` | identical, and `PROFILE=linux_workstation` with 8 `HAS_` names in each |
| full suite | `make test` | rc 0, run by the pre-push hook |
| oracle is load-bearing | delete the `claude \| claude-1)` arm, re-run `bats tests/setup_env/profiles.bats` | red; green when replaced |
| twin is load-bearing | delete `[claude-1]` from `PROFILE_MAP`, re-run the same file | red on the twin assertion |
| docs | `grep -n 'have been removed' CLAUDE.md` | no hit for the `WORKSTATION`/`CRUNCHER` claim |

The mutation rows are the point: each edit is a one-line data change whose absence a green
suite would otherwise hide — which the fourth measured arm above proves is a real risk in
this table rather than a hypothetical one.

## Rejected alternatives

- **Wired-only, no twin** — rejected on the `network-manager` evidence above. It also costs
  *more* than the twin: a `wired_only` exemption edit, plus corrections to
  `config/profiles.sh:6` and `CLAUDE.md`'s "3 edits across 2 files" claims.
- **Mint a `CLAUDE` legacy variable** — costs the two startup-file branches plus 43
  hand-typed lines across 5 files, and buys a distinction nothing needs.
- **No legacy variable, `HAS_*` only** — the cleanest end state, but `.zprofile`'s rbenv init
  and `7_final.zsh`'s venv activation both branch on legacy variables today, so the machine
  would silently skip both. Converting those two sites is a separate change.
- **A `claude`-vs-`workstation` equivalence test as the new coverage** — superseded by the
  derived `PROFILE_CAPS`-key test, which is the same size and catches the measured hole for
  every host rather than one.
- **Fold `acl`/`python3-venv` in** — they apply to every Ubuntu machine, not just this one.

## Multi-Lens Review

Reviewed at commit: `aadaf1b4` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: (1) The wired-only premise is falsified by this change's own downstream effect —
`ubuntu_common_packages.txt:46` installs `network-manager`, so the tooling whose absence
justified the exemption arrives with the first `setup_env.sh`. (2) The proposed equivalence
test is one host wide; exactly one new failure mode is unique to it, a wrong `PROFILE_MAP`
value, and a derived check over `PROFILE_CAPS` keys covers all hosts for the same size.
(3) `README.md` lines 340/343/361 are a missed doc surface of the same class as the
CLAUDE.md corrections.
Assumption: that `claude` will keep reporting `hostname -s` = `claude` after provisioning —
settled by `nmcli -t -f DEVICE,STATE device status` and `hostname -s` on the box after the
first setup run, or made irrelevant by adding the twin.
Disposition: Addressed. Twin added by operator decision (§2, with the `network-manager`
evidence). Equivalence test replaced by the derived `PROFILE_CAPS`-key test (§3), after the
hole was reproduced: a mistyped value passes 43 tests. `README.md` added to scope (§4).

### Ergonomics

Finding: (1) Same `network-manager` falsification, reached independently. (2) The doc
corrections would have missed the two in-code copies at `config/profiles.sh:6` and `:19` —
the file someone opens *in order to add a machine*. (3) The verification table's central row
pinned no value: `_profile_snapshot`'s capability arm ends with `compgen -v | grep '^HAS_' |
sort` then `exit 0`, so two capability-less snapshots compare equal; six of the profile's
eight capabilities are pinned for no Linux profile anywhere. (4) Three stale "13" comments,
not two — and a fourth in `legacy_oracle.bash:13` that is a frozen record and must not be
updated.
Assumption: same as Goal-Fit's, reached independently.
Disposition: Addressed. The twin decision makes both in-code comments stay true, so they
need no edit — recorded in §2 rather than left implicit. Value-pinning folded into §3's
equivalence-test note and the verification table. The third "13" comment and the
`legacy_oracle.bash:13` freeze are both now in §3.

### Risk

Finding: (1) The spec's "only host-keyed literals in `lib/` are `studio`/`studio-1`" claim is
false — `lib/legacy_rsync.sh:17`, `:19`, `:27` carry `bruce@workstation`, `bruce@laptop-1`
and `bruce@ratna` inside quoted ssh destinations, which a quoted-literal grep cannot see. The
conclusion survives, but the miss points at where the indistinguishability would acquire
teeth. (2) The equivalence test copies the unguarded `studio`/`studio-1` precedent rather
than the guarded `cross_shell.bats` one. (3) The `WORKSTATION`-in-tests count is 43 across 5
files, not 42 across 4 — the omitted file is the one a new legacy variable would also have to
touch.
Assumption: that nothing will bring `wlo2` up — same class as the other two, with the note
that the twin costs two data lines and removes the question entirely.
Disposition: Addressed. The `lib/` claim is replaced with the `git grep -nw 'WORKSTATION'`
derivation and the wrong version is kept as a recorded correction (§1). Counts corrected to
43 across 5. Guarding folded into §3.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
