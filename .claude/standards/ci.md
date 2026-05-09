## GitHub Actions / CI

- All jobs must run on Node.js 24
- Use `actions/checkout@v5` (natively runs on Node.js 24; v4 used Node.js 20 and is deprecated)
- Set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` as a fallback for third-party actions
- Do not add `actions/setup-node` to Rust or Python jobs that don't need it at the user-code level
- Every Rust build job must upload its release binary as an artifact using `actions/upload-artifact@v5` with 7-day retention
- Build jobs must depend on their test job (`needs: [test]`) — a build will not run if tests fail
- CI badge URLs in `README.md` must use `?event=pull_request` (e.g. `badge.svg?event=pull_request`) — workflows trigger on `pull_request` only so they never run on master directly; `?branch=master` and bare `badge.svg` both default to master runs and always show "no status"

### Personal Repos (`~/git-repos/personal/*`)

Every personal repo CI pipeline must have:

1. **Auto-merge** — an `auto-merge` job that merges the PR when all required jobs pass. Use `gh pr merge --squash --auto` triggered on `pull_request` events. Required jobs must be listed in `needs:`.
2. **Secrets scanning** — a `secret-scan` job running `gitleaks` against recent commits. Must have a `.gitleaks.toml` allowlist at the repo root. This job is advisory (non-blocking) but must be present.
3. **Snyk security scan** — only add a `snyk-scan` job to repos that contain languages Snyk Code supports (Python, JavaScript/TypeScript, Java, Go, Ruby, etc.). Do **not** add it to shell-script or config-only repos — `snyk code test` returns `SNYK-CODE-0006` (no supported files) and will always fail. When present, run `snyk code test` with `SNYK_TOKEN` from repository secrets. Never commit Snyk tokens to the repo.
4. **Pre-commit hook** — every repo must have a `scripts/pre-commit` file (committed to the repo, symlinked or copied to `.git/hooks/pre-commit`). The hook must:
   - Run `make lint` first — for single-Makefile repos call it directly; for multi-project repos (no root Makefile) iterate over sub-project dirs and run `make -C <dir> lint` for each dir that has staged changes
   - Run `ggshield secret scan pre-commit` after lint, guarded by `command -v ggshield` so it degrades gracefully if not installed
   - Use `set -e` so any lint failure aborts the commit

   Template for single-Makefile repos:

   ```bash
   #!/usr/bin/env bash
   set -e
   make lint
   if command -v ggshield &>/dev/null; then
       ggshield secret scan pre-commit
   fi
   ```

   Template for multi-project repos (adapt dir list to the repo):

   ```bash
   #!/usr/bin/env bash
   set -e
   for dir in proj1 proj1/proj1-rs proj2 proj2/proj2-rs; do
       if git diff --cached --name-only | grep -q "^${dir}/"; then
           printf "lint: %s\n" "${dir}"
           make -C "${dir}" lint
       fi
   done
   if command -v ggshield &>/dev/null; then
       ggshield secret scan pre-commit
   fi
   ```

5. **Pre-push hook (permanent)** — every repo must have a `scripts/pre-push` file that runs the test suite locally before the push reaches GitHub. Install alongside the pre-commit hook via `make install-hooks`. Never remove it — it is permanent, not a temporary workaround.

   **The installed hook is a copy, not a symlink.** After editing `scripts/pre-push`, always re-run `make install-hooks` — the installed `.git/hooks/pre-push` will not pick up changes automatically. Symptom of a stale hook: the full test suite runs on every push regardless of what files changed.

   Template for single-Makefile repos:

   ```bash
   #!/usr/bin/env bash
   # Pre-push hook: runs full test suite locally before push reaches GitHub.
   # Permanent: provides fast local feedback and conserves GitHub Actions minutes.
   # GitHub Actions is the final merge gate on PRs.
   set -e

   real_push=0
   while read -r local_ref local_sha remote_ref remote_sha; do
       [ "${local_sha}" != "0000000000000000000000000000000000000000" ] && real_push=1
   done
   [ "${real_push}" -eq 0 ] && exit 0

   printf "Running tests locally (pre-push)...\n"
   make -C "$(cd "$(git rev-parse --git-common-dir)/.." && pwd)" test
   ```

   Template for multi-project repos (detect changed sub-projects, adapt dir list):

   ```bash
   #!/usr/bin/env bash
   # Pre-push hook: runs tests for changed sub-projects before push reaches GitHub.
   # Permanent: provides fast local feedback and conserves GitHub Actions minutes.
   # GitHub Actions is the final merge gate on PRs.
   set -e

   REPO_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
   DIRS_TO_TEST=()

   while read -r local_ref local_sha remote_ref remote_sha; do
       [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && continue

       if [ "${remote_sha}" = "0000000000000000000000000000000000000000" ]; then
           base="$(git merge-base "${local_sha}" origin/master 2>/dev/null \
               || git rev-list --max-parents=0 "${local_sha}")"
           range="${base}..${local_sha}"
       else
           range="${remote_sha}..${local_sha}"
       fi

       for dir in proj1 proj1/proj1-rs proj2 proj2/proj2-rs; do
           if git diff --name-only "${range}" | grep -q "^${dir}/"; then
               DIRS_TO_TEST+=("${dir}")
           fi
       done
   done

   if [ "${#DIRS_TO_TEST[@]}" -eq 0 ]; then
       printf "No changed sub-projects detected. Skipping tests.\n"
       exit 0
   fi

   for dir in $(printf '%s\n' "${DIRS_TO_TEST[@]}" | sort -u); do
       printf "test: %s\n" "${dir}"
       make -C "${REPO_ROOT}/${dir}" test < /dev/null
   done
   ```

   Key implementation notes:
   - **Drain the full stdin loop before acting** — never `exit` inside the while loop; use a `real_push=0` flag and check after the loop. A single push command can send multiple refs (e.g. a real branch + a deletion); exiting on the first deletion ref would skip testing the real push.
   - **Use `git rev-parse --git-common-dir` not `--show-toplevel`** — in a git worktree, `--show-toplevel` returns the worktree path, not the main repo root. `--git-common-dir` returns the shared `.git` dir; `cd "$(git rev-parse --git-common-dir)/.."` gives the main repo root where the Makefile lives.
   - **Redirect stdin from `/dev/null` for `make test`** — git holds the write end of the hook's stdin pipe open while waiting for the hook to finish. Without `< /dev/null`, Python's `multiprocessing.resource_tracker` daemon (spawned by `ProcessPoolExecutor`) inherits the live git pipe as stdin, blocks on reads waiting for EOF, and deadlocks with git in a circular wait. Always use `make -C "${dir}" test < /dev/null`.

6. **GitHub Actions CI triggers** — workflows must trigger on `pull_request` only. Never use bare `push:` or `branches-ignore:` push triggers. The pre-push hook is the gate for branch pushes; GitHub Actions is the PR merge gate.

   ```yaml
   on:
     pull_request:
       branches:
         - master
   ```
