# Claude Plugin Provisioning Implementation Plan

> **Status: DONE** — merged as dotfiles#290, 2026-09-20.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision Claude Code plugins from ai-config's `settings.json`, registering the
declared marketplaces first, so a fresh box ends with every enabled plugin installed and
every failure named.

**Architecture:** One manifest reader (`_claude_plugin_manifest`) turns `settings.json` into
tab-separated lines. `setup_claude_plugins` reconciles against the CLI's `--json` lists. A
git-status write guard wraps every span in which the CLI may write settings. Three callers
use it: `run_setup_user`, `_install_ubuntu_brew_packages` and `run_update`'s claude section,
which also moves after the ai-config pull. All four hardcoded plugin lists are deleted.

**Tech Stack:** bash 5, python3 (JSON parsing only), bats, the `claude` CLI (2.1.278).

**Spec:** `docs/superpowers/specs/2026-09-19-claude-plugin-provisioning-design.md` (approved).

## Global Constraints

- Settings path: `${_OVERRIDE_CLAUDE_SETTINGS:-${HOME}/.claude/settings.json}`, resolved in one helper.
- Source types: `github` → `repo` (`owner/repo`); `git` → `url`; anything else is `unsupported`.
- Install only `enabledPlugins` values that are exactly `true`; update every declared id installed at user scope.
- Membership is exact id equality from `claude plugins list --json` (`scope == "user"`) and `claude plugins marketplace list --json` (`name`).
- Return contract: 0 all present; 2 partial (named on stderr); 1 only for an unreadable, unparsable or non-object settings file, or absent python3. A failed list call is 2.
- Every `claude` invocation inside a `while read` loop redirects stdin from `/dev/null`.
- git is `${_CLAUDE_GUARD_GIT:-git}`, always under `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`.
- The guard never changes a return code and never aborts.
- `make test` exceeds the Bash tool's 600 s cap in this repo, so task gates are scoped `bats` runs plus `make lint`; the orchestrator runs `make test` once after Task 8.
- New bats files get `#!/usr/bin/env bats` and use `load_setup_env` + `load_mocks`.

## Verification (session level)

1. `make test` exit 0 after Task 8 (full suite, run by the orchestrator in the background).
2. Real-CLI acceptance, spec section "Real-CLI acceptance", cases 1-4, run on `claude` (Linux)
   and on `studio` (macOS, over ssh), from a scratch `HOME` whose `.claude/settings.json` is a
   symlink to a copy of the real file, cwd outside any repo, `claude` wrapped by an
   argv-logging `PATH` shim. Expected: case 1 rc 0, 7 marketplaces, 11 plugins, 0 of the 4
   disabled installed, copy byte-identical, link intact; case 2 zero `marketplace add` and
   zero `plugins install` lines in the shim log; case 3 rc 2 naming the bogus marketplace;
   case 4 the guard warns and `git diff` is whitespace-only. Results go in the PR body.
3. Edge cases covered by the unit tests: unsupported source, zero enabled plugins, list-call
   failure (the login gate), re-list failure, superstring and project-scope ids, settings
   edited mid-run, symlink replaced by a regular file.

---

### Task 1: claude mock JSON modes, default settings fixture

```yaml-task
id: 1
description: Teach tests/mocks/claude the --json list calls and failure/edit modes, and add a default settings fixture exported by load_mocks
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/mocks_claude.bats
    exit_code: 0
  - cmd: bats -f 'claude' tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [tests/mocks/claude, tests/fixtures/claude-settings.json, tests/helpers/common.bash, tests/setup_env/mocks_claude.bats]
depends_on: []
```

