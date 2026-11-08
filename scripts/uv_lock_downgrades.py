#!/usr/bin/env python3
"""Flag version downgrades in `uv lock --upgrade` output read on stdin.

An `Updated <pkg> <old> -> <new>` line has one or more `v`-prefixed versions
on each side, joined by ", " when a package is locked at several versions
across resolution forks. A downgrade is max(new) < max(old) under PEP 440.
Prints the package name for each downgrade and `unparseable: <line>` for an
`Updated` line it cannot read (fail closed). Exit 0 when nothing printed.
"""

import re
import sys

from packaging.version import InvalidVersion, Version

UPDATED = re.compile(r"^Updated (\S+) (v\S+(?:, v\S+)*) -> (v\S+(?:, v\S+)*)$")


def newest(side: str) -> Version:
    """Return the highest version in a `v1, v2` list."""
    return max(Version(token.strip()[1:]) for token in side.split(","))


def check_line(line: str) -> str | None:
    """Return a report string for a bad `Updated` line, else None."""
    match = UPDATED.match(line)
    if match is None:
        return f"unparseable: {line}"
    package, old, new = match.groups()
    try:
        if newest(new) < newest(old):
            return package
    except InvalidVersion:
        return f"unparseable: {line}"
    return None


def main() -> int:
    reports = []
    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if not line.startswith("Updated "):
            continue
        report = check_line(line)
        if report is not None:
            reports.append(report)
    for report in reports:
        print(report)
    return 1 if reports else 0


if __name__ == "__main__":
    sys.exit(main())
