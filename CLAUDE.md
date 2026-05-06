# Routing map for `agentic-engineering`

The `agentic-engineering` plugin (under `plugins/agentic-engineering/`) bundles eleven composable skills. They are designed to compose; the right skill depends on **what artifact you have** and **what artifact you need next**.

## The build pipeline

```
nothing yet                  → write-a-prd       → issues/prd.md
issues/prd.md                → prd-to-issues     → issues/NNN-*.md (HITL or AFK)
issues/NNN-*.md (AFK)        → work-issues       → commits + issues/done/NNN-*.md
```

At any step you can sidestep into:

- `grill-with-docs` — interrogate the plan against `CONTEXT.md` + `docs/adr/`
- `improve-codebase-architecture` — find deep-module refactor candidates
- `tdd` — for any task with testable behavior
- `prototype` — when "what should this look like?" or "does this state model feel right?" needs a throwaway sketch
- `diagnose` — when something is broken
- `zoom-out` — when you don't know how this code fits

## Decision tree

| User wants… | Skill |
| --- | --- |
| To stress-test a plan / interrogate a design (default) | **`grill-with-docs`** |
| To brainstorm with no project context at all (rare) | `grill-me` |
| A PRD from a brief | `write-a-prd` |
| Work tickets from an existing PRD | `prd-to-issues` |
| To autonomously work the issue queue | `/work-issues` (explicit-only) |
| To debug a bug or perf regression | `diagnose` |
| To flush out a design before committing | `prototype` |
| To find architectural friction / deep-module candidates | `improve-codebase-architecture` |
| TDD on a behavior change | `tdd` |
| To understand unfamiliar code | `/zoom-out` (explicit-only) |
| To audit Claude Code's own overhead (cost, hooks, plugins) | `/audit-claude-overhead` (explicit-only) |

## Pairs that look similar — pick which

| Both about | Default | When |
| --- | --- | --- |
| Interrogating a plan | **`grill-with-docs`** | Almost always. Handles missing CONTEXT.md by creating it lazily. |
| Interrogating a plan | `grill-me` | Pure green-field thinking with no codebase at all. Rare. |
| PRD work | `write-a-prd` | Going from a brief / idea → `issues/prd.md` |
| PRD work | `prd-to-issues` | Going from `issues/prd.md` → individual issue files |
| Things "going wrong" | `diagnose` | Bug or perf regression in **user code** |
| Things "going wrong" | `audit-claude-overhead` | **Claude Code itself** is slow / hitting limits |

## Conventions assumed by these skills

| Path / file | Purpose | Created by |
| --- | --- | --- |
| `issues/*.md` | Local markdown issue queue (HITL or AFK tagged) | `prd-to-issues` |
| `issues/prd.md` | Project PRD | `write-a-prd` |
| `issues/done/` | Completed issues archive | `work-issues` |
| `CONTEXT.md` | Project domain glossary (DDD shared language) | `grill-with-docs` (lazily) |
| `CONTEXT-MAP.md` | Multi-context map (root) | manual |
| `docs/adr/NNNN-*.md` | Architectural decision records | `grill-with-docs` (lazily, when threshold met) |

**ADR threshold** (offer an ADR only when ALL three hold):

1. Hard to reverse — meaningful cost to change later.
2. Surprising without context — a future reader looks at the code and asks "why on earth?".
3. Real trade-off — there were genuine alternatives.

## Heavyweight skills (explicit-only)

These have `disable-model-invocation: true` and only fire on explicit slash invocation:

- `/audit-claude-overhead` — walks plugin scope, ~5KB SKILL.md + audit script
- `/work-issues` — commits code, modifies the issue queue
- `/zoom-out` — narrowly purposed micro-skill

The orchestrator will not auto-invoke these. The user must explicitly type the slash command.

## Attribution

Several skills are vendored from `mattpocock/skills` (MIT). Per-file attribution: `plugins/agentic-engineering/ATTRIBUTION.md`. License text: `plugins/agentic-engineering/licenses/`.