**Interfaces — Produces:** mock env vars `MOCK_CLAUDE_PLUGINS_LIST_JSON` (default `[]`),
`MOCK_CLAUDE_MARKETPLACE_LIST_JSON` (default `[]`), `MOCK_CLAUDE_FAIL_ARGS` (substring of
argv → exit 1), `MOCK_CLAUDE_FAIL_ON_CALL=<n>` (fail only the nth exact `plugins list --json`,
counter file `${BATS_TEST_TMPDIR}/mock_claude_list_calls`), `MOCK_CLAUDE_EDIT_SETTINGS=<verb>`
(on `plugins <verb>`, append `\n` to `$_OVERRIDE_CLAUDE_SETTINGS`). Fixture
`tests/fixtures/claude-settings.json`; `load_mocks` exports
`_OVERRIDE_CLAUDE_SETTINGS="${REPO_ROOT}/tests/fixtures/claude-settings.json"`.

- [ ] Write `tests/setup_env/mocks_claude.bats` with one test per mode: the two `--json`
      defaults print `[]`; a set value is echoed; `plugins list` (no `--json`) still prints
      `MOCK_CLAUDE_PLUGINS_LIST_OUTPUT`; `MOCK_CLAUDE_FAIL_ARGS="marketplace add"` fails that call
      (rc 1) and not `plugins install`; `MOCK_CLAUDE_FAIL_ON_CALL=2` passes call 1, fails call 2,
      and `plugins marketplace list --json` does not advance the counter; `MOCK_CLAUDE_EDIT_SETTINGS=install`
      grows a temp file by one byte on `plugins install -s user x@y` and not on `plugins update`;
      every call is logged to `MOCK_CALLS_FILE`. Run it: RED (modes do not exist).
- [ ] Create the fixture:

```json
{
  "extraKnownMarketplaces": {
    "claude-plugins-official": {
      "source": {
        "source": "github",
        "repo": "anthropics/claude-plugins-official"
      }
    },
    "caveman": {
      "source": {
        "source": "git",
        "url": "https://github.com/juliusbrussee/caveman.git"
      }
    }
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "caveman@caveman": true,
    "frontend-design@claude-plugins-official": false
  }
}
```

- [ ] Replace `tests/mocks/claude` with:

```bash
#!/usr/bin/env bash
printf "claude %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ -n "${MOCK_CLAUDE_FAIL_ARGS:-}" && "$*" == *"${MOCK_CLAUDE_FAIL_ARGS}"* ]]; then
  exit 1
fi
case "$*" in
  "plugins list --json")
    if [[ -n "${MOCK_CLAUDE_FAIL_ON_CALL:-}" ]]; then
      _cf="${BATS_TEST_TMPDIR:-/tmp}/mock_claude_list_calls"
      _n=$(( $(cat "${_cf}" 2>/dev/null || printf 0) + 1 ))
      printf '%s\n' "${_n}" > "${_cf}"
      [[ "${_n}" -eq "${MOCK_CLAUDE_FAIL_ON_CALL}" ]] && exit 1
    fi
    printf '%s\n' "${MOCK_CLAUDE_PLUGINS_LIST_JSON:-[]}"
    exit 0 ;;
  "plugins marketplace list --json")
    printf '%s\n' "${MOCK_CLAUDE_MARKETPLACE_LIST_JSON:-[]}"
    exit 0 ;;
esac
case "$1" in
  plugins|plugin)
    if [[ -n "${MOCK_CLAUDE_EDIT_SETTINGS:-}" && "$2" == "${MOCK_CLAUDE_EDIT_SETTINGS}" \
          && -n "${_OVERRIDE_CLAUDE_SETTINGS:-}" ]]; then
      printf '\n' >> "${_OVERRIDE_CLAUDE_SETTINGS}"
    fi
    [[ "$2" == "list" ]] && printf "%s\n" "${MOCK_CLAUDE_PLUGINS_LIST_OUTPUT:-}"
    exit 0 ;;
  -p)
    [[ "${MOCK_CLAUDE_EXIT:-0}" -ne 0 ]] && exit "${MOCK_CLAUDE_EXIT}"
    _default="## New Features
- Mock feature added"
    printf "%s\n" "${MOCK_CLAUDE_STDOUT:-${_default}}" ;;
  *)
    exit "${MOCK_CLAUDE_EXIT:-0}" ;;
esac
```

