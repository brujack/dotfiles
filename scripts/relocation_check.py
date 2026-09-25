#!/usr/bin/env python3
"""relocation_check: verify a CLAUDE.md -> ai-config/docs/knowledge relocation.

Implements spec checks 1-4 from
docs/superpowers/specs/2026-09-25-claude-md-relocation-design.md against the
pre-change file at a pinned git revision, a post-change file, a destination
directory of `dotfiles-*.md` knowledge files, and a relocation map.

CLI:
    python3 scripts/relocation_check.py measure --pre-rev REV --map MAP
    python3 scripts/relocation_check.py check --pre-rev REV --post FILE \
        --dest DIR --map MAP [--min-relocated N] [--slack N]

The pre-change file is read with `git show <rev>:CLAUDE.md`, never from the
worktree -- per the plan's Global Constraints, edits may already be underway.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# phrase_check.py lives beside this script, not in a package -- put its
# directory on sys.path and import the one function the plan authorizes.
# Do not copy normalize(): a second implementation could drift from the one
# #293's manifest checker already depends on.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from phrase_check import normalize

_TARGET_PATH = "CLAUDE.md"

# git exports these into a pre-push hook's environment when the push
# originates from a worktree; a subprocess that inherits them silently reads
# a DIFFERENT repository's objects. Per shell.md, `-C`/cwd does not override
# an exported GIT_DIR. Strip all four before shelling out.
_GIT_ENV_STRIP = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE")

_FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
_HEADING_ONLY_RE = re.compile(r"^#{1,6}\s+.+$")
_HR_ONLY_RE = re.compile(r"^-{3,}$")
_BULLET_MARKER_RE = re.compile(r"^(?:[-*+]|\d+[.)])\s")
_HEADING_LINE_RE = re.compile(r"^(#{1,6})\s+.+$")

# The pinned splitter (plan Global Constraints). Python rejects a
# variable-width lookbehind, so this is a boundary match consumed via
# finditer, never a re.split lookbehind -- see the module docstring's sibling
# note in the design doc. Capturing group 1 isolates the punctuation and any
# closing markup so the sentence boundary lands after it and before the
# whitespace that follows.
_SENTENCE_BOUNDARY_RE = re.compile(
    r'(?<!\be\.g)(?<!\bi\.e)(?<!\bvs)([.!?][*`)"]{0,3})\s+(?=[A-Z*`(\[])'
)

# Rule regex, case-insensitive (plan Global Constraints).
_RULE_REGEX = re.compile(
    r"\b(never|must|do not|don't|required|refuse[sd]?|HOLD|always|prefer|avoid|verify|only)\b",
    re.IGNORECASE,
)

# Pointer form: "read `ai-config/docs/knowledge/<file>.md` § `<heading>`".
_POINTER_RE = re.compile(
    r"read `ai-config/docs/knowledge/(dotfiles-[a-z0-9-]+\.md)` § `([^`]+)`"
)


class GitError(Exception):
    """git show failed; never treat a failed read as empty text."""


class MapError(Exception):
    """The relocation map, or a heading it names, could not be resolved."""


# --------------------------------------------------------------------------
# Reading the pre-change file
# --------------------------------------------------------------------------


def read_pre_file(rev: str, path: str = _TARGET_PATH, cwd: Path | None = None) -> str:
    """Read `path` as it stood at `rev`, via `git show`, with the git
    repo-location variables stripped from the child environment."""
    env = dict(os.environ)
    for var in _GIT_ENV_STRIP:
        env.pop(var, None)
    result = subprocess.run(
        ["git", "show", f"{rev}:{path}"],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise GitError(
            f"git show {rev}:{path} failed (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    return result.stdout


# --------------------------------------------------------------------------
# The splitter: fenced code -> paragraphs -> top-level bullet items -> units
# --------------------------------------------------------------------------


def strip_fenced_code(text: str) -> str:
    return _FENCE_RE.sub("", text)


def split_paragraphs(text: str) -> list[str]:
    """Blank-line-delimited paragraphs, non-empty only."""
    return [p for p in re.split(r"\n[ \t]*\n", text) if p.strip()]


def is_heading_or_rule_only(paragraph: str) -> bool:
    """True when a paragraph is entirely one ATX heading or one horizontal
    rule -- neither is a unit, since a unit is prose, a list item, a table,
    or a fenced block (and fenced blocks are already stripped)."""
    stripped = paragraph.strip()
    if not stripped:
        return False
    return bool(_HEADING_ONLY_RE.fullmatch(stripped)) or bool(
        _HR_ONLY_RE.fullmatch(stripped)
    )


def split_bullet_items(paragraph: str) -> list[str]:
    """Split a paragraph into its top-level list items when its first line
    opens one. A continuation line (indented, or otherwise not itself a
    top-level marker) stays attached to the item above it. A paragraph that
    is not a list is returned whole, as a single-element list."""
    lines = paragraph.split("\n")
    if not lines or not _BULLET_MARKER_RE.match(lines[0]):
        return [paragraph]
    items: list[str] = []
    current: list[str] = []
    for line in lines:
        if _BULLET_MARKER_RE.match(line):
            if current:
                items.append("\n".join(current))
            current = [line]
        else:
            current.append(line)
    if current:
        items.append("\n".join(current))
    return items


def extract_units(text: str) -> list[str]:
    """The full pinned splitter: strip fenced code, split into blank-line
    paragraphs, drop heading-only/rule-only paragraphs, then split each
    remaining paragraph into its top-level list items (or keep it whole)."""
    units: list[str] = []
    for raw_para in split_paragraphs(strip_fenced_code(text)):
        para = raw_para.strip("\n")
        if is_heading_or_rule_only(para):
            continue
        for item in split_bullet_items(para):
            item = item.strip()
            if item:
                units.append(item)
    return units


def split_sentences(normalized_text: str) -> list[str]:
    """Split an already-normalised unit's text into sentences at the pinned
    boundary regex. The sentence ends after its punctuation and any closing
    markup; the following whitespace is discarded, never counted into
    either sentence."""
    sentences: list[str] = []
    start = 0
    for match in _SENTENCE_BOUNDARY_RE.finditer(normalized_text):
        end_of_sentence = match.end(1)
        piece = normalized_text[start:end_of_sentence].strip()
        if piece:
            sentences.append(piece)
        start = match.end()
    tail = normalized_text[start:].strip()
    if tail:
        sentences.append(tail)
    return sentences


def anchor_of(unit: str) -> str:
    """The first 60 characters of a unit's normalised text -- the anchor
    form INLINE and MOVE records use. Matching against it is by prefix."""
    return normalize(unit)[:60]


# --------------------------------------------------------------------------
# Heading spans
# --------------------------------------------------------------------------


def find_heading_span(lines: list[str], heading_text: str) -> tuple[int, int, int]:
    """Return (start, end, level) for the section opened by the line that
    equals heading_text exactly, after stripping. `end` is exclusive and is
    the index of the next heading whose level is <= this one's, or len(lines)."""
    target = heading_text.strip()
    start = None
    level = None
    for index, raw_line in enumerate(lines):
        line = raw_line.rstrip("\n")
        if line.strip() != target:
            continue
        match = _HEADING_LINE_RE.match(line.strip())
        if match:
            start = index
            level = len(match.group(1))
            break
    if start is None or level is None:
        raise MapError(f"heading not found: {heading_text!r}")
    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index].rstrip("\n")
        match = _HEADING_LINE_RE.match(line.strip())
        if match and len(match.group(1)) <= level:
            end = index
            break
    return start, end, level


