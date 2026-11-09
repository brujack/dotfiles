#!/usr/bin/env python3
"""Cooldown helper for the weekly uv.lock refresh (scripts/refresh-uv-lock.sh).

Subcommands (each reads uv.lock files and prints to stdout):

  cutoff NOW DAYS            NOW minus DAYS days as YYYY-MM-DDTHH:MM:SSZ.
  plan BASE NEW CUTOFF REPORT
                             uv arguments, one per line, that hold every
                             changed package with a release newer than CUTOFF;
                             REPORT receives name<TAB>newest<TAB>earliest-upload.
  verify BASE FINAL CUTOFF   names of packages whose FINAL holds a changed,
                             fresh version (the cooldown was not honoured).
  diff BASE FINAL            uv-style Updated/Added/Removed lines.
  held REPORT FINAL          one markdown bullet per held package.

A registry package is a [[package]] whose `source` has a `registry` key. The
age of a version is the earliest `upload-time` over the sdist and wheels of
every entry that names it (a version may appear in several resolution forks);
a version none of whose entries has an `upload-time` is fresh. Timestamps
without an offset are refused. Versions are ordered with
uv_lock_downgrades.version_key and a version it cannot read is refused (exit
2) rather than guessed. Fresh means strictly later than CUTOFF, so a file
uploaded exactly at CUTOFF is aged. Only the standard library is used because
CI's test jobs install no Python packages.

Exit 0: success. Exit 1: findings (`verify` only). Exit 2: usage error,
unreadable or invalid input, or any uncaught exception (never 1, which means
findings).
"""

from __future__ import annotations

import sys
import tomllib
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from uv_lock_downgrades import version_key  # noqa: E402 - needs the path insert above

Versions = dict[str, dict[str, datetime | None]]  # name -> version -> earliest upload


class InputError(Exception):
    """Bad arguments or bad input; maps to exit 2."""


def parse_time(text: str) -> datetime:
    """Parse an RFC 3339 timestamp (Z or offset) into an aware datetime."""
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as err:
        raise InputError(f"bad timestamp {text!r}") from err
    if parsed.tzinfo is None:
        raise InputError(f"timestamp {text!r} has no offset")
    return parsed


