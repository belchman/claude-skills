## Parent PRD

`issues/prd.md`

## Type

**AFK**

## What to build

Extend `plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` with two new functions that `bin/feature-helpers.sh` (issue 005) will consume:

1. **`allowlist_for <spec-file> <lane-name>`** — read a spec file (markdown with H3 lane headings + fenced ```paths blocks), extract the paths under the named lane heading, print them one per line. Empty output + exit 0 if the lane is not found.
2. **`route_findings <findings-file> <spec-file>`** — read a findings file (the `/adversarial-review` output: markdown with file:line references), classify each finding by file path against each lane's allowlist (from the spec), print classification as `<lane-name>\t<finding-summary>` per line. Unmapped findings get `<unmapped>` as the lane name.

Both functions are pure (no global state), composable, and testable in isolation.

Add shell tests at `tests/test_work_issues_lib.sh` covering:
- `allowlist_for` happy path (lane exists, paths extracted in order)
- `allowlist_for` lane not found (empty output, exit 0)
- `allowlist_for` malformed input (missing fenced block under H3) — define and pin behavior
- `route_findings` happy path (findings split correctly across lanes + unmapped)
- `route_findings` empty findings file (empty output, exit 0)

Full mechanics: `docs/plans/feature-factory.md` §C (Spec → allowlist format) + §E (Severity routing).

## Acceptance criteria

- [ ] `bin/work-issues-lib.sh` exports `allowlist_for` and `route_findings` functions.
- [ ] Lib header doc-block updated with one-line descriptions of both new functions.
- [ ] `tests/test_work_issues_lib.sh` includes at least the 5 test cases listed above.
- [ ] Existing 6 tests in `tests/test_work_issues_lib.sh` still pass.
- [ ] `allowlist_for` handles missing spec file gracefully (empty output, exit 0 — matches `list_issue_files` pattern from Round 0).
- [ ] `route_findings` does NOT match a path to multiple lanes (parser fails loud on duplicate paths in the spec — matches §C "A path may appear in only one lane").
- [ ] Pure bash (POSIX awk/grep) — no Python, no jq beyond what's already a project dependency.
- [ ] No changes to `once.sh`, `loop.sh`, or any existing function in the lib.

## Blocked by

None — can start immediately (extends existing lib from Round 0).

## User stories addressed

- User story 4 (lane scoping via spec's file list)
- User story 6 (validator findings auto-routed to correct lane)
- User story 7 (unmapped findings surfaced explicitly)
- User story 13 (fenced `paths` block convention)