def section_substring(lines: list[str], span: tuple[int, int]) -> str:
    start, end = span
    return "".join(lines[start:end])


def build_non_moving_text(lines: list[str], spans: list[tuple[int, int]]) -> str:
    """The pre-file with every moving-section span removed, with a blank
    line inserted at each cut so paragraphs on either side never merge."""
    pieces: list[str] = []
    prev_end = 0
    for start, end in sorted(spans):
        pieces.append("".join(lines[prev_end:start]))
        prev_end = end
    pieces.append("".join(lines[prev_end:]))
    return "\n\n".join(pieces)


# --------------------------------------------------------------------------
# Map format
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class MoveRecord:
    anchor: str  # normalised, first 60 chars
    dest_file: str
    dest_heading: str  # heading text, no leading "### "


@dataclass
class MapData:
    section_headings: list[str] = field(default_factory=list)
    inline_anchors: list[str] = field(default_factory=list)
    waive_sentences: set[str] = field(default_factory=set)
    move_records: list[MoveRecord] = field(default_factory=list)


_MAP_FENCE_RE = re.compile(r"```relocation-map\n(.*?)```", re.DOTALL)


def parse_map(path: Path) -> MapData:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise MapError(f"cannot read map {path}: {exc}") from exc
    fence = _MAP_FENCE_RE.search(text)
    if not fence:
        raise MapError(f"no ```relocation-map fenced block found in {path}")
    data = MapData()
    for line_no, raw_line in enumerate(fence.group(1).splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = [f.strip() for f in line.split(" | ")]
        kind = fields[0].upper()
        if kind == "SECTION":
            if len(fields) != 2 or not fields[1]:
                raise MapError(f"map:{line_no}: SECTION needs 1 field: {line!r}")
            data.section_headings.append(fields[1])
        elif kind == "INLINE":
            if len(fields) != 2 or not fields[1]:
                raise MapError(f"map:{line_no}: INLINE needs 1 field: {line!r}")
            data.inline_anchors.append(normalize(fields[1]))
        elif kind == "WAIVE":
            if len(fields) != 3 or not fields[1]:
                raise MapError(f"map:{line_no}: WAIVE needs 2 fields: {line!r}")
            data.waive_sentences.add(normalize(fields[1]))
        elif kind == "MOVE":
            if len(fields) != 4 or not fields[1] or not fields[2] or not fields[3]:
                raise MapError(f"map:{line_no}: MOVE needs 3 fields: {line!r}")
            data.move_records.append(
                MoveRecord(normalize(fields[1]), fields[2], fields[3])
            )
        else:
            raise MapError(f"map:{line_no}: unknown record type {fields[0]!r}")
    return data


# --------------------------------------------------------------------------
# Section analysis (feeds measure's counts and check3's floor)
# --------------------------------------------------------------------------


@dataclass
class SectionAnalysis:
    units: list[str]  # non-inline units within moving sections
    inline_units: list[str]  # INLINE-matched units within moving sections
    retained_sentences: list[str]  # rule sentences that must survive in post


def analyze_sections(
    lines: list[str],
    spans: list[tuple[int, int]],
    inline_anchors: list[str],
    waive_sentences: set[str],
) -> SectionAnalysis:
    units: list[str] = []
    inline_units: list[str] = []
    retained_sentences: list[str] = []
    for span in spans:
        for unit in extract_units(section_substring(lines, span)):
            norm = normalize(unit)
            if any(anchor and norm.startswith(anchor) for anchor in inline_anchors):
                inline_units.append(unit)
                continue
            units.append(unit)
            for sentence in split_sentences(norm):
                if _RULE_REGEX.search(sentence) and sentence not in waive_sentences:
                    retained_sentences.append(sentence)
    return SectionAnalysis(units, inline_units, retained_sentences)


def non_moving_bytes_for(lines: list[str], spans: list[tuple[int, int]]) -> int:
    text = build_non_moving_text(lines, spans)
    return sum(len(unit.encode("utf-8")) for unit in extract_units(text))


def compute_floor(non_moving_bytes: int, analysis: SectionAnalysis) -> int:
    """Floor = non-moving units, plus INLINE units, plus retained rule
    sentences, counted once -- a retained sentence inside an INLINE unit is
    never added twice, because analyze_sections never puts an INLINE unit's
    sentences into retained_sentences in the first place."""
    inline_bytes = sum(len(u.encode("utf-8")) for u in analysis.inline_units)
    sentence_bytes = sum(len(s.encode("utf-8")) for s in analysis.retained_sentences)
    return non_moving_bytes + inline_bytes + sentence_bytes


def resolve_spans(
    lines: list[str], section_headings: list[str]
) -> list[tuple[int, int]]:
    return [find_heading_span(lines, heading)[:2] for heading in section_headings]


# --------------------------------------------------------------------------
# check 1-4
# --------------------------------------------------------------------------


def _read_dest_texts(dest_dir: Path) -> dict[str, str]:
    return {
        p.name: p.read_text(encoding="utf-8")
        for p in sorted(dest_dir.glob("dotfiles-*.md"))
    }


def run_check(
    pre_text: str,
    post_text: str,
    dest_dir: Path,
    map_data: MapData,
    min_relocated: int = 60_000,
    slack: int = 8_000,
) -> list[tuple[int, bool, str]]:
    """Run checks 1-4 and return (check_number, passed, detail) triples, one
    per check, in order. Raises MapError if a SECTION heading named in the
    map cannot be found in the pre-file -- that is a broken map, not a
    check failure."""
    lines = pre_text.splitlines(keepends=True)
    spans = resolve_spans(lines, map_data.section_headings)

    pre_units = extract_units(pre_text)
    post_norm = normalize(post_text)
    dest_texts = _read_dest_texts(dest_dir)
    dest_norm_all = normalize("\n".join(dest_texts.values()))

    # CHECK 1: nothing lost from the destination.
    lost: list[str] = []
    relocated: list[str] = []
    for unit in pre_units:
        norm = normalize(unit)
        if norm in post_norm:
            continue
        if norm in dest_norm_all:
            relocated.append(unit)
        else:
            lost.append(unit)
    check1_ok = not lost
    check1_detail = (
        ""
        if check1_ok
        else "unit missing from post and dest: "
        + "; ".join(u[:80].replace("\n", " ") for u in lost[:5])
    )

    # Sections analysis, shared by check 2 and the check-3 floor.
    analysis = analyze_sections(
        lines, spans, map_data.inline_anchors, map_data.waive_sentences
    )

    # CHECK 2: retained rule sentences.
    missing_sentences = [
        s for s in analysis.retained_sentences if s not in post_norm
    ]
    check2_ok = not missing_sentences
    check2_detail = (
        ""
        if check2_ok
        else "rule sentence not retained in post: "
        + "; ".join(s[:80] for s in missing_sentences[:5])
    )

    # CHECK 3: non-zero and size.
    relocated_bytes = sum(len(u.encode("utf-8")) for u in relocated)
    floor = compute_floor(non_moving_bytes_for(lines, spans), analysis)
    post_bytes = len(post_text.encode("utf-8"))
    reasons: list[str] = []
    if len(relocated) == 0:
        reasons.append("no relocated units")
    if relocated_bytes < min_relocated:
        reasons.append(f"relocated bytes {relocated_bytes} < min {min_relocated}")
    if post_bytes > floor + slack:
        reasons.append(f"post bytes {post_bytes} > floor {floor} + slack {slack}")
    check3_ok = not reasons
    check3_detail = "; ".join(reasons)

    # CHECK 4: every pointer resolves, and every MOVE landed under its heading.
    check4_errors: list[str] = []
    for match in _POINTER_RE.finditer(post_text):
        file_name, heading_text = match.group(1), match.group(2).strip()
        dest_path = dest_dir / file_name
        if not dest_path.is_file():
            check4_errors.append(f"pointer names missing file {file_name}")
            continue
        content = dest_texts.get(file_name, "")
        occurrences = sum(
            1 for line in content.splitlines() if line.strip() == f"### {heading_text}"
        )
        if occurrences == 0:
            check4_errors.append(
                f"pointer heading not found: {file_name} § {heading_text}"
            )
        elif occurrences > 1:
            check4_errors.append(
                f"pointer heading duplicated {occurrences}x: "
                f"{file_name} § {heading_text}"
            )
    for move in map_data.move_records:
        target = next(
            (u for u in pre_units if normalize(u).startswith(move.anchor)), None
        )
        if target is None:
            check4_errors.append(f"MOVE anchor not found in pre-file: {move.anchor!r}")
            continue
        target_norm = normalize(target)
        if target_norm in post_norm:
            check4_errors.append(f"MOVE unit still present in post: {move.anchor!r}")
            continue
        dest_path = dest_dir / move.dest_file
        if not dest_path.is_file():
            check4_errors.append(f"MOVE dest file missing: {move.dest_file}")
            continue
        dest_content = dest_texts.get(move.dest_file, "")
        dest_lines = dest_content.splitlines(keepends=True)
        try:
            hstart, hend, _level = find_heading_span(
                dest_lines, f"### {move.dest_heading}"
            )
        except MapError:
            check4_errors.append(
                f"MOVE dest heading missing: {move.dest_file} § {move.dest_heading}"
            )
            continue
        heading_section = "".join(dest_lines[hstart:hend])
        if target_norm not in normalize(heading_section):
            check4_errors.append(
                f"MOVE unit not found under heading: "
                f"{move.dest_file} § {move.dest_heading}"
            )
    check4_ok = not check4_errors
    check4_detail = "; ".join(check4_errors[:5])

    return [
        (1, check1_ok, check1_detail),
        (2, check2_ok, check2_detail),
        (3, check3_ok, check3_detail),
        (4, check4_ok, check4_detail),
    ]


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="relocation_check.py")
    sub = parser.add_subparsers(dest="command", required=True)

    measure_p = sub.add_parser("measure")
    measure_p.add_argument("--pre-rev", required=True)
    measure_p.add_argument("--map", required=True, type=Path)

    check_p = sub.add_parser("check")
    check_p.add_argument("--pre-rev", required=True)
    check_p.add_argument("--post", required=True, type=Path)
    check_p.add_argument("--dest", required=True, type=Path)
    check_p.add_argument("--map", required=True, type=Path)
    check_p.add_argument("--min-relocated", type=int, default=60_000)
    check_p.add_argument("--slack", type=int, default=8_000)

    return parser


