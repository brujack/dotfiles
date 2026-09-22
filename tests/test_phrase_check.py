"""Tests for scripts/phrase_check.py.

Loaded by path (the script is not a package) — same pattern as test_triage_log.py.
"""

import contextlib
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from hypothesis import given
from hypothesis import strategies as st

_REPO = Path(__file__).resolve().parent.parent
_MODULE = _REPO / "scripts" / "phrase_check.py"


def _load():
    # Bypass the bytecode cache. SourceFileLoader validates a cached .pyc on
    # mtime plus size, so two mutants that change the file by the same number
    # of bytes within one mtime second are indistinguishable to it: the second
    # runs against the first's cached module and silently inherits its verdict.
    # Reproduced on Python 3.14.6 -- a same-size edit with mtime restored
    # served stale bytecode and the change was invisible, which would make
    # every mutation test of this module report on the wrong source.
    sys.dont_write_bytecode = True
    for stale in (_MODULE.parent / "__pycache__").glob(f"{_MODULE.stem}.*.pyc"):
        stale.unlink()
    spec = importlib.util.spec_from_file_location("phrase_check", _MODULE)
    # Not an assert: python -O strips asserts, and this one is the only thing
    # standing between a bad module path and an opaque AttributeError far away
    # from the cause. bandit flags the assert form as B101 for that reason.
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load phrase_check from {_MODULE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["phrase_check"] = module
    spec.loader.exec_module(module)
    return module


_PC = _load()


def _run_and_capture(argv: list[str]) -> tuple[int, str]:
    """Run main() and return (rc, combined stdout+stderr) regardless of which
    stream the tool writes its informational output to."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = _PC.main(argv)
    return rc, out.getvalue() + err.getvalue()


class PhraseCheckTestCase(unittest.TestCase):
    """Base class that gives every test its own scratch directory."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp_path = Path(self._tmp.name)

    def _write(self, name: str, content: str) -> Path:
        path = self.tmp_path / name
        path.write_text(content, encoding="utf-8")
        return path

    def _write_manifest(self, name: str, rows: list[str]) -> Path:
        return self._write(name, "\n".join(rows) + "\n")


class TestNormalize(unittest.TestCase):
    def test_collapses_a_newline_to_a_single_space(self):
        self.assertEqual(
            _PC.normalize("wraps across\na line boundary"),
            "wraps across a line boundary",
        )

    def test_collapses_a_run_of_mixed_whitespace(self):
        self.assertEqual(_PC.normalize("a   \t\n  b"), "a b")

    def test_empty_string_stays_empty(self):
        self.assertEqual(_PC.normalize(""), "")

    @given(st.text())
    def test_is_idempotent(self, s):
        once = _PC.normalize(s)
        twice = _PC.normalize(once)
        self.assertEqual(once, twice)


class TestParagraphPrefixArmHandlesIndentedParagraphs(PhraseCheckTestCase):
    """The paragraph-prefix arm must fire for a paragraph that begins indented.

    normalize() collapses a run of whitespace to a single space but does not
    strip it, so an indented paragraph's stored norm starts with that space
    and `para.startswith(phrase)` never matches. The arm then fails OPEN --
    a fragile paragraph-initial phrase is certified safe.

    Every case here gives the PREVIOUS block no sentence-ending punctuation,
    so the punctuation arm cannot fire and only the prefix arm can. A fixture
    whose previous paragraph ends in '.' passes either way and discriminates
    nothing.
    """

    def test_indented_paragraph_start_is_sentence_initial(self):
        for name, indent in (("two spaces", "  "), ("a tab", "\t"), ("none", "")):
            with self.subTest(indent=name):
                source = f"The rules are:\n\n{indent}Delta epsilon zeta here."
                norms = _PC.paragraph_start_norms(source)
                count, initial = _PC.match_phrase(
                    _PC.normalize(source), "Delta epsilon zeta here.", norms
                )
                self.assertEqual(count, 1)
                self.assertTrue(initial)

    def test_a_genuinely_mid_paragraph_phrase_is_not_flagged(self):
        source = "The rules are:\n\n  Delta epsilon zeta here."
        norms = _PC.paragraph_start_norms(source)
        count, initial = _PC.match_phrase(_PC.normalize(source), "epsilon zeta here.", norms)
        self.assertEqual(count, 1)
        self.assertFalse(initial)


class TestParagraphPrefixArmSeesThroughProseMarkers(PhraseCheckTestCase):
    """A phrase opening a paragraph behind a prose marker is still paragraph-initial.

    The prefix arm compares against the paragraph's normalised text, so a
    leading `- `, `> `, `1. ` or `### ` sits between the marker and the
    phrase and `startswith()` cannot match. The arm then fails OPEN for the
    exact case it exists to catch: a bullet's first word carries the same
    position-dependent capital a sentence's first word does.

    Every fixture ends the previous block without sentence-ending
    punctuation, so the punctuation arm cannot fire and only the prefix arm
    discriminates.
    """

    def test_phrase_opening_a_paragraph_behind_a_prose_marker_is_initial(self):
        for name, marker in (
            ("dash bullet", "- "),
            ("star bullet", "* "),
            ("plus bullet", "+ "),
            ("blockquote", "> "),
            ("ordered dot", "1. "),
            ("ordered paren", "2) "),
            ("heading", "### "),
        ):
            with self.subTest(marker=name):
                source = f"The rules are:\n\n{marker}Delta epsilon zeta here."
                norms = _PC.paragraph_start_norms(source)
                count, initial = _PC.match_phrase(
                    _PC.normalize(source), "Delta epsilon zeta here.", norms
                )
                self.assertEqual(count, 1)
                self.assertTrue(initial)

    def test_a_fenced_code_line_is_NOT_treated_as_paragraph_initial(self):
        """Deliberate exclusion, pinned so nobody "completes" the marker list.

        The rule rejects a phrase whose leading capital is a function of its
        POSITION. A line inside a fence has its case fixed by the shell --
        `make`, `./setup_env.sh`, `grep -A1` are lowercase wherever they
        appear -- so the rationale does not reach it. Measured 2026-09-22
        against this repo's own manifest: stripping fences alongside prose
        markers turns 10 correctly-anchored rows RED and 3 genuinely
        fragile ones, so the wider rule is 4x the hazard and mostly wrong.
        """
        source = "The command is:\n\n```bash\nmake validate-plan PLAN=x\n```"
        norms = _PC.paragraph_start_norms(source)
        count, initial = _PC.match_phrase(
            _PC.normalize(source), "make validate-plan PLAN=x", norms
        )
        self.assertEqual(count, 1)
        self.assertFalse(initial)

    def test_a_mid_bullet_phrase_is_not_flagged(self):
        source = "The rules are:\n\n- Delta epsilon zeta here."
        norms = _PC.paragraph_start_norms(source)
        count, initial = _PC.match_phrase(
            _PC.normalize(source), "epsilon zeta here.", norms
        )
        self.assertEqual(count, 1)
        self.assertFalse(initial)


class TestNoCheckRequestedIsAnError(PhraseCheckTestCase):
    """A manifest-only invocation must not report success having checked nothing.

    The `ran_any` guard is the sibling of the --survives zero-row guard: both
    exist so the tool cannot run, examine nothing, and exit 0. Mutation
    testing found this one pinned by no test at all.
    """

    def test_manifest_without_any_check_flag_errors(self):
        path = self._write_manifest("m.md", ["HAZARD | alpha beta gamma | - | - | n"])
        self.assertEqual(_PC.main(["--manifest", str(path)]), 2)


class TestManifestSplitsOnNewlineOnly(PhraseCheckTestCase):
    """A phrase carrying a Unicode line separator must stay one row.

    str.splitlines() breaks on VT, FF, FS, GS, RS, NEL, LS and PS as well as
    LF, so a phrase containing one is silently split into two rows and the
    phrase is truncated at the separator -- measured: 2 rows, phrase 'alpha'.
    No exception is raised, so the manifest parses and the truncated phrase
    then fails to match, or matches something it was never meant to.
    CLAUDE.md carries none of these today, so this is latent rather than live.
    """

    def test_a_unicode_line_separator_in_a_phrase_stays_one_row(self):
        for name, sep in (
            ("LS", "\u2028"),
            ("PS", "\u2029"),
            ("NEL", "\x85"),
            ("VT", "\x0b"),
            ("FF", "\x0c"),
            ("FS", "\x1c"),
            ("GS", "\x1d"),
            ("RS", "\x1e"),
        ):
            with self.subTest(separator=name):
                path = self._write_manifest(
                    f"sep-{name}.md",
                    [f"HAZARD | alpha{sep}beta gamma | - | - | note"],
                )
                rows = _PC.parse_manifest(path)
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0].phrase, f"alpha{sep}beta gamma")


