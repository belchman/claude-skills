# Operating Model

Use this reference when you need to remember what the skill is abstracting from `ASI-Evolve-dev`.

## What this skill preserves

The original repository uses three cooperating roles:

- Researcher: read prior results and propose the next candidate
- Engineer: execute the candidate and capture metrics
- Analyzer: turn outcomes into reusable lessons

This skill collapses those roles into one Codex loop without changing the logic of the system.

## The four-stage loop

1. Learn
- sample prior nodes from the experiment database
- search the cognition store for heuristics, constraints, and useful analogies

2. Design
- choose a parent or branch
- decide patch vs partial rewrite vs fresh branch
- write only inside the approved mutation scope

3. Experiment
- run the evaluator through `evolve-eval run`
- collect structured metrics in `results.json`

4. Analyze
- explain why the candidate helped or failed
- record the node in the database
- update the best snapshot
- carry durable lessons into later rounds

## The two memory systems

- Cognition store:
  - seed with user heuristics, paper notes, constraints, and approved research
  - query when you need ideas or guardrails before writing the next candidate
- Experiment database:
  - record every branch, result, analysis, and lineage
  - use it to avoid retrying dead ends and to branch from informative parents

## Decision heuristics

- Patch when the defect is local and the current structure is mostly right.
- Partially rewrite when one subsystem is blocking progress but the overall framing is still useful.
- Start a fresh branch when the current direction is repeatedly failing or when a radically different idea deserves an isolated trial.

## Good fit

Use this skill when all three are true:

- a measurable evaluator exists
- code or prompt changes are allowed in a bounded scope
- domain knowledge can improve the search

## Poor fit

Do not default to this skill for one-off bug fixes, purely qualitative tasks, or situations where no evaluator can distinguish better from worse candidates.
