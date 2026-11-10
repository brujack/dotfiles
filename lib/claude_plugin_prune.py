#!/usr/bin/env python3
"""Prune redundant project/local records from Claude's installed_plugins.json.

A project or local record is removed when either holds: its plugin also has a
user-scope record that is at least as new (see the design spec, section "Record
prune"), or its projectPath is an absolute path that no longer exists. A plugin
key whose records are all removed is dropped from the map; a key that was
already an empty list is left as is.
Runs on Python 3.9: timestamps are parsed with an explicit format because
datetime.fromisoformat rejects a trailing "Z" before 3.11.

Exit codes: 0 done or nothing to do, 3 refused, 4 file changed during prune.
Prints exactly one stdout line.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

_TS_FORMAT = "%Y-%m-%dT%H:%M:%S.%fZ"
_BACKUP_PREFIX = "installed_plugins-"
_BACKUP_SUFFIX = ".json"
_PRUNABLE_SCOPES = ("project", "local")
_CHANGED_LINE = "skipped: plugins file changed during prune"


def parse_ts(s):
    """Return a datetime for a "...%f Z" timestamp, or None if absent or invalid."""
    if not isinstance(s, str):
        return None
    try:
        return datetime.strptime(s, _TS_FORMAT)
    except ValueError:
        return None


def path_gone(record):
    """True when the record's projectPath is an absolute path that does not exist.

    Any other lstat failure (permissions, not-a-directory, I/O) is not proof of
    absence, so it counts as not gone. lstat, not stat: a dangling symlink exists.
    """
    p = record.get("projectPath")
    if not _nonempty_str(p) or not os.path.isabs(p):
        return False
    try:
        os.lstat(p)
    except FileNotFoundError:
        return True
    except (OSError, ValueError):
        # ValueError: embedded NUL in the path; not proof of absence either.
        return False
    return False


def should_remove(record, user_record):
    """True when a project/local record is redundant or its project directory is gone."""
    if record.get("scope") not in _PRUNABLE_SCOPES:
        return False
    if path_gone(record):
        return True
    if user_record is None:
        return False
    # Equal versions decide first: no timestamp is read.
    mine_v, user_v = record.get("version"), user_record.get("version")
    if _nonempty_str(mine_v) and _nonempty_str(user_v) and mine_v == user_v:
        return True
    mine = parse_ts(record.get("lastUpdated"))
    theirs = parse_ts(user_record.get("lastUpdated"))
    if mine is None or theirs is None:
        return False
    return theirs >= mine


def _refuse(reason):
    return 3, "refused: " + reason


def _prune_records(plugins):
    """Return (new plugins map, removed count, kept count)."""
    new_plugins = {}
    removed = kept = 0
    for plugin_id, records in plugins.items():
        if not isinstance(records, list):
            new_plugins[plugin_id] = records
            continue
        user_record = next(
            (r for r in records if isinstance(r, dict) and r.get("scope") == "user"), None
        )
        survivors = []
        for r in records:
            if isinstance(r, dict) and should_remove(r, user_record):
                removed += 1
            else:
                survivors.append(r)
                kept += 1
        # A key the prune emptied is dropped; an input list that was already empty stays.
        if records and not survivors:
            continue
        new_plugins[plugin_id] = survivors
    return new_plugins, removed, kept


def _nonempty_str(v):
    return isinstance(v, str) and v != ""


def _write_backup(raw, backup_dir, stamp):
    """Write the bytes already read from the plugins file; return the backup path."""
    os.makedirs(backup_dir, exist_ok=True)
    dest = os.path.join(backup_dir, _BACKUP_PREFIX + stamp + _BACKUP_SUFFIX)
    try:
        with open(dest, "wb") as dst:
            dst.write(raw)
    except OSError:
        # Cleanup only: a truncated backup must not look like a real one.
        _remove_quietly(dest)
        raise
    return dest


def _trim_backups(backup_dir, keep):
    """Best-effort retention after a successful replace: a failure here is cleanup only."""
    try:
        listing = os.listdir(backup_dir)
    except OSError:
        return
    names = sorted(
        n for n in listing if n.startswith(_BACKUP_PREFIX) and n.endswith(_BACKUP_SUFFIX)
    )
    for n in names[: max(0, len(names) - keep)]:
        try:
            os.remove(os.path.join(backup_dir, n))
        except OSError:
            pass


def _signature(st):
    return (st.st_mtime_ns, st.st_ino, st.st_size)


def _remove_quietly(path):
    """Cleanup of this run's own artefact; a failure must not skip later cleanup."""
    try:
        os.remove(path)
    except OSError:
        pass