class TestPhraseSpanningLineWrapIsFound(PhraseCheckTestCase):
    """RED test 1: the defect that retired grep -n."""

    def test_phrase_spanning_a_line_wrap_is_found(self):
        source = self._write(
            "source.md",
            "Intro text. This sentence wraps across\na line boundary here.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | wraps across a line boundary | | | note"],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertEqual(rc, 0)

    def test_grep_style_line_oriented_match_would_have_missed_it(self):
        # Sanity control: prove the fixture actually spans a real line boundary
        # in the raw (non-normalised) text, i.e. this is not a vacuous fixture.
        source_text = "Intro text. This sentence wraps across\na line boundary here."
        self.assertNotIn("wraps across a line boundary", source_text)
        self.assertIn("wraps across a line boundary", _PC.normalize(source_text))


class TestAssertComplete(PhraseCheckTestCase):
    """RED test 2: --assert-complete N exits non-zero below N."""

    def test_fails_when_row_count_is_below_n(self):
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | first phrase | | | note",
                "HAZARD | second phrase | | | note",
            ],
        )
        rc = _PC.main(["--manifest", str(manifest), "--assert-complete", "3"])
        self.assertNotEqual(rc, 0)

    def test_passes_when_row_count_meets_n(self):
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | first phrase | | | note",
                "HAZARD | second phrase | | | note",
                "HAZARD | third phrase | | | note",
            ],
        )
        rc = _PC.main(["--manifest", str(manifest), "--assert-complete", "3"])
        self.assertEqual(rc, 0)