def format_time(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def file_times(package: dict) -> list[datetime]:
    entries = list(package.get("wheels", []))
    if isinstance(package.get("sdist"), dict):
        entries.append(package["sdist"])
    times = []
    for entry in entries:
        stamp = entry.get("upload-time") if isinstance(entry, dict) else None
        if isinstance(stamp, datetime):
            if stamp.tzinfo is None:
                raise InputError(f"timestamp {stamp} has no offset")
            times.append(stamp)
        elif isinstance(stamp, str):
            times.append(parse_time(stamp))
    return times


def read_lock(path: str) -> Versions:
    """Return name -> {version: earliest upload or None} for registry packages."""
    try:
        data = tomllib.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as err:
        raise InputError(f"cannot read {path}: {err}") from err
    seen: dict[str, dict[str, list[datetime]]] = {}
    for package in data.get("package", []):
        source = package.get("source")
        if not isinstance(source, dict) or "registry" not in source:
            continue
        name, version = package.get("name"), package.get("version")
        if not isinstance(name, str) or not isinstance(version, str):
            raise InputError(f"{path}: registry package without name or version")
        slot = seen.setdefault(name, {})
        slot.setdefault(version, []).extend(file_times(package))
    if not seen:
        raise InputError(f"{path}: no registry packages")
    return {
        name: {version: (min(times) if times else None) for version, times in versions.items()}
        for name, versions in seen.items()
    }


def is_fresh(upload: datetime | None, cutoff: datetime) -> bool:
    return upload is None or upload > cutoff


def version_sort_key(version: str) -> tuple:
    """PEP 440 sort key; refuse a version uv_lock_downgrades cannot read."""
    try:
        return version_key("v" + version)
    except ValueError as err:
        raise InputError(f"cannot order version {version!r}") from err


def changed_names(base: Versions, other: Versions) -> list[str]:
    return sorted(
        name
        for name in set(base) | set(other)
        if set(base.get(name, {})) != set(other.get(name, {}))
    )


def cmd_cutoff(args: list[str]) -> int:
    now_text, days_text = args
    if not (days_text.isascii() and days_text.isdigit()) or int(days_text) < 1:
        raise InputError(f"day count must be a positive integer, got {days_text!r}")
    days = int(days_text)
    print(format_time(parse_time(now_text) - timedelta(days=days)))
    return 0


def cmd_plan(args: list[str]) -> int:
    base_path, new_path, cutoff_text, report_path = args
    cutoff = parse_time(cutoff_text)
    base, new = read_lock(base_path), read_lock(new_path)
    lines: list[str] = []
    rows: list[str] = []
    for name in changed_names(base, new):
        base_versions = base.get(name, {})
        fresh_new = [
            v
            for v, up in new.get(name, {}).items()
            if v not in base_versions and is_fresh(up, cutoff)
        ]
        if not fresh_new:
            continue
        fresh_base = [v for v, up in base_versions.items() if is_fresh(up, cutoff)]
        if fresh_base:
            lines += ["--upgrade-package", f"{name}=={max(fresh_base, key=version_sort_key)}"]
        else:
            lines += ["--upgrade-package", name, "--exclude-newer-package", f"{name}={cutoff_text}"]
        newest = max(fresh_new, key=version_sort_key)
        upload = new[name][newest]
        rows.append(f"{name}\t{newest}\t{format_time(upload) if upload else 'unknown'}\n")
    try:
        Path(report_path).write_text("".join(rows), encoding="utf-8")
    except OSError as err:
        raise InputError(f"cannot write {report_path}: {err}") from err
    for line in lines:
        print(line)
    return 0


def cmd_verify(args: list[str]) -> int:
    base_path, final_path, cutoff_text = args
    cutoff = parse_time(cutoff_text)
    base, final = read_lock(base_path), read_lock(final_path)
    bad = [
        name
        for name in changed_names(base, final)
        if any(
            v not in base.get(name, {}) and is_fresh(up, cutoff)
            for v, up in final.get(name, {}).items()
        )
    ]
    for name in bad:
        print(name)
    return 1 if bad else 0


def side(versions: dict[str, datetime | None]) -> str:
    return ", ".join(f"v{v}" for v in sorted(versions, key=version_sort_key))


def cmd_diff(args: list[str]) -> int:
    base, final = read_lock(args[0]), read_lock(args[1])
    for name in changed_names(base, final):
        old, new = base.get(name), final.get(name)
        if old and new:
            print(f"Updated {name} {side(old)} -> {side(new)}")
        elif new:
            print(f"Added {name} {side(new)}")
        else:
            print(f"Removed {name} {side(old or {})}")
    return 0


def cmd_held(args: list[str]) -> int:
    report_path, final_path = args
    final = read_lock(final_path)
    try:
        text = Path(report_path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as err:
        raise InputError(f"cannot read {report_path}: {err}") from err
    for row in text.splitlines():
        fields = row.split("\t")
        if len(fields) != 3:
            raise InputError(f"malformed report row: {row!r}")
        name, newest, uploaded = fields
        took = ", ".join(sorted(final.get(name, {}), key=version_sort_key)) or "(removed)"
        print(f"- {name}: newest {newest} uploaded {uploaded}; took {took}")
    return 0


COMMANDS = {
    "cutoff": (2, cmd_cutoff),
    "plan": (4, cmd_plan),
    "verify": (3, cmd_verify),
    "diff": (2, cmd_diff),
    "held": (2, cmd_held),
}


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in COMMANDS:
        raise InputError(f"usage: uv_lock_cooldown.py {{{'|'.join(COMMANDS)}}} ARGS...")
    count, handler = COMMANDS[argv[0]]
    if len(argv) - 1 != count:
        raise InputError(f"{argv[0]} takes {count} arguments, got {len(argv) - 1}")
    return handler(argv[1:])


def run() -> int:
    """Run main(); any failure exits 2, never 1 (1 means findings)."""
    try:
        return main(sys.argv[1:])
    except InputError as err:
        print(f"uv_lock_cooldown: {err}", file=sys.stderr)
        return 2
    except Exception as err:  # noqa: BLE001 - the exit code is the contract
        print(f"uv_lock_cooldown: crashed: {err!r}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(run())