- [ ] In `load_mocks` (`tests/helpers/common.bash`), next to the `_CARGO_BIN` export, add the
      `_OVERRIDE_CLAUDE_SETTINGS` export with a one-line comment: every `run_update`/`run_setup_user`
      test runs under a redirected `HOME` with no settings file.
- [ ] Run the gates; commit (`test(mocks): claude --json modes and settings fixture`).

### Task 2: `_claude_plugin_manifest` and the CLI list readers

```yaml-task
id: 2
description: Add the settings path helper, the manifest reader and the two --json list readers
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/claude_plugins.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/claude_plugins.bats]
depends_on: [1]
```

**Interfaces — Produces** (all in `lib/workflows.sh`, above `setup_claude_plugins`):
`_claude_settings_path` (prints the path); `_claude_plugin_manifest` (lines
`marketplace\t<name>\t<source>`, `unsupported\t<name>\t<type>`, `plugin\t<id>\t<true|false>`;
rc 1 and no stdout on missing/unreadable/non-JSON/non-object file or absent python3);
`_claude_registered_marketplaces` (one name per line; rc 1 if the CLI call or the parse
fails, CLI output echoed to stderr); `_claude_installed_user_ids` (one id per line, `scope ==
"user"` only; same failure contract).

- [ ] Create `tests/setup_env/claude_plugins.bats`. `setup()`: `load_setup_env`, `load_mocks`,
      `MOCK_CALLS_FILE` in `BATS_TEST_TMPDIR`, `HOME` redirected, `SETTINGS` = a copy of the
      fixture in `BATS_TEST_TMPDIR`, `export _OVERRIDE_CLAUDE_SETTINGS="${SETTINGS}"`.
      Tests: github source emits `marketplace\tclaude-plugins-official\tanthropics/claude-plugins-official`;
      git source emits the URL; a `{"source":"url"}` entry emits `unsupported\t<name>\turl`; an
      entry missing `repo` emits `unsupported`; plugins emit `true`/`false` (a string `"true"`
      emits `false`); missing file, `not json`, and `[]` each return 1 with empty stdout; a file
      with neither key returns 0 with no marketplace or plugin lines;
      `_claude_installed_user_ids` with
      `MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"a@m","scope":"user"},{"id":"b@m","scope":"project"}]'`
      prints only `a@m`; both readers return 1 when `MOCK_CLAUDE_FAIL_ARGS` matches their call,
      and when the mock prints `not json`. RED first.
- [ ] Implement:

```bash
_claude_settings_path() {
  printf '%s' "${_OVERRIDE_CLAUDE_SETTINGS:-${HOME}/.claude/settings.json}"
}

_claude_plugin_manifest() {
  local _file
  _file="$(_claude_settings_path)"
  [[ -r "${_file}" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "${_file}" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError):
    sys.exit(1)
if not isinstance(data, dict):
    sys.exit(1)
out = []
markets = data.get("extraKnownMarketplaces") or {}
for name, entry in (markets.items() if isinstance(markets, dict) else []):
    src = entry.get("source") if isinstance(entry, dict) else None
    kind = src.get("source") if isinstance(src, dict) else None
    key = {"github": "repo", "git": "url"}.get(kind)
    ref = src.get(key) if key else None
    if isinstance(ref, str) and ref:
        out.append(f"marketplace\t{name}\t{ref}")
    else:
        out.append(f"unsupported\t{name}\t{kind or 'missing'}")
plugins = data.get("enabledPlugins") or {}
for pid, val in (plugins.items() if isinstance(plugins, dict) else []):
    out.append(f"plugin\t{pid}\t{'true' if val is True else 'false'}")
if out:
    print("\n".join(out))
PY
}

_claude_registered_marketplaces() {
  local _json
  _json="$(claude plugins marketplace list --json < /dev/null 2>&1)" \
    || { printf '%s\n' "${_json}" >&2; return 1; }
  printf '%s' "${_json}" | python3 -c 'import json,sys
print("\n".join(m["name"] for m in json.load(sys.stdin)))' 2>/dev/null
}

_claude_installed_user_ids() {
  local _json
  _json="$(claude plugins list --json < /dev/null 2>&1)" \
    || { printf '%s\n' "${_json}" >&2; return 1; }
  printf '%s' "${_json}" | python3 -c 'import json,sys
print("\n".join(p["id"] for p in json.load(sys.stdin) if p.get("scope") == "user"))' 2>/dev/null
}
```