class TestAssertCompleteDerived(PhraseCheckTestCase):
    """RED test 3: N is derived from --source, never a literal."""

    def test_derives_n_from_source_paragraph_count_and_passes(self):
        source = self._write(
            "source.md", "Paragraph one text here.\n\nParagraph two text here."
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | aragraph one text here | | | note",
                "HAZARD | aragraph two text here | | | note",
            ],
        )
        rc = _PC.main(
            [
                "--manifest",
                str(manifest),
                "--source",
                str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)

    def test_fails_when_manifest_has_fewer_rows_than_derived_paragraphs(self):
        source = self._write(
            "source.md", "Paragraph one text here.\n\nParagraph two text here."
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | paragraph one text here | | | note"]
        )
        rc = _PC.main(
            [
                "--manifest",
                str(manifest),
                "--source",
                str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertNotEqual(rc, 0)

    def test_a_different_source_with_a_different_paragraph_count_changes_the_verdict(
        self,
    ):
        # Proves derivation, not a hardcoded baseline: the same 2-row manifest
        # passes against a 2-paragraph source and fails against a 3-paragraph one.
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | aragraph one text here | | | note",
                "HAZARD | aragraph two text here | | | note",
            ],
        )
        two_para_source = self._write(
            "two.md", "Paragraph one text here.\n\nParagraph two text here."
        )
        three_para_source = self._write(
            "three.md",
            "Paragraph one text here.\n\nParagraph two text here.\n\nA third one.",
        )
        rc_two = _PC.main(
            [
                "--manifest",
                str(manifest),
                "--source",
                str(two_para_source),
                "--assert-complete-derived",
            ]
        )
        rc_three = _PC.main(
            [
                "--manifest",
                str(manifest),
                "--source",
                str(three_para_source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc_two, 0)
        self.assertNotEqual(rc_three, 0)


class TestAssertUnique(PhraseCheckTestCase):
    """RED test 4: --assert-unique rejects a phrase occurring more than once."""

    def test_rejects_a_phrase_occurring_twice(self):
        source = self._write(
            "source.md",
            "Note: the widget calibration steps matter "
            "and the widget calibration steps repeat.",
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | the widget calibration steps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_accepts_a_phrase_occurring_exactly_once(self):
        source = self._write(
            "source.md", "Note: the widget calibration steps matter today."
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | the widget calibration steps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertEqual(rc, 0)


class TestAssertUniqueSkipsDeleted(PhraseCheckTestCase):
    """A row marked deleted asserts its phrase is GONE, not present -- so
    --assert-unique must skip it rather than reporting the intended removal
    as a failure. A row merely marked withdrawn (text never removed) still
    keeps the ordinary uniqueness check."""

    def test_deleted_row_whose_phrase_is_absent_does_not_fail(self):
        source = self._write("source.md", "Nothing relevant is written here.")
        manifest = self._write_manifest(
            "phrases.md",
            ["RECORD-deleted | this phrase was removed from source | | | note"],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertEqual(rc, 0)

    def test_duplicate_deleted_row_whose_phrase_is_absent_does_not_fail(self):
        source = self._write("source.md", "Nothing relevant is written here.")
        manifest = self._write_manifest(
            "phrases.md",
            ["DUPLICATE-deleted | this phrase was removed too | | | note"],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertEqual(rc, 0)

    def test_a_non_deleted_row_is_still_checked_alongside_a_deleted_one(self):
        # The deleted row's absence must not mask a real uniqueness failure
        # on the row that survives.
        source = self._write(
            "source.md",
            "Note: the widget calibration steps matter and the widget "
            "calibration steps repeat.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "RECORD-deleted | this phrase was removed from source | | | note",
                "HAZARD | the widget calibration steps | | | note",
            ],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_withdrawn_row_is_not_skipped_and_still_fails_when_absent(self):
        # "withdrawn" means the text was never removed -- unlike "deleted",
        # is_deleted must not treat it as gone.
        source = self._write("source.md", "Nothing relevant is written here.")
        manifest = self._write_manifest(
            "phrases.md",
            ["RECORD-withdrawn | this phrase is supposed to still be there | | | note"],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)


class TestSentenceInitialPhraseRejected(PhraseCheckTestCase):
    """RED test 5: a phrase beginning at a sentence boundary is rejected."""

    def test_rejects_a_phrase_that_begins_a_sentence(self):
        source = self._write(
            "source.md",
            "Intro line stands alone. The quick brown fox jumps over lazy dogs.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | The quick brown fox jumps | | | note"],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_accepts_the_same_phrase_when_mid_sentence(self):
        source = self._write(
            "source.md",
            "Intro line says the quick brown fox jumps over lazy dogs.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | the quick brown fox jumps | | | note"],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertEqual(rc, 0)

    def test_the_very_start_of_the_source_counts_as_sentence_initial(self):
        source = self._write("source.md", "The quick brown fox jumps over lazy dogs.")
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | The quick brown fox jumps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)


class TestSentenceInitialAtParagraphStart(PhraseCheckTestCase):
    """A phrase that opens a paragraph is sentence-initial even though the
    character preceding it, in the whole-file-normalised haystack, is not
    one of '.'/'!'/'?' -- it's whatever ended the previous block (a
    heading's last letter, a code-fence backtick, a colon, a bullet dash),
    none of which is in _SENTENCE_END_CHARS. A later HAZARD remedy
    capitalises a sentence's leading word, and a paragraph's first word is
    the strongest case of that."""

    def test_phrase_opening_a_paragraph_after_a_heading_is_rejected(self):
        source = self._write(
            "source.md",
            "## Heading\n\nThe quick brown fox jumps over lazy dogs.",
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | The quick brown fox jumps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_phrase_opening_a_paragraph_after_a_fenced_code_block_is_rejected(self):
        source = self._write(
            "source.md",
            "```bash\necho hi\n```\n\nThe quick brown fox jumps over lazy dogs.",
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | The quick brown fox jumps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_phrase_opening_a_paragraph_after_a_colon_is_rejected(self):
        source = self._write(
            "source.md",
            "Intro says this:\n\nThe quick brown fox jumps over lazy dogs.",
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | The quick brown fox jumps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_phrase_opening_a_paragraph_after_a_bullet_dash_is_rejected(self):
        source = self._write(
            "source.md",
            "- a bullet point\n\nThe quick brown fox jumps over lazy dogs.",
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | The quick brown fox jumps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_phrase_not_opening_a_paragraph_is_still_accepted(self):
        # Positive control: a phrase that genuinely sits mid-paragraph,
        # even in a document that has a heading elsewhere, must still pass
        # -- this rule must not reject every phrase that merely follows a
        # heading somewhere in the file.
        source = self._write(
            "source.md",
            "## Heading\n\nIntro clause says the quick brown fox jumps over lazy dogs.",
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | the quick brown fox jumps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertEqual(rc, 0)


class TestSurvives(PhraseCheckTestCase):
    """RED test 6: --survives CLASS exits non-zero when a row of that class is gone."""

    def test_fails_when_a_hazard_row_no_longer_matches(self):
        source = self._write("source.md", "Nothing relevant is written here.")
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | this safety phrase must remain | | | note"]
        )
        rc = _PC.main(
            [
                "--manifest",
                str(manifest),
                "--source",
                str(source),
                "--survives",
                "HAZARD",
            ]
        )
        self.assertNotEqual(rc, 0)

    def test_passes_when_the_hazard_row_still_matches(self):
        source = self._write(
            "source.md", "Reminder: this safety phrase must remain in place."
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | this safety phrase must remain | | | note"]
        )
        rc = _PC.main(
            [
                "--manifest",
                str(manifest),
                "--source",
                str(source),
                "--survives",
                "HAZARD",
            ]
        )
        self.assertEqual(rc, 0)

    def test_ignores_rows_of_a_different_class(self):
        # A DUPLICATE row missing entirely from source must not fail a HAZARD survival check.
        source = self._write(
            "source.md", "Reminder: this safety phrase must remain in place."
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | this safety phrase must remain | | | note",
                "DUPLICATE | a phrase that is nowhere in source | | | note",
            ],
        )
        rc = _PC.main(
            [
                "--manifest",
                str(manifest),
                "--source",
                str(source),
                "--survives",
                "HAZARD",
            ]
        )
        self.assertEqual(rc, 0)


class TestSurvivesZeroRowsIsAnError(PhraseCheckTestCase):
    """--survives CLASS must fail when the manifest carries zero rows of
    that class, rather than passing having examined nothing. check_survives
    filtered with exact string equality and no zero-row guard, so a
    mistyped, wrong-case, trailing-space, or later-renamed class name
    silently checked nothing and reported clean."""

    def test_fails_when_no_row_carries_the_named_class(self):
        source = self._write("source.md", "Alpha beta gamma delta epsilon here.")
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | THIS TEXT IS NOT IN THE SOURCE AT ALL | - | - | n"],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--survives", "NOSUCHCLASS",
            ]
        )
        self.assertNotEqual(rc, 0)
        self.assertIn("NOSUCHCLASS", combined)

    def test_fails_on_a_lowercase_typo_of_an_existing_class(self):
        source = self._write("source.md", "Alpha beta gamma delta epsilon here.")
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | THIS TEXT IS NOT IN THE SOURCE AT ALL | - | - | n"],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--survives", "hazard",
            ]
        )
        self.assertNotEqual(rc, 0)
        self.assertIn("hazard", combined)

    def test_fails_on_a_trailing_space_variant_of_an_existing_class(self):
        source = self._write("source.md", "Alpha beta gamma delta epsilon here.")
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | THIS TEXT IS NOT IN THE SOURCE AT ALL | - | - | n"],
        )
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--survives", "HAZARD ",
            ]
        )
        self.assertNotEqual(rc, 0)

    def test_still_fails_normally_when_the_class_exists_and_the_row_is_gone(self):
        # Positive control: an existing class whose only row genuinely
        # fails must still report the real per-row failure -- the zero-row
        # guard must not swallow or replace it.
        source = self._write("source.md", "Alpha beta gamma delta epsilon here.")
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | THIS TEXT IS NOT IN THE SOURCE AT ALL | - | - | n"],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--survives", "HAZARD",
            ]
        )
        self.assertNotEqual(rc, 0)
        self.assertIn("phrase no longer found", combined)

    def test_passes_when_the_class_exists_and_every_row_survives(self):
        # Positive control: an existing class whose row genuinely survives
        # must still pass -- the zero-row guard must not fire when rows
        # were actually examined.
        source = self._write(
            "source.md", "Reminder: this safety phrase must remain in place."
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | this safety phrase must remain | | | note"]
        )
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--survives", "HAZARD",
            ]
        )
        self.assertEqual(rc, 0)


