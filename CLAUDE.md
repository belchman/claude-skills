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
| A technical spec / brief from an approved story (data model, API, file-by-file with lane allowlists, tests, risks) | Pipeline | `write-a-spec` |
| To autonomously work the issue queue | Pipeline | `/work-issues` (slash-only) |
| To orchestrate the full chain on one brief — research → story → spec → rubric → backend → validator → frontend → validator → PR, with three human checkpoints | Pipeline | `/feature` (slash-only) |
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

## Lane boundaries

The `/feature` orchestrator and `/work-issues` (when invoked with a lane preamble) scope each lane's allowlist via a per-lane prompt (`## Allowlist` block + escape valve). Lane labels in `issues/NNN-*.spec.md` H3 headings must match the labels declared in this section. **For `claude-skills` there is no real backend/frontend split** — this repo is a flat marketplace of skills, so the two labels below are illustrative only and used exclusively by the integration tests in `tests/test_feature_orchestrator.sh`.

- `backend` — illustrative patterns: `plugins/*/skills/*/bin/*.sh`, `plugins/*/skills/crap/*.py`, `tests/test_*.sh`
- `frontend` — illustrative patterns: `plugins/*/skills/*/SKILL.md`, `plugins/*/SKILLS.md`, `README.md`

A downstream repo using `/feature` **must define its own** `## Lane boundaries` section in its own `CLAUDE.md` reflecting that repo's actual backend/frontend (or backend/CLI, or service/library) split. The `write-a-spec` skill reads this section to allocate file lists to the right lane; if it's missing, the resulting spec carries a Risks-section note and the user picks the labels at Checkpoint 2.

## Heavyweight skills (slash-only by intent)

Skills below are intended for explicit slash invocation only. Two enforcement
mechanisms are in use:

- **Hard gate**: `disable-model-invocation: true` in the SKILL.md frontmatter. The runtime refuses to fire the skill from conversational context — only explicit slash invocation works.
- **Soft gate**: prose in the `description:` field ("Use only when explicitly asked…"). Softer than the flag, but lets another orchestrator skill (`/feature`) dispatch them programmatically when needed.

| Skill | Enforcement | What it does |
| --- | --- | --- |
| `/zoom-out` | hard (frontmatter flag) | narrowly purposed micro-skill |
| `/feature` | hard (frontmatter flag) | orchestrates the chain end-to-end; commits via lane builders |
| `/work-issues` | soft (description prose) | commits code, modifies the issue queue; `/feature` dispatches per lane |
| `/adversarial-review` | soft (description prose) | dispatches parallel agents, can modify files; `/feature` dispatches for validator |
| `/map` | soft (description prose) | writes `ARCHITECTURE.md`, dispatches parallel agents; `/feature` dispatches `step_refresh_map` |
| `/audit-agent-overhead` | separate plugin | walks plugin scope, ~5KB SKILL.md + audit script |

## Attribution

Several skills are vendored from `mattpocock/skills` (MIT) and
`GAIR-NLP/ASI-Evolve` (Apache 2.0). Per-file attribution:
`plugins/agentic-engineering/ATTRIBUTION.md`. License texts:
`plugins/agentic-engineering/licenses/`.
