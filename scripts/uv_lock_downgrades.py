#!/usr/bin/env python3
"""Flag version downgrades in `uv lock --upgrade` output read on stdin.

An `Updated <pkg> <old> -> <new>` line has one or more `v`-prefixed versions
on each side, joined by ", " when a package is locked at several versions
across resolution forks. A downgrade is max(new) < max(old) or
min(new) < min(old), compared as PEP 440 versions.

CI's test jobs install no Python packages, so the comparison uses the standard
library and understands only the forms uv emits: optional epoch, release,
optional a/b/rc pre-release, optional .post and optional .dev. Any other form
(a local `+...` version, say) is unparseable and refused.

Prints the package name for each downgrade and `unparseable: <line>` for an
`Updated` line it cannot read (fail closed).
Exit 0: nothing found. Exit 1: findings. Exit 2: unreadable input or any
uncaught exception (never 1, which means findings).
"""

from __future__ import annotations

import re
import sys

UPDATED = re.compile(r"^Updated (\S+) (v\S+(?:, v\S+)*) -> (v\S+(?:, v\S+)*)$")
VERSION = re.compile(
    r"^(?:(\d+)!)?(\d+(?:\.\d+)*)"
    r"(?:(a|b|rc)(\d+))?"
    r"(?:\.post(\d+))?"
    r"(?:\.dev(\d+))?$"
)
PRE_RANK = {"a": 0, "b": 1, "rc": 2}
INF = float("inf")


def version_key(text: str) -> tuple:
    """Return a sort key for a `v`-prefixed version; ValueError if not a handled form."""
    match = VERSION.match(text[1:])
    if match is None:
        raise ValueError(text)
    epoch, release, pre_tag, pre_num, post, dev = match.groups()
    parts = [int(part) for part in release.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()  # 1.0 == 1.0.0
    if pre_tag is not None:
        pre = (0, PRE_RANK[pre_tag], int(pre_num))
    elif post is None and dev is not None:
        pre = (-1, 0, 0)  # 1.0.dev1 sorts before every 1.0 pre-release
    else:
        pre = (1, 0, 0)  # a final release sorts after its pre-releases
    post_key = -1 if post is None else int(post)
    dev_key = INF if dev is None else int(dev)
    return (int(epoch or 0), tuple(parts), pre, post_key, dev_key)


def check_line(line: str) -> str | None:
    """Return a report string for a bad `Updated` line, else None."""
    match = UPDATED.match(line)
    if match is None:
        return f"unparseable: {line}"
    package, old_side, new_side = match.groups()
    try:
        old = [version_key(token) for token in old_side.split(", ")]
        new = [version_key(token) for token in new_side.split(", ")]
    except ValueError:
        return f"unparseable: {line}"
    if max(new) < max(old) or min(new) < min(old):
        return package
    return None


def main() -> int:
    try:
        text = sys.stdin.buffer.read().decode("utf-8")
    except UnicodeDecodeError as err:
        print(f"uv_lock_downgrades: unreadable input: {err}", file=sys.stderr)
        return 2
    reports = []
    for line in text.splitlines():
        if not line.startswith("Updated "):
            continue
        report = check_line(line)
        if report is not None:
            reports.append(report)
    for report in reports:
        print(report)
    return 1 if reports else 0


def run() -> int:
    """Run main(); any uncaught exception exits 2, never 1 (1 means findings)."""
    try:
        return main()
    except Exception as err:  # noqa: BLE001 - the exit code is the contract
        print(f"uv_lock_downgrades: crashed: {err!r}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(run())