class TestDeletedHaveCounterparts(PhraseCheckTestCase):
    """RED test 7: a deleted row must have its phrase in its counterpart-file."""

    def test_fails_when_the_counterpart_file_lacks_the_phrase(self):
        counterpart = self._write("shell.md", "Some unrelated content entirely.")
        manifest = self._write_manifest(
            "phrases.md",
            [
                f"DUPLICATE-deleted | some duplicated phrase text | {counterpart} | | note"
            ],
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertNotEqual(rc, 0)

    def test_passes_when_the_counterpart_file_has_the_phrase(self):
        counterpart = self._write(
            "shell.md", "Elsewhere: some duplicated phrase text lives here too."
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                f"DUPLICATE-deleted | some duplicated phrase text | {counterpart} | | note"
            ],
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertEqual(rc, 0)

    def test_ignores_rows_not_marked_deleted(self):
        # A HAZARD row with no counterpart-file at all must not trip this check.
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | never appears anywhere | | | note"]
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertEqual(rc, 0)

    def test_fails_when_a_deleted_row_has_no_counterpart_file_named(self):
        manifest = self._write_manifest(
            "phrases.md", ["DUPLICATE-deleted | some phrase | | | note"]
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertNotEqual(rc, 0)

    def test_fails_when_a_duplicate_deleted_row_names_dash_as_counterpart(self):
        # DUPLICATE asserts the text lives elsewhere; '-' names no elsewhere.
        manifest = self._write_manifest(
            "phrases.md", ["DUPLICATE-deleted | some phrase | - | | note"]
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertNotEqual(rc, 0)

    def test_passes_when_a_record_deleted_row_names_dash_as_counterpart(self):
        # RECORD asserts git history holds provenance -- no counterpart to check.
        manifest = self._write_manifest(
            "phrases.md",
            ["RECORD-deleted | some phrase never verified | - | | note"],
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertEqual(rc, 0)

    def test_passes_when_a_record_deleted_row_names_a_counterpart_with_the_phrase(
        self,
    ):
        # A RECORD row that DOES name a counterpart is a claim, and a claim
        # gets checked whatever the class.
        counterpart = self._write(
            "tdd.md", "Provenance for the deleted record phrase lives here."
        )
        manifest = self._write_manifest(
            "phrases.md",
            [f"RECORD-deleted | the deleted record phrase | {counterpart} | | note"],
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertEqual(rc, 0)

    def test_fails_when_a_record_deleted_row_names_a_counterpart_missing_the_phrase(
        self,
    ):
        counterpart = self._write("tdd.md", "Nothing relevant is in this file.")
        manifest = self._write_manifest(
            "phrases.md",
            [f"RECORD-deleted | the deleted record phrase | {counterpart} | | note"],
        )
        rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertNotEqual(rc, 0)

    def test_expands_a_tilde_prefixed_counterpart_path_that_exists(self):
        fake_home = self.tmp_path / "home"
        standards_dir = fake_home / ".claude" / "standards"
        standards_dir.mkdir(parents=True)
        (standards_dir / "tdd.md").write_text(
            "Elsewhere: the tilde-expanded counterpart phrase lives here.",
            encoding="utf-8",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "RECORD-deleted | the tilde-expanded counterpart phrase | ~/.claude/standards/tdd.md | | note"
            ],
        )
        with mock.patch.dict(os.environ, {"HOME": str(fake_home)}, clear=False):
            rc = _PC.main(["--manifest", str(manifest), "--deleted-have-counterparts"])
        self.assertEqual(rc, 0)

    def test_tilde_prefixed_counterpart_path_that_does_not_exist_still_fails(self):
        fake_home = self.tmp_path / "home"
        fake_home.mkdir()
        manifest = self._write_manifest(
            "phrases.md",
            ["RECORD-deleted | some phrase | ~/.claude/standards/tdd.md | | note"],
        )
        with mock.patch.dict(os.environ, {"HOME": str(fake_home)}, clear=False):
            rc, output = _run_and_capture(
                ["--manifest", str(manifest), "--deleted-have-counterparts"]
            )
        self.assertNotEqual(rc, 0)
        expanded = str(fake_home / ".claude" / "standards" / "tdd.md")
        self.assertIn(
            expanded,
            output,
            "error message must name the expanded path, not the literal '~/...'",
        )


class TestParseManifest(PhraseCheckTestCase):
    def test_skips_blank_lines_and_comments(self):
        manifest = self._write_manifest(
            "phrases.md",
            [
                "# a comment line",
                "",
                "HAZARD | first phrase | | | note",
                "   ",
                "HAZARD | second phrase | | | note",
            ],
        )
        rows = _PC.parse_manifest(manifest)
        self.assertEqual(len(rows), 2)

    def test_accepts_markdown_style_leading_and_trailing_pipes(self):
        manifest = self._write_manifest(
            "phrases.md", ["| HAZARD | first phrase | | | note |"]
        )
        rows = _PC.parse_manifest(manifest)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].phrase, "first phrase")

    def test_rejects_a_row_with_no_phrase_field(self):
        manifest = self._write_manifest("phrases.md", ["HAZARD"])
        with self.assertRaises(_PC.ManifestError):
            _PC.parse_manifest(manifest)


class TestCliUsage(unittest.TestCase):
    def test_help_exits_zero(self):
        with self.assertRaises(SystemExit) as cm:
            _PC.main(["--help"])
        self.assertEqual(cm.exception.code, 0)

    def test_missing_source_for_assert_unique_is_a_usage_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "phrases.md"
            manifest.write_text("HAZARD | a phrase | | | note\n", encoding="utf-8")
            rc = _PC.main(["--manifest", str(manifest), "--assert-unique"])
            self.assertNotEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()


class TestParagraphCoverage(PhraseCheckTestCase):
    """--assert-complete-derived asserts coverage, not merely a count.

    A row count equal to the paragraph count is an aggregate; coverage is a
    per-paragraph property. A manifest whose rows all sit in one paragraph
    reaches the count while leaving the rest unclassified -- and an
    unclassified paragraph is invisible to every later gate, because the
    gate's universe is the manifest, so it is absent from numerator and
    denominator alike and the figure does not move.
    """

    _SRC = "alpha one here.\n\nbeta two here.\n\ngamma three here."

    def test_count_matches_but_a_paragraph_has_no_row(self):
        source = self._write("source.md", self._SRC)
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | lpha one here | | | all three rows",
                "HAZARD | one here | | | sit inside paragraph 1",
                "HAZARD | pha one | | | so beta and gamma are uncovered",
            ],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source),
             "--assert-complete-derived"]
        )
        self.assertNotEqual(rc, 0)

    def test_every_paragraph_covered_passes(self):
        source = self._write("source.md", self._SRC)
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | lpha one here | | | para 1",
                "HAZARD | eta two here | | | para 2",
                "HAZARD | amma three here | | | para 3",
            ],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source),
             "--assert-complete-derived"]
        )
        self.assertEqual(rc, 0)


