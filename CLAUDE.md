# Routing map for `agentic-engineering`

The `agentic-engineering` plugin (under `plugins/agentic-engineering/`) bundles
the composable skills below, organized by **phase of work**. Pick the phase
first, then the skill.

For the per-skill detail table, see `plugins/agentic-engineering/SKILLS.md`.
This file is the *routing* map — "which phase am I in, and what comes next?"

> `audit-agent-overhead` is **no longer** part of `agentic-engineering`; it
> ships as a standalone plugin at `plugins/audit-agent-overhead/`.

## The build pipeline

```
nothing yet                  → write-a-prd       → issues/prd.md
issues/prd.md                → prd-to-issues     → issues/NNN-*.md (HITL or AFK)
issues/NNN-*.md              → write-a-rubric    → issues/NNN-*.rubric.md  (optional sidecar)
issues/NNN-*.md (AFK)        → work-issues       → commits + issues/done/NNN-*.md (rubric travels)
```

## Phase map

| Phase | Skills | What's it for |
| --- | --- | --- |
| **1. Pipeline** | `write-a-prd`, `prd-to-issues`, `write-a-rubric`, `/work-issues` | Brief → PRD → issues → autonomous work. |
| **2. Design** | `grill-with-docs`, `grill-me`, `prototype` | Stress-test a plan before code changes. |
| **3. Implement** | `tdd`, `improve-codebase-architecture`, `evolve` | Move the code itself. |
| **4. Debug** | `diagnose`, `/zoom-out` | Find and fix what's broken. |
| **5. Review** | `/adversarial-review`, `crap` | Audit existing code for gaps and risk. |
| **6. Document** | `/map` | Keep `ARCHITECTURE.md` current. |

## Decision tree

| User wants… | Phase | Skill |
| --- | --- | --- |
| A PRD from a brief | Pipeline | `write-a-prd` |
| Work tickets from an existing PRD | Pipeline | `prd-to-issues` |
| A grader-checkable rubric for an issue/PRD | Pipeline | `write-a-rubric` |
| To autonomously work the issue queue | Pipeline | `/work-issues` (slash-only) |
| To stress-test a plan / interrogate a design (default) | Design | **`grill-with-docs`** |
| To brainstorm with no project context at all (rare) | Design | `grill-me` |
| To flush out a design before committing | Design | `prototype` |
| TDD on a behavior change | Implement | `tdd` |
| To find architectural friction / deep-module candidates | Implement | `improve-codebase-architecture` |
| Best-of-N search against a measurable evaluator | Implement | `evolve` |
| To debug a bug or perf regression | Debug | `diagnose` |
| To understand unfamiliar code | Debug | `/zoom-out` (slash-only) |
| To find cross-cutting gaps in docs/config/tests | Review | `/adversarial-review` (slash-only) |
| To find the riskiest function on the branch | Review | `crap` |
| To generate or update `ARCHITECTURE.md` | Document | `/map` (slash-only) |
| To audit Claude Code's own overhead | (separate plugin) | `/audit-agent-overhead` — in `plugins/audit-agent-overhead/` |

## Pairs that look similar — pick which

| Both about | Default | When to flip |
| --- | --- | --- |
| Interrogating a plan | **`grill-with-docs`** | Use `grill-me` only when there's no codebase at all. |
| Things "going wrong" | `diagnose` | If **Claude Code itself** is slow / hitting limits, use `/audit-agent-overhead` (separate plugin). |
| Iterating on code | `tdd` | Use `evolve` when the spec is *a score*, not a behavior. |
| Reviewing code | `/adversarial-review` | Cross-cutting gaps (docs ↔ config ↔ tests). |
| Reviewing code | `crap` | A single risky function (complexity × poor coverage). |

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
| `ARCHITECTURE.md` | Living map of structure, deps, high-coupling zones | `/map` |

**ADR threshold** (offer an ADR only when ALL three hold):

1. Hard to reverse — meaningful cost to change later.
2. Surprising without context — a future reader looks at the code and asks "why on earth?".
3. Real trade-off — there were genuine alternatives.

## Heavyweight skills (slash-only)

These have `disable-model-invocation: true` and only fire on explicit slash
invocation — the orchestrator will never auto-trigger them:

- `/work-issues` — commits code, modifies the issue queue
- `/zoom-out` — narrowly purposed micro-skill
- `/adversarial-review` — dispatches parallel agents, can modify files
- `/map` — writes `ARCHITECTURE.md`, dispatches parallel agents
- `/audit-agent-overhead` — separate plugin; walks plugin scope, ~5KB SKILL.md + audit script

## Attribution

Several skills are vendored from `mattpocock/skills` (MIT) and
`GAIR-NLP/ASI-Evolve` (Apache 2.0). Per-file attribution:
`plugins/agentic-engineering/ATTRIBUTION.md`. License texts:
`plugins/agentic-engineering/licenses/`.
