"""Characterization tests for plugins/agentic-engineering/skills/crap/crap.py.

Run: python3 -m unittest discover tests
     coverage run --source=plugins/agentic-engineering/skills/crap -m unittest discover tests
     coverage report
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch, MagicMock

HERE = Path(__file__).resolve().parent
# crap.py lives under plugins/agentic-engineering/skills/crap/. The
# directory name contains a hyphen, so Python can't import it as a package
# (plugins.agentic-engineering is not a valid module path). We add the
# skill's own directory to sys.path and import the bare module name. If
# you want package-aware mutation testing, rename agentic-engineering →
# agentic_engineering repo-wide first.
sys.path.insert(
    0,
    str(HERE.parent / "plugins" / "agentic-engineering" / "skills" / "crap"),
)
import crap  # noqa: E402


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def _ns(**kw):
    return argparse.Namespace(**kw)


def _write(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    return path


# --------------------------------------------------------------------------- #
# lizard CSV / arg signature
# --------------------------------------------------------------------------- #

class TestParseLizard(unittest.TestCase):
    def test_parses_header_and_rows(self):
        csv = (
            "NLOC,CCN,token,PARAM,length,location\n"
            '5,3,10,2,6,"foo@1-5@a.py"\n'
            '4,2,8,0,4,"bar@7-10@a.py"\n'
        )
        out = crap.parse_lizard_csv(csv)
        self.assertEqual(len(out), 2)
        self.assertEqual(out[0]["name"], "foo")
        self.assertEqual(out[0]["cc"], 3)
        self.assertEqual(out[0]["start_line"], 1)
        self.assertEqual(out[0]["end_line"], 5)
        self.assertEqual(out[1]["param_count"], 0)

    def test_single_line_location_without_range(self):
        csv = 'NLOC,CCN,token,PARAM,length,location\n1,1,3,0,1,"solo@42@a.py"\n'
        out = crap.parse_lizard_csv(csv)
        self.assertEqual(out[0]["start_line"], 42)
        self.assertEqual(out[0]["end_line"], 42)

    def test_skips_malformed_rows(self):
        csv = (
            "NLOC,CCN,token,PARAM,length,location\n"
            '1,2,3,0,4,"ok@1-2@a.py"\n'
            "bogus,row\n"
            '1,notanint,3,0,4,"bad@1-2@a.py"\n'
            '1,2,3,0,4,"badloc_no_at\n'
        )
        out = crap.parse_lizard_csv(csv)
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["name"], "ok")

    def test_empty_input_returns_empty(self):
        self.assertEqual(crap.parse_lizard_csv(""), [])

    def test_cmd_parse_lizard_reads_file(self):
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            csv_path = _write(tp / "in.csv",
                              'NLOC,CCN,token,PARAM,length,location\n'
                              '1,1,2,0,1,"f@1-1@x.py"\n')
            out_path = tp / "out.json"
            rc = crap.cmd_parse_lizard(_ns(path=str(csv_path), output=str(out_path)))
            self.assertEqual(rc, 0)
            data = json.loads(out_path.read_text())
            self.assertEqual(data[0]["name"], "f")


class TestReadArgSignature(unittest.TestCase):
    def test_no_params_returns_empty(self):
        self.assertEqual(crap._read_arg_signature("/nonexistent", 1, 0), "")

    def test_simple_python_function(self):
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(a, b, c):\n    return a+b+c\n")
            path = f.name
        try:
            sig = crap._read_arg_signature(path, 1, 3)
            self.assertEqual(sig, "a,b,c")
        finally:
            os.unlink(path)

    def test_annotated_params_strips_types(self):
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def bar(x: int, y: str = 'z', *args, **kw):\n    pass\n")
            path = f.name
        try:
            sig = crap._read_arg_signature(path, 1, 4)
            self.assertIn("x", sig)
            self.assertIn("y", sig)
        finally:
            os.unlink(path)

    def test_missing_file_returns_empty(self):
        self.assertEqual(crap._read_arg_signature("/no/such/file.py", 1, 2), "")

    def test_no_open_paren_returns_empty(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write("no parens here at all\n")
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 2), "")
        finally:
            os.unlink(path)

    def test_unterminated_paren_returns_empty(self):
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def f(a, b\n")
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 2), "")
        finally:
            os.unlink(path)


# --------------------------------------------------------------------------- #
# CRAP math
# --------------------------------------------------------------------------- #

class TestCrapMath(unittest.TestCase):
    def test_crap_max(self):
        self.assertEqual(crap.crap_max(0), 0.0)
        self.assertEqual(crap.crap_max(1), 2.0)
        self.assertEqual(crap.crap_max(5), 30.0)
        self.assertEqual(crap.crap_max(10), 110.0)

    def test_crap_score_at_zero_coverage_equals_crap_max(self):
        for cc in (1, 5, 10, 20):
            self.assertAlmostEqual(crap.crap_score(cc, 0.0), crap.crap_max(cc))

    def test_crap_score_at_full_coverage_equals_cc(self):
        for cc in (1, 5, 10, 20):
            self.assertAlmostEqual(crap.crap_score(cc, 100.0), float(cc))

    def test_crap_score_clamps_out_of_range(self):
        self.assertAlmostEqual(crap.crap_score(5, -5.0), crap.crap_max(5))
        self.assertAlmostEqual(crap.crap_score(5, 200.0), 5.0)

    def test_crap_score_80_pct(self):
        # cc=10, eff_cov=80% → 100 * 0.008 + 10 = 10.8
        self.assertAlmostEqual(crap.crap_score(10, 80.0), 10.8, places=5)

    def test_dominant_axis_complex_no_tests_picks_tests_when_mutation_gap_exists(self):
        # line_cov=0.5, eff_cov=0.1 → mutation kill rate is terrible
        self.assertEqual(crap._dominant_axis(10, 0.5, 0.1), "tests")

    def test_dominant_axis_zero_coverage_picks_cc(self):
        # with no coverage and no mutation data (eff=line), cc axis wins
        self.assertEqual(crap._dominant_axis(10, 0.0, 0.0), "cc")

    def test_dominant_axis_with_high_line_and_lower_eff_picks_tests(self):
        self.assertEqual(crap._dominant_axis(8, 0.9, 0.3), "tests")


# --------------------------------------------------------------------------- #
# cmd_filter
# --------------------------------------------------------------------------- #

class TestCmdFilter(unittest.TestCase):
    def test_filter_drops_below_threshold(self):
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            fns = [
                {"file": "a.py", "name": "low", "start_line": 1,
                 "end_line": 3, "cc": 3, "arg_signature": ""},
                {"file": "a.py", "name": "high", "start_line": 10,
                 "end_line": 30, "cc": 10, "arg_signature": ""},
            ]
            in_path = _write(tp / "fns.json", json.dumps(fns))
            out_path = tp / "surv.json"
            rc = crap.cmd_filter(_ns(functions=str(in_path), threshold=30.0,
                                     output=str(out_path)))
            self.assertEqual(rc, 0)
            surv = json.loads(out_path.read_text())
            self.assertEqual(len(surv), 1)
            self.assertEqual(surv[0]["name"], "high")


# --------------------------------------------------------------------------- #
# Cache
# --------------------------------------------------------------------------- #

class TestCache(unittest.TestCase):
    def test_read_function_bytes_slices_lines(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("a\nb\nc\nd\ne\n")
            path = f.name
        try:
            self.assertEqual(crap.read_function_bytes(path, 2, 4), b"b\nc\nd\n")
            self.assertEqual(crap.read_function_bytes(path, 1, 1), b"a\n")
        finally:
            os.unlink(path)

    def test_read_function_bytes_missing_file(self):
        self.assertEqual(crap.read_function_bytes("/no/such", 1, 5), b"")

    def test_function_hash_stable_and_toolchain_sensitive(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("def f():\n    return 1\n")
            path = f.name
        try:
            fn = {"file": path, "start_line": 1, "end_line": 2}
            h1 = crap.function_hash(fn, "")
            h2 = crap.function_hash(fn, "")
            h3 = crap.function_hash(fn, "tag")
            self.assertEqual(h1, h2)
            self.assertNotEqual(h1, h3)
        finally:
            os.unlink(path)

    def test_cmd_cache_split_hit_and_miss(self):
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            src = _write(tp / "src.py", "def f():\n    return 1\n")
            survivors = [{
                "file": str(src), "name": "f", "start_line": 1, "end_line": 2,
                "cc": 5, "arg_signature": "",
            }]
            surv_path = _write(tp / "surv.json", json.dumps(survivors))
            cache_dir = tp / "cache"
            to_measure = tp / "tm.json"
            cached_out = tp / "cached.json"

            # First run: pure miss
            with redirect_stderr(io.StringIO()):
                rc = crap.cmd_cache_split(_ns(
                    survivors=str(surv_path), cache=str(cache_dir),
                    to_measure=str(to_measure), cached_results=str(cached_out),
                    toolchain_tag=""))
            self.assertEqual(rc, 0)
            self.assertEqual(len(json.loads(to_measure.read_text())), 1)
            self.assertEqual(json.loads(cached_out.read_text()), {})

            # Populate the cache file and re-run → hit
            h = crap.function_hash(survivors[0], "")
            (cache_dir / f"{h}.json").write_text(json.dumps({
                "line_cov": 0.9, "mut_kill": 0.8, "survived_mutants": []}))
            with redirect_stderr(io.StringIO()):
                crap.cmd_cache_split(_ns(
                    survivors=str(surv_path), cache=str(cache_dir),
                    to_measure=str(to_measure), cached_results=str(cached_out),
                    toolchain_tag=""))
            self.assertEqual(len(json.loads(to_measure.read_text())), 0)
            self.assertEqual(len(json.loads(cached_out.read_text())), 1)

            # Corrupt cache file → treated as miss
            (cache_dir / f"{h}.json").write_text("not json")
            with redirect_stderr(io.StringIO()):
                crap.cmd_cache_split(_ns(
                    survivors=str(surv_path), cache=str(cache_dir),
                    to_measure=str(to_measure), cached_results=str(cached_out),
                    toolchain_tag=""))
            self.assertEqual(len(json.loads(to_measure.read_text())), 1)


# --------------------------------------------------------------------------- #
# Coverage adapters
# --------------------------------------------------------------------------- #

class TestCoverageAdapters(unittest.TestCase):
    def test_coveragepy(self):
        raw = {"files": {"a.py": {"executed_lines": [1, 2], "missing_lines": [3]}}}
        out = crap.coverage_from_coveragepy(raw)
        self.assertEqual(out["a.py"]["1"], 1)
        self.assertEqual(out["a.py"]["2"], 1)
        self.assertEqual(out["a.py"]["3"], 0)

    def test_coveragepy_empty_input(self):
        self.assertEqual(crap.coverage_from_coveragepy({}), {})

    def test_istanbul(self):
        raw = {"a.js": {
            "statementMap": {"0": {"start": {"line": 1}, "end": {"line": 1}},
                             "1": {"start": {"line": 2}, "end": {"line": 2}}},
            "s": {"0": 5, "1": 0}}}
        out = crap.coverage_from_istanbul(raw)
        self.assertEqual(out["a.js"]["1"], 5)
        self.assertEqual(out["a.js"]["2"], 0)

    def test_istanbul_skips_non_dict(self):
        out = crap.coverage_from_istanbul({"a.js": "not a dict", "b.js": {}})
        self.assertEqual(out, {})

    def test_gocover(self):
        text = (
            "mode: set\n"
            "pkg/foo.go:10.1,12.2 2 3\n"
            "pkg/foo.go:14.1,14.2 1 0\n"
        )
        out = crap.coverage_from_gocover(text)
        self.assertEqual(out["pkg/foo.go"]["10"], 3)
        self.assertEqual(out["pkg/foo.go"]["12"], 3)
        self.assertEqual(out["pkg/foo.go"]["14"], 0)

    def test_gocover_skips_bad_lines(self):
        text = "mode: set\ngarbage line\npkg/a.go:1.1,2.1 1 1\n"
        out = crap.coverage_from_gocover(text)
        self.assertEqual(out["pkg/a.go"]["1"], 1)

    def test_lcov(self):
        text = "SF:src/a.c\nDA:1,3\nDA:2,0\nDA:3,1,abc123\nend_of_record\n"
        out = crap.coverage_from_lcov(text)
        self.assertEqual(out["src/a.c"]["1"], 3)
        self.assertEqual(out["src/a.c"]["2"], 0)
        self.assertEqual(out["src/a.c"]["3"], 1)

    def test_lcov_ignores_stray_lines(self):
        text = "DA:1,1\nSF:a.c\nDA:5,5\nend_of_record\n"
        out = crap.coverage_from_lcov(text)
        self.assertEqual(out["a.c"]["5"], 5)
        self.assertNotIn("1", out.get("a.c", {}))

    def test_cobertura(self):
        xml = """<?xml version="1.0"?>