class TestIsExcludedParagraph(unittest.TestCase):
    """Unit tests for the exclusion predicate itself, independent of the CLI."""

    def test_one_hash_heading_is_excluded(self):
        self.assertTrue(_PC.is_excluded_paragraph("# Title"))

    def test_six_hash_heading_is_excluded(self):
        self.assertTrue(_PC.is_excluded_paragraph("###### Deep Heading"))

    def test_three_dash_rule_is_excluded(self):
        self.assertTrue(_PC.is_excluded_paragraph("---"))

    def test_many_dash_rule_is_excluded(self):
        self.assertTrue(_PC.is_excluded_paragraph("----------"))

    def test_two_dashes_is_not_a_rule(self):
        self.assertFalse(_PC.is_excluded_paragraph("--"))

    def test_ordinary_prose_is_not_excluded(self):
        self.assertFalse(_PC.is_excluded_paragraph("Just a normal sentence here."))

    def test_fenced_code_block_is_not_excluded(self):
        self.assertFalse(_PC.is_excluded_paragraph("```bash\necho hi\n```"))

    def test_heading_with_prose_in_same_chunk_is_not_excluded(self):
        self.assertFalse(
            _PC.is_excluded_paragraph(
                "## Heading\nFollowing prose in the same chunk."
            )
        )

    def test_heading_with_surrounding_whitespace_is_still_excluded(self):
        self.assertTrue(_PC.is_excluded_paragraph("   ## Heading   "))


