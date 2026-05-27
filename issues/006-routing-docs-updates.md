## Parent PRD

`issues/prd.md`

## Type

**AFK**

## What to build

Update the three routing/documentation surfaces so users (including future-matt) can discover and use the new pieces:

1. **`plugins/agentic-engineering/SKILLS.md`** — add `write-a-spec` to the Pipeline phase table; add `/feature` to the Heavyweight slash-only list (if applicable, depending on whether 005 keeps `disable-model-invocation: true`).
2. **`CLAUDE.md`** (project root) — add `write-a-spec` and `/feature` to the routing decision tree. Add a new `## Lane boundaries` section that documents the two lane labels used in this repo with illustrative patterns, noting that for downstream projects the patterns should reflect their own backend/frontend split.
3. **`README.md`** — one paragraph under "Recommended workflow → Build" describing the `/feature` chain at a glance: `feature.sh start "<brief>"` → 3 checkpoints → done. Link to `docs/plans/feature-factory.md` for depth.

## Acceptance criteria

- [ ] `SKILLS.md` Pipeline table has a new row for `write-a-spec` with a one-sentence "use when" hook.
- [ ] `SKILLS.md` lists `/feature` (or removes it from heavyweight if 005 dropped the flag).
- [ ] `CLAUDE.md` "Decision tree" table has new rows for `write-a-spec` and `/feature` with their trigger phrases.
- [ ] `CLAUDE.md` has a new `## Lane boundaries` section with at least 2 lane definitions for this repo (illustrative — note that real backend/frontend separation doesn't exist in claude-skills) plus the "project-specific in downstream repos" note.
- [ ] `README.md` "Recommended workflow → Build" section has a new paragraph describing `/feature`, with the link to the plan.
- [ ] No content removed from existing sections (additive only).

## Blocked by

- `issues/001-write-a-spec-skill.md` (so the routing entry isn't a forward reference)
- `issues/005-feature-skill-and-orchestrator.md` (same)

## User stories addressed

- User story 11 (lessons-learned → skill edits — this is the "skill edits" outlet for discoverability lessons)
