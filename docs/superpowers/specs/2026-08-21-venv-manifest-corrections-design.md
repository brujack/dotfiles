# Two venv manifest corrections — Design

**Date:** 2026-08-21
**Status:** Proposed

## Two changes, one file, one re-lock

Both are one-line edits to `pyproject.toml`'s `runtime` group, both require the same
`uv lock` re-resolve, and both need the same stale comment rewritten. Splitting them means
two cycles re-locking the same file twice.

1. **Remove `"boto3"`** — the fleet stops asking for a package nothing uses.
2. **Floor `checkov>=3.3.13`** — operator decision 2026-08-21, so a bump cannot silently walk
   it backwards again.
3. **Take the `shell-gpt` upgrade the floor unblocks** — 1.0.1 -> 1.5.1, openai 0.28.1 ->
   2.54.0. **Added by operator instruction 2026-08-21**, after being found mid-implementation
   and initially deferred. Recorded as a scope change rather than allowed to drift: the spec
   originally declared two changes and this is a third.

## Change 1 — drop the `boto3` declaration, stated narrowly because the obvious framing is wrong

Remove `"boto3"` from the `runtime` dependency group in `pyproject.toml`.

**This does NOT remove boto3 from the venv.** Measured against the lock (`tomllib`, not grep):
`checkov` and `cloudsplaining` both declare `boto3` as a dependency, so it stays installed at
1.35.49 regardless. What changes is that the fleet stops *asking* for a package it does not
use; boto3 becomes purely transitive, and leaves on its own the day checkov does.

Anyone reading "remove boto3" and expecting `boto3` to disappear from `uv pip list` will be
wrong. That is the single most likely misreading and it is why this section is first.

## Why it should go

**The reason it was installed is gone.** The operator installed boto3 because **AWS CLI v1**
was a Python package that required botocore/boto3. **v2 ships as a self-contained binary with
its own bundled Python** — measured: `aws --version` reports `aws-cli/2.36.25 Python/3.14.6`,
`/usr/local/bin/aws` is a symlink into `/usr/local/aws-cli/`, and `import boto3` from system
python3 raises `ModuleNotFoundError`. The vendored copy is private to the CLI.

**Nothing in the fleet consumes it.** The only shape that would is an Ansible AWS module call.
Checked across four call shapes, by two sessions independently:

| shape | result |
| --- | --- |
| `amazon.aws.*` / `community.aws.*` FQCN | 0 files |
| short form (`ec2_instance:` with a `collections:` block) | 0 files |
| `lookup('amazon.aws.aws_secret', ...)` | 0 files |
| `connection: aws_ssm`, `aws_ec2` inventory plugin | 0 files |

`environments/aws_bruce/hosts` is a static INI inventory — SSH only, no API call. No
`requirements.yml` exists anywhere in the fleet, so the collections were never galaxy-requested.

**The AWS work that does happen never loads Python.** `terraform_ansible` has 22 `.tf` files
referencing AWS and declares `hashicorp/aws` — a Go provider using the AWS SDK for Go. It needs
credentials and the CLI binary; it does not need boto3.

**Operator-confirmed 2026-08-18**, recorded in terraform_ansible's backlog: the AWS surface and
Test Kitchen are legacy. This change is downstream of a decision already taken.

## Change 2 — floor `checkov>=3.3.13`

**Operator decision, 2026-08-21.** Accepts two unreachable advisories for a current scanner,
over pinning `==3.2.414` for zero advisories at 15 months stale.

**Why a floor is needed at all.** dotfiles#227, titled *"bump asteval from 1.0.6 to 1.0.9"*,
walked checkov **3.3.13 -> 3.2.414** and removed `asteval` and `ecdsa` entirely — 20
insertions, 85 deletions — and auto-merged. checkov pins `asteval` exactly, so forcing 1.0.9
made every checkov >=3.2.459 unsatisfiable and the resolver chose an older checkov that does
not need asteval at all. Renovate edited the **lock, not the manifest**: `asteval>=1.0.9`
appears nowhere in `pyproject.toml`, so the manifest never recorded the change.

Measured by the ai-config session before proposing it:

```
floor alone         -> checkov 3.3.13, asteval 1.0.6, ecdsa 0.19.2, 275 packages   [ai-config's tree]
boto3 drop + floor  -> same versions, **273** packages                          [this branch, derived]
floor + forced bump -> "No solution found ... checkov>=3.3.13 depends on asteval==1.0.6 and
                        dotfiles-venv:runtime depends on asteval>=1.0.9 ... unsatisfiable"
```

