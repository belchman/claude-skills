# Issue 004 — `work-issues-lib.sh` allowlist helpers — Rubric

## Deliverable

- Modified file at `plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` defining two new bash functions: `allowlist_for` and `route_findings`.
- Modified file at `tests/test_work_issues_lib.sh` containing the existing 6 test functions PLUS at least 5 new test functions for the helpers above.
- No other files in the repo are modified or created.

## Lib API

- **LIB-1**: `work-issues-lib.sh` contains a shell function named `allowlist_for` defined with either `allowlist_for()` or `function allowlist_for` syntax. _Check: `grep -E '^(function )?allowlist_for[[:space:]]*\(\)' plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` returns at least one match._
- **LIB-2**: `work-issues-lib.sh` contains a shell function named `route_findings` defined with either `route_findings()` or `function route_findings` syntax. _Check: same `grep` against `route_findings`._
- **LIB-3**: After sourcing the lib in a subshell, both functions are visible via `declare -F`. _Check: `bash -c 'source plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh; declare -F allowlist_for route_findings'` exits 0 and prints both names._
- **LIB-4**: The lib's header doc-block (the leading `#` comment block) names both `allowlist_for` and `route_findings` in its `Functions:` list with a one-line description each. _Check: `awk '/^[^#]/{exit} {print}' plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` mentions both function names._
- **LIB-5**: The pre-existing functions `strip_frontmatter` and `list_issue_files` remain defined and behaviourally unchanged. _Check: existing test cases for them still pass; their function bodies in the lib are byte-identical to the Round 0 versions (or differ only in surrounding whitespace)._

## Behavior — `allowlist_for <spec-file> <lane-name>`

- **AF-1**: Given a spec file containing an H3 heading matching `<lane-name>` (case-sensitive after a leading `### `) immediately followed (possibly with blank lines) by a fenced block opened with ` ```paths`, prints each path inside the fence on its own line, in source order, and exits 0. _Check: new test `test_allowlist_for_happy_path` (or equivalent) constructs such a spec and asserts equality of captured stdout with the expected newline-joined path list._
- **AF-2**: Given a spec file that has no H3 heading matching `<lane-name>`, prints nothing to stdout and exits 0 (no error to stderr). _Check: new test asserts empty stdout, exit code 0, and empty stderr._
- **AF-3**: Given a non-existent spec file path, prints nothing to stdout and exits 0 (matches the `list_issue_files` Round-0 missing-input convention). _Check: new test invokes `allowlist_for /nonexistent/path.md Backend` and asserts empty stdout + exit 0._
- **AF-4**: Given a spec file where the named H3 lane heading exists but is NOT followed by a ` ```paths` fenced block (malformed input), the documented behavior is pinned by a test. The behavior MUST be one of {empty stdout + exit 0, non-zero exit with explanatory stderr} and the lib's header doc-block states which. _Check: new test `test_allowlist_for_malformed_*` exists and asserts the same behavior the header doc-block claims._
- **AF-5**: Extracts paths from ONLY the fenced block under the requested lane — paths under sibling H3 lane headings are not included in the output. _Check: a multi-lane fixture in `test_allowlist_for_happy_path` (or sibling test) asserts the Backend lane's output does not contain any path that appears only under the Frontend lane._

## Behavior — `route_findings <findings-file> <spec-file>`

- **RF-1**: For each finding in the findings file that references a file path matching exactly one lane's allowlist (parsed from `<spec-file>` via the same logic as `allowlist_for`), prints a line of the form `<lane-name>\t<finding-summary>` to stdout. _Check: new test `test_route_findings_happy_path` constructs a findings file with at least one finding per lane plus one unmapped finding, then asserts stdout contains the expected `<lane>\t<summary>` lines (tab-separated, one per finding)._
- **RF-2**: For each finding whose file path matches NO lane allowlist, prints a line of the form `<unmapped>\t<finding-summary>`. _Check: the same happy-path test asserts the unmapped finding shows up with the literal lane name `<unmapped>`._
- **RF-3**: Given an empty findings file (zero bytes, or no findings recognised), prints nothing to stdout and exits 0. _Check: new test `test_route_findings_empty` writes an empty file and asserts empty stdout + exit 0._
- **RF-4**: If the same path appears in two or more `### Lane` blocks within `<spec-file>`, `route_findings` exits non-zero and writes an explanatory message to stderr naming the duplicated path (per `docs/plans/feature-factory.md` §C: "A path may appear in only one lane"). _Check: new test constructs a spec with one path under two lanes, invokes `route_findings`, asserts non-zero exit and that stderr contains the duplicate path string._
- **RF-5**: A finding's file path is never reported under more than one lane in a single run (no double-classification). _Check: covered by RF-4 fail-loud behavior on duplicate-path specs; for non-duplicate specs the happy-path test asserts each finding appears on exactly one output line._

## Tests

- **T-1**: `tests/test_work_issues_lib.sh` defines at least 11 test functions whose names begin with `test_` (the 6 existing + at least 5 new). _Check: `grep -cE '^test_[a-zA-Z_]+\(\)' tests/test_work_issues_lib.sh` returns ≥ 11._
- **T-2**: Running `bash tests/test_work_issues_lib.sh` exits 0 and the final summary line reports zero failures. _Check: run command; assert exit code 0 and that stdout does NOT contain a line beginning with `  FAIL`._
- **T-3**: Among the new test functions, names (or `assert_eq` description strings) cover each of: `allowlist_for` happy path, `allowlist_for` lane-not-found, `allowlist_for` malformed input, `route_findings` happy path, `route_findings` empty findings. _Check: `grep -E '(allowlist_for|route_findings)' tests/test_work_issues_lib.sh` shows at least one occurrence per bullet across function names or assertion labels._

## Constraints

- **C-1**: No Python interpreter is invoked from `work-issues-lib.sh`. _Check: `grep -E '\b(python|python3)\b' plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` returns no matches._
- **C-2**: No new `jq` invocation is added beyond pre-existing project usage. _Check: `grep -c '\bjq\b' plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` equals 0 (the Round-0 lib has no `jq` usage)._
- **C-3**: `plugins/agentic-engineering/skills/work-issues/bin/once.sh` and `plugins/agentic-engineering/skills/work-issues/bin/loop.sh` are unchanged. _Check: `git diff --name-only HEAD~..HEAD -- plugins/agentic-engineering/skills/work-issues/bin/once.sh plugins/agentic-engineering/skills/work-issues/bin/loop.sh` is empty (or `git diff HEAD~..HEAD -- <those files>` is empty)._
- **C-4**: No new files are created outside `tests/` and no files are deleted. _Check: `git diff --name-status HEAD~..HEAD` shows only `M` entries for `work-issues-lib.sh` and `tests/test_work_issues_lib.sh`._
- **C-5**: The lib is POSIX-tool-portable bash — only `awk`, `grep`, `sed`, `find`, `sort`, and bash builtins are invoked (no GNU-only flags, no `gawk`/`mawk` explicit calls, no external scripts). _Check: `grep -oE '\b(gawk|mawk|python|python3|node|ruby|perl|jq)\b' plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` returns no matches._

Next: pass as {type:'text', content:...} to user.define_outcome, or upload via Files API.