def run(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        pre_text = read_pre_file(args.pre_rev)
    except GitError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    try:
        map_data = parse_map(args.map)
    except MapError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.command == "measure":
        try:
            lines = pre_text.splitlines(keepends=True)
            spans = resolve_spans(lines, map_data.section_headings)
            analysis = analyze_sections(
                lines, spans, map_data.inline_anchors, map_data.waive_sentences
            )
            floor = compute_floor(non_moving_bytes_for(lines, spans), analysis)
        except MapError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        rule_bytes = sum(len(s.encode("utf-8")) for s in analysis.retained_sentences)
        print(
            f"units={len(analysis.units)} "
            f"rule_sentences={len(analysis.retained_sentences)} "
            f"rule_bytes={rule_bytes} floor={floor}"
        )
        return 0

    # args.command == "check"
    post_text = args.post.read_text(encoding="utf-8")
    try:
        results = run_check(
            pre_text, post_text, args.dest, map_data, args.min_relocated, args.slack
        )
    except MapError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    all_ok = True
    for number, ok, detail in results:
        if ok:
            print(f"CHECK{number} PASS")
        else:
            all_ok = False
            print(f"CHECK{number} FAIL {detail}" if detail else f"CHECK{number} FAIL")
    return 0 if all_ok else 1


def main() -> None:
    sys.exit(run(sys.argv[1:]))


if __name__ == "__main__":
    main()
