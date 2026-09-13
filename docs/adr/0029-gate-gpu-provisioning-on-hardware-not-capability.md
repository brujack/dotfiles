# ADR-0029: Gate GPU provisioning on detected hardware, not on a profile capability

**Date:** 2026-09-12
**Status:** Accepted

## Context

Until dotfiles#273 this repo provisioned no GPU stack at all — zero occurrences of
`nvidia`, `nouveau`, `cuda` or `HAS_GPU` across `lib/`, `config/`, `Brewfile` and
`ubuntu_*.txt`. The gap surfaced on the Linux `claude` box, which carries an RTX 2060
SUPER that was running the open-source **nouveau** driver with no `nvidia-smi`, no CUDA,
and no container toolkit — so `ollama`, which `_install_ubuntu_brew_packages` installs on
that machine, ran CPU-only against an idle GPU.

Adding the driver raised a question the existing machine model does not answer: **what
decides whether a box gets it?**

Every other optional install in `_install_ubuntu_*` gates on a `HAS_*` capability derived
from `config/profiles.sh` — `HAS_DOCKER`, `HAS_K8S`, `HAS_RUST`. Following that pattern
would mean a new `HAS_GPU` on the profiles table. It does not work here, for three
measured reasons:

1. **`claude` and `workstation` share one profile.** `PROFILE_MAP` maps both to
   `linux_workstation`, whose capabilities are `gui devtools aws k8s docker rust snap
flatpak`. A capability is a property of the _profile_, so any `HAS_GPU` on
   `linux_workstation` fires on every machine with that profile — including a future
   GPU-less one — and splitting the profile to avoid that would duplicate eight
   capabilities to express one hardware fact.
2. **The same profile covers WSL2**, where the NVIDIA driver lives on the Windows side and
   installing a Linux driver is wrong rather than merely redundant.
3. **Hardware is not stable per host anyway.** A card can be added or removed without the
   hostname or profile changing, and the profile table would not notice.

## Decision

`_install_ubuntu_nvidia` gates on **detected hardware**: `_nvidia_gpu_present` matches PCI
vendor `10de:` in `lspci -nn` output. No `HAS_GPU` capability is added to
`config/profiles.sh`.

```bash
_nvidia_gpu_present() {
  if [[ -n ${_OVERRIDE_NVIDIA_GPU_PRESENT+x} ]]; then
    return "${_OVERRIDE_NVIDIA_GPU_PRESENT}"
  fi
  lspci -nn 2> /dev/null | grep -qi '\[10de:'
}
```

The vendor ID rather than a device-class match is load-bearing. `workstation` carries
**two** display adapters — the discrete 4070 Ti SUPER and the Ryzen 7950X's integrated AMD
Raphael on the CPU die — so a gate reading "is there a VGA controller" would fire on AMD
silicon and try to install an NVIDIA driver for it. Matching `10de:` sees exactly one card
on each Linux box and ignores Raphael.

Absent `lspci` (macOS, or a stripped container) the pipeline yields no match and the
function returns non-zero, so the default is **skip** rather than attempt.

`_OVERRIDE_NVIDIA_GPU_PRESENT` exists because `lspci` is not mocked in `tests/mocks/` and
the bats suite runs on a machine with no NVIDIA card, making the install branch otherwise
unreachable.

## Consequences

**Good.** One code path serves every Linux box without a profile change; adding or removing
a card needs no repo edit; WSL2 and GPU-less machines skip automatically; and the tests can
drive both branches through one seam.

**Costs, accepted.**

- The gate is a shell-out per `install_ubuntu_packages` run. Negligible, and only on the
  setup/developer paths — `-t update` does not reach it.
- `lspci` comes from `pciutils`, which is present on Ubuntu server and desktop images but is
  not guaranteed on a minimal container. The failure mode is a skip, not an error, which is
  the safe direction but is silent — a box that _should_ get the driver and lacks `lspci`
  gets nothing and says nothing.
- Hardware detection cannot express intent. An operator who wants the driver installed on a
  machine whose card is absent or not yet seated has no way to say so.

**Not covered by this ADR.** The _download_ half of the NVIDIA work — pinning the driver
version and verifying third-party artifacts — is already decided by
[ADR-0013](0013-no-curl-bash-installs.md) and
[ADR-0028](0028-awscli-download-signature-verification.md); `_install_ubuntu_nvidia` applies
those rather than introducing a new position. One honest deviation is recorded there rather
than here: NVIDIA's container-toolkit signing key has **no published digest**, so it cannot
be pinned the way `rustup-init` is. The mitigation is `signed-by=`, scoping that key to the
one repo it vouches for. That is byte-identical to what the existing `teleport`,
`cloudflare` and `gcloud` blocks in `lib/linux_ubuntu.sh` already do, and to what the
workstation already carries on disk — a pre-existing house pattern, not a new exposure.

Installing the driver does **not** bind it: nouveau holds the card until a reboot, so the
function emits a warning rather than implying the GPU is live. Verified end to end on
`claude` — driver installed, reboot, `nvidia-smi` reporting the 2060 SUPER on `610.57.04`,
`nouveau` unloaded, boot id changed.

## Related

- [ADR-0003](0003-profile-capability-model-for-machine-detection.md) — the profile/capability
  model this decision deliberately does not extend
- [ADR-0013](0013-no-curl-bash-installs.md) — no `curl | bash` installs
- [ADR-0028](0028-awscli-download-signature-verification.md) — verify a downloaded artifact
  before executing it
- `docs/superpowers/specs/2026-09-12-rustup-provisioning-design.md` — the spec this shipped under