class TestExcludedParagraphsDoNotCountTowardDerivedCoverage(PhraseCheckTestCase):
    """A heading-only or rule-only chunk has no claim sentence for a manifest
    row's phrase to be drawn from, so it must not inflate the derived
    denominator or require a row of its own."""

    def test_heading_only_paragraph_excluded_from_derived_count(self):
        source = self._write(
            "source.md",
            "## Heading One\n\nContent paragraph text here.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | ontent paragraph text here | | | note"],
        )
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)

    def test_separator_only_paragraph_excluded_from_derived_count(self):
        source = self._write(
            "source.md",
            "Content paragraph text here.\n\n---\n\nSecond content paragraph.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | ontent paragraph text here | | | note",
                "HAZARD | econd content paragraph | | | note",
            ],
        )
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)

    def test_fenced_code_block_paragraph_is_not_excluded_and_still_requires_a_row(
        self,
    ):
        source = self._write(
            "source.md",
            "Intro paragraph text here.\n\n```bash\necho hello\n```",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | ntro paragraph text here | | | note"],
        )
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertNotEqual(rc, 0)

    def test_markdown_table_paragraph_is_not_excluded(self):
        source = self._write(
            "source.md",
            "Intro paragraph text here.\n\n"
            "| Var | Values |\n| --- | --- |\n| PROFILE | example |",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | ntro paragraph text here | | | note"],
        )
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertNotEqual(rc, 0)

    def test_heading_with_following_prose_in_same_chunk_is_not_excluded(self):
        source = self._write(
            "source.md",
            "## Heading With Prose\nThis is prose right after the heading.",
        )
        manifest = self._write_manifest("phrases.md", [])
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertNotEqual(rc, 0)

    def test_manifest_covering_content_but_no_heading_now_passes(self):
        # Before the exclusion, this manifest (3 rows) would have failed
        # --assert-complete-derived twice over: the row count would be
        # short against 7 raw paragraphs, and the 4 heading/rule chunks
        # would each report "no manifest row". With headings and the rule
        # excluded, the 3 content paragraphs are the whole denominator.
        source = self._write(
            "source.md",
            "# Title\n\n"
            "## Section One\n\n"
            "First content paragraph.\n\n"
            "## Section Two\n\n"
            "Second content paragraph.\n\n"
            "---\n\n"
            "Third content paragraph.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | irst content paragraph | | | note",
                "HAZARD | econd content paragraph | | | note",
                "HAZARD | hird content paragraph | | | note",
            ],
        )
        rc = _PC.main(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)


