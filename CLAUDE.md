# Routing map for `agentic-engineering`

The `agentic-engineering` plugin (under `plugins/agentic-engineering/`) bundles the composable skills below. They are designed to compose; the right skill depends on **what artifact you have** and **what artifact you need next**. Note: `audit-claude-overhead` was extracted to its own standalone plugin (`plugins/audit-claude-overhead/`) and is no longer part of `agentic-engineering`.

## The build pipeline

```
nothing yet                  → write-a-prd       → issues/prd.md
issues/prd.md                → prd-to-issues     → issues/NNN-*.md (HITL or AFK)
issues/NNN-*.md              → write-a-rubric    → issues/NNN-*.rubric.md  (optional sidecar)
issues/NNN-*.md (AFK)        → work-issues       → commits + issues/done/NNN-*.md (rubric travels)
```

At any step you can sidestep into:

- `grill-with-docs` — interrogate the plan against `CONTEXT.md` + `docs/adr/`
- `improve-codebase-architecture` — find deep-module refactor candidates
- `tdd` — for any task with testable behavior
- `prototype` — when "what should this look like?" or "does this state model feel right?" needs a throwaway sketch
- `diagnose` — when something is broken
- `zoom-out` — when you don't know how this code fits
- `evolve` — evaluator-driven search loop when you have a measurable score and want 50–200 candidates, not 5
- `crap` — rank functions by CRAP score (complexity × lack of effective coverage), then propose either a refactor or missing tests for the worst offender
- `/map` — generate or update `ARCHITECTURE.md` (slash-only)

## Decision tree

| User wants… | Skill |
| --- | --- |
| To stress-test a plan / interrogate a design (default) | **`grill-with-docs`** |
| To brainstorm with no project context at all (rare) | `grill-me` |
| A PRD from a brief | `write-a-prd` |
| Work tickets from an existing PRD | `prd-to-issues` |
| A grader-checkable rubric for an issue/PRD ("what does done look like") | `write-a-rubric` |
| To autonomously work the issue queue | `/work-issues` (explicit-only) |
| To debug a bug or perf regression | `diagnose` |
| To flush out a design before committing | `prototype` |
| To find architectural friction / deep-module candidates | `improve-codebase-architecture` |
| TDD on a behavior change | `tdd` |
| To search for a better solution against a measurable evaluator (algorithm tuning, prompt search, pipeline optimization — any "best-of-N under a score") | `evolve` |
| To understand unfamiliar code | `/zoom-out` (explicit-only) |
| To find the riskiest function on the branch (complexity × poor coverage) | `crap` |
| To generate or update `ARCHITECTURE.md` | `/map` (explicit-only) |
| To audit Claude Code's own overhead (cost, hooks, plugins) | `/audit-claude-overhead` — now its own plugin (`plugins/audit-claude-overhead/`) |

## Pairs that look similar — pick which

| Both about | Default | When |
| --- | --- | --- |
| Interrogating a plan | **`grill-with-docs`** | Almost always. Handles missing CONTEXT.md by creating it lazily. |
| Interrogating a plan | `grill-me` | Pure green-field thinking with no codebase at all. Rare. |
| PRD work | `write-a-prd` | Going from a brief / idea → `issues/prd.md` |
| PRD work | `prd-to-issues` | Going from `issues/prd.md` → individual issue files |
| Things "going wrong" | `diagnose` | Bug or perf regression in **user code** |
| Things "going wrong" | `audit-claude-overhead` | **Claude Code itself** is slow / hitting limits |
| Iterating on code | `tdd` | Behavior change with a clear spec. |
| Iterating on code | `evolve` | Open-ended search where the spec is *a score*, not a behavior — and you want 50–200 candidates per run with a cognition store + experiment DB. |

## Conventions assumed by these skills

| Path / file | Purpose | Created by |
| --- | --- | --- |
| `issues/*.md` | Local markdown issue queue (HITL or AFK tagged) | `prd-to-issues` |
| `issues/prd.md` | Project PRD | `write-a-prd` |
| `issues/done/` | Completed issues archive | `work-issues` |
| `issues/NNN-*.rubric.md` | Sidecar grader-checkable success criteria for an issue | `write-a-rubric` |
| `rubrics/*.md` | Free-form / PRD-level rubrics not tied to a specific issue | `write-a-rubric` |
| `CONTEXT.md` | Project domain glossary (DDD shared language) | `grill-with-docs` (lazily) |
| `CONTEXT-MAP.md` | Multi-context map (root) | manual |
| `docs/adr/NNNN-*.md` | Architectural decision records | `grill-with-docs` (lazily, when threshold met) |
| `.evolve_runs/<run-name>/` | Per-run state: `run_spec.yaml`, `cognition_seed.md`, `preflight_summary.md`, `cognition_data/`, `database_data/`, `steps/`, `best/` | `evolve` |

**ADR threshold** (offer an ADR only when ALL three hold):

1. Hard to reverse — meaningful cost to change later.
2. Surprising without context — a future reader looks at the code and asks "why on earth?".
3. Real trade-off — there were genuine alternatives.

## Heavyweight skills (explicit-only)

These have `disable-model-invocation: true` and only fire on explicit slash invocation:

- `/work-issues` — commits code, modifies the issue queue
- `/zoom-out` — narrowly purposed micro-skill
- `/map` — writes `ARCHITECTURE.md`, dispatches parallel agents
- `/audit-claude-overhead` — walks plugin scope, ~5KB SKILL.md + audit script (now in its own plugin)

The orchestrator will not auto-invoke these. The user must explicitly type the slash command.

## Attribution

Several skills are vendored from `mattpocock/skills` (MIT) and `GAIR-NLP/ASI-Evolve` (Apache 2.0). Per-file attribution: `plugins/agentic-engineering/ATTRIBUTION.md`. License texts: `plugins/agentic-engineering/licenses/`.
