# Work-Issues SKILL.md — Lane Preamble Honored — Rubric

## Deliverable

- A modified file at `plugins/agentic-engineering/skills/work-issues/SKILL.md` containing one new paragraph (a single contiguous block of prose; one heading immediately above it is permitted, no multi-paragraph rewrite) describing how the model honors a lane preamble.
- No other files modified. No new files created. _Check: `git diff --name-only <base>..HEAD` lists exactly one path: `plugins/agentic-engineering/skills/work-issues/SKILL.md`._

## Scope of edit (what changed)

- **SCOPE-1**: Diff against `<base>` for `plugins/agentic-engineering/skills/work-issues/SKILL.md` consists of additions only (one paragraph, optionally with a heading line directly above it). No lines deleted from pre-existing prose. _Check: `git diff <base>..HEAD -- plugins/agentic-engineering/skills/work-issues/SKILL.md | grep -E '^-[^-]' | wc -l` equals `0`._
- **SCOPE-2**: No diff touches `plugins/agentic-engineering/skills/work-issues/bin/once.sh`, `plugins/agentic-engineering/skills/work-issues/bin/loop.sh`, or `plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh`. _Check: `git diff --name-only <base>..HEAD | grep -E 'work-issues/bin/(once|loop|work-issues-lib)\.sh$'` returns no output._
- **SCOPE-3**: The frontmatter of `SKILL.md` (the block delimited by the first two `---` lines) is byte-identical before and after. _Check: `diff <(git show <base>:plugins/agentic-engineering/skills/work-issues/SKILL.md | awk '/^---$/{n++; if(n==2){print; exit} } {print}') <(awk '/^---$/{n++; if(n==2){print; exit} } {print}' plugins/agentic-engineering/skills/work-issues/SKILL.md)` produces no output._

## Content (what the paragraph says)

The added paragraph (the new prose introduced by this diff) must satisfy every assertion below. "The paragraph" = the set of added lines in `SKILL.md` per `git diff <base>..HEAD`.

- **CON-1**: References the concept of a "lane preamble" (or equivalent: "lane prompt", "lane wrapper", "prepended lane prompt") — i.e., names the thing it is teaching the model to honor. _Check: case-insensitive grep for `lane` in the added lines returns ≥1 match._
- **CON-2**: References the `## Allowlist` (or "allowlist") section that the preamble contains and ties the constraint to "only edit files in the allowlist" (or equivalent restrictive phrasing: "may only edit", "must not edit outside", "restrict edits to"). _Check: added lines contain both the substring `Allowlist` (case-insensitive) and a restrictive verb phrase such as `only edit`, `may only`, `must not edit`, or `restrict`._
- **CON-3**: Names the literal escape-valve section header `## Allowlist additions requested` (exact spelling, including the leading `## ` and capitalization of `Allowlist`). _Check: `grep -F '## Allowlist additions requested' plugins/agentic-engineering/skills/work-issues/SKILL.md` returns ≥1 match._
- **CON-4**: States that the escape valve is appended to **the issue file** (not the SKILL.md, not the spec, not a side log) and that each entry contains a path plus a one-sentence reason. _Check: added lines contain a phrase referencing "issue file" (or "the issue") AND a phrase referencing "path" AND a phrase referencing "reason" or "why" (one sentence)._
- **CON-5**: Explicitly forbids silent expansion — wording such as "never silently expand the allowlist" or "do not edit a file outside the allowlist without writing the escape-valve section first." _Check: added lines contain the words `never` or `do not` / `don't` adjacent to language about expanding the allowlist or editing outside it._
- **CON-6**: States that on hitting the escape-valve condition the loop stops/exits (rather than continuing past it). _Check: added lines contain a verb phrase such as `stop`, `exit`, `halt`, or `do not continue`._
- **CON-7**: Backward-compatibility statement is present OR the paragraph is unambiguously gated on "if a lane preamble is present" (so a reader can verify the no-preamble path is unaffected). _Check: added lines contain a conditional clause such as `if the prompt`, `if a lane preamble`, `when a lane preamble`, or an explicit "no change when absent" sentence._

## Placement

- **PLACE-1**: The added paragraph appears under, or is adjacent to (within 5 lines of), a heading whose title contains `Implementation` or `Hard rules` (case-insensitive substring match on heading text). _Check: in the post-change `SKILL.md`, the nearest preceding `^#` heading to the first added line matches `/implementation|hard rules/i`, OR the paragraph itself sits within 5 lines after such a heading._
- **PLACE-2**: The paragraph is not inserted before the first `^# ` (top-level) heading of the body — i.e., it lives inside a section, not floating above all headings. _Check: line number of the first added line is greater than the line number of the first `^# ` heading after the closing frontmatter `---`._

## Constraints

- **CONS-1**: The paragraph does not introduce any new flag, env var, or CLI argument name (no occurrences of `--lane`, `LANE=`, `WORK_ISSUES_PROMPT`, or similar) — per the issue, prompt injection is the orchestrator's job. _Check: added lines do not contain `--lane`, `WORK_ISSUES_PROMPT`, `LANE_PROMPT`, or `export `._
- **CONS-2**: The paragraph does not instruct the model to modify `bin/once.sh`, `bin/loop.sh`, `work-issues-lib.sh`, or `settings.local.json` (no behavioral coupling to the shell layer or hard-mode enforcement). _Check: added lines do not reference `once.sh`, `loop.sh`, `work-issues-lib.sh`, or `settings.local.json`._
- **CONS-3**: SKILL.md remains valid markdown with intact YAML frontmatter (opens and closes with `---`, no unterminated fences introduced). _Check: `head -1 plugins/agentic-engineering/skills/work-issues/SKILL.md` equals `---`; count of `^---$` lines in the file is ≥ 2; count of triple-backtick fences is even._
- **CONS-4**: The addition is lean — net additions ≤ 25 lines (the issue calls for "one paragraph", optionally with a heading line above). _Check: `git diff --numstat <base>..HEAD -- plugins/agentic-engineering/skills/work-issues/SKILL.md` shows added-lines count ≤ 25._

Next: pass as {type:'text', content:...} to user.define_outcome, or upload via Files API.