class TestDerivedDenominatorIsReported(PhraseCheckTestCase):
    """The tool must state the denominator it used and how many paragraphs
    it excluded, on success as well as on failure -- a ratio over an
    unstated denominator is not a coverage figure."""

    def test_success_output_states_denominator_and_excluded_count(self):
        source = self._write(
            "source.md",
            "## Heading One\n\nContent paragraph one.\n\nContent paragraph two.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | ontent paragraph one | | | note",
                "HAZARD | ontent paragraph two | | | note",
            ],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)
        self.assertIn("excluded", combined)
        self.assertIn("denominator=2", combined)
        self.assertIn("excluded=1", combined)

    def test_failure_output_also_states_denominator_and_excluded_count(self):
        source = self._write(
            "source.md",
            "## Heading One\n\nContent paragraph one.\n\nContent paragraph two.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | ontent paragraph one | | | note"],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertNotEqual(rc, 0)
        self.assertIn("excluded", combined)
        self.assertIn("denominator=2", combined)
        self.assertIn("excluded=1", combined)


class TestSplitParagraphsWhitespaceOnlySeparatorLine(PhraseCheckTestCase):
    """A separator line holding only spaces or tabs is blank to a reader,
    but text.split('\\n\\n') does not treat it as a paragraph break: it
    silently merges two paragraphs into one, undercounting the derived
    coverage denominator with nothing in the excluded count to reveal it."""

    def test_denominator_counts_two_paragraphs_across_a_whitespace_only_separator(
        self,
    ):
        source = self._write(
            "source.md",
            "First content paragraph here.\n   \nSecond content paragraph here.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | irst content paragraph here | | | note",
                "HAZARD | econd content paragraph here | | | note",
            ],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)
        self.assertIn("denominator=2", combined)

    def test_a_tab_only_separator_line_also_splits(self):
        source = self._write(
            "source.md",
            "First content paragraph here.\n\t\nSecond content paragraph here.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | irst content paragraph here | | | note",
                "HAZARD | econd content paragraph here | | | note",
            ],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)
        self.assertIn("denominator=2", combined)

    def test_a_genuinely_blank_line_still_splits_the_same_way(self):
        # Positive control: an ordinary blank-line separator must keep
        # splitting exactly as before.
        source = self._write(
            "source.md",
            "First content paragraph here.\n\nSecond content paragraph here.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            [
                "HAZARD | irst content paragraph here | | | note",
                "HAZARD | econd content paragraph here | | | note",
            ],
        )
        rc, combined = _run_and_capture(
            [
                "--manifest", str(manifest),
                "--source", str(source),
                "--assert-complete-derived",
            ]
        )
        self.assertEqual(rc, 0)
        self.assertIn("denominator=2", combined)


