## Ansible

### Linting

`ansible-lint` — run via `make lint`. Must pass before committing.

### Conventions

- **FQCN:** Use `ansible.builtin.*` fully qualified collection names for all built-in modules (e.g. `ansible.builtin.copy`, not `copy`)
- **Variable facts syntax:** Use `ansible_facts['key']` dict syntax (e.g. `ansible_facts['distribution']`) — never bare `ansible_*` magic variables; the bare form is deprecated and emits warnings
- **Role variable prefixing:** All role variables must be prefixed with the role name (e.g. `docker_`, `common_`)
- **Sensitive variables:** Sensitive vars (passwords, keys, tokens) must be empty string in `vars/main.yml` with an `ansible.builtin.assert` guard at the top of `tasks/main.yml` that verifies they are non-empty at runtime

### Idempotency

- Use modules that declare desired state (`package`, `file`, `template`, `service`) rather than `command`/`shell` wherever possible
- When `command`/`shell` is unavoidable, add `creates:`, `removes:`, or a `when:` guard so the task skips if already complete
- Never use `command`/`shell` for something a module handles natively — it bypasses idempotency guarantees
- All molecule scenarios must include the idempotence step — do NOT add a custom `scenario: test_sequence:` block that skips it; every role must report `changed=0` on the second converge

#### Common Idempotence Gotchas

**`ansible.builtin.file` with `recurse: true` and `owner`/`group`** — falsely reports `changed` even when ownership is already correct. Fix: use `find /path -not -user X -o -not -group X` to detect wrong ownership, then fix via `ansible.builtin.command` only when find output is non-empty.

**Root-owned files from `become: true`** — tasks with `become: true` but no `become_user` create files as root. Add `become_user: <user>` to `git clone`, package install, and similar tasks where the target user matters.

**Stale stat after resource creation** — when a `stat` check gates a task and that task creates the resource, add a re-stat task after creation. Without it, subsequent tasks see a stale "does not exist" result and skip.

**`docker_compose_v2` with `pull: "always"`** — not idempotent. Parameterize via a variable (e.g. `<role>_docker_pull`, default `"always"`) and override to `"missing"` in molecule converge vars. Must be in `defaults/main.yml` (priority 2), not `vars/main.yml` (priority 17).

### Molecule Testing

**Required configuration:**

Every role's `molecule/*/molecule.yml` must set `remote_tmp: /tmp` under `provisioner.config_options.defaults` — without it, Ansible cannot create temp dirs inside Docker containers running systemd.

Every `prepare.yml` and `converge.yml` must have `wait_for_connection` as the first task — without it, Ansible may start before systemd is fully initialized, causing deserialization errors.

**Handler testing:** When a role notifies handlers defined outside the role (e.g. in a playbook handlers file), add those handlers to molecule `converge.yml` with `failed_when: false` (services won't exist in the test container). Handler names must match exactly — watch for hyphen vs underscore mismatches.

**Symlink assertions:** Use `ansible.builtin.stat` with `follow: false` and assert on `lnk_target` (the symlink's direct target), not `lnk_source` (the fully resolved real path).
