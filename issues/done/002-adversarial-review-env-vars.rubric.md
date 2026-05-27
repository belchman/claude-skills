# Adversarial-review env-var hooks — Rubric

Issue: [`issues/002-adversarial-review-env-vars.md`](002-adversarial-review-env-vars.md)
Source-of-truth for mechanics: [`docs/plans/feature-factory.md`](../docs/plans/feature-factory.md) §D.
Grader assumption: the grader sees the post-change repository (and can run `git diff` against the pre-change `HEAD`); no conversation, no other context.

## Deliverable

- **DEL-1**: Exactly one tracked file under the repository is modified: `plugins/agentic-engineering/skills/adversarial-review/SKILL.md`. No new files. No other `.md`, hooks, configs, or scripts touched. _Check: `git diff --name-only <pre-change-sha>..HEAD` returns exactly that single path._

## SKILL.md — content

- **SK-1**: The Phase 3 block in `adversarial-review/SKILL.md` (the section beginning with the heading `## Phase 3: User Checkpoint`) contains a paragraph that names the env var `ADVERSARIAL_REVIEW_REPORT_ONLY` with value `1`, states that the prompt is skipped when it is set, and states that the behavior is the same as if the user chose option **D**. _Check: in the file, the run of text between the headings `## Phase 3: User Checkpoint` and `## Phase 4: Adversarial Product Manager Agent` matches all three of: regex `ADVERSARIAL_REVIEW_REPORT_ONLY[^\n]*=[^\n]*1`, the substring `skip` (case-insensitive), and a reference to option `D`._

- **SK-2**: The Phase 1 file-discovery block in `adversarial-review/SKILL.md` (the section beginning with the heading `## Phase 1: Discovery`) contains a paragraph that names the env var `ADVERSARIAL_REVIEW_TARGETS`, states that its value is a **colon-separated** list of globs, states that when it is set the listed globs are used as the file list directly, and states that auto-discovery (Step 3) and the user summary (Step 5) are skipped in that mode. _Check: in the file, the run of text between the headings `## Phase 1: Discovery` and `## Phase 2: Parallel Adversarial Review (use agent teams)` matches all of: substring `ADVERSARIAL_REVIEW_TARGETS`, substring `colon` (case-insensitive) or literal `:` shown in the example, and substring `skip` (case-insensitive) referring to discovery/summary._

- **SK-3**: The YAML frontmatter `description:` field of `adversarial-review/SKILL.md` mentions that the skill can be driven by env-var hooks for programmatic / orchestrator invocation (≤1 added sentence; existing trigger phrases preserved). _Check: parse the frontmatter; `description` contains the substring `env` (case-insensitive) AND the original trigger phrase `find gaps in my docs/config` (or equivalent existing-marketing phrase) is still present so model-routing isn't broken._

- **SK-4**: Both env-var paragraphs explicitly note that **unset** = unchanged behavior (the default interactive UX). _Check: each Phase 1 and Phase 3 added paragraph contains a phrase such as `if unset`, `when not set`, or `default` describing the no-env-var case._

## Behavior preservation

- **BP-1**: The `## Phase 3: User Checkpoint` block still contains the verbatim option-D text the issue depends on: `Skip fixes — I just wanted the review`. _Check: `grep -F 'Skip fixes — I just wanted the review' plugins/agentic-engineering/skills/adversarial-review/SKILL.md` returns one line._

- **BP-2**: The `## Phase 4: Adversarial Product Manager Agent` section is unchanged. _Check: `git diff <pre-change-sha>..HEAD -- plugins/agentic-engineering/skills/adversarial-review/SKILL.md` shows zero hunks whose range is between the line of `## Phase 4: Adversarial Product Manager Agent` and the line of `## Phase 5: Summary`._

- **BP-3**: The `## Phase 5: Summary` section is unchanged. _Check: `git diff <pre-change-sha>..HEAD -- plugins/agentic-engineering/skills/adversarial-review/SKILL.md` shows zero hunks whose range is at or after the line of `## Phase 5: Summary` and before `## Error Handling`._

- **BP-4**: The `allowed-tools` line of the frontmatter is unchanged. _Check: `git diff <pre-change-sha>..HEAD` for the file shows no edited line matching `^[+-]allowed-tools:`._

## Constraints / scope

- **C-1**: No env-var name is invented beyond the two specified. The only new env-var identifiers introduced into `adversarial-review/SKILL.md` are `ADVERSARIAL_REVIEW_REPORT_ONLY` and `ADVERSARIAL_REVIEW_TARGETS`. _Check: `git diff <pre-change-sha>..HEAD -- plugins/agentic-engineering/skills/adversarial-review/SKILL.md | grep -E '^\+' | grep -oE 'ADVERSARIAL_REVIEW_[A-Z_]+' | sort -u` returns exactly those two names._

- **C-2**: No source code in `bin/`, `hooks/`, or any other skill is modified by this change. _Check: `git diff --name-only <pre-change-sha>..HEAD` lists only the single SKILL.md path from DEL-1._

- **C-3**: The Phase 1 env-var paragraph documents the **format** of `ADVERSARIAL_REVIEW_TARGETS` clearly enough that an automated caller (e.g. `bin/feature.sh`) can construct the value from a list of globs without guessing. _Check: the paragraph shows at least one concrete example string of the form `glob:glob[:glob…]` (e.g. `src/**/*.py:tests/**/*.py`) or states the PATH-style separator convention explicitly._

---

Next: pass as `{type:'text', content:...}` to `user.define_outcome`, or upload via Files API.
