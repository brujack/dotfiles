# Changelog


## Bug Fixes

- drop unused gitleaks path allowlists (#480)

- load Google Cloud creds per command (#481)

- account for every cloned repo in the hook config (#482)

- put pyenv shims on PATH without activation (#485)

- gate sudo seams on BATS_TEST_TMPDIR (#489)

- harden Windows PowerShell setup (#490)

- honour checksum and root-path seams only under bats (#491)

- honour root-path and install seams only under bats (#492)

- install pinned globals through Homebrew npm, never the system npm (#493)

- honour verifier and trust-anchor seams only under bats (#495)



## Documentation

- doctor checks for installed hooks and ggshield auth

- revise doctor hook checks after Step 8 round 1

- revise doctor hook checks after Step 8 round 2

- doctor hook checks external review round 1

- approve doctor hook and ggshield checks design

- doctor hook and ggshield checks

- mark doctor hook/ggshield plan done, update audit rows

- doctor check for hooks that drift from HEAD

- revise hook drift spec after round-1 lenses

- scope hook drift check to symlinks after round 2

- make hook drift requirements self-contained

- 2026-11-22-doctor-hook-drift-design external review round 1

- approve hook drift spec

- doctor hook drift check

- mark doctor hook drift plan done

- record jscpd version drift across boxes

- doctor jscpd version check

- retire doctor jscpd check after Step 8

- perf_event_paranoid ceiling design

- perf spec notes CLAUDE.md byte ceiling

- perf spec multi-lens review round 1

- perf spec persists exactly 2 after lens round 1

- perf spec round 2 revisions

- 2026-11-25-perf-event-paranoid-ceiling-design external review round 1

- approve perf_event_paranoid ceiling spec

- perf_event_paranoid ceiling plan

- mark perf ceiling done and list it in doctor

- note JSCPD_VER bump needs ai-config (#487)

- add manifest link drift and dir mode race

- add link-helper recurse, PSGallery trust, sudo seam

- list the PowerShell pin table, note Boxstarter drift gap

- close security audit F1 and F3/F4/F7/F12 rows

- describe the push gates and what skipping hooks skips

- extend the real-root-path guard beyond workflows.bats



## Features

- check installed hooks and ggshield authentication (#479)

- flag symlinked hooks that drift from the default branch (#483)

- warn on .gitguardian config that sets ggshield ignore rules (#484)

- hold perf_event_paranoid at 2 on devtools hosts (#486)

- run the push-time gates through ai-config's stub (#488)



## Testing

- keep workflows e2e tests off real /etc paths (#494)


