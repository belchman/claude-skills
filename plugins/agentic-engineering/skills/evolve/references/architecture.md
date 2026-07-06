# Architecture

This skill is intentionally split into two layers:

1. `SKILL.md`
- Teaches the agent the evolve policy.
- Owns the preflight gate and the round-by-round decision loop.

2. `scripts/`
- Provide deterministic helpers for persistence and retrieval.
- Do not hide orchestration decisions from the agent.

## Vendored runtime

`scripts/evolve_core/` contains:
- cognition store
- experiment database
- samplers: `ucb1`, `greedy`, `random`, `island`
- centralized sampling config helpers for run-level algorithm selection, island features, and custom sampler validation/loading
- optional external custom sampler loading via `sampling.custom_sampler_path` and `sampling.custom_sampler_class`
- core structures such as `Node` and `CognitionItem`
- diff helpers
- best snapshot persistence
- embedding and vector-index helpers with graceful local fallbacks

## Explicit non-goals

The skill does not vendor:
- `pipeline/`
- repo LLM clients
- repo manager / researcher / engineer / analyzer orchestration

The agent is expected to use the skill instructions plus the CLI wrappers to run the process.

## Run layout

Every run lives under:

```text
.evolve_runs/<run-name>/
|- run_spec.yaml
|- cognition_seed.md
|- preflight_summary.md
|- round_log.jsonl
|- cognition_data/
|- database_data/
|- steps/
`- best/
```

`steps/<step-name>/` typically contains:
- `code`
- `results.json`
- `eval.stdout`
- `eval.stderr`
- `analysis.md`
- `node.json`

`steps/best/` is maintained automatically by `evolve-db record`.
