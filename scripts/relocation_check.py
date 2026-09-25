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
_FENCE_LINE_RE = re.compile(r"^```")

# The pinned splitter (plan Global Constraints). Python rejects a
# variable-width lookbehind, so this is a boundary match consumed via
# finditer, never a re.split lookbehind. Capturing group 1 isolates the
# punctuation and any closing markup so the sentence boundary lands after
# it and before the whitespace that follows.
# Lookahead includes 0-9 per the plan's amended pinned constant; otherwise
# these are the same boundaries as the originally pinned string.
_SENTENCE_BOUNDARY_RE = re.compile(
    r'(?<!\be\.g)(?<!\bi\.e)(?<!\bvs)([.!?][*`)"]{0,3})\s+(?=[A-Z0-9*`(\[])'
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
    """Split a paragraph at every top-level list-item marker, wherever it
    appears -- not only when the paragraph opens with one. Fence-stripping
    can recombine text that was never meant to share a unit with a bullet
    that follows it (a fence inside a list item, once removed, can rejoin
    its trailing prose with the next line into one blank-line paragraph
    whose first line is that prose, not a marker); a leading chunk before
    the first marker becomes its own unit rather than swallowing the
    bullet after it. A continuation line (indented, or otherwise not
    itself a top-level marker) stays attached to the item above it. A
    paragraph with no marker at all is returned whole, as a single unit."""
    lines = paragraph.split("\n")
    if not any(_BULLET_MARKER_RE.match(line) for line in lines):
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


# --------------------------------------------------------------------------
# Heading spans
# --------------------------------------------------------------------------


def _fence_mask(lines: list[str]) -> list[bool]:
    """True for every line inside, opening, or closing a fenced code block,
    so heading detection can skip a heading-shaped line a fence hides --
    e.g. a `# comment` inside a ```bash block, which is not a real heading."""
    mask = [False] * len(lines)
    in_fence = False
    for index, raw_line in enumerate(lines):
        if _FENCE_LINE_RE.match(raw_line.rstrip("\n").strip()):
            mask[index] = True
            in_fence = not in_fence
            continue
        mask[index] = in_fence
    return mask


def find_heading_span(lines: list[str], heading_text: str) -> tuple[int, int, int]:
    """Return (start, end, level) for the BODY of the heading that equals
    heading_text exactly, after stripping. `end` is exclusive and is the
    index of the very next heading line of ANY level (`^#{1,6} `), or
    len(lines) -- a span never crosses into a subsection, so nesting two
    SECTION entries can never overlap and there is nothing to merge.
    Lines inside fenced code are never read as headings, in either search."""
    target = heading_text.strip()
    fenced = _fence_mask(lines)
    start = None
    level = None
    for index, raw_line in enumerate(lines):
        if fenced[index]:
            continue
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
        if fenced[index]:
            continue
        line = lines[index].rstrip("\n")
        if _HEADING_LINE_RE.match(line.strip()):
            end = index
            break
    return start, end, level


def section_substring(lines: list[str], span: tuple[int, int]) -> str:
    start, end = span
    return "".join(lines[start:end])


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
        # A unit's anchor or a waived sentence can itself contain " | " --
        # a markdown table row's normalised text starts with "| ...", and
        # prose can quote a literal pipe. Splitting the whole line on every
        # " | " would shred that content into extra fields. Instead, peel
        # off only the record-type tag with a single left split, then
        # parse the remainder structurally: SECTION/INLINE take it whole
        # (their one field IS the remainder, pipes and all); MOVE/WAIVE
        # peel their trailing, pipe-free fields off the RIGHT with rsplit,
        # leaving anything left over -- including embedded " | " -- as the
        # anchor or sentence.
        tag_split = line.split(" | ", 1)
        kind = tag_split[0].strip().upper()
        rest = tag_split[1] if len(tag_split) == 2 else ""
        if kind == "SECTION":
            heading = rest.strip()
            if not heading:
                raise MapError(f"map:{line_no}: SECTION needs 1 field: {line!r}")
            if heading in data.section_headings:
                raise MapError(
                    f"map:{line_no}: duplicate SECTION heading: {heading!r}"
                )
            data.section_headings.append(heading)
        elif kind == "INLINE":
            anchor = rest.strip()
            if not anchor:
                raise MapError(f"map:{line_no}: INLINE needs 1 field: {line!r}")
            data.inline_anchors.append(normalize(anchor))
        elif kind == "WAIVE":
            parts = rest.rsplit(" | ", 1)
            if len(parts) != 2 or not parts[0].strip() or not parts[1].strip():
                raise MapError(f"map:{line_no}: WAIVE needs 2 fields: {line!r}")
            sentence, _reason = parts
            data.waive_sentences.add(normalize(sentence.strip()))
        elif kind == "MOVE":
            parts = rest.rsplit(" | ", 2)
            if len(parts) != 3 or not all(p.strip() for p in parts):
                raise MapError(f"map:{line_no}: MOVE needs 3 fields: {line!r}")
            anchor, dest_file, dest_heading = (p.strip() for p in parts)
            data.move_records.append(
                MoveRecord(normalize(anchor), dest_file, dest_heading)
            )
        else:
            raise MapError(f"map:{line_no}: unknown record type {tag_split[0]!r}")
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
    """Raw whole-file bytes outside every moving-section span -- headings,
    fenced code, and blank lines all count, matching how the post file's
    own byte count is measured (`wc -c`, i.e. `len(text.encode())`). Using
    extract_units() here instead would drop exactly the structure the post
    file still has to carry, undercounting the floor by every heading and
    fenced block in the unmoved text."""
    excluded_indexes = {i for start, end in spans for i in range(start, end)}
    return sum(
        len(line.encode("utf-8"))
        for i, line in enumerate(lines)
        if i not in excluded_indexes
    )


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


def find_completeness_errors(
    lines: list[str],
    spans: list[tuple[int, int]],
    inline_anchors: list[str],
    move_records: list[MoveRecord],
) -> list[str]:
    """Every unit inside a SECTION span must be claimed by exactly one
    INLINE or MOVE record -- one saying it stays whole, the other saying
    where it goes. A unit claimed by neither is ambiguous: nothing in the
    map says what happens to it, and today's code silently treated that as
    "stays, but only its rule sentences are retained", which is a decision
    nobody made. A unit claimed by two or more is contradictory. Returns
    one message per offending unit, naming its anchor, in map order."""
    errors: list[str] = []
    move_anchors = [move.anchor for move in move_records]
    for span in spans:
        for unit in extract_units(section_substring(lines, span)):
            norm = normalize(unit)
            match_count = sum(
                1 for anchor in inline_anchors if anchor and norm.startswith(anchor)
            ) + sum(1 for anchor in move_anchors if anchor and norm.startswith(anchor))
            if match_count == 0:
                errors.append(f"no INLINE/MOVE record matches unit: {norm[:60]!r}")
            elif match_count > 1:
                errors.append(
                    f"{match_count} INLINE/MOVE records match unit: {norm[:60]!r}"
                )
    return errors


# --------------------------------------------------------------------------
# check 1-4
# --------------------------------------------------------------------------


def _read_dest_texts(dest_dir: Path) -> dict[str, str]:
    return {
        p.name: p.read_text(encoding="utf-8")
        for p in sorted(dest_dir.glob("dotfiles-*.md"))
    }


_SHORT_UNIT_MAX_LEN = 40


def _unit_present(unit: str, norm: str, raw_text: str, norm_blob: str) -> bool:
    """Is a unit's normalised text present in a target? A unit shorter than
    _SHORT_UNIT_MAX_LEN normalised characters, with no embedded newline in
    its own (pre-normalised) text, counts as present only if it equals a
    WHOLE, stripped, normalised line of the target -- a short string is
    generic enough to turn up as a coincidental embedded substring of an
    unrelated line, and normalize() alone does not strip a line's leading
    or trailing whitespace (it collapses a run to one space, it does not
    remove it), so an indented copy would otherwise be missed.

    A unit that originally spans more than one physical line can still
    normalise to something short once its internal newline collapses to a
    space, but no single target line can ever equal a multi-line-collapsed
    string -- so that case, and every longer unit, keeps substring matching
    against the flattened, whitespace-normalised blob (norm_blob), since a
    real multi-sentence block can be re-wrapped across different line
    breaks in its destination."""
    if len(norm) < _SHORT_UNIT_MAX_LEN and "\n" not in unit:
        target_lines_norm = {normalize(line).strip() for line in raw_text.splitlines()}
        return norm in target_lines_norm
    return norm in norm_blob


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
    dest_text_all = "\n".join(dest_texts.values())
    dest_norm_all = normalize(dest_text_all)

    # CHECK 1: nothing lost from the destination.
    lost: list[str] = []
    relocated: list[str] = []
    for unit in pre_units:
        norm = normalize(unit)
        if _unit_present(unit, norm, post_text, post_norm):
            continue
        if _unit_present(unit, norm, dest_text_all, dest_norm_all):
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
    reasons.extend(
        find_completeness_errors(
            lines, spans, map_data.inline_anchors, map_data.move_records
        )
    )
    check3_ok = not reasons
    check3_detail = "; ".join(reasons)

    # CHECK 4: every pointer resolves, and every MOVE landed under its heading.
    check4_errors: list[str] = []
    pointer_matches = list(_POINTER_RE.finditer(post_text))
    if relocated and not pointer_matches:
        check4_errors.append(
            f"relocated units present (n={len(relocated)}) but "
            f"pointer count={len(pointer_matches)} in post"
        )
    for match in pointer_matches:
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
            completeness_errors = find_completeness_errors(
                lines, spans, map_data.inline_anchors, map_data.move_records
            )
        except MapError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        rule_bytes = sum(len(s.encode("utf-8")) for s in analysis.retained_sentences)
        print(
            f"units={len(analysis.units)} "
            f"rule_sentences={len(analysis.retained_sentences)} "
            f"rule_bytes={rule_bytes} floor={floor}"
        )
        if completeness_errors:
            for error in completeness_errors:
                print(f"error: {error}", file=sys.stderr)
            return 1
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
