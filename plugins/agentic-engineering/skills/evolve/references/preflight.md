# Preflight

Preflight is a hard gate.

## Required alignment topics

- objective
- core score
- secondary metrics
- evaluator command or evaluator script
- evaluator timeout
- success criteria
- stop conditions
- round budget
- writable paths
- primary targets
- sampling algorithm
- island feature dimensions when using `island`
- custom sampler path and class when using `custom`
- cognition source mode

## Confirmation rule

Preflight is not complete until:

1. `run_spec.yaml` has all required fields.
2. `preflight_summary.md` reflects the current plan.
3. `approval.confirmed` is explicitly set to `true`.

Always present a concrete plan/approach summary to the user before confirmation, even if the initial task description already seems complete.
Do not treat the user's original task request as implicit approval to start evolve.

Before that point:
- `evolve-db sample`
- `evolve-db record`
- `evolve-db best`
- `evolve-db stats`
- `evolve-eval run`
- `evolve-files write`
- `evolve-summary final`

must refuse to proceed.

Timeout rule:
- Preflight must record an explicit evaluation timeout.
- The evaluator path used for the run must honor that timeout contract instead of relying on an unstated default.

## Cognition sources

Use cognition only for reusable external insight sources.

Good cognition inputs:
- Approved web research
- Paper takeaways
- Distilled heuristics from external sources

Keep these out of cognition:
- Problem definition
- Function or file interface details
- Evaluator command details
- Round-by-round experimental conclusions

Approved agent research:
- Use subagents only when the user explicitly allows it.
- Summarize the candidate seeds back to the user.
- Only initialize cognition after confirmation.
