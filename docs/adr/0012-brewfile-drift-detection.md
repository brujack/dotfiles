# ADR-0012: Brewfile Drift Detection in Update Summary

**Date:** 2026-04-29
**Status:** Accepted

## Context

The dotfiles update workflow runs `brew upgrade` and `apt-get dist-upgrade` to keep system packages current. The inverse problem — packages installed on the machine that are NOT in the managed Brewfile — was invisible. Ad-hoc `brew install` commands leave untracked formulas that accumulate and cause machine state to diverge from the managed manifest.

Two Homebrew commands are relevant:

- `brew list --formula` returns all installed formulas including auto-installed dependencies, making raw comparison noisy.
- `brew leaves --installed-on-request` returns only explicitly installed formulas (not pulled in as dependencies), which is the correct signal for drift.

Capability-conditional packages added an additional complication: the Brewfile may reference formulas tied to a capability flag (e.g. `HAS_PRINTING`) that is inactive on headless or non-printing machines. Comparing against the full Brewfile formula list produces false positives for packages that were never intended to be installed on that machine.

## Decision

Add Brewfile drift detection to the update summary output. The `_update_brew_drift` function:

1. Reads the managed Brewfile to extract formula names.
2. Runs `brew leaves --installed-on-request` to get explicitly installed formulas.
3. Computes the set difference: installed-but-not-in-Brewfile.
4. Filters out formulas tagged with a capability flag that is inactive on the current machine, suppressing false positives for e.g. printing-only packages on a headless machine.
5. Reports the drift list in the update summary — advisory only, not blocking.

Drift output is advisory. The operator resolves it by either running `brew uninstall <formula>` or adding the formula to the managed Brewfile. The detection does not auto-remediate.

Drift detection is macOS-only. The `_update_brew_drift` function is gated with `[[ "${MACOS}" == "1" ]]`; the Brewfile and Homebrew tooling are macOS-specific and the function is never called on Linux.

## Consequences

- Machines are auditable — drift surfaces immediately in every update run rather than accumulating silently.
- Capability filtering is required to avoid false positives; the filter logic must stay in sync with the capability flags defined in `lib/detect_env.sh`.
- BATS tests for drift must mock `brew leaves` and the Brewfile read; the capability filter logic must be exercised with both active and inactive capability flags.
- The drift report is a list, not a count — operators can act on the exact formula names without additional investigation.

## Related

- [ADR-0003: Profile/capability model for machine detection](0003-profile-capability-model-for-machine-detection.md)
- [ADR-0004: Modular lib/ structure for setup_env.sh](0004-lib-modular-structure-for-setup-env.md)
