Tools: Read, Bash, SubagentHandback

The spec's strongest choices should stay as they are. Routing defaults to direct, and the probe can only add the Cloudflare jump, so an absent or broken probe on any host leaves ssh as it is today. The probe checks host identity rather than whether the address answers. `HostName` is the IP the probe just verified, plus a literal `HostKeyAlias`, which removes the DNS and FQDN known_hosts dependency. On the unit, `KillMode=process` with no `-` on `ExecStart`, together with doctor's `is-failed` check, keeps a partial boot failure visible without killing the sessions that did start. The review history also shows the machinery shrinking: removing `home-ssh` and ControlMaster was right. What remains are gaps at the boundaries; the core design is settled.

### F1.1 How `repo-session --all` finds `config/repo-sessions.sh` is unspecified, and the installed symlink breaks the obvious choice

The spec never says how the installed `~/.local/bin/repo-session` (a `safe_link` symlink) locates `config/repo-sessions.sh`. It also does not separate "this host has no entry" from "the list could not be read".

- **How it fails.** The usual idiom, `$(dirname "${BASH_SOURCE[0]}")/../config`, resolves through the symlink to `~/.local/config/repo-sessions.sh`, which does not exist.
  - At boot the unit then either fails every dir, or, if a missing file is treated like "a host with no entry has no sessions", exits 0. In that case the unit reads `active`, no sessions exist, and doctor gives only a WARN.
  - That is the one path the unit exists for (component 5), and V1 is the only check that would catch it.
- **Why the tests miss it.** Every planned bats case runs `bin/repo-session` from inside the repo, so all of them pass.
- **Measured** (bash 5.3.9, Ubuntu 26.04 on `claude`). A script run through a symlink in a fixture `~/.local/bin` printed `dirname=<scratch>/sl/home/.local/bin`, not the repo's `bin/`.
- **Fix.**
  - State the lookup: `readlink -f` on `BASH_SOURCE[0]`, or a fixed `${HOME}/git-repos/personal/dotfiles/config/repo-sessions.sh` with a seam.
  - Make an unreadable or missing list exit non-zero, distinct from "no entry, exit 0".
  - Add one test that runs `--all` through a symlink in a fixture `~/.local/bin`.
  - This changes R3 and adds a Testing case.

### F1.2 The Warp test compares a set of dirs, so a tab aimed at the wrong host passes

R14 and the Warp test check only that "the set of `repo-session` arguments equals the union of the `REPO_SESSIONS` lists".

- **How it fails.** `ssh -t claude .local/bin/repo-session terraform_ansible/ansible` (wrong host) passes. So does a config that swaps the hosts of two tabs. The host is the most likely mistake when editing three YAML files by hand, and the result is a tab that fails or starts a stray session.
- **Fix.** Parse each tab into a (host, dir) pair and require the multiset of pairs to equal `{(h, d) : d in REPO_SESSIONS[h]}`, with no duplicates. This changes R14's "exactly the union" wording.

### F1.3 `Match exec` runs under `$SHELL`, not `sh -c`

The spec says this twice: in component 3's `$HOME` bullet and in the Testing ssh-routing bullet. It is wrong.

- **Measured** (OpenSSH_10.2p1 Ubuntu-2ubuntu3.8, on `claude`). The config was `Match host claude exec "echo \$0 >> log; true"`.
  - Run with `SHELL=/bin/bash`, the exec logged `/bin/bash` and `hostname` resolved to the `Match` value.
  - Run with `SHELL=/bin/false`, the exec failed and `hostname claude` came back unchanged.
  - A non-matching `Match host other exec "touch …"` was skipped, so the exec runs only when the host matches.
- **Consequences.**
  1. On every Mac, and on the Linux hosts, each `ssh claude` or `ssh workstation` starts `zsh -c`. That zsh sources `~/.zshenv` and `~/.zshenv.local`, so N6's "only side effect is the `uname -s` test" is not literally true. It is harmless today.
  2. The routing tests run under whatever `SHELL` the runner exports: zsh on development boxes, bash on CI.
- **Fix.**
  - Correct both sentences.
  - Pin `SHELL=/bin/sh` in the routing tests' `setup()`.
  - Optionally add one case with `SHELL=` set to zsh, which is what the Macs run.

### F1.4 The known_hosts premise was measured on the three machines that never use the Cloudflare route

"Every machine's known_hosts holds these hosts under the bare names" was checked on `claude`, `workstation` and the Studio. The machines that do take the Cloudflare chain are reception and the laptop. Today they reach the hosts through `*-home` aliases whose `HostName` is the FQDN, so their entries are most likely under `claude.home.conecrazy.ca` and `workstation.home.conecrazy.ca`. Not measured.

- **How it fails.** On reception's first launch, the seven session tabs all hit `HostKeyAlias claude` or `workstation` with no matching entry, which gives up to seven trust-on-first-use prompts at once. Any BatchMode use fails outright.
- **The jump hop is a separate case.** The claude chain still jumps through `workstation.home.conecrazy.ca` with no alias. So the laptop needs that FQDN entry while also needing the bare `workstation` entry for direct `ssh workstation`.
- **Fix, pick one.**
  - Before planning, run `ssh-keygen -F claude`, `ssh-keygen -F workstation` and `ssh-keygen -F workstation.home.conecrazy.ca` on reception and the laptop.
  - Or ship the two host keys, which are already pinned by fingerprint, in a tracked `UserKnownHostsFile` added beside `~/.ssh/known_hosts`. That removes trust-on-first-use from both routes.
- **Where it lands.** This changes the component 3 "Host keys" bullet and adds a V item.

### Smaller items

- **F1.5** `repo-session dotfiles/` (tab completion adds the trailing slash) gives an empty session name. Measured with bash 5.3.9: `name=[]`. What tmux 3.6 does with `-s ""` is unmeasured. R4 should strip a trailing `/` or reject it.
- **F1.6** `safe_link` does not create the parent directory (`lib/helpers.sh:109`). The spec never says who creates `~/.config/systemd/user/` on a host where it does not exist yet.
- **F1.7** Measured offline with `systemctl --root=<scratch> --global` on systemd 259:
  - Before `enable`, a symlinked unit reports `is-enabled` as `linked` with rc 1. After it, `enabled` with rc 0.
  - `enable` points the `default.target.wants` link directly at the repo file, not at the `~/.config` link.
  - Doctor's "not enabled" check should key on the rc, not on the string.
- **F1.8** V1 covers only `claude`. Nothing verifies the `workstation` `ansible` session after a reboot.

No earlier external round, so there are no `Author response` rows to answer.

F1.1 and F1.2 must be fixed before the plan, since both are cheap changes to requirements and tests. F1.3 is a text correction plus pinning `SHELL` in one test file. F1.4 needs one measurement on reception and the laptop. The design itself did not move in this round. The remaining items are test apparatus and premises that the first red tests or V2 would expose, so another round would cost more than it finds.

Recommend: stop
