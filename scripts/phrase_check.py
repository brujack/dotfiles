#!/usr/bin/env python3
"""phrase_check: whitespace-normalised manifest checker for the CLAUDE.md four-class resort.

Manifest rows are pipe-separated: `class | phrase | counterpart-file | counterpart-symbol | note`.
Blank lines and lines starting with `#` are ignored; a row may optionally be wrapped in a
leading/trailing `|` (markdown-table style). A row is "deleted" when its class field
contains the substring "deleted" (case-insensitive), e.g. `DUPLICATE-deleted`.

Matching is always whitespace-normalised (every run of whitespace, including a line wrap,
collapses to a single space) and never line-oriented — a hand-wrapped paragraph routinely
splits a sentence across a line wrap that a line-oriented grep cannot cross.

A phrase is rejected wherever it matches if that match begins at a sentence boundary
(immediately after `.`/`!`/`?`, or at the very start of the haystack): a later HAZARD
remedy capitalises a sentence's leading word, and matching is case-sensitive, so a
sentence-initial phrase is fragile against edits made elsewhere in the file.

CLI:
    python3 .claude/scripts/phrase_check.py --manifest phrases.md --source CLAUDE.md --assert-unique
    python3 .claude/scripts/phrase_check.py --manifest phrases.md --source CLAUDE.md --assert-complete-derived
    python3 .claude/scripts/phrase_check.py --manifest phrases.md --source CLAUDE.md --survives HAZARD
    python3 .claude/scripts/phrase_check.py --manifest phrases.md --deleted-have-counterparts
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

_WHITESPACE_RE = re.compile(r"\s+")
_SENTENCE_END_CHARS = (".", "!", "?")


class ManifestError(Exception):
    """The manifest file could not be read or a row could not be parsed."""


@dataclass(frozen=True)
class Row:
    cls: str
    phrase: str
    counterpart_file: str
    counterpart_symbol: str
    note: str
    line_no: int
    raw: str

    @property
    def is_deleted(self) -> bool:
        return "deleted" in self.cls.lower()


def normalize(text: str) -> str:
    """Collapse every run of whitespace (including a line wrap) to a single space."""
    return _WHITESPACE_RE.sub(" ", text)


def parse_manifest(path: Path) -> list[Row]:
    """Parse a pipe-separated phrase manifest into rows.

    Blank lines and lines starting with '#' are skipped. A row may optionally be
    wrapped in a leading/trailing '|' (markdown-table style); either form is accepted.
    """
    try:
        raw_lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ManifestError(f"cannot read manifest {path}: {exc}") from exc

    rows: list[Row] = []
    for line_no, raw_line in enumerate(raw_lines, start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        body = stripped
        body = body.removeprefix("|")
        body = body.removesuffix("|")
        fields = [field.strip() for field in body.split("|", 4)]
        if len(fields) < 2 or not fields[0] or not fields[1]:
            raise ManifestError(
                f"{path}:{line_no}: expected at least 'class | phrase', got: {raw_line!r}"
            )
        fields += [""] * (5 - len(fields))
        cls, phrase, counterpart_file, counterpart_symbol, note = fields[:5]
        rows.append(
            Row(
                cls,
                phrase,
                counterpart_file,
                counterpart_symbol,
                note,
                line_no,
                raw_line,
            )
        )
    return rows


def derive_paragraph_count(text: str) -> int:
    """Count non-empty blank-line-delimited paragraphs, matching the baseline probe's method."""
    return len([p for p in text.split("\n\n") if p.strip()])


def find_occurrences(haystack_norm: str, needle_norm: str) -> list[int]:
    """Return the start index of every non-overlapping occurrence of needle in haystack."""
    if not needle_norm:
        return []
    positions = []
    start = 0
    while True:
        idx = haystack_norm.find(needle_norm, start)
        if idx == -1:
            break
        positions.append(idx)
        start = idx + len(needle_norm)
    return positions


def is_sentence_initial(haystack_norm: str, index: int) -> bool:
    """True if the match starting at index begins a sentence in the normalised haystack."""
    if index <= 0:
        return True
    before = haystack_norm[:index].rstrip()
    return bool(before) and before[-1] in _SENTENCE_END_CHARS


def match_phrase(haystack_norm: str, phrase: str) -> tuple[int, bool]:
    """Return (occurrence count, whether any occurrence begins a sentence)."""
    needle_norm = normalize(phrase)
    positions = find_occurrences(haystack_norm, needle_norm)
    sentence_initial = any(is_sentence_initial(haystack_norm, p) for p in positions)
    return len(positions), sentence_initial


def check_unique(rows: list[Row], source_norm: str) -> list[str]:
    errors = []
    for row in rows:
        count, sentence_initial = match_phrase(source_norm, row.phrase)
        if count != 1:
            errors.append(
                f"line {row.line_no} [{row.cls}]: phrase occurs {count} time(s), "
                f"expected exactly 1: {row.phrase!r}"
            )
        elif sentence_initial:
            errors.append(
                f"line {row.line_no} [{row.cls}]: phrase begins at a sentence "
                f"boundary: {row.phrase!r}"
            )
    return errors


def check_complete(row_count: int, minimum: int) -> list[str]:
    if row_count < minimum:
        return [f"manifest has {row_count} row(s), expected at least {minimum}"]
    return []