- [ ] Run the gates; commit (`feat(workflows): read plugin manifest from settings.json`).

### Task 3: the settings write guard

```yaml-task
id: 3
description: Add _claude_settings_git_state and _claude_settings_guard_check, tested against a real temporary git repo
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/claude_plugins.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/claude_plugins.bats]
depends_on: [2]
```

**Interfaces — Produces:** `_claude_settings_git_state` prints one line
`<state>\t<repo or ->\t<path>` where state is `clean|dirty|untracked|unknown` (`path` is
relative to `repo` for clean/dirty, absolute otherwise); always rc 0.
`_claude_settings_guard_check <before> <after>` prints at most one line; rc 2 when it is a
warning, rc 0 otherwise (info or nothing).

- [ ] Tests (add to `claude_plugins.bats`; a helper builds `${BATS_TEST_TMPDIR}/repo` with
      `git init -q`, commits `settings.json`, and points `_OVERRIDE_CLAUDE_SETTINGS` at a symlink
      `${HOME}/.claude/settings.json` → that file; `_CLAUDE_GUARD_GIT` = the real git, resolved
      with the `tests/mocks` directories stripped from `PATH`): clean state reads `clean`; an
      appended byte reads `dirty`; a file outside any repo reads `untracked`; the symlink
      replaced by a regular file reads `untracked`; `GIT_DIR` exported to a decoy repo still
      reads the real state (env strip). Check: clean→clean prints nothing, rc 0;
      clean→dirty prints `changed during plugin provisioning — review: git -C <repo> diff --
settings.json`, rc 2; clean→untracked prints `no longer resolves into a tracked file`,
      rc 2; dirty→dirty prints `was already modified; not checked`, rc 0; untracked→untracked
      prints `not checked`, rc 0. RED first.
- [ ] Implement:

```bash
_claude_settings_git_state() {
  local _path _real _top _rel _out _git="${_CLAUDE_GUARD_GIT:-git}"
  local -a _env=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE)
  _path="$(_claude_settings_path)"
  if ! _real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${_path}" 2>/dev/null)"; then
    printf 'unknown\t-\t%s\n' "${_path}"; return 0
  fi
  _top="$("${_env[@]}" "${_git}" -C "$(dirname "${_real}")" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -z ${_top} ]]; then printf 'untracked\t-\t%s\n' "${_real}"; return 0; fi
  _rel="${_real#"${_top}"/}"
  if ! "${_env[@]}" "${_git}" -C "${_top}" ls-files --error-unmatch -- "${_rel}" >/dev/null 2>&1; then
    printf 'untracked\t%s\t%s\n' "${_top}" "${_real}"; return 0
  fi
  if ! _out="$("${_env[@]}" "${_git}" -C "${_top}" status --porcelain -- "${_rel}" 2>/dev/null)"; then
    printf 'unknown\t%s\t%s\n' "${_top}" "${_rel}"; return 0
  fi
  if [[ -z ${_out} ]]; then printf 'clean\t%s\t%s\n' "${_top}" "${_rel}"
  else printf 'dirty\t%s\t%s\n' "${_top}" "${_rel}"; fi
}

_claude_settings_guard_check() {
  local _bs _br _bp _as _ar _ap
  IFS=$'\t' read -r _bs _br _bp <<<"$1"
  IFS=$'\t' read -r _as _ar _ap <<<"$2"
  case "${_bs}" in
    clean) ;;
    dirty) printf '%s/%s was already modified; not checked\n' "${_br}" "${_bp}"; return 0 ;;
    *) printf '%s is %s; not checked\n' "${_bp}" "${_bs}"; return 0 ;;
  esac
  case "${_as}" in
    clean) return 0 ;;
    dirty) printf '%s/%s changed during plugin provisioning — review: git -C %s diff -- %s\n' \
             "${_ar}" "${_ap}" "${_ar}" "${_ap}"; return 2 ;;
    *) printf '%s/%s no longer resolves into a tracked file (%s)\n' "${_br}" "${_bp}" "${_as}"
       return 2 ;;
  esac
}
```

