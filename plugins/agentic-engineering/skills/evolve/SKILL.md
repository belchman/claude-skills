---
name: "evolve"
description: "Run an ASI-Evolve style evaluator-driven search workflow for code, algorithms, prompts, or pipelines. Use when Claude needs to align the objective, scoring, evaluator, writable scope, and cognition first, then execute a preflight-gated learn/design/experiment/analyze loop with the bundled Evolve CLI instead of the repository's multi-agent pipeline."
---

# Evolve

Treat this skill as the single-agent abstraction of `ASI-Evolve-dev`. Preserve the system's core idea: learn from prior knowledge, design the next candidate, run the evaluator, analyze the outcome, and feed the lesson back into the next round.

## Preserve the operating model
- Keep the four-stage loop intact: learn, design, experiment, analyze.
- Use the bundled wrappers in `scripts/` for stateful operations. Let the agent make orchestration decisions; do not recreate the repository's pipeline stack.
- The agent itself must choose mutations, run experiments, inspect outputs, and write round analyses step by step.
- Keep two memory systems alive for the whole run:
  - cognition store for approved external research, paper takeaways, and search-derived insights that may help future rounds
  - experiment database for every candidate, score, analysis, lineage, best snapshot, and lessons learned from actual experiments
- Treat `.evolve_runs/<run-name>/` as the source of truth for the active run.

## Start with preflight
- Draft or update the run spec before any mutate or evaluate step.
- Align with the user on:
  - objective
  - core score
  - secondary metrics
  - evaluation command or script
  - evaluation timeout
  - success criteria
  - stop conditions and round budget
  - writable file scope and primary targets
  - sampling algorithm
  - island feature dimensions when `sampling.algorithm=island`
  - cognition source mode
- Inspect the evaluator before confirmation. If the command or script is vague, pause and resolve it before continuing.
- Even when the user already gave a detailed task description, you must still produce a concrete preflight plan/approach summary before any evolve round starts.
- Require an explicit evaluator timeout during preflight. Do not treat timeout as an implicit default.
- Confirm that the evaluator path you will use has timeout handling. The outer `evolve-eval run` timeout is mandatory, and the evaluator command or script should also accept or honor the configured timeout when it can hang internally.
- Confirm that the evaluator can load the materialized candidate path that `evolve-eval run` produces. The default step artifact is `steps/<step-name>/code` with no forced extension or filename convention.
- If you choose the sampling algorithm yourself during preflight, tell the user explicitly which algorithm you picked and why.
- If you choose `island`, also tell the user the default feature semantics: `complexity=len(code)` and `diversity=code-difference heuristic over stored programs`, and mention that they can override the feature list before confirmation.
- Refresh the preflight artifacts with `scripts/evolve-brief normalize`.
- Keep `approval.confirmed=false` until the user explicitly approves the preflight summary.
- Only flip `approval.confirmed` after the user says the plan is confirmed or approved. Never self-confirm because the request seemed detailed or complete.
- Refuse to run evolve commands that mutate files, execute the evaluator, or write the final summary before confirmation.

## Initialize cognition
- Initialize the experiment database and cognition store before the first real round, even if they only contain the baseline at the start.
- Seed cognition only with insight-like external knowledge that is safe to reuse across rounds, such as approved web research, paper takeaways, or distilled heuristics.
- Use direct web research when local cognition is insufficient or freshness matters, and distill what you learned back into cognition before continuing.
- Use subagents only if the user explicitly permits research help. Treat those outputs as candidate seeds, not authoritative truth.
- Collect that research-derived material in `cognition_seed.md`. Use fenced `json` blocks when deterministic ingestion matters.
- Initialize or refresh the store with `scripts/evolve-cognition init`, and add incremental items with `scripts/evolve-cognition add`.
- Do not treat transient chat context as durable memory. Refresh the important context from the database or cognition store whenever a round needs grounding.
- Keep task scaffolding out of cognition. Problem definitions, function signatures, evaluator details, writable paths, and round-by-round experimental conclusions belong in the run spec or the experiment database, not in cognition.

## Run each evolution round explicitly
Perform each round yourself with direct edits plus the provided wrappers. Do not batch the loop into a generated local runner.

