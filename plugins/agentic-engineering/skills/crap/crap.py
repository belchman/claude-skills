#!/usr/bin/env python3
"""crap.py — CRAP-score pipeline helper (stdlib only).

Subcommands:
  lizard        run `lizard --csv` on files → normalized functions.json
  parse-lizard  parse an existing lizard --csv file → functions.json
  filter        drop fns whose CRAP_max <= threshold → survivors.json
  cache-split   split survivors into cached/to-measure by content hash
  normalize-coverage  convert a tool-specific coverage report → normalized JSON
  normalize-mutation  convert a tool-specific mutation report  → normalized JSON
  score         compute CRAP, join churn + baseline, emit markdown table, set exit code

CRAP(fn) = cc^2 * (1 - eff_cov/100)^3 + cc
eff_cov  = line_cov * mutation_kill_rate
"""
from __future__ import annotations

import argparse
import csv
import fnmatch
import hashlib
import io
import json
import math
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

# ----------------------------------------------------------------------------- #
# IO helpers
# ----------------------------------------------------------------------------- #

def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def dump_json(obj: Any, path: str | None = None) -> None:
    text = json.dumps(obj, indent=2, sort_keys=True)
    if path is None:
        sys.stdout.write(text + "\n")
    else:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)


def eprint(*args: Any) -> None:
    print(*args, file=sys.stderr)


# ----------------------------------------------------------------------------- #
# lizard CSV parsing
# ----------------------------------------------------------------------------- #
#
# `lizard --csv` emits one row per function with:
#   NLOC,CCN,token,PARAM,length,location
# where `location` = "funcname@startline-endline@path/to/file"
# or occasionally "funcname@startline@path/to/file" (when start==end).
#
# Example row:
#   12,3,45,2,15,"my_func@10-24@src/foo.py"
#
# We normalize into:
#   {"file": str, "name": str, "start_line": int, "end_line": int,
#    "cc": int, "arg_signature": str}
#
# `arg_signature` is a best-effort "a,b,c" derived from the source lines.
# It is only used as a secondary baseline key (name+args), so a crude reading
# is fine: we fall back to PARAM count if we can't parse.

_LOC_RE = re.compile(r"^(?P<name>.+)@(?P<start>\d+)(?:-(?P<end>\d+))?@(?P<file>.+)$")


def parse_lizard_csv(text: str) -> list[dict[str, Any]]:
    reader = csv.reader(io.StringIO(text))
    rows = list(reader)
    if not rows:
        return []
    # Detect header row. Lizard's first row is the header.
    header = [c.strip().lower() for c in rows[0]]
    has_header = header[:2] == ["nloc", "ccn"]
    data_rows = rows[1:] if has_header else rows

    out: list[dict[str, Any]] = []
    for row in data_rows:
        if len(row) < 6:
            continue
        nloc, ccn, _tokens, param, _length, location = row[:6]
        try:
            cc = int(ccn)
            param_n = int(param)
        except ValueError:
            continue
        m = _LOC_RE.match(location)
        if not m:
            continue
        start = int(m.group("start"))
        end = int(m.group("end")) if m.group("end") else start
        file_path = m.group("file")
        name = m.group("name")
        # Best-effort arg sig: first N identifiers we can read from the source
        arg_sig = _read_arg_signature(file_path, start, param_n)
        out.append({
            "file": file_path,
            "name": name,
            "start_line": start,
            "end_line": end,
            "cc": cc,
            "nloc": int(nloc) if nloc.isdigit() else 0,
            "param_count": param_n,
            "arg_signature": arg_sig,
        })
    return out


def _read_arg_signature(file_path: str, start_line: int, param_count: int) -> str:
    """Read the first few lines of the function and extract a param sig.

    Best-effort, language-agnostic. We look for a '(' and take up to the matching
    ')', then split on commas and strip types/annotations. Returns a string of
    the form "a,b,c" or "" on any failure.
    """
    if param_count == 0:
        return ""
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as fh:
            # Read at most 50 lines starting at start_line
            lines = []
            for idx, line in enumerate(fh, start=1):
                if idx < start_line:
                    continue
                lines.append(line)
                if len(lines) >= 50:
                    break
    except OSError:
        return ""
    blob = "".join(lines)
    open_idx = blob.find("(")
    if open_idx < 0:
        return ""
    depth = 0
    end_idx = -1
    for i, ch in enumerate(blob[open_idx:], start=open_idx):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end_idx = i
                break
    if end_idx < 0:
        return ""
    inner = blob[open_idx + 1:end_idx]
    # Split on commas at depth 0
    parts: list[str] = []
    depth = 0
    buf: list[str] = []
    for ch in inner:
        if ch in "([{<":
            depth += 1
            buf.append(ch)
        elif ch in ")]}>":
            depth -= 1
            buf.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    if buf:
        parts.append("".join(buf).strip())
    names = []
    for p in parts:
        if not p:
            continue
        # Strip trailing default value
        p = p.split("=", 1)[0].strip()
        # Strip type annotation "name: Type" or "Type name"
        if ":" in p:
            p = p.split(":", 1)[0].strip()
        tokens = p.replace("*", " ").replace("&", " ").split()
        if tokens:
            names.append(tokens[-1])
    return ",".join(names)