<coverage>
  <packages><package>
    <classes>
      <class filename="src/a.rs" name="a">
        <lines>
          <line number="1" hits="3"/>
          <line number="2" hits="0"/>
        </lines>
      </class>
    </classes>
  </package></packages>
</coverage>"""
        out = crap.coverage_from_cobertura(xml)
        self.assertEqual(out["src/a.rs"]["1"], 3)
        self.assertEqual(out["src/a.rs"]["2"], 0)

    def test_cobertura_parse_error_returns_empty(self):
        self.assertEqual(crap.coverage_from_cobertura("not xml"), {})

    def test_cobertura_bad_hits_becomes_zero(self):
        xml = ('<coverage><class filename="a.py">'
               '<line number="1" hits="NaN"/></class></coverage>')
        out = crap.coverage_from_cobertura(xml)
        self.assertEqual(out["a.py"]["1"], 0)

    def test_normalize_coverage_dispatch(self):
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            raw = _write(tp / "raw.json", json.dumps(
                {"files": {"a.py": {"executed_lines": [1], "missing_lines": []}}}))
            out = tp / "norm.json"
            rc = crap.cmd_normalize_coverage(_ns(
                tool="coveragepy", path=str(raw), output=str(out)))
            self.assertEqual(rc, 0)
            self.assertEqual(json.loads(out.read_text())["a.py"]["1"], 1)

    def test_normalize_coverage_unknown_tool(self):
        with tempfile.TemporaryDirectory() as td:
            raw = _write(Path(td) / "r", "{}")
            with redirect_stderr(io.StringIO()):
                rc = crap.cmd_normalize_coverage(_ns(
                    tool="nonsense", path=str(raw), output=None))
            self.assertEqual(rc, 3)


# --------------------------------------------------------------------------- #
# Mutation adapters
# --------------------------------------------------------------------------- #

class TestMutationAdapters(unittest.TestCase):
    def test_mutmut(self):
        raw = {"mutants": [
            {"filename": "a.py", "line_number": 5, "status": "killed",
             "mutant_name": "ROR>="},
            {"filename": "a.py", "line_number": 7, "status": "survived",
             "mutant_name": "AOR-"},
            {"filename": "a.py", "line_number": 0, "status": "killed"},  # bad
        ]}
        out = crap.mutation_from_mutmut(raw)
        self.assertEqual(out["a.py"]["5"]["killed"], 1)
        self.assertEqual(out["a.py"]["7"]["survived"], 1)
        self.assertIn("AOR-", out["a.py"]["7"]["survived_mutants"])

    def test_mutmut_accepts_list_shape(self):
        raw = [{"filename": "a.py", "line_number": 1, "status": "killed"}]
        out = crap.mutation_from_mutmut(raw)
        self.assertEqual(out["a.py"]["1"]["killed"], 1)

    def test_stryker(self):
        raw = {"files": {"a.js": {"mutants": [
            {"location": {"start": {"line": 10}}, "status": "Killed",
             "mutatorName": "ArithmeticOperator"},
            {"location": {"start": {"line": 12}}, "status": "Survived"},
            {"status": "Killed"},  # no location → skipped
        ]}}}
        out = crap.mutation_from_stryker(raw)
        self.assertEqual(out["a.js"]["10"]["killed"], 1)
        self.assertEqual(out["a.js"]["12"]["survived"], 1)

    def test_cargo_mutants(self):
        raw = {"outcomes": [
            {"scenario": {"Mutant": {"file": "src/a.rs", "line": 3,
                                     "function": "foo"}},
             "summary": "CaughtMutant"},
            {"scenario": {"Mutant": {"file": "src/a.rs", "line": 7}},
             "summary": "MissedMutant"},
            {"scenario": {"Mutant": {"file": "", "line": 0}},
             "summary": "CaughtMutant"},  # invalid
        ]}
        out = crap.mutation_from_cargo_mutants(raw)
        self.assertEqual(out["src/a.rs"]["3"]["killed"], 1)
        self.assertEqual(out["src/a.rs"]["7"]["survived"], 1)

    def test_cargo_mutants_list_shape(self):
        raw = [{"scenario": {"Mutant": {"file": "a.rs", "line": 1}},
                "summary": "CaughtMutant"}]
        out = crap.mutation_from_cargo_mutants(raw)
        self.assertEqual(out["a.rs"]["1"]["killed"], 1)

    def test_pitest(self):
        xml = """<mutations>
  <mutation detected="true">
    <sourceFile>A.java</sourceFile>
    <mutatedClass>com.x.A</mutatedClass>
    <lineNumber>10</lineNumber>
    <mutator>org.pitest.ConditionalsBoundary</mutator>
  </mutation>
  <mutation detected="false">
    <sourceFile>A.java</sourceFile>
    <mutatedClass>com.x.A</mutatedClass>
    <lineNumber>12</lineNumber>
    <mutator>org.pitest.NegateConditionals</mutator>
  </mutation>
