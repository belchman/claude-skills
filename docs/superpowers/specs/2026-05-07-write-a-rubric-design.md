# write-a-rubric — design spec

Date: 2026-05-07
Status: Draft, awaiting user review

## Purpose

Produce a `*.rubric.md` file that meets the discipline of Anthropic's Managed Agents [`user.define_outcome`](https://platform.claude.com/docs/en/managed-agents/define-outcomes) event: independently gradeable criteria that a separate grader, with access only to the produced artifact, can score without consulting the originating conversation.

The skill is a sidecar — it never modifies issues, PRDs, or code. It produces one file.

## Slot in the agentic-engineering pipeline

```
write-a-prd     →  issues/prd.md
prd-to-issues   →  issues/NNN-*.md
write-a-rubric  →  issues/NNN-*.rubric.md     ← new, optional sidecar
work-issues     →  commits + issues/done/NNN-*.md (+ NNN-*.rubric.md travels with)
```

The skill is **additive**: nothing in the existing pipeline changes its primary behavior. Only one downstream tweak: `work-issues` housekeeping moves a sibling `*.rubric.md` along with the issue when archiving (a one-line addition).

## Skill metadata

- **Path:** `plugins/agentic-engineering/skills/write-a-rubric/SKILL.md`
- **Invocation:** model-invocable (no `disable-model-invocation`)
- **Trigger surface:** "rubric", "outcome rubric", "define-outcome", "managed-agent outcome", "grader", "what does done look like for this issue"

## Inputs (priority order)

1. Path to an `issues/NNN-*.md` file
2. Path to `issues/prd.md` (rare — produces a project-level rubric at `rubrics/prd.md`)
3. Free-form goal in the user's message

If invoked from an issue, the skill also reads `issues/prd.md` for parent context if it exists.

## Output

- **Issue-derived:** `issues/NNN-<slug>.rubric.md` (mirrors the issue filename)
- **PRD-derived:** `rubrics/prd.md`
- **Free-form:** `rubrics/<slug>.md`

The skill creates `rubrics/` lazily if needed.

## Process

1. **Read input.** Issue file, PRD file, or capture the user's free-form goal.
2. **Identify the deliverable artifact.** What is being produced (file? PR? data? report?), where it lives, and in what format. If unclear, ask once.
3. **Seed from existing acceptance criteria** if the source is an issue with a `## Acceptance criteria` block. Treat them as starting points to *sharpen*, not as the rubric itself.
4. **Draft criteria.** Each criterion is independently gradeable; group by category. Categories typically: Deliverable, Inputs/Data, Behavior, Output Quality, Constraints.
5. **Self-critique pass.** For each criterion, ask: "Could a grader with ONLY the produced artifact — no conversation, no source code, no context — verify this?" If no, sharpen or split.
6. **Stop check.** Continue until ≥4 gradeable criteria across ≥2 categories AND the deliverable is unambiguous, OR the user explicitly says "ship it."
7. **Write the file.** Path per the Output section.
8. **Print one-line next-step:** `Next: pass as {type:'text', content:...} to user.define_outcome, or upload via Files API.`

## Rubric template

```markdown
# <Outcome title> — Rubric

## Deliverable
- <what artifact, where, in what format>

## <Category 1, e.g. Inputs / Data>
- <gradeable criterion>
- <gradeable criterion>

## <Category 2, e.g. Behavior>
- ...

## Output Quality
- <file format, naming, location>
- <any "must include" sections>

## Constraints
- <hard limits, must-not-do items>
```

## Mandatory anti-patterns block in SKILL.md

The SKILL.md must include this block — it is the densest signal in similar skills (`audit-claude-overhead`, `tdd`, `prototype`):

- Vague verbs: "looks good", "is reasonable", "handles edge cases", "is clean"
- Multi-check bullets: "validates input and returns a token and logs the event" — split into three
- Taste-based criteria: "is well-written", "is elegant" — push into examples instead
- Restating the description as a criterion ("does what was asked")
- Criteria the grader can't check without the conversation ("matches what we discussed")

## Boundaries (what the skill does NOT do)

- Does not call the Managed Agents API
- Does not call the Files API
- Does not modify the source issue or PRD
- Does not produce the artifact being graded — only the rubric for it

A future `/dispatch-outcome` skill would consume `*.rubric.md` files and call the API; that is out of scope here.

## Companion edits

These are part of this work, not separate:

1. **`CLAUDE.md` routing map** — add row:
   `| To define what "done" looks like for an issue/PRD as a gradeable rubric | write-a-rubric |`
2. **`work-issues/SKILL.md`** — two additions:
   - Under "Issue housekeeping": sibling `*.rubric.md` (if present) moves alongside the issue.
   - **(Tier 2)** New step after "Feedback loops": if a sibling `*.rubric.md` exists, walk its criteria. Report any unmet item in the iteration summary. Do not block the commit on unmet items — surface, don't gate.
3. **`prd-to-issues/SKILL.md`** — add forward reference:
   `After issues are written, you may run write-a-rubric per AFK issue to define grader-checkable success criteria.`
4. **`write-a-prd/SKILL.md`** — fix audit findings:
   - Add `# write-a-prd` heading
   - Add guard for existing `issues/prd.md` (ask before overwriting)
   - Add forward ref to `prd-to-issues`

## Audit-driven companion edits (in this batch)

5. **`diagnose/SKILL.md`** — add Phase 0 (or a paragraph before Phase 1) requiring the user-described symptom to be captured: actual behavior, expected behavior, when it started, repro known-good. Without this, Phase 1 builds a loop for the wrong bug.
6. **`grill-me/SKILL.md`** — add stop conditions matching `grill-with-docs` (user signals done; every open branch has a one-sentence answer; plan is concrete enough to feed into next step). Keep the body terse — these are appended bullets, not a rewrite.

## Decisions recorded (no ADR — none meet the threshold)

- "Rubric" is the canonical term, even though `prd-to-issues` issues already have `## Acceptance criteria`. Acceptance criteria are PR-checklist style for humans; rubrics are grader-checkable assertions for an independent context window. Different audience, different precision level. Reversible by rename.
- `*.rubric.md` siblings (rather than inlining into the issue) because (a) the issue stays clean for human reading, (b) the file can be uploaded via Files API for reuse, (c) a future dispatch tool can find it by filename glob.
- No local grader. Self-critique pass replaces it. A real grader call would require an API key and is left to a future `dispatch-outcome` skill.

## Open questions

None outstanding after the grill. Ready to plan implementation.
