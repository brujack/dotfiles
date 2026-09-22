"""Tests for scripts/phrase_check.py.

Loaded by path (the script is not a package) — same pattern as test_triage_log.py.
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from hypothesis import given
from hypothesis import strategies as st

_REPO = Path(__file__).resolve().parent.parent
_MODULE = _REPO / "scripts" / "phrase_check.py"


def _load():
    spec = importlib.util.spec_from_file_location("phrase_check", _MODULE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["phrase_check"] = module
    spec.loader.exec_module(module)
    return module


_PC = _load()


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
                "HAZARD | paragraph one text here | | | note",
                "HAZARD | paragraph two text here | | | note",
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
                "HAZARD | paragraph one text here | | | note",
                "HAZARD | paragraph two text here | | | note",
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
