## Ansible

### Idempotency

- Use modules that declare desired state (`package`, `file`, `template`, `service`) rather than `command`/`shell` wherever possible
- When `command`/`shell` is unavoidable, add `creates:`, `removes:`, or a `when:` guard so the task skips if already complete
- Never use `command`/`shell` for something a module handles natively — it bypasses idempotency guarantees
