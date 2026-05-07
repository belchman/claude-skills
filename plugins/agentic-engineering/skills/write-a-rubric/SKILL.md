---
name: write-a-rubric
description: Produce a gradeable rubric file from an issue, PRD, or free-form goal — sharpened to the standard required by Anthropic's Managed Agents user.define_outcome event. Sidecar artifact (issues/NNN-*.rubric.md or rubrics/<slug>.md); does not modify source files. Use when the user wants to define "what done looks like" for grader-checkable success criteria. Triggers: /write-a-rubric, "write a rubric", "outcome rubric", "define-outcome", "managed-agent outcome", "make this gradeable".
---

# write-a-rubric

A rubric is a markdown document of **independently gradeable criteria**: assertions a separate context — given only the produced artifact, no conversation, no source code — can verify pass/fail. Vague criteria produce noisy evaluations; this skill exists to keep them sharp.

Source discipline: [Anthropic Managed Agents — Define outcomes](https://platform.claude.com/docs/en/managed-agents/define-outcomes).

## When to run

- Triggered by an issue, PRD, or free-form goal that needs a grader-checkable spec.
- Optional sidecar to `prd-to-issues` — produce a rubric per AFK issue worth grading.
- Required input for a future `/dispatch-outcome` skill that calls the Managed Agents API.

## Inputs (priority order)

1. Path to an `issues/NNN-*.md` file (most common).
2. Path to `issues/prd.md` (rare — produces a project-level rubric at `rubrics/prd.md`).
3. Free-form goal in the user's message.

If invoked from an issue, also read `issues/prd.md` for parent context if it exists.

## Output

| Source | Path |
|---|---|
| `issues/NNN-<slug>.md` | `issues/NNN-<slug>.rubric.md` (mirrors filename) |
| `issues/prd.md` | `rubrics/prd.md` |
| Free-form goal | `rubrics/<slug>.md` |

Create `rubrics/` lazily if needed.

## Process

1. **Read input.** Issue, PRD, or capture the free-form goal.
2. **Identify the deliverable.** What artifact is produced, where it lives, in what format. If unclear, ask once.
3. **Seed from acceptance criteria** if the source is an issue with `## Acceptance criteria`. Treat them as starting points to *sharpen*, not as the rubric itself.
4. **Draft criteria.** Group by category. Common categories: Deliverable, Inputs/Data, Behavior, Output Quality, Constraints. Each criterion is one independent assertion.
5. **Self-critique pass.** For each criterion ask: *"Could a grader with ONLY the produced artifact — no conversation, no source code, no extra context — verify this?"* If no, sharpen or split.
6. **Stop check.** Continue until **≥4 gradeable criteria across ≥2 categories** AND the deliverable is unambiguous, OR the user explicitly says "ship it."
7. **Write the file** at the path above.
8. **Print the closing one-liner**:
   `Next: pass as {type:'text', content:...} to user.define_outcome, or upload via Files API.`

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
- <"must include" sections>

## Constraints
- <hard limits, must-not-do items>
```

## Anti-patterns

- **Vague verbs.** "looks good", "is reasonable", "handles edge cases", "is clean", "is well-structured" — all unscorable. Replace with the specific observable.
- **Multi-check bullets.** "validates input AND returns a token AND logs the event" — split into three.
- **Taste-based criteria.** "is elegant", "is well-written" — push into examples instead, or drop.
- **Restating the description.** "does what was asked" — adds nothing the grader can check.
- **Conversation-dependent criteria.** "matches what we discussed", "covers the edge case Sarah mentioned" — the grader can't read the conversation. Make it explicit in the rubric.
- **Bloated rubrics.** A rubric with 30 criteria is not 3× better than one with 10 — it's noisier. Each criterion must earn its place.

## Hard rules

- One file per outcome.
- Do not modify the source issue or PRD.
- Do not call the Managed Agents API. Do not call the Files API. This skill produces text only.
- If the source is too thin to produce ≥4 sharp criteria, ask the user — don't fabricate.
