## Parent PRD

`issues/prd.md`

## Type

**AFK**

## What to build

A new read-only skill `write-a-spec` that turns an approved story (issues/NNN-*.md) + research dump (issues/research/NNN-*.md) + repo `CLAUDE.md` and `ARCHITECTURE.md` (if present) into a technical brief at `issues/NNN-*.spec.md`. The spec must include a fenced `paths` block per lane (H3 headings) so `bin/feature.sh`'s parser can extract per-lane allowlists deterministically.

The skill is the "Spec Writer" role from the 7-agent factory — sits between approved story (Story Writer) and the lane builders (Backend Builder / Frontend Builder). Discipline mirrors `write-a-rubric`: no taste-based items, no conversation-dependent items, "could a builder follow this without re-asking?" as the self-critique pass.

Full mechanics: `docs/plans/feature-factory.md` §C (the spec→allowlist protocol).

Also includes a skill-creator-style eval file at `plugins/agentic-engineering/skills/write-a-spec/evals/evals.json` with 3–4 test prompts.

## Acceptance criteria

- [ ] New file at `plugins/agentic-engineering/skills/write-a-spec/SKILL.md` with valid frontmatter (`name`, `description`).
- [ ] Allowed tools restricted to `Read`, `Grep`, `Glob` (no `Edit`/`Write` on project files; only writes its own output).
- [ ] Output path convention matches the plan: input `issues/NNN-*.md` → output `issues/NNN-*.spec.md` (mirrors the `write-a-rubric` sidecar pattern).
- [ ] Spec template includes named sections: `Deliverable`, `Data model`, `API`, `File-by-file change list` (with H3 lane subheadings + fenced ```paths blocks), `Tests required`, `Risks & open questions`, `Tenant/timezone concerns`.
- [ ] The `paths` block format is documented inline with a worked example (parser-readable: literal paths, one per line, no globs in v1).
- [ ] Anti-patterns section explicitly forbids: globs in paths, multi-lane paths, taste-based items, conversation-dependent items.
- [ ] Closing one-liner printed (mirrors `write-a-rubric` pattern) pointing to `prd-to-issues` or `/feature` as next step.
- [ ] Evals JSON at `plugins/agentic-engineering/skills/write-a-spec/evals/evals.json` with 3-4 test prompts exercising: typical issue, thin issue (assumptions), multi-lane feature, single-lane feature.

## Blocked by

None — can start immediately.

## User stories addressed

- User story 2 (chain auto-produces a technical spec + rubric, pauses for approval)
- User story 4 (backend/frontend builders scoped per spec's file list)
- User story 13 (fenced `paths` block convention)