def check_paragraph_coverage(rows: list[Row], source_text: str) -> list[str]:
    """Every source paragraph must carry at least one manifest row.

    A row count equal to the paragraph count is an aggregate, and coverage is a
    per-paragraph property: a manifest whose rows all sit in one paragraph
    reaches the count while leaving the rest unclassified. An unclassified
    paragraph is invisible to every later gate, because the gate's universe is
    the manifest -- so it is absent from numerator and denominator alike and
    the figure does not move.
    """
    paragraphs = [p for p in source_text.split("\n\n") if p.strip()]
    phrases = [normalize(row.phrase) for row in rows]
    errors: list[str] = []
    for index, paragraph in enumerate(paragraphs, start=1):
        para_norm = normalize(paragraph)
        if not any(phrase and phrase in para_norm for phrase in phrases):
            head = " ".join(para_norm.split()[:8])
            errors.append(
                f"paragraph {index} has no manifest row: {head!r}"
            )
    return errors


def check_survives(rows: list[Row], cls: str, source_norm: str) -> list[str]:
    errors = []
    for row in rows:
        if row.cls != cls:
            continue
        count, sentence_initial = match_phrase(source_norm, row.phrase)
        if count == 0:
            errors.append(
                f"line {row.line_no} [{row.cls}]: phrase no longer found: {row.phrase!r}"
            )
        elif sentence_initial:
            errors.append(
                f"line {row.line_no} [{row.cls}]: surviving phrase begins at a "
                f"sentence boundary: {row.phrase!r}"
            )
    return errors


def check_deleted_have_counterparts(rows: list[Row]) -> list[str]:
    errors = []
    for row in rows:
        if not row.is_deleted:
            continue
        if not row.counterpart_file:
            errors.append(
                f"line {row.line_no} [{row.cls}]: deleted row has no counterpart-file"
            )
            continue
        counterpart_path = Path(row.counterpart_file)
        try:
            counterpart_text = counterpart_path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(
                f"line {row.line_no} [{row.cls}]: cannot read counterpart-file "
                f"{row.counterpart_file}: {exc}"
            )
            continue
        counterpart_norm = normalize(counterpart_text)
        count, _ = match_phrase(counterpart_norm, row.phrase)
        if count == 0:
            errors.append(
                f"line {row.line_no} [{row.cls}]: deleted phrase has no counterpart "
                f"in {row.counterpart_file}: {row.phrase!r}"
            )
    return errors


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="phrase_check.py",
        description=(
            "Whitespace-normalised manifest checker. Manifest rows are pipe-separated: "
            "'class | phrase | counterpart-file | counterpart-symbol | note'. A row is "
            "'deleted' when its class field contains 'deleted' (case-insensitive), e.g. "
            "'DUPLICATE-deleted'. Matching is never line-oriented, and a phrase that "
            "begins a sentence is always rejected."
        ),
    )
    parser.add_argument(
        "--manifest", required=True, type=Path, help="path to the phrase manifest"
    )
    parser.add_argument(
        "--source", type=Path, help="path to the file to match phrases against"
    )
    parser.add_argument(
        "--assert-unique",
        action="store_true",
        help="every row's phrase occurs exactly once in --source",
    )
    parser.add_argument(
        "--assert-complete",
        type=int,
        metavar="N",
        help="manifest row count >= N, else exit 1",
    )
    parser.add_argument(
        "--assert-complete-derived",
        action="store_true",
        help="derive N from --source by blank-line paragraph split, compare, and assert every paragraph carries at least one row",
    )
    parser.add_argument(
        "--survives",
        metavar="CLASS",
        help="every row of CLASS still matches in --source",
    )
    parser.add_argument(
        "--deleted-have-counterparts",
        action="store_true",
        help="every row marked deleted has its phrase in its counterpart-file",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        rows = parse_manifest(args.manifest)
    except ManifestError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    needs_source = (
        args.assert_unique or bool(args.survives) or args.assert_complete_derived
    )
    source_text = ""
    source_norm = ""
    if needs_source:
        if args.source is None:
            print(
                "error: --source is required for --assert-unique, --survives, "
                "or --assert-complete-derived",
                file=sys.stderr,
            )
            return 2
        try:
            source_text = args.source.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"error: cannot read source {args.source}: {exc}", file=sys.stderr)
            return 2
        source_norm = normalize(source_text)

    ran_any = False
    errors: list[str] = []

    if args.assert_unique:
        ran_any = True
        errors += check_unique(rows, source_norm)

    if args.assert_complete is not None:
        ran_any = True
        errors += check_complete(len(rows), args.assert_complete)

    if args.assert_complete_derived:
        ran_any = True
        minimum = derive_paragraph_count(source_text)
        errors += check_complete(len(rows), minimum)
        errors += check_paragraph_coverage(rows, source_text)

    if args.survives:
        ran_any = True
        errors += check_survives(rows, args.survives, source_norm)

    if args.deleted_have_counterparts:
        ran_any = True
        errors += check_deleted_have_counterparts(rows)

    if not ran_any:
        print(
            "error: no check requested (pass --assert-unique, --assert-complete, "
            "--assert-complete-derived, --survives, or --deleted-have-counterparts)",
            file=sys.stderr,
        )
        return 2

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