def cmd_parse_lizard(args: argparse.Namespace) -> int:
    with open(args.path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    fns = parse_lizard_csv(text)
    dump_json(fns, args.output)
    return 0


def cmd_lizard(args: argparse.Namespace) -> int:
    """Run lizard --csv on the given files and emit functions.json.

    Uses `python -m lizard` so it works regardless of whether the `lizard`
    console script is on PATH (common pip-install-without-symlink case).
    """
    files = args.files
    if not files:
        eprint("crap: no files given to lizard")
        dump_json([], args.output)
        return 0
    cmd = [sys.executable, "-m", "lizard", "--csv", *files]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        eprint("crap: python executable not found?")
        return 3
    # `python -m lizard` exits non-zero only when the module isn't importable
    if proc.returncode != 0 and "No module named" in (proc.stderr or ""):
        eprint("crap: lizard is not installed. Install with: pip install lizard")
        return 3
    if not proc.stdout.strip():
        eprint("crap: lizard produced no output")
        eprint(proc.stderr)
        return 3
    fns = parse_lizard_csv(proc.stdout)
    dump_json(fns, args.output)
    return 0


# ----------------------------------------------------------------------------- #
# Filter (CRAP_max pass 1)
# ----------------------------------------------------------------------------- #

def crap_max(cc: int) -> float:
    """Value of CRAP when eff_cov = 0 — the worst case for a given cc."""
    return float(cc * cc + cc)


def crap_score(cc: int, eff_cov_pct: float) -> float:
    """eff_cov_pct is 0..100."""
    gap = 1.0 - (max(0.0, min(100.0, eff_cov_pct)) / 100.0)
    return float(cc * cc) * (gap ** 3) + float(cc)


def cmd_filter(args: argparse.Namespace) -> int:
    fns = load_json(args.functions)
    threshold = args.threshold
    survivors = [fn for fn in fns if crap_max(int(fn["cc"])) > threshold]
    dump_json(survivors, args.output)
    return 0


# ----------------------------------------------------------------------------- #
# Cache
# ----------------------------------------------------------------------------- #

def read_function_bytes(file_path: str, start: int, end: int) -> bytes:
    try:
        with open(file_path, "rb") as fh:
            data = fh.read()
    except OSError:
        return b""
    lines = data.splitlines(keepends=True)
    # 1-indexed inclusive
    start_i = max(0, start - 1)
    end_i = min(len(lines), end)
    return b"".join(lines[start_i:end_i])


def function_hash(fn: dict[str, Any], toolchain_tag: str = "") -> str:
    body = read_function_bytes(fn["file"], fn["start_line"], fn["end_line"])
    h = hashlib.sha256()
    h.update(body)
    if toolchain_tag:
        h.update(b"\x00")
        h.update(toolchain_tag.encode("utf-8"))
    return h.hexdigest()


def cmd_cache_split(args: argparse.Namespace) -> int:
    survivors = load_json(args.survivors)
    cache_dir = Path(args.cache)
    cache_dir.mkdir(parents=True, exist_ok=True)

    to_measure: list[dict[str, Any]] = []
    cached: dict[str, dict[str, Any]] = {}   # fn_hash → {line_cov, mut_kill, survived_mutants}
    for fn in survivors:
        h = function_hash(fn, args.toolchain_tag or "")
        fn["_hash"] = h
        cache_file = cache_dir / (h + ".json")
        if cache_file.exists():
            try:
                cached[h] = load_json(str(cache_file))
            except Exception:
                to_measure.append(fn)
        else:
            to_measure.append(fn)

    dump_json(to_measure, args.to_measure)
    dump_json(cached, args.cached_results)
    eprint(f"crap: cache-split {len(cached)}/{len(survivors)} hit, {len(to_measure)} to measure")
    return 0


# ----------------------------------------------------------------------------- #
# Coverage adapters
# ----------------------------------------------------------------------------- #
#
# Normalized format: {file_path: {line_num (str): hit_count (int)}}
# Paths are repo-relative.

def _resolve_path(p: str, root: Path | None = None) -> str:
    if not p:
        return p
    pp = Path(p)
    if pp.is_absolute() and root is not None:
        try:
            return str(pp.relative_to(root))
        except ValueError:
            return str(pp)
    return str(pp)


def coverage_from_coveragepy(raw: dict[str, Any]) -> dict[str, dict[str, int]]:
    """coverage json output:
    {"files": {path: {"executed_lines": [..], "missing_lines": [..], ...}}}
    """
    out: dict[str, dict[str, int]] = {}
    for path, data in (raw.get("files") or {}).items():
        norm = _resolve_path(path)
        lines: dict[str, int] = {}
        for ln in data.get("executed_lines", []) or []:
            lines[str(ln)] = 1
        for ln in data.get("missing_lines", []) or []:
            lines.setdefault(str(ln), 0)
        out[norm] = lines
    return out


def coverage_from_istanbul(raw: dict[str, Any]) -> dict[str, dict[str, int]]:
    """jest/vitest coverage-final.json (istanbul shape):
    {path: {statementMap: {id: {start: {line}, end: {line}}},
            s: {id: hits}, ...}}
    """
    out: dict[str, dict[str, int]] = {}
    for path, data in raw.items():
        if not isinstance(data, dict) or "statementMap" not in data:
            continue
        norm = _resolve_path(path)
        stmt_map = data.get("statementMap") or {}
        hits = data.get("s") or {}
        lines: dict[str, int] = {}
        for stmt_id, loc in stmt_map.items():
            try:
                ln = int(loc["start"]["line"])
            except (KeyError, TypeError, ValueError):
                continue
            h = int(hits.get(stmt_id, 0) or 0)
            cur = lines.get(str(ln), 0)
            lines[str(ln)] = cur + h if h else cur
            lines.setdefault(str(ln), 0)
        out[norm] = lines
    return out


def coverage_from_gocover(text: str) -> dict[str, dict[str, int]]:
    """`go test -coverprofile=x.out` text:
    mode: set|count|atomic
    path/to/file.go:startLine.startCol,endLine.endCol numStmts hits
    """
    out: dict[str, dict[str, int]] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("mode:"):
            continue
        # file.go:sl.sc,el.ec n h
        try:
            loc, _nstmts, hits_s = line.rsplit(" ", 2)
            path, span = loc.split(":", 1)
            start_s, end_s = span.split(",")
            sl = int(start_s.split(".")[0])
            el = int(end_s.split(".")[0])
            hits = int(hits_s)
        except ValueError:
            continue
        norm = _resolve_path(path)
        file_map = out.setdefault(norm, {})
        for ln in range(sl, el + 1):
            cur = file_map.get(str(ln), 0)
            file_map[str(ln)] = cur + hits
    return out


_LCOV_SF_RE = re.compile(r"^SF:(.+)$")
_LCOV_DA_RE = re.compile(r"^DA:(\d+),(\d+)(?:,[A-Fa-f0-9]+)?$")


def coverage_from_lcov(text: str) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    cur_file: str | None = None
    cur_map: dict[str, int] | None = None
    for raw in text.splitlines():
        line = raw.strip()
        m = _LCOV_SF_RE.match(line)
        if m:
            cur_file = _resolve_path(m.group(1))
            cur_map = out.setdefault(cur_file, {})
            continue
        if line == "end_of_record":
            cur_file = None
            cur_map = None
            continue
        if cur_map is None:
            continue
        m = _LCOV_DA_RE.match(line)
        if m:
            ln, hits = m.group(1), int(m.group(2))
            cur_map[ln] = hits
    return out


def coverage_from_cobertura(xml_text: str) -> dict[str, dict[str, int]]:
    """Cobertura XML (tarpaulin, some others)."""
    out: dict[str, dict[str, int]] = {}
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return out
    for cls in root.iter("class"):
        path = cls.attrib.get("filename") or cls.attrib.get("name") or ""
        if not path:
            continue
        norm = _resolve_path(path)
        file_map = out.setdefault(norm, {})
        for line in cls.iter("line"):
            ln = line.attrib.get("number")
            hits = line.attrib.get("hits", "0")
            if ln is None:
                continue
            try:
                file_map[ln] = int(hits)
            except ValueError:
                file_map[ln] = 0
    return out


COVERAGE_ADAPTERS = {
    "normalized": lambda t: json.loads(t),
    "coveragepy":  lambda t: coverage_from_coveragepy(json.loads(t)),
    "istanbul":    lambda t: coverage_from_istanbul(json.loads(t)),
    "jest":        lambda t: coverage_from_istanbul(json.loads(t)),
    "vitest":      lambda t: coverage_from_istanbul(json.loads(t)),
    "gocover":     coverage_from_gocover,
    "lcov":        coverage_from_lcov,
    "cobertura":   coverage_from_cobertura,
    "tarpaulin":   coverage_from_cobertura,
}


def cmd_normalize_coverage(args: argparse.Namespace) -> int:
    adapter = COVERAGE_ADAPTERS.get(args.tool)
    if adapter is None:
        eprint(f"crap: unknown coverage tool '{args.tool}'. "
               f"Supported: {', '.join(sorted(COVERAGE_ADAPTERS))}")
        return 3
    with open(args.path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    out = adapter(text)
    dump_json(out, args.output)
    return 0


# ----------------------------------------------------------------------------- #
# Mutation adapters
# ----------------------------------------------------------------------------- #
#
# Normalized format:
# {file_path: {line (str): {"killed": int, "survived": int,
#                           "survived_mutants": [str, ...]}}}

def _mut_bucket() -> dict[str, Any]:
    return {"killed": 0, "survived": 0, "survived_mutants": []}


def _mut_add(dst: dict[str, dict[str, Any]], path: str, line: int,
             status: str, label: str = "") -> None:
    norm = _resolve_path(path)
    file_map = dst.setdefault(norm, {})
    bucket = file_map.setdefault(str(line), _mut_bucket())
    s = status.lower()
    if s in ("killed", "detected", "k"):
        bucket["killed"] += 1
    elif s in ("survived", "alive", "live", "no_coverage", "s"):
        bucket["survived"] += 1
        if label:
            bucket["survived_mutants"].append(label)
    # skip timeout/suspicious/runtime_error/etc. — they're noise


def mutation_from_mutmut(raw: Any) -> dict[str, dict[str, dict[str, Any]]]:
    """mutmut results --json:
    {"mutants": [{"filename":..., "line_number":..., "status":...,
                  "mutant_name":..., "source":...}, ...]}
    """
    out: dict[str, dict[str, dict[str, Any]]] = {}
    items = raw.get("mutants") if isinstance(raw, dict) else raw
    for m in items or []:
        path = m.get("filename") or m.get("file") or ""
        line = int(m.get("line_number") or m.get("line") or 0)
        if not path or line <= 0:
            continue
        label = m.get("mutant_name") or m.get("source") or f"L{line}"
        _mut_add(out, path, line, str(m.get("status", "")), label)
    return out


def mutation_from_stryker(raw: dict[str, Any]) -> dict[str, dict[str, dict[str, Any]]]:
    """Stryker mutation-report JSON:
    {"files": {path: {"mutants": [{"location":{"start":{"line":..}},
                                   "status":..., "mutatorName":...}]}}}
    """
    out: dict[str, dict[str, dict[str, Any]]] = {}
    for path, data in (raw.get("files") or {}).items():
        for m in data.get("mutants") or []:
            try:
                ln = int(m["location"]["start"]["line"])
            except (KeyError, TypeError, ValueError):
                continue
            label = m.get("mutatorName") or m.get("description") or f"L{ln}"
            _mut_add(out, path, ln, str(m.get("status", "")), label)
    return out


def mutation_from_cargo_mutants(raw: Any) -> dict[str, dict[str, dict[str, Any]]]:
    """cargo-mutants outcomes.json:
    {"outcomes": [{"scenario": {"Mutant": {"file": "...", "line": N,
                                           "function": "...", ...}},
                   "summary": "CaughtMutant"|"MissedMutant"|...}]}
    """
    out: dict[str, dict[str, dict[str, Any]]] = {}
    items = raw.get("outcomes") if isinstance(raw, dict) else raw
    for o in items or []:
        scen = o.get("scenario", {})
        mut = scen.get("Mutant") or scen.get("mutant") or {}
        path = mut.get("file") or ""
        line = int(mut.get("line") or 0)
        if not path or line <= 0:
            continue
        summary = str(o.get("summary", ""))
        status = "killed" if "caught" in summary.lower() or "timeout" in summary.lower() \
                 else "survived" if "missed" in summary.lower() else "skip"
        label = mut.get("function") or mut.get("description") or f"L{line}"
        _mut_add(out, path, line, status, label)
    return out


def mutation_from_pitest(xml_text: str) -> dict[str, dict[str, dict[str, Any]]]:
    """PIT mutations.xml: <mutation detected="true|false">...<sourceFile>..</>
       <mutatedClass>..</><lineNumber>..</></mutation>"""
    out: dict[str, dict[str, dict[str, Any]]] = {}
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return out
    for m in root.iter("mutation"):
        src = (m.findtext("sourceFile") or "").strip()
        cls = (m.findtext("mutatedClass") or "").strip()
        ln = (m.findtext("lineNumber") or "").strip()
        mutator = (m.findtext("mutator") or "").strip()
        detected = m.attrib.get("detected", "false").lower() == "true"
        if not src or not ln:
            continue
        # Build a path that uses the package hint if present
        path = f"{cls.replace('.', '/').rsplit('/', 1)[0]}/{src}" if cls else src
        try:
            line = int(ln)
        except ValueError:
            continue
        label = mutator.rsplit(".", 1)[-1] or f"L{line}"
        _mut_add(out, path, line, "killed" if detected else "survived", label)
    return out


MUTATION_ADAPTERS = {
    "normalized":     lambda t: json.loads(t),
    "mutmut":         lambda t: mutation_from_mutmut(json.loads(t)),
    "stryker":        lambda t: mutation_from_stryker(json.loads(t)),
    "cargo-mutants":  lambda t: mutation_from_cargo_mutants(json.loads(t)),
    "pitest":         mutation_from_pitest,
}


def cmd_normalize_mutation(args: argparse.Namespace) -> int:
    adapter = MUTATION_ADAPTERS.get(args.tool)
    if adapter is None:
        eprint(f"crap: unknown mutation tool '{args.tool}'. "
               f"Supported: {', '.join(sorted(MUTATION_ADAPTERS))}")
        return 3
    with open(args.path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    out = adapter(text)
    dump_json(out, args.output)
    return 0


# ----------------------------------------------------------------------------- #
# Churn
# ----------------------------------------------------------------------------- #

def churn_commits(file_path: str, window_days: int) -> int:
    try:
        proc = subprocess.run(
            ["git", "log", f"--since={window_days} days ago",
             "--follow", "--format=%H", "--", file_path],
            capture_output=True, text=True, check=False,
        )
    except FileNotFoundError:
        return 0
    if proc.returncode != 0:
        return 0
    return sum(1 for line in proc.stdout.splitlines() if line.strip())


def churn_weight(commits: int) -> float:
    # 1 + log1p(commits) — 0 commits → 1x, 10 commits → ~3.4x, 30 → ~4.4x
    return 1.0 + math.log1p(max(0, commits))


# ----------------------------------------------------------------------------- #
# Scoring
# ----------------------------------------------------------------------------- #

def pct(numer: float, denom: float) -> float:
    if denom <= 0:
        return 0.0
    return 100.0 * numer / denom


def _slice_coverage(coverage: dict[str, dict[str, int]], file: str,
                    start: int, end: int) -> tuple[int, int]:
    """Returns (executed_lines, total_lines_with_data) within [start, end]."""
    file_map = coverage.get(file) or coverage.get(file.lstrip("./")) or {}
    if not file_map:
        return (0, 0)
    hit = total = 0
    for ln_s, h in file_map.items():
        try:
            ln = int(ln_s)
        except ValueError:
            continue
        if start <= ln <= end:
            total += 1
            if h > 0:
                hit += 1
    return hit, total


def _slice_mutation(mutation: dict[str, dict[str, dict[str, Any]]], file: str,
                    start: int, end: int) -> tuple[int, int, list[str]]:
    file_map = mutation.get(file) or mutation.get(file.lstrip("./")) or {}
    if not file_map:
        return (0, 0, [])
    killed = survived = 0
    survivors: list[str] = []
    for ln_s, bucket in file_map.items():
        try:
            ln = int(ln_s)
        except ValueError:
            continue
        if start <= ln <= end:
            killed += int(bucket.get("killed", 0))
            survived += int(bucket.get("survived", 0))
            survivors.extend(bucket.get("survived_mutants") or [])
    return killed, survived, survivors


def _dominant_axis(cc: int, line_cov: float, eff_cov: float) -> str:
    """Decide whether reducing cc or improving tests yields more CRAP reduction.
    Both inputs are 0..1 fractions.
    """
    gap_line = 1.0 - line_cov
    gap_eff = 1.0 - eff_cov
    cc_axis = (cc * cc) * (gap_line ** 3)
    test_axis = (cc * cc) * (gap_eff ** 3) - cc_axis
    return "cc" if cc_axis > test_axis else "tests"


def _baseline_key(fn: dict[str, Any]) -> str:
    return f"{fn['file']}::{fn['name']}::{fn.get('arg_signature', '')}"


def load_baseline(path: str | None) -> dict[str, dict[str, Any]]:
    if not path or not os.path.exists(path):
        return {}
    try:
        data = load_json(path)
    except Exception:
        return {}
    if isinstance(data, dict) and "rows" in data:
        rows = data["rows"]
    elif isinstance(data, list):
        rows = data
    else:
        return {}
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        key = f"{row.get('file')}::{row.get('name')}::{row.get('arg_signature', '')}"
        out[key] = row
    return out


def _measure_one(fn: dict[str, Any], coverage: dict[str, Any],
                 mutation: dict[str, Any], cached_results: dict[str, dict[str, Any]],
                 cache_dir: Path | None, toolchain_tag: str
                 ) -> tuple[float, float, list[str]]:
    """Return (line_cov_frac, mut_kill_frac, survived_mutants) for a survivor.

    Uses the cache when available; otherwise slices coverage/mutation and
    writes the cache. Mutates fn to set "_hash".
    """
    h = fn.get("_hash") or function_hash(fn, toolchain_tag)
    fn["_hash"] = h
    cached = cached_results.get(h)
    if cached:
        return (
            float(cached.get("line_cov", 0.0)),
            float(cached.get("mut_kill", 1.0)),
            list(cached.get("survived_mutants") or []),
        )
    file, start, end = fn["file"], int(fn["start_line"]), int(fn["end_line"])
    hit, total = _slice_coverage(coverage, file, start, end)
    line_cov_frac = (hit / total) if total > 0 else 0.0
    killed, survived, survived_mutants = _slice_mutation(mutation, file, start, end)
    mut_total = killed + survived
    # No mutation data → treat as 1.0 (don't punish for a tool that wasn't run).
    mut_kill_frac = (killed / mut_total) if mut_total > 0 else 1.0
    # Only cache when we actually measured something. Caching a "no data"
    # default would shadow a real measurement on the next run.
    if cache_dir is not None and (total > 0 or mut_total > 0):
        try:
            with open(cache_dir / (h + ".json"), "w", encoding="utf-8") as fh:
                json.dump({
                    "line_cov": line_cov_frac,
                    "mut_kill": mut_kill_frac,
                    "survived_mutants": survived_mutants,
                }, fh)
        except OSError:
            pass
    return line_cov_frac, mut_kill_frac, survived_mutants


def _baseline_tag(base_score: float, prev: dict[str, Any] | None
                  ) -> tuple[str, float | None]:
    if prev is None:
        return "new", None
    delta = base_score - float(prev.get("crap", 0.0))
    if delta > 0.5:
        return "regressed", delta
    if delta < -0.5:
        return "improved", delta
    return "same", delta


def _score_one(fn: dict[str, Any], coverage: dict[str, Any],
               mutation: dict[str, Any], cached_results: dict[str, dict[str, Any]],
               cache_dir: Path | None, toolchain_tag: str,
               baseline_map: dict[str, dict[str, Any]],
               no_churn: bool, churn_window: int) -> dict[str, Any]:
    cc = int(fn["cc"])
    line_cov, mut_kill, survived_mutants = _measure_one(
        fn, coverage, mutation, cached_results, cache_dir, toolchain_tag)
    eff_cov = line_cov * mut_kill
    base_score = crap_score(cc, eff_cov * 100.0)
    if no_churn:
        churn, weight = 0, 1.0
    else:
        churn = churn_commits(fn["file"], churn_window)
        weight = churn_weight(churn)
    tag, delta = _baseline_tag(base_score, baseline_map.get(_baseline_key(fn)))
    return {
        "file": fn["file"],
        "name": fn["name"],
        "start_line": int(fn["start_line"]),
        "end_line": int(fn["end_line"]),
        "cc": cc,
        "arg_signature": fn.get("arg_signature", ""),
        "line_cov": line_cov,
        "mut_kill": mut_kill,
        "eff_cov": eff_cov,
        "churn": churn,
        "weight": weight,
        "crap": base_score,
        "crap_weighted": base_score * weight,
        "tag": tag,
        "delta": delta,
        "survived_mutants": survived_mutants,
        "dominant_axis": _dominant_axis(cc, line_cov, eff_cov),
    }


def _write_baseline(rows: list[dict[str, Any]], survivors: list[dict[str, Any]],
                    all_functions: list[dict[str, Any]], out_path: str) -> int:
    # Baseline for ALL functions, not just survivors, so a future branch
    # can detect "new function above threshold" using the registry.
    # Survivors get measurements; other functions get cc-only defaults.
    survivor_keys = {_baseline_key(fn): True for fn in survivors}
    all_rows: list[dict[str, Any]] = [{
        "file": r["file"], "name": r["name"],
        "arg_signature": r["arg_signature"],
        "cc": r["cc"], "crap": r["crap"], "eff_cov": r["eff_cov"],
    } for r in rows]
    for fn in all_functions:
        if _baseline_key(fn) in survivor_keys:
            continue
        all_rows.append({
            "file": fn["file"], "name": fn["name"],
            "arg_signature": fn.get("arg_signature", ""),
            "cc": int(fn["cc"]), "crap": float(int(fn["cc"])),  # eff_cov=1 → crap = cc
            "eff_cov": 1.0,
        })
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"rows": all_rows}, fh, indent=2, sort_keys=True)
    eprint(f"crap: wrote baseline with {len(all_rows)} functions → {out_path}")
    return 0


def _compute_summary(rows: list[dict[str, Any]], total_functions: int,
                     survivors_count: int, threshold: float) -> dict[str, Any]:
    above = sum(1 for r in rows if r["crap"] > threshold)
    # Savoia's 5% project rule. Denominator is ALL methods — functions below
    # CRAP_max are guaranteed below threshold, so they count as "not above".
    pct_above = (above / total_functions * 100.0) if total_functions else 0.0
    return {
        "threshold": threshold,
        "total_functions": total_functions,
        "survivors": survivors_count,
        "above_threshold": above,
        "project_pct_above_threshold": round(pct_above, 2),
        "project_crappy": pct_above > 5.0,
        "regressions": sum(1 for r in rows if r["tag"] == "regressed" and r["crap"] > threshold),
        "new_above_threshold": sum(1 for r in rows if r["tag"] == "new" and r["crap"] > threshold),
    }


def _emit_summary(summary: dict[str, Any]) -> None:
    eprint(f"crap: {summary['above_threshold']}/{summary['survivors']} over threshold; "
           f"{summary['regressions']} regressed, {summary['new_above_threshold']} new")
    verdict = "CRAPPY" if summary["project_crappy"] else "clean"
    eprint(f"crap: {summary['project_pct_above_threshold']:.1f}% of "
           f"{summary['total_functions']} methods above CRAP {summary['threshold']} "
           f"— project is {verdict} by Savoia's 5% rule")


def _exit_code(rows: list[dict[str, Any]], threshold: float) -> int:
    any_regression = any(r["tag"] in ("regressed", "new") and r["crap"] > threshold for r in rows)
    if any_regression:
        return 2
    if any(r["crap"] > threshold for r in rows):
        return 1
    return 0


def cmd_score(args: argparse.Namespace) -> int:
    functions = load_json(args.functions)
    survivors = load_json(args.survivors)
    coverage = load_json(args.coverage) if args.coverage else {}
    mutation = load_json(args.mutation) if args.mutation else {}
    cached_results: dict[str, dict[str, Any]] = (
        load_json(args.cached) if args.cached and os.path.exists(args.cached) else {}
    )
    cache_dir = Path(args.cache) if args.cache else None
    if cache_dir is not None:
        cache_dir.mkdir(parents=True, exist_ok=True)
    baseline_map = load_baseline(args.baseline) if not args.no_baseline else {}

    rows = [
        _score_one(fn, coverage, mutation, cached_results, cache_dir,
                   args.toolchain_tag or "", baseline_map,
                   args.no_churn, args.churn_window)
        for fn in survivors
    ]
    rows.sort(key=lambda r: r["crap_weighted"], reverse=True)

    if args.set_baseline:
        return _write_baseline(rows, survivors, functions,
                               args.baseline or ".crap-baseline.json")

    top_rows = rows[:(args.top or len(rows))]
    print(_render_markdown(top_rows, threshold=args.threshold))

    summary = _compute_summary(rows, len(functions), len(survivors), args.threshold)
    if args.summary_out:
        dump_json({"summary": summary, "rows": top_rows}, args.summary_out)
    _emit_summary(summary)
    return _exit_code(rows, args.threshold)


def _render_markdown(rows: list[dict[str, Any]], threshold: float) -> str:
    if not rows:
        return "_No functions above CRAP_max filter. Clean._"

    headers = ["file:line", "function", "cc", "cov%", "mut%",
               "eff_cov%", "churn", "CRAP", "Δ", "tag"]
    data: list[list[str]] = []
    for r in rows:
        delta = r.get("delta")
        delta_s = "—" if delta is None else (f"+{delta:.1f}" if delta > 0 else f"{delta:.1f}")
        data.append([
            f"{r['file']}:{r['start_line']}",
            r["name"],
            str(r["cc"]),
            f"{r['line_cov'] * 100:.0f}",
            f"{r['mut_kill'] * 100:.0f}",
            f"{r['eff_cov'] * 100:.0f}",
            str(r["churn"]),
            f"{r['crap']:.1f}",
            delta_s,
            r["tag"],
        ])

    widths = [max(len(headers[i]), *(len(row[i]) for row in data))
              for i in range(len(headers))]

    def line(cells: list[str]) -> str:
        return "| " + " | ".join(c.ljust(widths[i]) for i, c in enumerate(cells)) + " |"

    sep = "|" + "|".join("-" * (w + 2) for w in widths) + "|"
    lines = [line(headers), sep]
    lines.extend(line(row) for row in data)
    return "\n".join(lines)


# ----------------------------------------------------------------------------- #
# Entry
# ----------------------------------------------------------------------------- #

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="crap.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("lizard", help="Run lizard on files → functions JSON")
    sp.add_argument("files", nargs="+")
    sp.add_argument("-o", "--output", default=None)
    sp.set_defaults(func=cmd_lizard)

    sp = sub.add_parser("parse-lizard", help="Parse existing lizard --csv output")
    sp.add_argument("path")
    sp.add_argument("-o", "--output", default=None)
    sp.set_defaults(func=cmd_parse_lizard)

    sp = sub.add_parser("filter", help="Drop fns with CRAP_max <= threshold")
    sp.add_argument("--functions", required=True)
    sp.add_argument("--threshold", type=float, default=30.0)
    sp.add_argument("-o", "--output", default=None)
    sp.set_defaults(func=cmd_filter)

    sp = sub.add_parser("cache-split", help="Split survivors into cached/to_measure")
    sp.add_argument("--survivors", required=True)
    sp.add_argument("--cache", required=True)
    sp.add_argument("--to-measure", required=True)
    sp.add_argument("--cached-results", required=True)
    sp.add_argument("--toolchain-tag", default="")
    sp.set_defaults(func=cmd_cache_split)

    sp = sub.add_parser("normalize-coverage", help="Normalize a coverage report")
    sp.add_argument("--tool", required=True,
                    choices=sorted(COVERAGE_ADAPTERS))
    sp.add_argument("path")
    sp.add_argument("-o", "--output", default=None)
    sp.set_defaults(func=cmd_normalize_coverage)

    sp = sub.add_parser("normalize-mutation", help="Normalize a mutation report")
    sp.add_argument("--tool", required=True,
                    choices=sorted(MUTATION_ADAPTERS))
    sp.add_argument("path")
    sp.add_argument("-o", "--output", default=None)
    sp.set_defaults(func=cmd_normalize_mutation)

    sp = sub.add_parser("score", help="Compute CRAP, write cache, emit report")
    sp.add_argument("--functions", required=True)
    sp.add_argument("--survivors", required=True)
    sp.add_argument("--coverage", default=None,
                    help="Normalized coverage JSON (see normalize-coverage)")
    sp.add_argument("--mutation", default=None,
                    help="Normalized mutation JSON (see normalize-mutation)")
    sp.add_argument("--cached", default=None, help="cached.json from cache-split")
    sp.add_argument("--cache", default=None, help="Cache dir (writes new entries)")
    sp.add_argument("--toolchain-tag", default="")
    sp.add_argument("--churn-window", type=int, default=90)
    sp.add_argument("--no-churn", action="store_true")
    sp.add_argument("--baseline", default=None, help=".crap-baseline.json path")
    sp.add_argument("--no-baseline", action="store_true")
    sp.add_argument("--threshold", type=float, default=30.0)
    sp.add_argument("--top", type=int, default=20)
    sp.add_argument("--set-baseline", action="store_true",
                    help="Write baseline JSON instead of gating")
    sp.add_argument("--summary-out", default=None,
                    help="Also write JSON summary+rows to this path")
    sp.set_defaults(func=cmd_score)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
