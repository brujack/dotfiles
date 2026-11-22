Tools: Read, Bash, SubagentHandback

The spec gets the parts that matter right, so keep them as they are. Choosing `quota` over `api-status` is measured, not assumed. The identity rule matches by name and needs no per-repo map; it catches a cross-hook swap and a shim sitting in a tracked slot. The shim check runs the absolute `INSTALL_PYTHON` instead of trusting `PATH`. Keeping the resolver in two copies with a drift test is correct, because a shared `lib/` file sourced from the tree under scan fails open. The zero-repos FAIL stops a wrong `PERSONAL_GITREPOS` from reading as healthy. Two rounds have settled the design. What is left is one wrong exit-code mapping, one test gap, and some wording.

## F1.1 `quota` rc 1 means "could not reach GitGuardian", but R18 grades it as a rejected key

**Defect.** R18 maps every non-zero rc other than 3 and 124 to `doctor_fail "... API key rejected or check failed (rc <rc>) — remedy: ggshield auth login"`. ggshield 1.56.1 does not catch connection errors in `quota`. They escape as a Python traceback with rc 1, so this is a different cause from a rejected key, which gives 128.

**Concrete failure.** On a host that is offline, behind a dead proxy, or whose DNS fails, doctor prints FAIL and tells the operator to run `ggshield auth login`. That command fails for the same network reason. This is the "ignore this arm" outcome the Ergonomics lens warned about, on the laptop or Windows box in particular. The spec's test list has an rc 1 case but never says what rc 1 means.

**Measurement** (Linux 7.0.0-43, `/home/linuxbrew/.linuxbrew/bin/ggshield` 1.56.1, throwaway HOME, `GITGUARDIAN_DONT_LOAD_ENV=1`, `GITGUARDIAN_API_KEY=fake`):
- `GITGUARDIAN_API_URL=https://127.0.0.1:9 ggshield quota` gave `rc=1`, `requests.exceptions.ConnectionError: ... [Errno 111] Connection refused`.
- `GITGUARDIAN_API_URL=https://nonexistent.invalid ggshield quota` gave `rc=1`, `NameResolutionError ... Name or service not known`.
- An `http://` URL gave rc 2 (`Invalid scheme for API URL`).
- Source: `cmd/quota.py` raises `UnexpectedError` (128) only for a `Detail` response, meaning any HTTP error status, 5xx included. `core/errors.py` defines 4 (`GITGUARDIAN_SERVER_UNAVAILABLE`), but `quota` never raises it.

**Fix.**
- Map rc 1 and rc 4 to `doctor_warn "<path>: could not reach GitGuardian (rc <rc>)"` with no auth remedy. This matches the treatment of rc 124 ("not verified" is not "safe", and not "broken" either).
- Keep 128 and other codes as FAIL.
- Change R18 and the ggshield test list: the rc 1 case expects WARN.
- Add a V-item: run doctor on `claude` with `HTTPS_PROXY=http://127.0.0.1:9` and expect WARN.

## F1.2 R20 does not keep the "not found" test away from the real ggshield

**Defect.** Resolution order is `GGSHIELD_BIN`, then `command -v ggshield`, then the fallbacks. R20 only requires each test to set `GGSHIELD_BIN` or `GGSHIELD_FALLBACK_PATHS`. A test that empties `GGSHIELD_BIN` and points the fallbacks at a missing path still reaches `command -v`, so it finds the real binary.

**Concrete failure.** On `claude`, the Studio and `workstation`, the "not found" case runs the real `ggshield quota`. Under the suite's isolated HOME that gives "no API key" instead of "not installed", which breaks R20's no-real-binary promise. CI installs no ggshield, so the same test is green there. The result depends on the machine.

**Measurement.**
- `command -v ggshield` in this session prints `/home/linuxbrew/.linuxbrew/bin/ggshield`.
- `grep -c ggshield .github/workflows/ci.yml` prints 0.
- `tests/scripts/pre_commit_hook.bats:58-61` already solves this for the hook with `MINIMAL_PATH="/usr/bin:/bin"`.

