## Parent PRD

`issues/prd.md`

## Type

**AFK**

## What to build

Two env-var hooks added to `plugins/agentic-engineering/skills/adversarial-review/SKILL.md` so an orchestrator (`/feature`) can dispatch the skill programmatically without losing the existing interactive UX:

1. **`ADVERSARIAL_REVIEW_REPORT_ONLY=1`** — at Phase 3 (user-checkpoint), if set, auto-answer D ("Skip fixes — I just wanted the review") and stop. No prompt shown.
2. **`ADVERSARIAL_REVIEW_TARGETS=<colon-separated-globs>`** — at Phase 1 (file discovery), if set, use this as the target file list and skip the interactive auto-discovery + summarization steps. Format: colon-separated globs (matching PATH convention).

Both env vars are **optional** — if unset, the skill behaves identically to today. Default UX for direct `/adversarial-review` users is unchanged.

Full mechanics: `docs/plans/feature-factory.md` §D (Adversarial-review automation).

## Acceptance criteria

- [ ] `adversarial-review/SKILL.md` Phase 3 block (around line 198) gets a paragraph: "if `ADVERSARIAL_REVIEW_REPORT_ONLY=1` is set, skip the prompt and behave as if the user chose D."
- [ ] `adversarial-review/SKILL.md` Phase 1 file-discovery block gets a paragraph: "if `ADVERSARIAL_REVIEW_TARGETS=<glob>:<glob>:...` is set, use this as the file list directly and skip auto-discovery + summary."
- [ ] When env vars are unset, no behavior change vs current (verify by reading through the skill prompt as a human).
- [ ] The frontmatter description is updated to note the env-var automation hooks (one sentence).
- [ ] No changes to `Phase 4` or `Phase 5` logic — fixes are still gated by the user's choice when interactive.

## Blocked by

None — can start immediately.

## User stories addressed

- User story 5 (validator runs in report-only mode without keyboard)
- User story 12 (validator invokable programmatically by another orchestrator)