- [ ] Run the gates; commit (`feat(workflows): git-status guard on settings.json`).

### Task 4: rewrite `setup_claude_plugins` as a reconcile

```yaml-task
id: 4
description: Reconcile declared marketplaces and enabled plugins against the CLI lists with the tri-state contract; update the old setup_claude_plugins tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/claude_plugins.bats
    exit_code: 0
  - cmd: bats -f 'setup_claude_plugins' tests/setup_env/workflows.bats tests/setup_env/install_guards.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/claude_plugins.bats, tests/setup_env/workflows.bats, tests/setup_env/install_guards.bats]
depends_on: [3]
```

**Interfaces — Consumes:** Task 2 readers. **Produces:** `setup_claude_plugins` (same name),
rc 0/1/2 per Global Constraints.

- [ ] Tests (claude_plugins.bats), all with the fixture copy: unregistered github
      marketplace → `claude plugins marketplace add anthropics/claude-plugins-official` in
      `MOCK_CALLS_FILE`; git one → the URL; registered (`MOCK_CLAUDE_MARKETPLACE_LIST_JSON`
      names both) → no `marketplace add` line; `superpowers` missing → `plugins install -s user
superpowers@claude-plugins-official`; `frontend-design` (false) in no `install` line;
      installed `superpowers@claude-plugins-official-fork` does not count; `superpowers`
      installed at `project` scope does not count; `MOCK_CLAUDE_FAIL_ARGS="marketplace add
https"` → rc 2, output names `caveman`, and `superpowers` is still installed; an
      unsupported source → rc 2 naming name and type; a file with only false plugins → rc 2
      `no enabled plugins declared`; missing / unparsable / `[]` settings → rc 1 and
      `MOCK_CALLS_FILE` has no `claude plugins` line; `MOCK_CLAUDE_FAIL_ARGS="plugins list
--json"` → rc 2, zero `install`/`add` lines; everything registered and installed → rc 0,
      zero `add`/`install` lines, and `_claude_plugin_manifest` printed at least one
      `plugin\t...\ttrue` line. RED first.
- [ ] Replace the body of `setup_claude_plugins` (keep the `claude`-absent guard) with the
      reconcile: read manifest (rc 1 → `log_error` naming `$(_claude_settings_path)`, return 1);
      read both lists (either fails → `log_warn` "claude plugin state unreadable (list call
      failed; logged in?)", return 2); loop `marketplace` lines, `add` those not in the
      registered set with `grep -qxF`; record each `unsupported` line; loop `plugin` lines with
      value `true`, count them, `install -s user` those not in the installed set; zero `true` →
      record `no enabled plugins declared in <path>`; `log_warn` each recorded failure and return
      2 if any, else 0. Every `claude` call inside a loop gets `< /dev/null`. Keep the existing
      `-s user` explanation comment, shortened to two lines.
- [ ] Update the three `setup_claude_plugins` tests in `workflows.bats` (lines ~298-316) and
      `install_guards.bats` (~1113-1152) to the JSON mock: "installs when not listed" sets
      `MOCK_CLAUDE_PLUGINS_LIST_JSON='[]'`; "skips when listed" sets it to
      `[{"id":"superpowers@claude-plugins-official","scope":"user"}]` (keep the flag-agnostic
      `! grep` comment); the "already installed" output assertion stays. The `claude`-absent test
      is unchanged.
