#!/usr/bin/env bats
# bin/home-lan-probe: succeeds only when the host at <ip> presents the expected
# ed25519 host key. ssh-keyscan is a stub reached through _SSH_KEYSCAN_BIN, so no
# test touches the network; the real ssh-keygen parses the stub's output.

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/bin/home-lan-probe"

  ssh-keygen -q -t ed25519 -N '' -f "${BATS_TEST_TMPDIR}/k"
  ssh-keygen -q -t ed25519 -N '' -f "${BATS_TEST_TMPDIR}/other"
  FPR="$(ssh-keygen -lf "${BATS_TEST_TMPDIR}/k.pub" | awk '{print $2}')"
  OTHER_FPR="$(ssh-keygen -lf "${BATS_TEST_TMPDIR}/other.pub" | awk '{print $2}')"

  STUB="${BATS_TEST_TMPDIR}/keyscan-stub"
  cat > "${STUB}" << STUBEOF
#!/usr/bin/env bash
printf '%s %s\n' "\$4" "\$(cut -d' ' -f1,2 "${BATS_TEST_TMPDIR}/k.pub")"
STUBEOF
  chmod +x "${STUB}"
  export _SSH_KEYSCAN_BIN="${STUB}"
}

@test "matching fingerprint exits 0" {
  run "${SCRIPT}" 192.0.2.10 "${FPR}"
  [ "${status}" -eq 0 ]
}

@test "different fingerprint exits 1" {
  run "${SCRIPT}" 192.0.2.10 "${OTHER_FPR}"
  [ "${status}" -eq 1 ]
}

@test "keyscan printing nothing exits 1" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB}"
  run "${SCRIPT}" 192.0.2.10 "${FPR}"
  [ "${status}" -eq 1 ]
}

@test "keyscan printing garbage (ssh-keygen rc 255) exits 1" {
  printf '#!/usr/bin/env bash\nprintf "not a key\\n"\n' > "${STUB}"
  run "${SCRIPT}" 192.0.2.10 "${FPR}"
  [ "${status}" -eq 1 ]
}

@test "nonexistent keyscan binary exits 1" {
  export _SSH_KEYSCAN_BIN="${BATS_TEST_TMPDIR}/does-not-exist"
  run "${SCRIPT}" 192.0.2.10 "${FPR}"
  [ "${status}" -eq 1 ]
}

@test "non-executable keyscan binary exits 1" {
  chmod -x "${STUB}"
  run "${SCRIPT}" 192.0.2.10 "${FPR}"
  [ "${status}" -eq 1 ]
}

@test "no arguments exits 2 with usage" {
  run "${SCRIPT}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *usage* ]]
}

@test "one argument exits 2" {
  run "${SCRIPT}" 192.0.2.10
  [ "${status}" -eq 2 ]
}

@test "three arguments exits 2" {
  run "${SCRIPT}" 192.0.2.10 "${FPR}" extra
  [ "${status}" -eq 2 ]
}

@test "stub output parses through real ssh-keygen and field 2 is what is compared" {
  out="$("${STUB}" -T 1 -t ed25519 192.0.2.10 | ssh-keygen -lf - 2> /dev/null)"
  [ "$(printf '%s\n' "${out}" | awk '{print $2}')" = "${FPR}" ]
  run "${SCRIPT}" 192.0.2.10 "${FPR}"
  [ "${status}" -eq 0 ]
  # Field 1 (key size) and the comment must not count as a match.
  run "${SCRIPT}" 192.0.2.10 "256"
  [ "${status}" -eq 1 ]
}
