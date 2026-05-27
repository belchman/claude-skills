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
- [ ] Tool allowlist permits `Read`, `Grep`, `Glob`, `Write` — Write is for the sidecar output only; the skill body explicitly forbids editing or creating any file outside the output `issues/NNN-*.spec.md` path. (Per Round 2 grilling Q1: matches how `write-a-rubric` works.)
- [ ] Output path convention matches the plan: input `issues/NNN-*.md` → output `issues/NNN-*.spec.md` (mirrors the `write-a-rubric` sidecar pattern).
- [ ] Spec template includes named sections: `Deliverable`, `Data model`, `API`, `File-by-file change list` (with H3 lane subheadings + fenced ```paths blocks), `Tests required`, `Risks & open questions`, `Tenant/timezone concerns`. Sections that are N/A for a given feature should still appear with body `_N/A_` and a one-sentence reason — forces conscious consideration.
- [ ] The `paths` block format is documented inline with a worked example (parser-readable: literal paths, one per line, no globs in v1).
- [ ] **Lane discovery**: SKILL.md instructs the writer to read `CLAUDE.md`'s `## Lane boundaries` section (if present) to learn the project's lane vocabulary. Lane H3 headings in the spec MUST match labels defined there. (Per Round 2 grilling Q3.)
- [ ] **Single-lane handling**: SKILL.md states that if a feature is single-lane, the spec OMITS the unused lane's H3 entirely (no empty `paths` block). The orchestrator's parser treats a missing lane as "skip." (Per Round 2 grilling Q2.)
- [ ] **Tests required content shape**: SKILL.md states the `Tests required` section is a **behavior list** — one bullet per testable behavior (e.g. `over-limit-minute returns 429 + Retry-After`), not test file paths and not coverage percentages. The downstream `write-a-rubric` step turns each bullet into a gradeable criterion. (Per Round 2 grilling Q4.)
- [ ] **Missing-research handling**: SKILL.md states that if the expected `issues/research/NNN-*.md` is missing, the skill proceeds anyway and adds a Risks bullet noting "no research pass performed; consider running /feature for fuller context." (Per Round 2 grilling Q5 — keeps direct-user invocation working alongside orchestrated.)
- [ ] Anti-patterns section explicitly forbids: globs in paths, multi-lane paths, taste-based items, conversation-dependent items.
- [ ] Closing one-liner printed (mirrors `write-a-rubric` pattern) pointing to `prd-to-issues` or `/feature` as next step.
- [ ] Evals JSON at `plugins/agentic-engineering/skills/write-a-spec/evals/evals.json` with 3-4 test prompts exercising: typical issue, thin issue (assumptions), multi-lane feature, single-lane feature.

## Blocked by

None — can start immediately.

## User stories addressed

- User story 2 (chain auto-produces a technical spec + rubric, pauses for approval)
- User story 4 (backend/frontend builders scoped per spec's file list)
- User story 13 (fenced `paths` block convention)
