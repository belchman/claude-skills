## Parent PRD

`issues/prd.md`

## Type

**AFK**

## What to build

A single short paragraph added to `plugins/agentic-engineering/skills/work-issues/SKILL.md` that tells the model: if the prompt prepends a lane preamble (containing an `## Allowlist` section with literal paths), honor it — only edit files in the allowlist. If a needed edit is outside the allowlist, append an `## Allowlist additions requested` section to the issue file (path + one-sentence reason) and stop.

This is the soft-mode enforcement for the `--lane` mechanic. The orchestrator (`/feature`) prepends the lane preamble to the SKILL.md body via `WORK_ISSUES_PROMPT`; the SKILL.md just needs to declare that lane preambles are honored.

Full mechanics: `docs/plans/feature-factory.md` §B (The `--lane` protocol).

## Acceptance criteria

- [ ] One paragraph added to `work-issues/SKILL.md`, placed near the existing "Implementation" or "Hard rules" section so it's discoverable in context.
- [ ] Paragraph explicitly names the `## Allowlist additions requested` escape valve.
- [ ] Paragraph clarifies: never silently expand the allowlist; never edit a file outside it without writing the escape-valve section first.
- [ ] No behavior change when no lane preamble is present (backward compatible — existing `/work-issues` callers unaffected).
- [ ] No changes to `bin/once.sh`, `bin/loop.sh`, or `bin/work-issues-lib.sh` (the prompt injection is the orchestrator's job, not the shell wrapper's).

## Blocked by

None — can start immediately.

## User stories addressed

- User story 4 (backend/frontend builders scoped per spec's file list)
- User story 14 (mid-implementation discovery via `## Allowlist additions requested`)
