# Skills in `agentic-engineering`, grouped by phase

The skills live in a flat `skills/<name>/SKILL.md` layout because Claude Code's
resolver only scans one level deep. This file is the conceptual grouping —
when picking a skill, find the phase first, then the skill.

## 1. Pipeline — turn intent into shipped work

The autonomous build loop: brief → PRD → issues → rubrics → AFK work.

| Skill | Use when |
| --- | --- |
| `write-a-prd` | You have a brief or idea and need a PRD at `issues/prd.md`. |
| `prd-to-issues` | You have a PRD and need it sliced into `issues/NNN-*.md` tickets. |
| `write-a-rubric` | You want a grader-checkable "what does done look like" sidecar (`issues/NNN-*.rubric.md`) for an issue or PRD. |
| `write-a-spec` | You have an approved story/issue and need a technical brief (data model, API, file-by-file change list with lane-scoped `paths` blocks, tests, risks). |
| `/work-issues` | Autonomously run an issue end-to-end (explore, TDD, commit, archive). **Slash-only.** |
| `/feature` | Orchestrate the full chain on one brief: map → research → story → spec → rubric → backend → validator → frontend → validator → PR, with three human checkpoints. Resumable. **Slash-only.** |

## 2. Design — think before coding

Stress-test the plan before any code changes land.

| Skill | Use when |
| --- | --- |
| `grill-with-docs` | Default planning interrogator. Pulls in `CONTEXT.md` + `docs/adr/`; creates them lazily when missing. |
| `grill-me` | Pure green-field thinking with **no** codebase context. Rare. |
| `prototype` | "What should this look like?" or "does this state model feel right?" — throwaway sketches. |

## 3. Implement — write or change code

Move the code itself.

| Skill | Use when |
| --- | --- |
| `tdd` | Behavior change with a clear spec — red → green → refactor. |
| `improve-codebase-architecture` | Find deep-module refactor candidates (Ousterhout-style). |
| `evolve` | Evaluator-driven search loop. You have a measurable score and want 50–200 candidates per run, not 5. |

## 4. Debug — find and fix what's broken

| Skill | Use when |
| --- | --- |
| `diagnose` | A bug or perf regression in **user code**. |
| `/zoom-out` | You're lost — need to understand how unfamiliar code fits. **Slash-only.** |

## 5. Review — audit existing code

| Skill | Use when |
| --- | --- |
| `/adversarial-review` | Three parallel reviewer agents find contradictions, config gaps, and coverage holes — then fix what you approve. **Slash-only.** |
| `crap` | Rank functions by CRAP score (complexity × lack of effective coverage); refactor or test the worst offender. |

## 6. Document — keep the map current

| Skill | Use when |
| --- | --- |
| `/map` | Generate or update `ARCHITECTURE.md`. Diff-aware on incremental runs. **Slash-only.** |

## Heavyweight skills (slash-only by intent)

Skills below are intended for explicit slash invocation only. Some enforce
that via `disable-model-invocation: true` in their YAML frontmatter (a hard
gate the runtime checks); others enforce it via prose in the `description:`
field ("Use only when explicitly asked…") — softer, but lets another
orchestrator skill (`/feature`) dispatch them programmatically when needed.

| Skill | How slash-only is enforced |
| --- | --- |
| `/zoom-out` | frontmatter `disable-model-invocation: true` |
| `/feature` | frontmatter `disable-model-invocation: true` |
| `/work-issues` | description prose (so `/feature` can dispatch it per-lane) |
| `/adversarial-review` | description prose (so `/feature` can dispatch the validator pass) |
| `/map` | description prose (so `/feature` can dispatch `step_refresh_map`) |

## Pairs that look similar

| Both about | Default | When to flip |
| --- | --- | --- |
| Interrogating a plan | `grill-with-docs` | Use `grill-me` only when there's no codebase at all. |
| PRD work | `write-a-prd` | Use `prd-to-issues` when you already have a PRD and need tickets. |
| Things going wrong | `diagnose` | If **Claude Code itself** is slow / hitting limits, use the standalone `audit-agent-overhead` plugin instead. |
| Iterating on code | `tdd` | Use `evolve` when the spec is *a score*, not a behavior — and you want 50–200 candidates with a cognition store + experiment DB. |
| Reviewing code | `/adversarial-review` | Cross-cutting gaps (docs ↔ config ↔ tests). |
| Reviewing code | `crap` | A single risky function (complexity × poor coverage). |