1. Sample parent context from the experiment database at the start of every round.
2. Anchor the next candidate on the sampled parent. Use the sampled node as the primary memory for what to improve, preserve, or branch from.
3. If the next improvement is already clear, proceed directly from that sampled context. Otherwise search cognition for heuristics, prior lessons, and relevant analogies.
4. If local cognition is still insufficient or the task needs fresh information, do targeted web research and add the distilled findings back into cognition before editing.
5. Decide whether the next candidate should be a patch, partial rewrite, or fresh branch.
6. Modify code only inside the approved mutation scope.
7. Run the evaluator and collect structured results.
8. Analyze what changed, why it helped or hurt, and which sampled parent informed the move. Record that experimental lesson in the database entry for the round.
9. Record the node, results, and analysis in the database.
10. Check the best snapshot and decide whether another round is justified.

## Serialize database operations
- Treat `evolve-db record`, `evolve-db sample`, `evolve-db best`, and `evolve-db stats` as one shared critical section per run.
- Wait for each database command to finish before starting the next database command against the same `run_dir`.
- Do not fire a read-after-write query in parallel with `evolve-db record`.
- If you need both the new node and a fresh best/sample decision, run them in order: `record` first, then `best` or `sample`.

## Make good round decisions
- Prefer patching when the last result reveals a specific local defect, missing constraint, or narrow optimization opportunity.
- Prefer rewriting when the current structure fights the objective, repeats the same failure mode, or needs a cleaner decomposition.
- Prefer branching from the best-performing or most informative parent, not automatically from the newest one.
- Treat the sampling algorithm as a run-level choice. Do not switch algorithms mid-run; start a new run if the search needs a different sampling regime.
- Choose the sampling algorithm deliberately:
  - `random`: highest exploration pressure. Good for early scouting, escaping local ruts, or checking whether the current search narrative is too narrow.
  - `island`: the diversity-oriented option, closer to a MAP-Elites-style long-horizon search. Prefer it when you want more balanced exploration across families and better long-run coverage of different solution types. Its default features are `complexity` and `diversity`.
  - `ucb1`: the default when there is already a plausible direction and you want to keep exploring while still pushing harder on promising parents.
  - `greedy`: pure exploitation. Use it only when you intentionally want to squeeze the current best family rather than broaden the search.
- For `island`, use built-in features unless there is a clear reason to override them:
  - `complexity`: code length
  - `diversity`: code-difference heuristic across stored programs
  - any other feature name must map to a numeric evaluator result field
- If the built-in samplers are not enough, use a custom sampler only after preflight aligns on its path, class name, and intended behavior.
- Treat evaluator regressions as information. Record the lesson instead of erasing the failed branch from history.
- Stop early when success criteria are met, patience is exhausted, the evaluator signal is too noisy to rank candidates, or the approved mutation scope is no longer sufficient.

## Escalate back to the user when needed
- Ask for confirmation before the first real evolve round.
- Pause if the evaluator, mutation scope, or objective changes materially.
- Pause if the best next move would require writing outside the approved paths, changing the benchmark definition, or pulling in external knowledge that the user has not approved.
- Summarize candidate cognition before initializing it when any of it came from subagents or broad research.

## Avoid these failures
- Do not run `python main.py`.
- Do not import or rely on `pipeline/` agents for orchestration.
- Do not replace the manual learn/design/experiment/analyze loop with a generated evolution script.
- Do not mutate files outside `mutation_scope.writable_paths`.
- Do not mark preflight as confirmed while required fields are missing.
- Do not confirm preflight without an explicit evaluation timeout.
- Do not interpret a detailed task request as confirmation. A separate user confirmation is always required.
- Do not treat unstructured evaluator output as authoritative. Normalize it into explicit metrics before comparing candidates.
- Do not run an evaluator that can hang indefinitely or ignores the agreed timeout contract.
- Do not skip the per-round database sample. Each round must begin from sampled run memory, not just whatever remains in chat context.
- Do not rely on raw chat context as the only memory of prior rounds. Use the database and cognition store as the durable sources of truth.
- Do not put task definitions, interfaces, evaluator specs, or per-round experimental lessons into cognition. Cognition is for reusable external insights, while experiment outcomes belong in the database.
- Do not try to override the sampling algorithm inside `evolve-db sample`. Sampling configuration is owned by the run spec and fixed for the run.
- Do not launch multiple `evolve-db` commands concurrently against the same run.

## Read when needed
- `references/operating_model.md`: how the original ASI-Evolve architecture maps into this skill's single-agent loop.
- `references/preflight.md`: preflight gate and confirmation behavior.
- `references/run_spec.md`: run spec schema and required fields.
- `references/toolbelt.md`: CLI wrappers, grouped by stage.
- `references/architecture.md`: run directory layout and vendored runtime pieces.
