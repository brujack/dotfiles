---
name: ntfy user add uses NTFY_PASSWORD env var not --password flag
description: ntfy CLI user management syntax for scripted/Ansible use
type: feedback
---

`ntfy user add --password <pass> <user>` does not work — there is no `--password` flag. Use the `NTFY_PASSWORD` environment variable instead:

```bash
docker exec -e NTFY_PASSWORD=secret ntfy ntfy user add --ignore-exists bruce
docker exec ntfy ntfy access bruce mytopic rw
```

**Why:** Discovered after two failed Ansible runs. The ntfy help text shows the correct usage: `NTFY_PASSWORD=... ntfy user add USERNAME`.

**How to apply:**

- In Ansible, use `argv:` form with `-e` and `NTFY_PASSWORD={{ ntfy_user_password }}` passed to `docker exec`
- Use `--ignore-exists` for idempotency — skips silently if user already exists; no pre-check needed
- `ntfy access` is idempotent on its own (updates existing ACL entry)
- `no_log: true` on the create task to keep the password out of Ansible output