- [ ] Run the gates; commit (`fix(workflows): register marketplaces before plugin install`).

### Task 5: guarded provision and `run_setup_user`

```yaml-task
id: 5
description: Add provision_claude_plugins (guard around setup_claude_plugins) and wire run_setup_user to rc 1 abort / rc 2 warn
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/claude_plugins.bats
    exit_code: 0
  - cmd: bats -f 'setup_claude_plugins|run_setup_user' tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/claude_plugins.bats, tests/setup_env/workflows.bats]
depends_on: [4]
```

**Interfaces — Produces:** `provision_claude_plugins` (records guard state, runs
`setup_claude_plugins`, reports the guard via `log_warn` on rc 2 / `log_info` otherwise,
returns `setup_claude_plugins`' rc unchanged).

- [ ] Tests: with the Task 3 repo helper and `MOCK_CLAUDE_EDIT_SETTINGS=install`,
      `provision_claude_plugins` prints `changed during plugin provisioning` and returns the
      same rc as without the edit (0); with the settings already dirty it prints `was already
modified; not checked`; in `workflows.bats`, `run_setup_user` with
      `provision_claude_plugins() { return 2; }` completes (status 0) and prints `partial`, and
      with `return 1` returns non-zero. The two existing `run_setup_user` tests stay green
      unchanged (they stub `setup_claude_plugins`). RED first.
- [ ] Implement `provision_claude_plugins` after `setup_claude_plugins`:

```bash
provision_claude_plugins() {
  local _before _rc=0 _msg
  _before="$(_claude_settings_git_state)"
  setup_claude_plugins || _rc=$?
  if _msg="$(_claude_settings_guard_check "${_before}" "$(_claude_settings_git_state)")"; then
    [[ -n ${_msg} ]] && log_info "${_msg}"
  else
    log_warn "${_msg}"
  fi
  return "${_rc}"
}
```

- [ ] In `run_setup_user`, replace `setup_claude_plugins || return 1` with:

```bash
  local _plugins_rc=0
  provision_claude_plugins || _plugins_rc=$?
  if [[ ${_plugins_rc} -eq 1 ]]; then
    return 1
  elif [[ ${_plugins_rc} -ne 0 ]]; then
    log_warn "Claude plugin provisioning was partial — see the warnings above"
  fi
```

- [ ] Run the gates; commit (`feat(workflows): guard settings.json during plugin setup`).

### Task 6: `run_update` — pull ai-config first, reconcile, update from the manifest

```yaml-task
id: 6
description: Move the ai-config section ahead of claude, rewrite the claude section around reconcile/re-list/update/guard, reorder the summary array
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/update_claude.bats
    exit_code: 0
  - cmd: bats -f 'claude|_UPDATE_SECTION_ORDER' tests/setup_env/workflows.bats tests/setup_env/unit.bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, lib/update_summary.sh, tests/setup_env/update_claude.bats, tests/setup_env/workflows.bats, tests/setup_env/unit.bats, tests/setup_env/update_summary.bats]
depends_on: [5]
```

**Interfaces — Consumes:** Tasks 2-4.

- [ ] New `tests/setup_env/update_claude.bats` (setup like `update_plugin_node.bats`:
      `MACOS=1`, `TMPDIR`, `UPDATE_LOG_PATH`, fixture copy as `_OVERRIDE_CLAUDE_SETTINGS`). Cases:
      full run (no flags) with `setup_ai_config() { printf 'AI_PULL\n' >> "$MOCK_CALLS_FILE"; }`
      → the `AI_PULL` line precedes the first `claude plugins marketplace list --json` line;
      `UPDATE_CLAUDE=1` with `MOCK_CLAUDE_PLUGINS_LIST_JSON` naming `superpowers` and
      `frontend-design` at user scope → exactly two `claude plugins update` lines (count with
      `grep -c`), `frontend-design` among them; `MOCK_CLAUDE_FAIL_ARGS="marketplace add https"`
      → `status_claude` is `WARN` and the result names `partial`; `MOCK_CLAUDE_FAIL_ARGS="plugins
update superpowers"` → `FAIL`; settings missing (`_OVERRIDE_CLAUDE_SETTINGS` → nonexistent)
      → `FAIL`, zero `plugins update` lines; `MOCK_CLAUDE_FAIL_ON_CALL=2` → `FAIL` naming
      `installed-plugin list failed`, zero `plugins update` lines; with the Task 3 repo helper
      and `MOCK_CLAUDE_EDIT_SETTINGS=update` → `WARN` naming `changed during plugin
provisioning`; same edit plus `MOCK_CLAUDE_FAIL_ARGS="plugins update caveman"` →
      `status_claude` stays `FAIL` and `result_claude` contains the guard line. RED first.
- [ ] Move the `ai-config` record/`setup_ai_config` lines out of the "git-based tools + misc"
      block into their own `if [[ ${_run_all} -eq 1 ]]; then … fi` placed immediately before the
      claude section, with a two-line comment: the plugin reconcile must read the settings.json
      this run pulled.
- [ ] Rewrite the claude section body between `printf "Updating Claude plugins\\n"` and the
      skill-scan comment: record `_g_before`; `setup_claude_plugins 2>&1 | tee -a
"${_DOTFILES_RUN_TMPDIR}/err_claude"` and take `PIPESTATUS[0]`; rc 1 → fail with
      `plugin settings unreadable: <path>`; otherwise rc 2 adds `plugin provisioning partial —
see detail`, then `_manifest="$(_claude_plugin_manifest)"`,
      `_installed="$(_claude_installed_user_ids)"` (failure → fail with `installed-plugin list
failed — updates skipped`), then for each `plugin` line whose id is in `_installed`, run
      `claude plugins update "${_id}" < /dev/null 2>&1 | tee -a …err_claude` and collect
      `${_id%%@*}` on non-zero into `_claude_failed` (→ fail with `N plugin(s) failed (…)`).
      Then the guard: warning (rc 2) is appended to the message list, info is printed. Join
      messages with `printf '%s; '` and strip the trailing `; ` (never `IFS='; '`). If failed:
      write the joined line to `fail_result_claude`, then `_update_record_end "claude" 1`, and
      never call `_update_warn`. Else `_update_record_end "claude" 0`, then `_update_warn "claude"
"<joined>"` only if messages exist.
- [ ] In `lib/update_summary.sh`, move `ai-config` to sit immediately before `claude` in
      `_UPDATE_SECTION_ORDER`; add an `update_summary.bats` test "`_UPDATE_SECTION_ORDER` puts
      ai-config immediately before claude" in the style of the existing pyenv-shims one.
- [ ] Update `unit.bats` "run_update --claude-only" and `workflows.bats` "run_update calls
      claude plugins update when UPDATE_CLAUDE is set" to set `MOCK_CLAUDE_PLUGINS_LIST_JSON` to
      `superpowers` at user scope (the update set now comes from that list).
- [ ] Run the gates; commit (`feat(update): reconcile plugins after ai-config pull`).

### Task 7: provision plugins where Linux installs claude-code

```yaml-task
id: 7
description: Replace the hardcoded 4-plugin loop in _install_ubuntu_brew_packages with provision_claude_plugins
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats -f 'claude|brew_packages' tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [5]
```

- [ ] Replace the test "installs claude plugins at USER scope with a marketplace" with: under
      `HAS_DEVTOOLS=1`, `MOCK_CALLS_FILE` contains `claude plugins marketplace add
anthropics/claude-plugins-official` before `claude plugins install -s user
superpowers@claude-plugins-official`, and no `code-simplifier` line; and a new test:
      `MOCK_CLAUDE_FAIL_ARGS="plugins install"` → `_install_ubuntu_brew_packages` returns 2 and
      its output names `claude-plugins`. RED first.
- [ ] In `lib/linux_ubuntu.sh`, replace the `if command -v claude … fi` block (the comment and
      the `for _p in superpowers@… context7@…` loop) with:

```bash
    if command -v claude &> /dev/null; then
      provision_claude_plugins < /dev/null || _failed+=(claude-plugins)
    fi
```

- [ ] Run the gates; commit (`fix(ubuntu): provision plugins from settings.json`).

### Task 8: regression guard against a reintroduced hardcoded list

```yaml-task
id: 8
description: Test that no lib file or setup_env.sh carries a literal plugin id for a known marketplace
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats -f 'hardcoded' tests/setup_env/claude_plugins.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [tests/setup_env/claude_plugins.bats]
depends_on: [6, 7]
```

- [ ] Add `@test "no hardcoded plugin@marketplace ids remain in lib or setup_env.sh"`: `grep
-rnE '[A-Za-z0-9._-]+@(claude-plugins-official|claude-code-warp|context-mode|caveman|firecrawl|claude-ansible-skills|antonbabenko)\b'
"${REPO_ROOT}/lib" "${REPO_ROOT}/setup_env.sh"` must find nothing. Comment: the name list
      is a denylist of today's marketplaces, deliberately not derived from settings.json, so the
      test does not depend on a file outside the repo. Before Tasks 4/6/7 this pattern matched
      30 lines (measured 2026-09-19: 14 + 14 in `lib/workflows.sh`, 2 in
      `lib/linux_ubuntu.sh`); confirm it now matches 0, and that re-adding one id to `lib/workflows.sh` makes
      the test fail (revert after).
- [ ] Run the gates; commit (`test(workflows): forbid hardcoded plugin ids`).
- [ ] **Orchestrator:** run `make test < /dev/null` in the background and record the result.

### Task 9: docs, ADR, backlog

```yaml-task
id: 9
description: Document the settings.json source of truth, the seams and the guard; add ADR-0034; update the backlog (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_OVERRIDE_CLAUDE_SETTINGS" CLAUDE.md'
    exit_code: 0
  - cmd: 'test -f docs/adr/0034-claude-plugins-from-ai-config-settings.md'
    exit_code: 0
  - cmd: 'grep -q "0034" docs/adr/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0034-claude-plugins-from-ai-config-settings.md, docs/adr/README.md, docs/superpowers/README.md]
depends_on: [8]
```

- [ ] `CLAUDE.md`: `setup_user` bullet (plugins come from ai-config's `settings.json`);
      `update` bullet (ai-config pulled before the claude section; `--claude-only` reconciles the
      current checkout); Key Conventions `claude plugin install -s user` bullet (one call site now,
      `setup_claude_plugins`); a Test Seams paragraph for `_OVERRIDE_CLAUDE_SETTINGS` (and the
      `load_mocks` default fixture), `_CLAUDE_GUARD_GIT` (real git past `tests/mocks/git`) and the
      new mock variables, including why every `claude` call in a loop reads `/dev/null`.
- [ ] ADR-0034 (Nygard, like 0033): ai-config's `settings.json` is the plugin source of truth;
      a broken or unsupported entry WARNs every machine's next update until ai-config is fixed;
      the guard reports a dirty tracked file rather than preventing writes. Add the row to
      `docs/adr/README.md`.
- [ ] `docs/superpowers/README.md`: delete the #84 and #101 backlog rows; add a row: the update
      ledger entry records dotfiles' `git_sha` but not ai-config's HEAD, although plugin
      provisioning now depends on it; mark this plan's index row In Progress.
- [ ] Run the gates; commit (`docs: plugin provisioning from ai-config settings`).

**Post-merge (Phase 3 docs step, ai-config repo):** backlog row for the prettier hook making
`settings.json` non-canonical; knowledge-doc rows for the new seams.