def prune(path, backup_dir, keep, dry_run, before_restat=None):
    """Prune `path`. Returns (exit_code, stdout_line).

    Race guard: mtime, inode and size of the resolved file and of the link path itself are compared before reading and again just
    before os.replace. A write landing between that re-stat and os.replace is
    still lost; this cannot be closed without a lock Claude Code does not take.
    Any OSError becomes a refusal (exit 3) and leaves the plugins file as it was;
    pruning never proceeds without a backup.
    """
    if keep < 1:
        raise ValueError("keep must be at least 1")
    try:
        return _prune(path, backup_dir, keep, dry_run, before_restat)
    except OSError as exc:
        return _refuse("%s" % exc)


# The plugins file as first seen: the given path, its resolved target, and the
# stat of each, which the race guard compares again just before the replace.
_Source = collections.namedtuple("_Source", "path real before link_before")


def _validate(data):
    """Return a refusal (code, line) for an unusable plugins file, else None."""
    if not isinstance(data, dict):
        return _refuse("plugins file is not a JSON object")
    if data.get("version") != 2:
        return _refuse("unsupported plugins file version %r" % (data.get("version"),))
    if not isinstance(data.get("plugins"), dict):
        return _refuse("no plugins object")
    return None


def _write_temp(real, new_data, mode):
    """Write new_data to a fsynced temp file beside `real`; return its path.

    On failure the temp file is removed here and the error propagates.
    """
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(new_data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode & 0o7777)
    except (OSError, ValueError, TypeError):
        _remove_quietly(tmp)
        raise
    return tmp


def _changed_since(src):
    """True when the resolved file or the link path differs from what was read."""
    try:
        return (
            _signature(os.stat(src.real)) != _signature(src.before)
            or _signature(os.lstat(src.path)) != _signature(src.link_before)
        )
    except FileNotFoundError:
        return True


def _commit(src, new_data, backup, before_restat):
    """Write the temp file, re-check the race guard and replace.

    Returns None on success, else the (code, line) to report; this run's temp
    file and backup are removed on every failure path.
    """
    tmp = None
    try:
        tmp = _write_temp(src.real, new_data, src.before.st_mode)
        if before_restat is not None:
            before_restat()
        if _changed_since(src):
            _remove_quietly(tmp)
            _remove_quietly(backup)
            return 4, _CHANGED_LINE
        os.replace(tmp, src.real)
    except (OSError, ValueError, TypeError) as exc:
        # Cleanup, then report: the plugins file was not replaced.
        if tmp is not None:
            _remove_quietly(tmp)
        _remove_quietly(backup)
        return _refuse("cannot write plugins file: %s" % exc)
    return None


def _prune(path, backup_dir, keep, dry_run, before_restat):
    # Resolve a symlinked plugins file so the temp file and the replace target
    # live beside the real file and the link survives.
    real = os.path.realpath(path)
    try:
        before = os.stat(real)
        link_before = os.lstat(path)
    except FileNotFoundError:
        return 0, "no plugins file"
    now = datetime.now(timezone.utc)
    with open(real, "rb") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except ValueError as exc:
        return _refuse("cannot parse plugins file: %s" % exc)
    refusal = _validate(data)
    if refusal is not None:
        return refusal

    new_plugins, removed, kept = _prune_records(data["plugins"])
    line = "pruned at %s: removed %d, kept %d" % (now.strftime("%Y-%m-%dT%H:%M:%SZ"), removed, kept)
    if removed == 0 or dry_run:
        return 0, line

    backup = _write_backup(raw, backup_dir, now.strftime("%Y%m%dT%H%M%S%fZ"))
    new_data = dict(data)
    new_data["plugins"] = new_plugins
    src = _Source(path, real, before, link_before)
    failure = _commit(src, new_data, backup, before_restat)
    if failure is not None:
        return failure
    _trim_backups(backup_dir, keep)
    return 0, line


def _keep_arg(value):
    n = int(value)
    if n < 1:
        raise argparse.ArgumentTypeError("--keep must be at least 1")
    return n


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--file", required=True)
    parser.add_argument("--backup-dir", required=True)
    parser.add_argument("--keep", type=_keep_arg, default=5)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    code, line = prune(args.file, args.backup_dir, args.keep, args.dry_run)
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
