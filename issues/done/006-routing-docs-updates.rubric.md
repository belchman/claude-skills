# Routing docs updates — Rubric

Grader sees a diff (or the post-change `SKILLS.md`, `CLAUDE.md`, `README.md`) for issue `006-routing-docs-updates.md`. No conversation, no source code outside these three files. The source-of-truth for what must land is the **Modifications** table in `docs/plans/feature-factory.md` (rev. 2) and the issue's `## Acceptance criteria` block. The work is doc-only and additive; criteria below name the observable strings, table rows, and section headings the grader inspects.

## Deliverable

- Three files modified (additive only), all paths from repo root:
  - `plugins/agentic-engineering/SKILLS.md`
  - `CLAUDE.md`
  - `README.md`
- No new files, no deletions. _Check: `git diff --name-status master...HEAD` shows exactly three `M` entries matching the paths above._

## SKILLS.md changes

- **S1**: The Pipeline phase table (the one with `write-a-prd`, `prd-to-issues`, `write-a-rubric`, `/work-issues`) contains a new row whose first column is the literal string `` `write-a-spec` `` (backticked). _Check: `grep -E '^\| \`write-a-spec\` \|' plugins/agentic-engineering/SKILLS.md` returns exactly one line._
- **S2**: That new row's "Use when" cell is a single sentence ending in a period and is non-empty (excluding the surrounding pipe characters and whitespace). _Check: read the row, confirm one sentence, ≤ ~220 chars._
- **S3**: The `## Heavyweight skills (slash-only)` bullet list either (a) contains a new bullet for `` `/feature` `` with a brief justification clause, OR (b) does not — but only if `plugins/agentic-engineering/skills/feature/SKILL.md` does **not** contain `disable-model-invocation: true` in its frontmatter. _Check: if `grep -q 'disable-model-invocation: true' plugins/agentic-engineering/skills/feature/SKILL.md` returns 0, then `grep -E '^- \`/feature\`' plugins/agentic-engineering/SKILLS.md` must return ≥1 line; otherwise no bullet is required._
- **S4**: No row or bullet is removed from `SKILLS.md`. _Check: every line of pre-change `SKILLS.md` that starts with `` | ` `` (table row), `- `, or `## ` is still present byte-identical in the post-change file (additions allowed, deletions are not)._

## CLAUDE.md changes

- **C1**: The `## Decision tree` table contains a new row whose "User wants…" cell mentions a spec/technical-brief intent and whose "Skill" cell is the literal string `` `write-a-spec` ``. _Check: `grep -E '\| \`write-a-spec\` \|' CLAUDE.md` returns ≥1 line, and that line is inside the section delimited by `## Decision tree` and the next `## ` heading._
- **C2**: The same `## Decision tree` table contains a new row whose "Skill" cell is the literal string `` `/feature` ``. _Check: `grep -E '\| \`/feature\`' CLAUDE.md` returns ≥1 line inside the Decision tree section._
- **C3**: A new top-level section `## Lane boundaries` exists in `CLAUDE.md` (heading on its own line, exact match including the two-hash level). _Check: `grep -c '^## Lane boundaries$' CLAUDE.md` equals 1._
- **C4**: The `## Lane boundaries` section names **at least 2 lane labels** used in this repo, each accompanied by ≥1 illustrative glob/path pattern in fenced code or backticks. _Check: between the `## Lane boundaries` heading and the next `## ` heading, count distinct lane labels (e.g., `backend`, `frontend`, or whatever this repo uses) ≥ 2; each has at least one `` ` `` -wrapped pattern adjacent._
- **C5**: The `## Lane boundaries` section contains a sentence (or call-out) noting that real backend/frontend separation does not exist in `claude-skills` and that downstream repos should define their own lane patterns. _Check: between the section heading and the next `## ` heading, the substring "downstream" appears at least once AND the substring "claude-skills" (or equivalent disclaimer of no real split) appears at least once._
- **C6**: No existing row, heading, bullet, or paragraph in `CLAUDE.md` is removed. _Check: `git diff CLAUDE.md` shows only `+` lines (and whitespace-neutral context), no `-` lines that delete content (formatting-only line moves are acceptable if every removed line reappears elsewhere)._

## README.md changes

- **R1**: Within the `## Recommended workflow` section, under the `**Build (new work):**` heading, a new paragraph or numbered/bulleted item describing the `/feature` chain has been added. _Check: between `**Build (new work):**` and the next `**…:**` heading in `README.md`, the substring `/feature` appears at least once and was not present in the pre-change version of that subsection._
- **R2**: The new `/feature` description names the entry command and the checkpoint count — specifically, it contains the literal substring `feature.sh start` (or `feature.sh start "`) AND mentions "3 checkpoints" (or "three checkpoints"). _Check: `grep -E 'feature\.sh start' README.md` returns ≥1 line within the Build subsection AND `grep -Ei '(3|three) checkpoints' README.md` returns ≥1 line within the same subsection._
- **R3**: The new paragraph links to `docs/plans/feature-factory.md`. _Check: `grep -E '\]\(.*docs/plans/feature-factory\.md\)' README.md` returns ≥1 line within the Build subsection._
- **R4**: No content removed from `README.md` outside the new paragraph's location. _Check: `git diff README.md` shows only `+` lines (no `-` lines that delete substantive content; whitespace-only diffs allowed)._

## Cross-file consistency

- **X1**: The phrase or skill name used to refer to the new spec skill is the same string `write-a-spec` in all three files (no `spec-writer`, no `write_spec`, etc.). _Check: `grep -h 'write-a-spec' plugins/agentic-engineering/SKILLS.md CLAUDE.md README.md` returns ≥3 lines and no alternate spellings appear._
- **X2**: The orchestrator skill is referenced as `/feature` (leading slash) in `SKILLS.md` heavyweight list (if present per S3), `CLAUDE.md` decision tree, and `README.md` build paragraph. _Check: each file contains `/feature` at least once in the relevant section; no occurrences of bare `feature` (without slash, without `.sh`) standing in for the skill name in those sections._

## Constraints

- Additive only across all three files — `git diff master...HEAD -- plugins/agentic-engineering/SKILLS.md CLAUDE.md README.md` contains no `-` lines that delete substantive content (heading reformat or whitespace-only moves are tolerated only if the deleted text reappears unchanged elsewhere in the same file).
- No edits to any file other than the three listed. _Check: `git diff --name-only master...HEAD` returns exactly `plugins/agentic-engineering/SKILLS.md`, `CLAUDE.md`, `README.md` (order-independent)._
- No forward references — every routing entry for `write-a-spec` points at a skill that already exists at `plugins/agentic-engineering/skills/write-a-spec/SKILL.md`, and every `/feature` entry points at `plugins/agentic-engineering/skills/feature/SKILL.md`. _Check: `test -f plugins/agentic-engineering/skills/write-a-spec/SKILL.md && test -f plugins/agentic-engineering/skills/feature/SKILL.md` (this enforces the issue's "Blocked by 001 and 005" rule)._
- All three files remain valid markdown — no broken tables (every header row has a matching `---` separator and every body row has the same column count as the header). _Check: open each file and visually verify, or run a markdown table linter; no row in any modified table has a mismatched pipe count._

---

Next: pass as {type:'text', content:...} to user.define_outcome, or upload via Files API.
