#!/usr/bin/env bash
# lib/git_sync.sh — git-native repo sync (fetch/pull/push, never clobbers local work)

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