class TestFindOccurrencesCountsOverlappingMatches(PhraseCheckTestCase):
    """A self-similar phrase occurring twice, where the second occurrence
    starts inside the first, must count as two occurrences. A
    non-overlapping scan (advancing past the whole match) finds only one,
    so --assert-unique certified an ambiguous phrase as unique."""

    def test_an_overlapping_repeated_phrase_is_rejected_as_not_unique(self):
        source = self._write(
            "source.md",
            "Preface here: run make test run make test run make test and stop.",
        )
        manifest = self._write_manifest(
            "phrases.md",
            ["HAZARD | run make test run make test | | | note"],
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)

    def test_a_genuinely_unique_phrase_is_still_accepted(self):
        # Positive control: a phrase that occurs exactly once, with no
        # self-overlap anywhere in source, must still pass.
        source = self._write(
            "source.md", "Preface here: run make test once and stop."
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | run make test once | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertEqual(rc, 0)

    def test_a_non_overlapping_double_occurrence_is_still_rejected(self):
        # Positive control: the ordinary (non-overlapping) double-occurrence
        # case must not regress under the overlap-counting fix.
        source = self._write(
            "source.md",
            "Note: the widget calibration steps matter "
            "and the widget calibration steps repeat.",
        )
        manifest = self._write_manifest(
            "phrases.md", ["HAZARD | the widget calibration steps | | | note"]
        )
        rc = _PC.main(
            ["--manifest", str(manifest), "--source", str(source), "--assert-unique"]
        )
        self.assertNotEqual(rc, 0)
