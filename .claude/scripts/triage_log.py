#!/usr/bin/env python3
"""triage_log: JSONL emitter + validator for bug-fix-cycle telemetry.

Events land in .claude/triage-log/<session>.jsonl (gitignored).
The learnings skill mines this directory for bug-cluster and triage-thrashing patterns.

CLI:
    python3 .claude/scripts/triage_log.py emit --event bug_card \\
        --mode normal --symptom "..." --repro "..." --blast single-user
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

_REQUIRED_BASE = ("ts", "event")
_BUG_CARD_REQUIRED = ("mode", "symptom", "repro_cmd", "blast")
_VALID_MODES = ("normal", "hotfix", "regression")
_VALID_BLAST = ("single-user", "ci", "prod")


def validate_event(event: dict) -> None:
    """Raise ValueError if the event is malformed."""
    for key in _REQUIRED_BASE:
        if key not in event:
            raise ValueError(f"missing required key: {key}")
    if event["event"] == "bug_card":
        for key in _BUG_CARD_REQUIRED:
            if key not in event:
                raise ValueError(f"bug_card missing required field: {key}")
        if event["mode"] not in _VALID_MODES:
            raise ValueError(f"invalid mode: {event['mode']}")
        if event["blast"] not in _VALID_BLAST:
            raise ValueError(f"invalid blast: {event['blast']}")


def validate_chain(events: list[dict]) -> None:
    """Cross-event invariants. Raises ValueError on violation."""
    for e in events:
        validate_event(e)
    has_bisect_start = False
    for e in events:
        if e["event"] == "bisect_start":
            has_bisect_start = True
        elif e["event"] == "bisect_first_bad" and not has_bisect_start:
            raise ValueError("bisect_first_bad without preceding bisect_start")


def compute_cycle_complete(events: list[dict]) -> dict:
    """Return cycle_complete dict with total_duration_s computed from first triage_start to last gate event."""
    triage_start_ts = None
    last_ts = None
    for e in events:
        if e["event"] == "triage_start" and triage_start_ts is None:
            triage_start_ts = e["ts"]
        if e["event"] in ("gates_passed", "fix_landed", "cycle_complete"):
            last_ts = e["ts"]
    if triage_start_ts is None or last_ts is None:
        raise ValueError(
            "cannot compute duration: missing triage_start or final gate event"
        )
    start = datetime.fromisoformat(triage_start_ts.replace("Z", "+00:00"))
    end = datetime.fromisoformat(last_ts.replace("Z", "+00:00"))
    return {
        "ts": last_ts,
        "event": "cycle_complete",
        "total_duration_s": int((end - start).total_seconds()),
    }


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _emit(args: argparse.Namespace) -> int:
    event = {"ts": _now_iso(), "event": args.event}
    for attr in ("mode", "symptom", "blast"):
        val = getattr(args, attr, None)
        if val is not None:
            event[attr] = val
    if getattr(args, "repro", None) is not None:
        event["repro_cmd"] = args.repro
    try:
        validate_event(event)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    log_dir = Path(__file__).resolve().parent.parent / "triage-log"
    log_dir.mkdir(parents=True, exist_ok=True)
    session_file = (
        log_dir / f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H-%M-%SZ')}.jsonl"
    )
    with session_file.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(event) + "\n")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="triage_log")
    sub = parser.add_subparsers(dest="cmd", required=True)

    emit = sub.add_parser("emit", help="append a single JSONL event")
    emit.add_argument("--event", required=True)
    emit.add_argument("--mode", choices=_VALID_MODES)
    emit.add_argument("--symptom")
    emit.add_argument("--repro", dest="repro")
    emit.add_argument("--blast", choices=_VALID_BLAST)

    args = parser.parse_args(argv)
    if args.cmd == "emit":
        return _emit(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
