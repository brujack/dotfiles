# Ansible PR Review Reference

IaC Safety — findings in the CRITICAL section below are automatic HOLDs.

---

## CRITICAL — Automatic HOLD

- [ ] `ignore_errors: true` used without a comment explaining why — masks real failures
- [ ] `no_log: false` on tasks handling passwords, tokens, or keys
- [ ] Plays running as `root` or `become: true` without explicit justification in a comment
- [ ] Hardcoded IP addresses or hostnames that should be inventory variables
- [ ] Hardcoded credentials anywhere — passwords, tokens, keys in vars or tasks
- [ ] `shell:` or `command:` tasks with unsanitised variables (injection risk)
- [ ] `ansible-lint` errors (not warnings) in the diff

---

## Security

- Secrets in `vars:` blocks — should be in Ansible Vault or AWS Secrets Manager lookup
- `delegate_to: localhost` with sensitive operations — verify scope is intentional
- File permissions: `mode:` specified on all `copy:` / `template:` / `file:` tasks
  - Sensitive files: `0600` or `0640`
  - Never `0777` or `0666`
- `uri:` tasks: `validate_certs: true` (default) — never set to `false`
- `become_method` and `become_user` appropriate for the environment

## Idempotency

- All tasks must be idempotent — running the play twice should produce the same result
- `command:` / `shell:` tasks have `changed_when:` and `failed_when:` defined
- `creates:` or `removes:` arguments used on `command:` tasks where applicable
- No tasks that will always report `changed`

## Structure & Quality

- `ansible-lint` passes (warnings acceptable, errors are HOLD)
- `yamllint` passes — consistent YAML formatting
- Tasks have descriptive `name:` values (not blank, not "debug")
- Variables follow `role_varname` naming convention
- `defaults/main.yml` provides sensible defaults for all role variables
- Handlers named clearly and only notified when a real change occurs
- Tags applied consistently — allows partial runs
- No `include:` (deprecated) — use `import_tasks:` or `include_tasks:`

## Molecule / Testing

- Role changes accompanied by Molecule test updates if Molecule is configured
- At minimum: `ansible-lint` and `--syntax-check` must pass
- `--check` mode (dry run) passes without errors

## Commands to run

```bash
ansible-lint . 2>&1
yamllint . 2>&1
ansible-playbook playbook.yml --syntax-check 2>&1
ansible-playbook playbook.yml --check 2>&1    # dry-run if safe to do so
molecule test 2>&1                             # if Molecule configured
```
