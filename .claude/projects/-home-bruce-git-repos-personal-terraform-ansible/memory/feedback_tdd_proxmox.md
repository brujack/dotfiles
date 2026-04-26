---
name: TDD discipline in proxmox/ work
description: TDD RED→GREEN cycle must be followed for all proxmox test work, not just ansible work
type: feedback
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

Follow strict TDD (one failing test → minimal code → commit) when working in `proxmox/`, just as in `ansible/`.

**Why:** During a multi-PR proxmox refactoring session (April 2026), tests were written after implementation — cpu/memory/disk assertions, vm name assertions, check block assertions, and goss fixes were all added as retroactive "strengthening" rather than driving the implementation. The user explicitly called this out: "since we have been working in the proxmox directory we have not been following strong tdd practices."

**How to apply:** Before writing any new Terraform config, packer config, or goss rule, write the failing test first. One behavior at a time. Confirm RED with correct failure message, then write minimum code to go GREEN. The proxmox/ TDD cycle:

- New VM attribute → assert it in `expectedVMs` first, run test (fail), then add the attribute
- New goss check → add to `goss.yaml` assertion first, run validate (fail), then fix the template/script
- New check block → write Go assertion first, run test (fail), then add the HCL `check {}` block
