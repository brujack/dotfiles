#!/usr/bin/env bats
#
# .ssh/config is symlinked into ~/.ssh/config on every development machine, so
# a stanza change reaches all of them at once. These tests resolve the tracked
# file with the real ssh client (`ssh -G -F`), which reports the effective
# options for a host without connecting. -F also keeps the system-wide
# ssh_config out of the result, so only this file is under test.

bats_require_minimum_version 1.5.0

setup() {
  CONFIG="${BATS_TEST_DIRNAME}/../.ssh/config"
  export HOME="${BATS_TEST_TMPDIR}"
}

# Print the value ssh resolves for one option of one host.
resolved() {
  ssh -G -F "${CONFIG}" "$1" | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }'
}

@test "the Cloudflare entry host sends keepalives so an idle session is not reaped" {
  [ "$(resolved home-secure.conecrazy.ca serveraliveinterval)" = "30" ]
  [[ "$(resolved home-secure.conecrazy.ca proxycommand)" == *"cloudflared access ssh --hostname"* ]]
}

@test "keepalives are scoped to the home hosts, not every host" {
  [ "$(resolved example.com serveraliveinterval)" = "0" ]
  [ "$(resolved github.com serveraliveinterval)" = "60" ]
}

@test "claude-home jumps through the bastion and the workstation with the home key" {
  [ "$(resolved claude-home hostname)" = "claude.home.conecrazy.ca" ]
  [ "$(resolved claude-home proxyjump)" = "home-secure.conecrazy.ca,workstation.home.conecrazy.ca" ]
  [[ "$(resolved claude-home identityfile)" == */.ssh/home ]]
  [ "$(resolved claude-home serveraliveinterval)" = "30" ]
}

@test "home hosts log in as bruce whatever the local account is called" {
  # ssh takes its default user from the account database, not $USER, so the
  # local account cannot be faked. A trailing catch-all User stands in for it:
  # ssh keeps the first value it reads, so only an explicit User in the
  # tracked stanza beats the sentinel.
  CONFIG="${BATS_TEST_TMPDIR}/config"
  { cat "${BATS_TEST_DIRNAME}/../.ssh/config"; printf '\nHost *\n  User sentinel\n'; } > "${CONFIG}"
  [ "$(resolved example.com user)" = "sentinel" ]
  [ "$(resolved workstation.home.conecrazy.ca user)" = "bruce" ]
  [ "$(resolved claude-home user)" = "bruce" ]
  [ "$(resolved claude-home-tmux user)" = "bruce" ]
  [ "$(resolved workstation-home user)" = "bruce" ]
  [ "$(resolved workstation-home-tmux user)" = "bruce" ]
}

@test "workstation-home jumps through the bastion only, with the home key" {
  [ "$(resolved workstation-home hostname)" = "workstation.home.conecrazy.ca" ]
  [ "$(resolved workstation-home proxyjump)" = "home-secure.conecrazy.ca" ]
  [[ "$(resolved workstation-home identityfile)" == */.ssh/home ]]
  [ "$(resolved workstation-home serveraliveinterval)" = "30" ]
  [ -z "$(resolved workstation-home remotecommand)" ]
}

@test "workstation-home-tmux attaches to tmux on the workstation" {
  [ "$(resolved workstation-home-tmux hostname)" = "workstation.home.conecrazy.ca" ]
  [ "$(resolved workstation-home-tmux proxyjump)" = "home-secure.conecrazy.ca" ]
  [ "$(resolved workstation-home-tmux requesttty)" = "true" ]
  [ "$(resolved workstation-home-tmux remotecommand)" = "tmux attach-session || tmux new-session" ]
}

@test "claude-home carries no remote command, so scp and ad-hoc commands still work" {
  # Positive control first: the tmux alias does carry one, so an empty result
  # below means the plain alias lacks it, not that the probe cannot see it.
  [ -n "$(resolved claude-home-tmux remotecommand)" ]
  [ -z "$(resolved claude-home remotecommand)" ]
}

@test "claude-home-tmux attaches to tmux on the target over the same jump chain" {
  [ "$(resolved claude-home-tmux hostname)" = "claude.home.conecrazy.ca" ]
  [ "$(resolved claude-home-tmux proxyjump)" = "home-secure.conecrazy.ca,workstation.home.conecrazy.ca" ]
  [[ "$(resolved claude-home-tmux identityfile)" == */.ssh/home ]]
  [ "$(resolved claude-home-tmux requesttty)" = "true" ]
  [ "$(resolved claude-home-tmux remotecommand)" = "tmux attach-session || tmux new-session" ]
}