**Fix.**
- R20: every test that does not set `GGSHIELD_BIN` to the stub also runs under a scoped minimal `PATH`, the same way `pre_commit_hook.bats` does.
- Add one test that puts the stub on a scoped `PATH` to cover the `command -v` branch. The spec says doctor's own tests cover the resolution order, but no listed case reaches that branch.

## Smaller items

- **F1.3 Premise is false, design unchanged.** The spec says "`PYENV_VERSION` is not set by any zsh startup file" on `claude`. In fact `.config/.zshrc.d/7_final.zsh:63` runs `pyenv activate ansible` when `WORKSTATION` is set, and `config/profiles.sh:73` maps `[claude]="WORKSTATION"`. This session shows `PYENV_VERSION=[ansible]`. So every commit started from an interactive zsh can run state-ledger's shim, and only `env -i`-style callers fail. The FAIL verdict still stands, because a `/Users/...` interpreter on Linux is wrong. Correct the premise and the rationale for the rejected `generated-fallback` alternative, and say the live risk is limited to non-interactive callers.
- **F1.4 Message format.** `doctor_fail` and `doctor_warn` print `"%s: %s\n"` with `${2:-}` (`lib/helpers.sh:97-106`). Every existing caller passes two arguments. The spec's one-argument form renders a trailing `": "`, which V1's exact line would not match. Write the messages as `doctor_fail "<name>" "<message>"`.
- **F1.5 The import probe depends on doctor's environment.** The spec says the probe's answer does not depend on doctor's environment, but `python -c 'import pre_commit'` picks up the working directory and `PYTHONPATH`. Measured with Python 3.14.4: a `pre_commit.py` in the working directory gave rc 0, `PYTHONPATH=<dir with pre_commit/>` gave rc 0, and the same with `-I` gave rc 1. Use `"$INSTALL_PYTHON" -I -c 'import pre_commit'` in R9.
- **F1.6 Global `core.hooksPath` (unmeasured).** `_git_hooks_dir` uses `git rev-parse --git-path hooks`, which as I recall follows `core.hooksPath`. If so, a global pin makes this arm report nine repos as missing, foreign or stale with an `install-hooks` remedy, on top of `_doctor_check_hooks_path`'s FAIL for the real cause. I did not measure it: the branch guard refused the fixture. To check, set a throwaway `GIT_CONFIG_GLOBAL` with a hooksPath pin and run `git -C <repo> rev-parse --git-path hooks`. If confirmed, skip the arm with one line when the hooks-path check failed.
- **F1.7 Wrong cause when the repo list is empty.** If `HOOK_EXPECTED_REPOS` is empty (`config/hook_repos.sh` absent leads to the `()` fallback at `lib/git_hooks.sh:12`), R3's "check GITREPOS" names the wrong cause. Give it a separate message.
- **F1.8 ggshield key source (noted, not measured on the operator's setup).** `quota` reads the key from doctor's process: `GITGUARDIAN_API_KEY`, or a `.env` in the working directory or git root loaded with `override=True` (`core/env_utils.py:34-68`). The hook runs in each repo's root, in the committing process's environment. That is the same "doctor's environment predicts the hook's" gap that round 2 closed for pyenv. At minimum, say in the PASS line when the key came from `GITGUARDIAN_API_KEY`.

No previous `Author response` table, so there are no accepted / not accepted lines.

Before the plan: fix F1.1 (it changes R18's mapping) and F1.2 (it changes R20). F1.3 and F1.4 are text edits to fold in at the same time. Nothing here changes the hook-identity design. Another round would mostly find wording, so letting the first red tests find the rest is cheaper.

Spec: /tmp/claude-1000/-home-bruce-git-repos-personal-dotfiles/4281237e-abb2-4d7b-b999-2151f6c394a5/scratchpad/external-review/2026-11-22-doctor-hook-and-ggshield-checks-design/round1/repo/docs/superpowers/specs/2026-11-22-doctor-hook-and-ggshield-checks-design.md

Recommend: stop
