Tools: Read, Bash, SubagentHandback

The design is right, and I would not change its core. Persisting exactly 2 and applying 2 only when live is above 2 removes the loosening ratchet that round 1 found. Letting `-1` fail closed through the unchanged readers keeps the shared floor code out of scope. The `systemd-sysctl <conf>` form of V2 avoids a whole-system re-apply under live runners. I re-checked the premise read-only. `/proc/sys/kernel/perf_event_paranoid` reads `4` on `claude` (7.0.0-43-generic) and on `workstation` (7.0.0-44-generic). `systemd-sysctl --cat-config | grep perf_event` matches nothing on `claude`. `perf stat -x, -e cycles,instructions true` on `claude` (perf 7.0.14) fails with "No supported events found. Access to performance monitoring and observability operations is limited." All remaining findings are in requirements text and test apparatus, not the design.

## F1.1 The doctor's conf-refusal FAILs are missing from R11, the doctor table and the test list

- **Defect.** The prose says `_doctor_sysctl_ceiling` "classifies the conf as the step does (same FAIL texts)". But the "first match wins" table and R11 list only these, in order: live unreadable, conf missing, conf above 2, live above 2, conf below 2, live below 2, PASS. The four refusals (unreadable, non-text, other keys, unparseable) are in neither. The test list says only "each doctor row", so no test covers them. The step side has them: R8 plus "each classifier refusal".
- **Concrete failure.** Take a conf holding `kernel.perf_event_paranoid = -1`, which is the one case the spec's `-1` reasoning exists for. A doctor that skips the parse check and goes to `conf > 2` / `conf < 2` with an empty `_val` satisfies R11 and every listed test. The same goes for a doctor that prints the `tee` overwrite remedy for a conf holding other keys. The rule "never prints a `tee` remedy for a conf the step would keep" then has no test behind it.
- **Fix.** In R11 and in the table, put the four refusal FAILs straight after `cannot read <proc>`, with the texts `_doctor_sysctl_floor` uses (`lib/helpers.sh` around line 1355). Add one doctor test per refusal, one of them at conf `-1`, each asserting no `tee` line in the output.

## F1.2 R13 forces a third and fourth copy of the conf-refusal block, and the spec does not record that trade

- **Defect.** R13 freezes the `_sysctl_floor_step` and `_doctor_sysctl_floor` bodies. Each already holds the same inline block: four checks with literal message strings, about 20 lines each. So the ceiling step and the ceiling doctor must each paste the same block, which makes four copies.
- **Concrete failure.** The next refusal added (a new byte class, say) or the next message change lands in one or two copies. Step and doctor then disagree about which confs they will touch. That disagreement is the exact defect class the doctor comment warns about ("an existing conf it will not touch is never answered with a tee").
- **Simpler route.** Extract one `_sysctl_conf_classify <label> <conf> <key> <emit>` helper that all four call sites use. The floor functions change only by a call replacing their inline block, and their tests run unedited. This needs R13 narrowed to "floor behaviour and tests unchanged" rather than "bodies unchanged".
- **Ask.** I am not demanding the switch this late. Record the decision either way in "Why the existing sysctl step cannot be reused".

## F1.3 `PERF_EVENT_PARANOID_MAX` is defined by R1 but nothing reads it

- **Defect.** The design passes a literal `2` to `_sysctl_ceiling_step`, a literal `2` to `_doctor_sysctl_ceiling`, and a literal `= 2` in the doctor `tee`. Nothing in the spec reads the constant.
- **Concrete failure.** If someone bumps the constant to 1, nothing changes and no test notices.
- **Fix.** Make both call sites (and the `tee` text) use `${PERF_EVENT_PARANOID_MAX}`. Add one wiring test that runs `declare -f` on both callers and asserts the constant name appears. The kernel-keys "wiring" test in `tests/setup_env/unit.bats` around line 3294 is the pattern. If the value should stay literal, delete the constant and R1's first clause instead.

## Smaller items

- **F1.4 Test stubs for the new step and check are not named.** `_stub_ubuntu_steps` (`tests/setup_env/workflows.bats` around line 909) stubs every step except the new one. The run_doctor stub lists (three in `tests/setup_env/unit.bats`, one in `tests/setup_env/plugin_node_paths.bats`) would not stub `_doctor_check_perf_paranoid`. `workflows.bats` never unsets `HAS_DEVTOOLS`, which this session exports as `1` (measured). So on `claude` the real perf step runs inside those tests, and in CI it skips: the outcome depends on the host. Nothing breaks today, because the seams hold and stdout only grows. Name the stub additions in the Tests section, and extend the kernel-keys "stub count matches" test (unit.bats around line 2971) to the perf check.
- **F1.5 R6's "(including `-1`)" is left over from round 1.** The current text lists `-1` among values "at or below 2" that are left alone. Under round 2, a `-1` conf is refused with rc 1 (R8). The bytes stay identical either way, but R6 now reads as if `-1` is accepted. Delete the parenthetical; R8 already covers it.
- **F1.6 The live `-1` message gives one signal for two causes.** A readable proc holding the valid kernel value `-1` reports "cannot read live value" / `cannot read <proc>`, the same text as an unreadable file. Failing closed is the right call. A distinct message, such as "live value outside the supported range", would tell the operator which case they hit. Wording only.
- **F1.7 Unmeasured: does perf fall back to user-only counting at paranoid 2?** V1 assumes `perf stat -e cycles,instructions` drops to `:u` counting by itself. As I recall, perf's `evsel__fallback` does this on EACCES when paranoid is above 1. I could not measure it without `sysctl -w`, which I was not allowed to run. V1 checks it on both boxes, so no spec change is needed.

## What I checked and chose not to raise

- The PASS row is reachable only at live 2 / conf 2. So "PASS prints the constant instead of live" is not a test-vacuity hole.
- The step row "live 4, conf 1" leaves next boot at 1. The doctor's `conf < 2` WARN reports that, so it is coherent.
- Exposure through docker containers: pid namespaces stop a container naming host pids. Not measured.
- The CLAUDE.md byte budget handling is fine.

No `Author response` table exists from an earlier round, so there are no accepted / not accepted lines.

Fix F1.1 and F1.3 before the plan: each is a one-line requirement change plus tests. Record F1.2 as a decision; the rest can land in the plan. The design has not moved since round 2, and this round found nothing against it, so another round is not worth running.

Recommend: stop