**Why 273 and not 275, settled.** `checkov 3.2.414` depends on `openai 0.28.1`, which blocks `shell-gpt 1.5.1` (needs `openai>=2.0`), so the resolver has been holding shell-gpt at **1.0.1**. This floor removes that blocker, but `uv lock` is conservative and does not lift an existing resolution unaided — so shell-gpt stays at 1.0.1 and openai leaves with checkov, giving 273. Adding `--upgrade-package shell-gpt` yields 1.5.1 + openai 2.54.0 and **275**, which is ai-config's number and is correct for a tree that already carries shell-gpt 1.5.1. Both are right for their conditions. **This cycle deliberately does not take the shell-gpt upgrade** — it is a third change, and it is backlogged with the measurement.

**The two totals differ and the derived one governs.** ai-config measured 275 on their tree; this branch resolves to **273**, because flooring checkov also drops `openai` (3.2.414 requires it, 3.3.13 does not). Neither number is a contract — the package count is a consequence of the resolver, so case 4 asserts what this branch actually produces and must be re-derived if a new checkov ships, since `>=3.3.13` is a floor and not a pin.

So the floor converts a silent year-long downgrade into a resolver error naming both packages
and the incompatibility. That is the whole point: not preventing the conflict, but making it
loud.

**The `ACCEPTED RISK` comment block must be rewritten in the same change.** It currently
reasons at length about `asteval` 1.0.6's advisories and `ecdsa`'s Minerva finding — in a lock
where **neither package is present**. Correct when written, fiction since #227. After the
floor both return, so the block becomes accurate again, but it must state the floor as the
reason they are present rather than describing them as incidental.

## Explicitly out of scope

**Removing `amazon.aws` / `community.aws`.** They are not ours to remove from this manifest:
`ansible` 14.3.1 is the **bundle**, which ships ~800 collections including those two.
`ansible-core` is 2.21.3 underneath it. Dropping the collections means migrating the manifest
from `ansible` to `ansible-core` plus an explicit collection set — a different change, with its
own blast radius, and one that would need its own spec. Filed as a backlog row, not folded in.

**Anything about checkov.** Its `boto3` requirement is what keeps boto3 installed, and the
separate question of pinning checkov against silent resolver downgrades (dotfiles#227) is
ai-config's manifest to amend. Not touched here.

## Change surface

| file | change |
| --- | --- |
| `pyproject.toml` | remove the `"boto3"` line; add `>=3.3.13` to `checkov`; rewrite the `ACCEPTED RISK` block |
| `uv.lock` | re-lock; 272 -> **275**, `asteval` and `ecdsa` return, checkov 3.2.414 -> **3.3.13** |
| `CLAUDE.md` | drop `boto3` from the documented venv package list |
| tests | any assertion naming boto3 in the declared set |

## Verification

Every assertion pairs with a control in the same command; every case names its actor.

| # | assert | control / why falsifiable |
| --- | --- | --- |
| 1 | `boto3` absent from `pyproject.toml`'s `runtime` group | `grep -c` on a package that must remain (`ansible`) in the same command |
| 2 | `boto3` **still present** in `uv.lock` | pins the counter-intuitive half; goes red if someone "helpfully" purges it. Version will move with checkov's floor — assert presence, not a literal |
| 3 | `uv lock --check` resolves | proves the manifest is still satisfiable |
| 4 | lock has **275** packages; `asteval`, `ecdsa`, `jiter`, `openai` **present** | 272 -> 275. With change 3 taken, `openai` returns at **2.54.0** via shell-gpt 1.5.1 rather than 0.28.1 via checkov — a different package at a different version, so assert the version, not just presence |
| 5 | `shell-gpt --version` reports 1.5.1 | openai 0.28 -> 2.54 crosses a major boundary; a lock that resolves is not proof the tool runs. **Verified: `ShellGPT 1.5.1`** |
| 6 | `make test` rc=0 | aggregate gate |
| 7 | mutation: re-add `"boto3"` → case 1 red; drop the floor → case 4 red; revert shell-gpt to 1.0.1 → case 5 red | three arms, one per declared change |

Case 2 is the one that matters. Three of the four previous specs this session shipped a case
that passed on empty output; case 2 is deliberately an assertion that something **remains**, so
it cannot pass by absence.

## Risks

**Low, and the realistic failure is a wrong expectation rather than a broken venv.** boto3 stays
installed, so nothing that imports it breaks even if a consumer is later discovered. The change
is reversible by re-adding one line.

The one real risk is scope creep during implementation — removing the collections, or purging
boto3 from the lock by hand — both of which case 2 and case 4 catch.

**Residual, stated rather than implied:** all consumer evidence is a static grep over
checked-in files. An ad hoc `ansible -m amazon.aws.*` typed at a shell and never committed
would not appear. Judged unlikely given `aws_bruce` is a static inventory and the AWS work is
terraform, but it cannot be measured.

## Related

- ai-config `docs/adr/0070` — the lockfile design this manifest came from
- ai-config `specs/2026-08-20-python-dependency-management-v2-design.md` (Draft) — owns checkov
- terraform_ansible backlog, 2026-08-18 — operator confirmation that the AWS surface is legacy
