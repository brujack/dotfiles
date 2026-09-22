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
_HEADING_ONLY_RE = re.compile(r"^#{1,6} .+$")
_RULE_ONLY_RE = re.compile(r"^-{3,}$")


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


def split_paragraphs(text: str) -> list[str]:
    """Split text into non-empty blank-line-delimited paragraphs."""
    return [p for p in text.split("\n\n") if p.strip()]


def is_excluded_paragraph(paragraph: str) -> bool:
    """True when a paragraph carries no claim sentence for a manifest row.

    This exclusion follows from THIS TOOL's row contract, not from any
    general claim that headings are unimportant: a manifest row's phrase is
    drawn from a paragraph's claim sentence, and a chunk that is entirely one
    markdown ATX heading or entirely a horizontal rule has no sentence to
    draw one from. A fenced code block or a markdown table is real content
    and is never excluded here -- only these two content-free chunk shapes
    are.

    Do not copy this predicate into a tool with a different contract. A
    sibling tool computing "coverage" over the same kind of corpus, where
    every paragraph either survives unchanged or carries a disposition,
    finds a heading perfectly countable -- it can itself be deleted or
    promoted (a real case: two `###` subsections promoted to `##`) -- and
    excluding headings there would silently drop a recorded event. A
    denominator follows the contract, not the file.
    """
    stripped = paragraph.strip()
    if not stripped:
        return False
    return bool(_HEADING_ONLY_RE.fullmatch(stripped)) or bool(
        _RULE_ONLY_RE.fullmatch(stripped)
    )


def classify_paragraphs(text: str) -> tuple[list[str], int]:
    """Split into paragraphs and separate classifiable ones from excluded ones.

    Returns (classifiable_paragraphs, excluded_count). See
    is_excluded_paragraph for what "excluded" means and why.
    """
    paragraphs = split_paragraphs(text)
    classifiable = [p for p in paragraphs if not is_excluded_paragraph(p)]
    return classifiable, len(paragraphs) - len(classifiable)


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
    """Every classifiable source paragraph must carry at least one manifest row.

    A heading-only or rule-only paragraph is excluded from this population --
    see is_excluded_paragraph -- so this walks the same paragraph list the
    derived count is computed over.

    A row count equal to the paragraph count is an aggregate, and coverage is a
    per-paragraph property: a manifest whose rows all sit in one paragraph
    reaches the count while leaving the rest unclassified. An unclassified
    paragraph is invisible to every later gate, because the gate's universe is
    the manifest -- so it is absent from numerator and denominator alike and
    the figure does not move.
    """
    paragraphs, _ = classify_paragraphs(source_text)
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
    """Every DUPLICATE-deleted row must name a readable counterpart that
    contains its phrase; every other deleted row may name '-'/'' (no
    counterpart asserted) but, if it names one anyway, that claim is
    verified exactly like a DUPLICATE's.

    DUPLICATE asserts "this text exists elsewhere" and must prove it.
    RECORD (and any other non-DUPLICATE deleted class) asserts "git history
    holds this provenance" and names no counterpart at all -- '-' or an
    empty field is a valid absence there, not a gap. A stated counterpart
    is never taken on trust, whatever the class.
    """
    errors = []
    for row in rows:
        if not row.is_deleted:
            continue
        requires_counterpart = "duplicate" in row.cls.lower()
        no_counterpart_named = row.counterpart_file in ("", "-")
        if no_counterpart_named:
            if requires_counterpart:
                errors.append(
                    f"line {row.line_no} [{row.cls}]: deleted row has no counterpart-file"
                )
            continue
        # expanduser(), not os.path.expandvars(): no manifest row uses a
        # '$VAR' path segment, and expanding one would widen what a row can
        # reach.
        counterpart_path = Path(row.counterpart_file).expanduser()
        try:
            counterpart_text = counterpart_path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(
                f"line {row.line_no} [{row.cls}]: cannot read counterpart-file "
                f"{counterpart_path}: {exc}"
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
        classifiable, excluded = classify_paragraphs(source_text)
        minimum = len(classifiable)
        print(
            f"assert-complete-derived: denominator={minimum} paragraph(s), "
            f"excluded={excluded} (heading/rule chunks with no claim sentence)",
            file=sys.stderr,
        )
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