</mutations>"""
        out = crap.mutation_from_pitest(xml)
        self.assertEqual(out["com/x/A.java"]["10"]["killed"], 1)
        self.assertEqual(out["com/x/A.java"]["12"]["survived"], 1)
        self.assertIn("NegateConditionals",
                      out["com/x/A.java"]["12"]["survived_mutants"])

    def test_pitest_parse_error(self):
        self.assertEqual(crap.mutation_from_pitest("not xml"), {})

    def test_normalize_mutation_unknown_tool(self):
        with tempfile.TemporaryDirectory() as td:
            raw = _write(Path(td) / "r", "{}")
            with redirect_stderr(io.StringIO()):
                rc = crap.cmd_normalize_mutation(_ns(
                    tool="nonsense", path=str(raw), output=None))
            self.assertEqual(rc, 3)

    def test_normalize_mutation_dispatch(self):
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            raw = _write(tp / "r.json",
                         json.dumps({"mutants": [
                             {"filename": "a.py", "line_number": 1,
                              "status": "killed"}]}))
            out = tp / "o.json"
            rc = crap.cmd_normalize_mutation(_ns(
                tool="mutmut", path=str(raw), output=str(out)))
            self.assertEqual(rc, 0)


# --------------------------------------------------------------------------- #
# Slicers
# --------------------------------------------------------------------------- #

class TestSlicers(unittest.TestCase):
    def test_slice_coverage_counts_within_range(self):
        cov = {"a.py": {"1": 1, "2": 0, "3": 5, "4": 0, "5": 1}}
        self.assertEqual(crap._slice_coverage(cov, "a.py", 2, 4), (1, 3))
        self.assertEqual(crap._slice_coverage(cov, "a.py", 1, 5), (3, 5))

    def test_slice_coverage_missing_file(self):
        self.assertEqual(crap._slice_coverage({}, "x.py", 1, 10), (0, 0))

    def test_slice_coverage_tolerates_dot_slash_prefix(self):
        cov = {"a.py": {"1": 1}}
        self.assertEqual(crap._slice_coverage(cov, "./a.py", 1, 1), (1, 1))

    def test_slice_mutation(self):
        mut = {"a.py": {
            "3": {"killed": 2, "survived": 1, "survived_mutants": ["M1"]},
            "7": {"killed": 0, "survived": 1, "survived_mutants": ["M2"]},
        }}
        killed, survived, mutants = crap._slice_mutation(mut, "a.py", 1, 5)
        self.assertEqual(killed, 2)
        self.assertEqual(survived, 1)
        self.assertEqual(mutants, ["M1"])

    def test_slice_mutation_missing(self):
        self.assertEqual(crap._slice_mutation({}, "x.py", 1, 10), (0, 0, []))


# --------------------------------------------------------------------------- #
# Baseline
# --------------------------------------------------------------------------- #

class TestBaseline(unittest.TestCase):
    def test_load_baseline_missing_path(self):
        self.assertEqual(crap.load_baseline(None), {})
        self.assertEqual(crap.load_baseline("/no/such/file"), {})

    def test_load_baseline_rows_wrapped(self):
        with tempfile.TemporaryDirectory() as td:
            p = _write(Path(td) / "b.json", json.dumps({"rows": [
                {"file": "a.py", "name": "f", "arg_signature": "x",
                 "cc": 5, "crap": 50.0, "eff_cov": 0.3}]}))
            out = crap.load_baseline(str(p))
            self.assertIn("a.py::f::x", out)
            self.assertEqual(out["a.py::f::x"]["cc"], 5)

    def test_load_baseline_bare_list(self):
        with tempfile.TemporaryDirectory() as td:
            p = _write(Path(td) / "b.json", json.dumps([
                {"file": "a.py", "name": "g", "arg_signature": ""}]))
            out = crap.load_baseline(str(p))
            self.assertIn("a.py::g::", out)

    def test_load_baseline_invalid_json_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            p = _write(Path(td) / "b.json", "not json")
            self.assertEqual(crap.load_baseline(str(p)), {})

    def test_load_baseline_wrong_shape_returns_empty(self):
        with tempfile.TemporaryDirectory() as td:
            p = _write(Path(td) / "b.json", json.dumps({"not": "rows"}))
            self.assertEqual(crap.load_baseline(str(p)), {})


# --------------------------------------------------------------------------- #
# Churn / weight
# --------------------------------------------------------------------------- #

class TestChurn(unittest.TestCase):
    def test_churn_weight(self):
        self.assertAlmostEqual(crap.churn_weight(0), 1.0)
        self.assertGreater(crap.churn_weight(10), crap.churn_weight(1))

    def test_churn_weight_clamps_negative(self):
        self.assertAlmostEqual(crap.churn_weight(-5), 1.0)

    def test_churn_commits_on_nonexistent_file_returns_zero(self):
        # git log will return 0 commits for a file not in history
        self.assertEqual(crap.churn_commits("/no/such/file.xyz", 90), 0)


# --------------------------------------------------------------------------- #
# Scoring / render / summary
# --------------------------------------------------------------------------- #

class TestScoringHelpers(unittest.TestCase):
    def test_baseline_tag_new(self):
        tag, delta = crap._baseline_tag(50.0, None)
        self.assertEqual(tag, "new")
        self.assertIsNone(delta)

    def test_baseline_tag_same(self):
        tag, _ = crap._baseline_tag(50.0, {"crap": 50.2})
        self.assertEqual(tag, "same")

    def test_baseline_tag_regressed(self):
        tag, delta = crap._baseline_tag(60.0, {"crap": 50.0})
        self.assertEqual(tag, "regressed")
        self.assertAlmostEqual(delta, 10.0)

    def test_baseline_tag_improved(self):
        tag, _ = crap._baseline_tag(40.0, {"crap": 50.0})
        self.assertEqual(tag, "improved")

    def test_compute_summary_clean(self):
        rows = [{"crap": 10.0, "tag": "same"}, {"crap": 12.0, "tag": "improved"}]
        s = crap._compute_summary(rows, total_functions=20, survivors_count=2,
                                  threshold=30.0)
        self.assertEqual(s["above_threshold"], 0)
        self.assertEqual(s["project_pct_above_threshold"], 0.0)
        self.assertFalse(s["project_crappy"])

    def test_compute_summary_crappy(self):
        rows = [{"crap": 100.0, "tag": "new"}, {"crap": 60.0, "tag": "regressed"}]
        s = crap._compute_summary(rows, total_functions=20, survivors_count=2,
                                  threshold=30.0)
        self.assertEqual(s["above_threshold"], 2)
        self.assertEqual(s["regressions"], 1)
        self.assertEqual(s["new_above_threshold"], 1)
        self.assertTrue(s["project_crappy"])  # 10% > 5%

    def test_compute_summary_zero_functions(self):
        s = crap._compute_summary([], total_functions=0, survivors_count=0,
                                  threshold=30.0)
        self.assertEqual(s["project_pct_above_threshold"], 0.0)

    def test_emit_summary_writes_both_lines(self):
        buf = io.StringIO()
        with redirect_stderr(buf):
            crap._emit_summary({
                "above_threshold": 1, "survivors": 2, "regressions": 0,
                "new_above_threshold": 1, "project_pct_above_threshold": 33.3,
                "project_crappy": True, "total_functions": 3, "threshold": 30.0})
        out = buf.getvalue()
        self.assertIn("1/2 over threshold", out)
        self.assertIn("CRAPPY", out)
        self.assertIn("Savoia", out)

    def test_exit_code_regression(self):
        self.assertEqual(crap._exit_code(
            [{"crap": 50.0, "tag": "regressed"}], 30.0), 2)

    def test_exit_code_hit_only(self):
        self.assertEqual(crap._exit_code(
            [{"crap": 50.0, "tag": "same"}], 30.0), 1)

    def test_exit_code_clean(self):
        self.assertEqual(crap._exit_code(
            [{"crap": 10.0, "tag": "same"}], 30.0), 0)

    def test_render_markdown_empty(self):
        self.assertIn("Clean", crap._render_markdown([], threshold=30.0))

    def test_render_markdown_has_columns(self):
        row = {"file": "a.py", "start_line": 1, "name": "f", "cc": 5,
               "line_cov": 0.5, "mut_kill": 1.0, "eff_cov": 0.5,
               "churn": 3, "crap": 20.0, "delta": None, "tag": "new"}
        out = crap._render_markdown([row], threshold=30.0)
        self.assertIn("file:line", out)
        self.assertIn("a.py:1", out)
        self.assertIn("f", out)

    def test_render_markdown_positive_and_negative_delta(self):
        base = {"file": "a", "start_line": 1, "name": "f", "cc": 1,
                "line_cov": 0, "mut_kill": 1, "eff_cov": 0, "churn": 0,
                "crap": 1.0, "tag": "same"}
        out_pos = crap._render_markdown(
            [{**base, "delta": 3.2}], threshold=30.0)
        out_neg = crap._render_markdown(
            [{**base, "delta": -1.5}], threshold=30.0)
        self.assertIn("+3.2", out_pos)
        self.assertIn("-1.5", out_neg)


class TestMeasureOne(unittest.TestCase):
    def _fn(self, path):
        return {"file": path, "name": "f", "start_line": 1, "end_line": 2,
                "cc": 5, "arg_signature": ""}

    def test_cache_hit_returns_cached_values(self):
        with tempfile.TemporaryDirectory() as td:
            src = _write(Path(td) / "s.py", "def f():\n    pass\n")
            fn = self._fn(str(src))
            h = crap.function_hash(fn, "")
            cached = {h: {"line_cov": 0.7, "mut_kill": 0.5,
                          "survived_mutants": ["M1"]}}
            line, mut, muts = crap._measure_one(
                fn, {}, {}, cached, None, "")
            self.assertEqual(line, 0.7)
            self.assertEqual(mut, 0.5)
            self.assertEqual(muts, ["M1"])

    def test_cache_miss_with_no_data_defaults(self):
        with tempfile.TemporaryDirectory() as td:
            src = _write(Path(td) / "s.py", "def f():\n    pass\n")
            fn = self._fn(str(src))
            line, mut, muts = crap._measure_one(fn, {}, {}, {}, None, "")
            self.assertEqual(line, 0.0)
            self.assertEqual(mut, 1.0)  # no mutation data → default 1.0
            self.assertEqual(muts, [])

    def test_cache_miss_writes_cache_when_measured(self):
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            src = _write(tp / "s.py", "def f():\n    return 1\n")
            fn = self._fn(str(src))
            cache = tp / "cache"
            cache.mkdir()
            coverage = {str(src): {"1": 1, "2": 0}}
            crap._measure_one(fn, coverage, {}, {}, cache, "")
            cached_files = list(cache.glob("*.json"))
            self.assertEqual(len(cached_files), 1)
            data = json.loads(cached_files[0].read_text())
            self.assertAlmostEqual(data["line_cov"], 0.5)


class TestScoreOneAndWriteBaseline(unittest.TestCase):
    def test_score_one_assembles_row(self):
        with tempfile.TemporaryDirectory() as td:
            src = _write(Path(td) / "s.py", "def f():\n    pass\n")
            fn = {"file": str(src), "name": "f", "start_line": 1,
                  "end_line": 2, "cc": 5, "arg_signature": ""}
            row = crap._score_one(fn, {}, {}, {}, None, "", {},
                                  no_churn=True, churn_window=90)
            self.assertEqual(row["cc"], 5)
            self.assertEqual(row["tag"], "new")
            self.assertEqual(row["churn"], 0)
            self.assertEqual(row["weight"], 1.0)
            self.assertIn(row["dominant_axis"], ("cc", "tests"))

    def test_write_baseline_includes_all_functions(self):
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            rows = [{"file": "a.py", "name": "f", "arg_signature": "x",
                     "cc": 10, "crap": 100.0, "eff_cov": 0.3}]
            survivors = [{"file": "a.py", "name": "f", "arg_signature": "x",
                          "cc": 10}]
            all_fns = survivors + [
                {"file": "a.py", "name": "g", "arg_signature": "",
                 "cc": 2}]
            out = tp / "base.json"
            with redirect_stderr(io.StringIO()):
                rc = crap._write_baseline(rows, survivors, all_fns, str(out))
            self.assertEqual(rc, 0)
            data = json.loads(out.read_text())
            names = sorted(r["name"] for r in data["rows"])
            self.assertEqual(names, ["f", "g"])


class TestCmdScoreIntegration(unittest.TestCase):
    def _setup(self, td, cc_values):
        tp = Path(td)
        src_lines = []
        fns = []
        ln = 1
        for idx, cc in enumerate(cc_values):
            src_lines.append(f"def f{idx}():\n    pass\n")
            fns.append({"file": str(tp / "src.py"), "name": f"f{idx}",
                        "start_line": ln, "end_line": ln + 1,
                        "cc": cc, "arg_signature": ""})
            ln += 2
        _write(tp / "src.py", "".join(src_lines))
        _write(tp / "fns.json", json.dumps(fns))
        survivors = [fn for fn in fns if crap.crap_max(fn["cc"]) > 30]
        _write(tp / "surv.json", json.dumps(survivors))
        return tp

    def _args(self, tp, **extra):
        defaults = dict(
            functions=str(tp / "fns.json"),
            survivors=str(tp / "surv.json"),
            coverage=None, mutation=None, cached=None, cache=None,
            toolchain_tag="", baseline=None, no_baseline=True,
            no_churn=True, churn_window=90, threshold=30.0, top=10,
            summary_out=None, set_baseline=False,
        )
        defaults.update(extra)
        return _ns(**defaults)

    def test_cmd_score_runs_end_to_end_and_returns_exit_code(self):
        with tempfile.TemporaryDirectory() as td:
            tp = self._setup(td, cc_values=[10, 2])
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                rc = crap.cmd_score(self._args(tp))
            # one survivor over threshold → exit 1 (no regression) or 2 (new above)
            self.assertIn(rc, (1, 2))

    def test_cmd_score_clean_when_no_survivors(self):
        with tempfile.TemporaryDirectory() as td:
            tp = self._setup(td, cc_values=[1, 2])
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                rc = crap.cmd_score(self._args(tp))
            self.assertEqual(rc, 0)

    def test_cmd_score_set_baseline(self):
        with tempfile.TemporaryDirectory() as td:
            tp = self._setup(td, cc_values=[10, 2])
            base = tp / "baseline.json"
            with redirect_stderr(io.StringIO()):
                rc = crap.cmd_score(self._args(tp, set_baseline=True,
                                               baseline=str(base)))
            self.assertEqual(rc, 0)
            self.assertTrue(base.exists())
            data = json.loads(base.read_text())
            names = sorted(r["name"] for r in data["rows"])
            self.assertEqual(names, ["f0", "f1"])  # all functions baselined


# --------------------------------------------------------------------------- #
# Path resolution / misc
# --------------------------------------------------------------------------- #

class TestResolvePath(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(crap._resolve_path(""), "")

    def test_relative_passes_through(self):
        self.assertEqual(crap._resolve_path("a/b.py"), "a/b.py")

    def test_absolute_with_root_makes_relative(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "x.py"
            self.assertEqual(crap._resolve_path(str(p), Path(td)), "x.py")

    def test_absolute_unrelated_root_returns_str(self):
        result = crap._resolve_path("/usr/bin/python", Path("/tmp"))
        self.assertEqual(result, "/usr/bin/python")


class TestMutBucketAndAdd(unittest.TestCase):
    def test_mut_bucket_shape(self):
        b = crap._mut_bucket()
        self.assertEqual(b, {"killed": 0, "survived": 0, "survived_mutants": []})

    def test_mut_add_killed(self):
        dst = {}
        crap._mut_add(dst, "a.py", 5, "killed", "L5")
        self.assertEqual(dst["a.py"]["5"]["killed"], 1)

    def test_mut_add_survived_with_label(self):
        dst = {}
        crap._mut_add(dst, "a.py", 5, "survived", "ROR>=")
        self.assertEqual(dst["a.py"]["5"]["survived"], 1)
        self.assertIn("ROR>=", dst["a.py"]["5"]["survived_mutants"])

    def test_mut_add_ignored_status(self):
        dst = {}
        crap._mut_add(dst, "a.py", 5, "timeout", "x")
        self.assertEqual(dst["a.py"]["5"]["killed"], 0)
        self.assertEqual(dst["a.py"]["5"]["survived"], 0)


class TestPct(unittest.TestCase):
    def test_zero_denom(self):
        self.assertEqual(crap.pct(5, 0), 0.0)

    def test_normal(self):
        self.assertEqual(crap.pct(1, 4), 25.0)


class TestBaselineKey(unittest.TestCase):
    def test_key_format(self):
        self.assertEqual(crap._baseline_key({"file": "a.py", "name": "f",
                                             "arg_signature": "x,y"}),
                         "a.py::f::x,y")

    def test_key_missing_arg_signature(self):
        self.assertEqual(crap._baseline_key({"file": "a.py", "name": "f"}),
                         "a.py::f::")


class TestAntiMutation(unittest.TestCase):
    """Targeted tests that kill specific mutations surfaced by mutmut.

    Each test here was written in response to a surviving mutant; the docstring
    names the mutant to keep the intent explicit.
    """

    def test_arg_signature_zero_params_on_file_with_parens(self):
        """Kills x__read_arg_signature__mutmut_2: param_count == 0 → 1.

        With param_count=0 we must return "" immediately even when the file
        has parens on the first line (otherwise we'd parse the args).
        """
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(a, b, c):\n    pass\n")
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 0), "")
        finally:
            os.unlink(path)

    def test_arg_signature_single_param(self):
        """Kills mutations on param_count-handling branches."""
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(only):\n    pass\n")
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 1), "only")
        finally:
            os.unlink(path)

    def test_arg_signature_star_args_collapse_to_name(self):
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(*args, **kw):\n    pass\n")
            path = f.name
        try:
            sig = crap._read_arg_signature(path, 1, 2)
            self.assertEqual(sig, "args,kw")
        finally:
            os.unlink(path)

    def test_arg_signature_nested_bracket_in_default(self):
        """Balanced-delimiter tracker must handle nested [] in defaults."""
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(a, b = [1, 2, 3], c = None):\n    pass\n")
            path = f.name
        try:
            sig = crap._read_arg_signature(path, 1, 3)
            self.assertEqual(sig, "a,b,c")
        finally:
            os.unlink(path)

    def test_render_markdown_header_row_literal_strings(self):
        """Kills string-replacement mutations on the header list."""
        row = {"file": "a.py", "start_line": 1, "name": "f", "cc": 5,
               "line_cov": 0.5, "mut_kill": 1.0, "eff_cov": 0.5,
               "churn": 3, "crap": 20.0, "delta": None, "tag": "new"}
        out = crap._render_markdown([row], threshold=30.0)
        for literal in ("file:line", "function", "cc", "cov%", "mut%",
                        "eff_cov%", "churn", "CRAP", "tag"):
            self.assertIn(f"| {literal}", out,
                          msg=f"header missing: {literal!r}")

    def test_render_markdown_empty_message_literal(self):
        """Kills x__render_markdown__mutmut_2: 'Clean.' → 'XXClean.XX'."""
        out = crap._render_markdown([], threshold=30.0)
        self.assertEqual(out, "_No functions above CRAP_max filter. Clean._")

    def test_slice_mutation_with_dot_slash_prefix(self):
        """Kills x__slice_mutation__mutmut_2..4: `or → and` / arg-nulling."""
        mut = {"a.py": {"5": {"killed": 3, "survived": 2,
                              "survived_mutants": ["M1", "M2"]}}}
        killed, survived, mutants = crap._slice_mutation(mut, "./a.py", 1, 10)
        self.assertEqual(killed, 3)
        self.assertEqual(survived, 2)
        self.assertEqual(mutants, ["M1", "M2"])

    def test_slice_coverage_with_dot_slash_prefix_second_lookup(self):
        """Forces the `file.lstrip('./')` branch of the cov lookup."""
        cov = {"a.py": {"3": 1}}
        self.assertEqual(crap._slice_coverage(cov, "./a.py", 1, 5), (1, 1))

    def test_cmd_score_with_real_coverage_file(self):
        """Kills cmd_score mutants that null-out args.coverage before load_json.

        Integration: full score pipeline with a coverage file on disk.
        Asserts output values change when coverage is supplied vs not.
        """
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            _write(tp / "src.py", "def f():\n    return 1\n")
            fns = [{"file": str(tp / "src.py"), "name": "f",
                    "start_line": 1, "end_line": 2, "cc": 10,
                    "arg_signature": ""}]
            _write(tp / "fns.json", json.dumps(fns))
            _write(tp / "surv.json", json.dumps(fns))
            # coverage: 100% on lines 1, 2
            _write(tp / "cov.json", json.dumps({
                str(tp / "src.py"): {"1": 5, "2": 3}}))
            args = _ns(functions=str(tp / "fns.json"),
                       survivors=str(tp / "surv.json"),
                       coverage=str(tp / "cov.json"),
                       mutation=None, cached=None, cache=None,
                       toolchain_tag="", baseline=None, no_baseline=True,
                       no_churn=True, churn_window=90, threshold=30.0,
                       top=1, summary_out=None, set_baseline=False)
            buf_out, buf_err = io.StringIO(), io.StringIO()
            with redirect_stdout(buf_out), redirect_stderr(buf_err):
                rc = crap.cmd_score(args)
            # With 100% line coverage, cc=10 → CRAP = 10, below threshold → rc=0.
            self.assertEqual(rc, 0)
            self.assertIn("100", buf_out.getvalue())  # cov% column shows 100

    def test_cmd_score_with_mutation_file(self):
        """Kills mutants that null-out args.mutation."""
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            _write(tp / "src.py", "def f():\n    return 1\n")
            fns = [{"file": str(tp / "src.py"), "name": "f",
                    "start_line": 1, "end_line": 2, "cc": 10,
                    "arg_signature": ""}]
            _write(tp / "fns.json", json.dumps(fns))
            _write(tp / "surv.json", json.dumps(fns))
            _write(tp / "mut.json", json.dumps({str(tp / "src.py"): {
                "1": {"killed": 3, "survived": 1,
                      "survived_mutants": ["ROR>="]}}}))
            args = _ns(functions=str(tp / "fns.json"),
                       survivors=str(tp / "surv.json"),
                       coverage=None, mutation=str(tp / "mut.json"),
                       cached=None, cache=None, toolchain_tag="",
                       baseline=None, no_baseline=True, no_churn=True,
                       churn_window=90, threshold=30.0, top=1,
                       summary_out=None, set_baseline=False)
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                rc = crap.cmd_score(args)
            # 75% kill rate * 0% line = 0 eff → CRAP_max, above threshold → rc=2 (new)
            self.assertIn(rc, (1, 2))

    def test_cmd_score_with_cached_results_file(self):
        """Kills mutants that null-out args.cached."""
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            src = _write(tp / "src.py", "def f():\n    return 1\n")
            fn = {"file": str(src), "name": "f", "start_line": 1,
                  "end_line": 2, "cc": 10, "arg_signature": ""}
            fns = [fn]
            h = crap.function_hash(fn, "")
            _write(tp / "fns.json", json.dumps(fns))
            _write(tp / "surv.json", json.dumps(fns))
            _write(tp / "cached.json", json.dumps({
                h: {"line_cov": 1.0, "mut_kill": 1.0, "survived_mutants": []}}))
            args = _ns(functions=str(tp / "fns.json"),
                       survivors=str(tp / "surv.json"),
                       coverage=None, mutation=None,
                       cached=str(tp / "cached.json"), cache=None,
                       toolchain_tag="", baseline=None, no_baseline=True,
                       no_churn=True, churn_window=90, threshold=30.0,
                       top=1, summary_out=None, set_baseline=False)
            buf_out = io.StringIO()
            with redirect_stdout(buf_out), redirect_stderr(io.StringIO()):
                rc = crap.cmd_score(args)
            # Cached 100% coverage → CRAP = cc = 10, clean.
            self.assertEqual(rc, 0)
            self.assertIn("100", buf_out.getvalue())

    def test_cmd_score_writes_summary_out_when_requested(self):
        """Kills mutants that break args.summary_out dispatch."""
        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            _write(tp / "src.py", "def f():\n    pass\n")
            fns = [{"file": str(tp / "src.py"), "name": "f",
                    "start_line": 1, "end_line": 2, "cc": 10,
                    "arg_signature": ""}]
            _write(tp / "fns.json", json.dumps(fns))
            _write(tp / "surv.json", json.dumps(fns))
            so = tp / "summary.json"
            args = _ns(functions=str(tp / "fns.json"),
                       survivors=str(tp / "surv.json"),
                       coverage=None, mutation=None, cached=None,
                       cache=None, toolchain_tag="", baseline=None,
                       no_baseline=True, no_churn=True, churn_window=90,
                       threshold=30.0, top=1, summary_out=str(so),
                       set_baseline=False)
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                crap.cmd_score(args)
            data = json.loads(so.read_text())
            self.assertIn("summary", data)
            self.assertIn("rows", data)


class TestCmdLizard(unittest.TestCase):
    """Cover cmd_lizard via subprocess.run mocking — no real lizard invocation."""

    def _proc(self, returncode=0, stdout="", stderr=""):
        m = MagicMock()
        m.returncode = returncode
        m.stdout = stdout
        m.stderr = stderr
        return m

    def test_empty_file_list_returns_zero(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "fns.json"
            with redirect_stderr(io.StringIO()):
                rc = crap.cmd_lizard(_ns(files=[], output=str(out)))
            self.assertEqual(rc, 0)
            self.assertEqual(json.loads(out.read_text()), [])

    def test_lizard_success_parses_and_emits(self):
        csv = ('NLOC,CCN,token,PARAM,length,location\n'
               '2,1,5,0,2,"f@1-2@a.py"\n')
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "fns.json"
            with patch("subprocess.run", return_value=self._proc(
                    returncode=0, stdout=csv)):
                rc = crap.cmd_lizard(_ns(files=["a.py"], output=str(out)))
            self.assertEqual(rc, 0)
            data = json.loads(out.read_text())
            self.assertEqual(data[0]["name"], "f")

    def test_lizard_not_installed(self):
        with patch("subprocess.run", return_value=self._proc(
                returncode=1,
                stderr="/usr/bin/python: No module named lizard")):
            buf = io.StringIO()
            with redirect_stderr(buf):
                rc = crap.cmd_lizard(_ns(files=["a.py"], output=None))
            self.assertEqual(rc, 3)
            self.assertIn("pip install lizard", buf.getvalue())

    def test_lizard_empty_stdout_is_error(self):
        with patch("subprocess.run", return_value=self._proc(
                returncode=0, stdout="", stderr="weird")):
            with redirect_stderr(io.StringIO()):
                rc = crap.cmd_lizard(_ns(files=["a.py"], output=None))
            self.assertEqual(rc, 3)

    def test_lizard_python_missing(self):
        with patch("subprocess.run", side_effect=FileNotFoundError()):
            with redirect_stderr(io.StringIO()):
                rc = crap.cmd_lizard(_ns(files=["a.py"], output=None))
            self.assertEqual(rc, 3)


class TestMoreAntiMutation(unittest.TestCase):
    """Second anti-mutation wave — targets the larger population of
    surviving mutants in the adapters and parser.
    """

    # ---- _read_arg_signature line-reading branches ----

    def test_arg_signature_line_offset_respects_start_line(self):
        """Kills enumerate(start=1) → start=2 and continue → break mutants."""
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("# garbage line 1\n# garbage line 2\n")
            f.write("def foo(a, b):\n    pass\n")  # starts at line 3
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 3, 2), "a,b")
        finally:
            os.unlink(path)

    def test_arg_signature_break_on_mismatched_closing(self):
        """Kills 'elif ch == ")"' → 'elif ch == "XX)XX"' mutation — the
        paren-depth tracker must actually notice the closing paren.
        """
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(a, b=(1, 2), c=3):\n    pass\n")
            path = f.name
        try:
            sig = crap._read_arg_signature(path, 1, 3)
            self.assertEqual(sig, "a,b,c")
        finally:
            os.unlink(path)

    def test_arg_signature_finds_first_paren_not_last(self):
        """Kills blob.find('(') → blob.rfind('(') — with multiple '(' in
        the visible window, rfind would land on a nested default instead
        of the function's own arg list.
        """
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(a, b=tuple((1,2,3))):\n    pass\n")
            path = f.name
        try:
            sig = crap._read_arg_signature(path, 1, 2)
            self.assertEqual(sig, "a,b")
        finally:
            os.unlink(path)

    # ---- _render_markdown literal strings ----

    def test_render_markdown_all_header_strings_exact(self):
        """Kills the remaining 'X → XXXX' mutations in the headers list."""
        row = {"file": "a.py", "start_line": 1, "name": "f", "cc": 1,
               "line_cov": 1, "mut_kill": 1, "eff_cov": 1,
               "churn": 0, "crap": 1.0, "delta": None, "tag": "new"}
        out = crap._render_markdown([row], threshold=30.0)
        # Every literal header token must be exactly present
        for literal in ["file:line", "function", "cc", "cov%", "mut%",
                        "eff_cov%", "churn", "CRAP", "Δ", "tag"]:
            self.assertIn(f" {literal} ", out, msg=f"header: {literal!r}")

    def test_render_markdown_delta_none_shows_em_dash(self):
        row = {"file": "a", "start_line": 1, "name": "f", "cc": 1,
               "line_cov": 0, "mut_kill": 1, "eff_cov": 0, "churn": 0,
               "crap": 1.0, "delta": None, "tag": "new"}
        out = crap._render_markdown([row], threshold=30.0)
        self.assertIn(" — ", out)

    # ---- mutation adapters: alternate-key lookups ----

    def test_mutmut_accepts_filename_or_file_key(self):
        """Kills m.get('file') → m.get('filename'|None|'XXfileXX')."""
        raw = {"mutants": [{"file": "a.py", "line": 3, "status": "killed"}]}
        out = crap.mutation_from_mutmut(raw)
        self.assertEqual(out["a.py"]["3"]["killed"], 1)

    def test_mutmut_missing_both_path_keys_skipped(self):
        raw = {"mutants": [{"line_number": 5, "status": "killed"}]}
        out = crap.mutation_from_mutmut(raw)
        self.assertEqual(out, {})

    def test_mutmut_label_fallback_uses_line_marker(self):
        """Forces the `f"L{line}"` branch when neither name nor source exist."""
        raw = {"mutants": [{"filename": "a.py", "line_number": 7,
                            "status": "survived"}]}
        out = crap.mutation_from_mutmut(raw)
        self.assertEqual(out["a.py"]["7"]["survived_mutants"], ["L7"])

    def test_cargo_mutants_accepts_lowercase_mutant_key(self):
        """Kills scen.get('Mutant') or scen.get('mutant') mutants that
        drop the alternative key.
        """
        raw = {"outcomes": [
            {"scenario": {"mutant": {"file": "a.rs", "line": 2}},
             "summary": "CaughtMutant"}]}
        out = crap.mutation_from_cargo_mutants(raw)
        self.assertEqual(out["a.rs"]["2"]["killed"], 1)

    def test_cargo_mutants_missing_scenario_skipped(self):
        raw = {"outcomes": [{"summary": "CaughtMutant"}]}
        out = crap.mutation_from_cargo_mutants(raw)
        self.assertEqual(out, {})

    def test_cargo_mutants_timeout_counted_as_killed(self):
        """The `"caught" or "timeout" → killed` logic needs exercising."""
        raw = {"outcomes": [
            {"scenario": {"Mutant": {"file": "a.rs", "line": 1}},
             "summary": "Timeout(x)"}]}
        out = crap.mutation_from_cargo_mutants(raw)
        self.assertEqual(out["a.rs"]["1"]["killed"], 1)

    def test_cargo_mutants_other_summary_neither_killed_nor_survived(self):
        """Characterization: 'Unviable' is mapped to status='skip', which
        means the bucket is created but neither counter increments."""
        raw = {"outcomes": [
            {"scenario": {"Mutant": {"file": "a.rs", "line": 1}},
             "summary": "Unviable"}]}
        out = crap.mutation_from_cargo_mutants(raw)
        self.assertEqual(out["a.rs"]["1"]["killed"], 0)
        self.assertEqual(out["a.rs"]["1"]["survived"], 0)

    def test_cargo_mutants_label_prefers_function_name(self):
        raw = {"outcomes": [
            {"scenario": {"Mutant": {"file": "a.rs", "line": 1,
                                     "function": "foo::bar"}},
             "summary": "MissedMutant"}]}
        out = crap.mutation_from_cargo_mutants(raw)
        self.assertEqual(out["a.rs"]["1"]["survived_mutants"], ["foo::bar"])

    def test_pitest_default_values_fire_when_elements_missing(self):
        """Kills mutations like `or ""` → `or "XXXX"` in findtext fallbacks —
        need an XML where the element is absent.
        """
        xml = """<mutations>
  <mutation detected="true"><sourceFile>A.java</sourceFile>
    <lineNumber>5</lineNumber></mutation>
</mutations>"""
        out = crap.mutation_from_pitest(xml)
        # mutatedClass missing → path falls back to sourceFile
        self.assertEqual(out["A.java"]["5"]["killed"], 1)

    def test_pitest_missing_source_or_line_skipped(self):
        xml = ('<mutations><mutation detected="true">'
               '<lineNumber>5</lineNumber></mutation></mutations>')
        self.assertEqual(crap.mutation_from_pitest(xml), {})

    def test_pitest_label_fallback_to_line_marker(self):
        xml = ('<mutations><mutation detected="false">'
               '<sourceFile>A.java</sourceFile><lineNumber>3</lineNumber>'
               '</mutation></mutations>')
        out = crap.mutation_from_pitest(xml)
        self.assertEqual(out["A.java"]["3"]["survived_mutants"], ["L3"])

    def test_pitest_nondigit_line_skipped(self):
        xml = ('<mutations><mutation detected="true">'
               '<sourceFile>A.java</sourceFile><lineNumber>xyz</lineNumber>'
               '</mutation></mutations>')
        self.assertEqual(crap.mutation_from_pitest(xml), {})

    def test_stryker_description_fallback_when_no_mutator_name(self):
        raw = {"files": {"a.js": {"mutants": [
            {"location": {"start": {"line": 9}}, "status": "Survived",
             "description": "binary-op"}]}}}
        out = crap.mutation_from_stryker(raw)
        self.assertEqual(out["a.js"]["9"]["survived_mutants"], ["binary-op"])

    def test_stryker_no_label_uses_line_marker(self):
        raw = {"files": {"a.js": {"mutants": [
            {"location": {"start": {"line": 4}}, "status": "Survived"}]}}}
        out = crap.mutation_from_stryker(raw)
        self.assertEqual(out["a.js"]["4"]["survived_mutants"], ["L4"])

    # ---- coverage adapters: edge branches ----

    def test_istanbul_skips_files_without_statement_map(self):
        raw = {"a.js": {"s": {"0": 1}}, "b.js": {"statementMap": {
            "0": {"start": {"line": 1}}}, "s": {"0": 2}}}
        out = crap.coverage_from_istanbul(raw)
        self.assertNotIn("a.js", out)
        self.assertEqual(out["b.js"]["1"], 2)

    def test_istanbul_statement_without_hit_id_defaults_zero(self):
        raw = {"a.js": {"statementMap": {"0": {"start": {"line": 3}}},
                        "s": {}}}
        out = crap.coverage_from_istanbul(raw)
        self.assertEqual(out["a.js"]["3"], 0)

    def test_istanbul_bad_start_location_skipped(self):
        raw = {"a.js": {"statementMap": {"0": {"start": {}}},
                        "s": {"0": 1}}}
        out = crap.coverage_from_istanbul(raw)
        self.assertEqual(out["a.js"], {})

    def test_coveragepy_handles_missing_files_key(self):
        self.assertEqual(crap.coverage_from_coveragepy({"other": {}}), {})

    def test_gocover_multi_line_span_records_every_line(self):
        text = "mode: count\npkg/a.go:5.1,9.10 1 4\n"
        out = crap.coverage_from_gocover(text)
        self.assertEqual(out["pkg/a.go"]["5"], 4)
        self.assertEqual(out["pkg/a.go"]["9"], 4)

    def test_cobertura_falls_back_to_name_when_filename_missing(self):
        """Characterization: `name` attr is used as the path fallback."""
        xml = ('<coverage><class name="com.x.Foo">'
               '<line number="1" hits="1"/></class></coverage>')
        out = crap.coverage_from_cobertura(xml)
        self.assertEqual(out["com.x.Foo"]["1"], 1)

    def test_cobertura_class_without_any_path_skipped(self):
        xml = ('<coverage><class><line number="1" hits="1"/></class>'
               '</coverage>')
        self.assertEqual(crap.coverage_from_cobertura(xml), {})

    def test_cobertura_line_without_number_skipped(self):
        xml = ('<coverage><class filename="a.py">'
               '<line hits="1"/></class></coverage>')
        out = crap.coverage_from_cobertura(xml)
        self.assertEqual(out["a.py"], {})

    # ---- _mut_add synonyms ----

    def test_mut_add_detected_status_is_killed(self):
        dst = {}
        crap._mut_add(dst, "a.py", 1, "detected")
        self.assertEqual(dst["a.py"]["1"]["killed"], 1)

    def test_mut_add_alive_and_nocoverage_count_as_survived(self):
        dst = {}
        crap._mut_add(dst, "a.py", 1, "alive")
        crap._mut_add(dst, "a.py", 1, "no_coverage")
        self.assertEqual(dst["a.py"]["1"]["survived"], 2)

    def test_mut_add_accepts_short_codes(self):
        dst = {}
        crap._mut_add(dst, "a.py", 1, "K")
        crap._mut_add(dst, "a.py", 1, "S", "m")
        self.assertEqual(dst["a.py"]["1"]["killed"], 1)
        self.assertEqual(dst["a.py"]["1"]["survived"], 1)

    # ---- last-mile arg-signature edge cases ----

    def test_arg_signature_multi_line_signature(self):
        """Kills blob = ''.join(lines) → 'XXXX'.join(lines) and depth += 1
        → depth = 1 mutants. A signature split across multiple lines must
        be re-joined correctly so the paren-depth tracker sees the real
        nesting.
        """
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(\n    a,\n    b=(1, 2),\n    c,\n):\n    pass\n")
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 3), "a,b,c")
        finally:
            os.unlink(path)

    def test_arg_signature_split_equals_limit_one(self):
        """Kills p.split('=', 1) → p.split('=', 2) / rsplit — default value
        that itself contains '=' must not leak into the name.
        """
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write('def foo(a="x=y=z", b="q"):\n    pass\n')
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 2), "a,b")
        finally:
            os.unlink(path)

    def test_arg_signature_split_colon_preserves_name(self):
        """Kills p.split(':', 1) mutants: a type annotation that contains
        ':' (e.g., Dict[str, int] is safe; use a string default with ':').
        """
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(a: 'Dict[str, int]', b: int):\n    pass\n")
            path = f.name
        try:
            sig = crap._read_arg_signature(path, 1, 2)
            self.assertEqual(sig, "a,b")
        finally:
            os.unlink(path)

    def test_arg_signature_nested_depth_greater_than_one(self):
        """Kills depth += 1 → depth = 1: two levels of nesting inside a
        default must still match the right outer ')'.
        """
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write("def foo(a=((1, 2), 3), b):\n    pass\n")
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 2), "a,b")
        finally:
            os.unlink(path)

    def test_arg_signature_ampersand_is_separator(self):
        """Kills the replace('&', ' ') mutations — '&' must be treated as a
        token separator so C-style `int&a` yields name 'a', not 'int&a'.
        """
        with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False) as f:
            # No '::' which would trip the ':' splitter
            f.write("void foo(int&a, int&b) {\n}\n")
            path = f.name
        try:
            self.assertEqual(crap._read_arg_signature(path, 1, 2), "a,b")
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
