# Toolbelt

The CLI wrappers live in `skills/evolve/scripts/`.

## Typical sequence

1. Normalize the run brief.
2. Inspect the evaluator.
3. Present the preflight plan/approach summary to the user
4. Draft or update `cognition_seed.md`.
5. Initialize cognition.
6. Re-run brief normalization with `--confirmed true` only after explicit user approval of that presented plan.
7. Run per-round loops anchored on `sample`, with cognition lookup or web refresh added whenever the next improvement is not already clear.
8. Produce the final summary.

The evolve loop is agent-operated. Do not write a local runner script that performs the round loop, chooses parents, or mutates candidates for you.

## Concurrency rule

Database commands are serialized per run.

- Wait for `evolve-db record` to finish before calling `evolve-db best`, `evolve-db sample`, or `evolve-db stats` on the same `run_dir`.
- Do not issue multiple `evolve-db` commands in parallel against the same run, even if they look read-only.
- If you need parallelism, parallelize non-database work such as analysis drafting or cognition review instead.

## Commands by stage

### Preflight

- `python skills/evolve/scripts/evolve-brief normalize`
- `python skills/evolve/scripts/evolve-eval inspect`

Preflight must align an explicit evaluator timeout. Do not rely on the CLI default alone.
Do not skip the explicit plan/approach handoff. The initial task request is not equivalent to confirmation.

### Cognition

- `python skills/evolve/scripts/evolve-cognition init`
- `python skills/evolve/scripts/evolve-cognition add`
- `python skills/evolve/scripts/evolve-cognition search`

### Database and sampling

- `python skills/evolve/scripts/evolve-db sample`
- `python skills/evolve/scripts/evolve-db record`
- `python skills/evolve/scripts/evolve-db best`
- `python skills/evolve/scripts/evolve-db stats`

## Sampling algorithm guide

- `random`: use for high-exploration scouting. Best when the search space is poorly understood, the current family looks stale, or you want to sanity-check alternatives.
- `island`: use for broader and more diverse exploration over time. It is the closest option here to a MAP-Elites-style balance of coverage and progress across different families.
- `ucb1`: use when you already have a meaningful signal and want a balanced explore/exploit policy that can keep advancing a promising direction without collapsing too early.
- `greedy`: use for short-horizon exploitation only. It is appropriate when you explicitly want to focus on the current strongest parents and accept reduced diversity.

If unsure, start with `ucb1`. Switch to `island` when diversity matters more, and switch to `random` when you suspect the current search story is overfit or too narrow.
Treat the chosen sampling algorithm as run-level configuration, not a per-round toggle.

### Island feature guide

- Default `island` features are `complexity` and `diversity`.
- `complexity` means `len(code)`.
- `diversity` means the built-in code-difference heuristic over stored programs.
- Any additional feature name must appear as a numeric field in evaluator `results.json`.
- Align the `island` feature list during preflight, not mid-run.

### Custom sampler guide

Use a custom sampler only when the built-in samplers are not expressive enough.

Set these fields in `run_spec.yaml`:

```yaml
sampling:
  algorithm: "custom"
  custom_sampler_path: "samplers/my_sampler.py"
  custom_sampler_class: "MySampler"
```

Required interface:

- `sample(nodes, n) -> list[Node]`

Optional hooks:

- `on_node_added(node)`
- `on_node_removed(node)`
- `get_state()`
- `load_state(state)`
- `rebuild_from_nodes(nodes)`
- `get_island_stats(nodes)`

Useful `Node` fields include `id`, `parent`, `score`, `visit_count`, `results`, `analysis`, `motivation`, `meta_info`, and `code`.
Prefer custom features via evaluator result metrics before reaching for a custom sampler.

### File and evaluation helpers

- `python skills/evolve/scripts/evolve-files read`
- `python skills/evolve/scripts/evolve-files write`
- `python skills/evolve/scripts/evolve-files diff`
- `python skills/evolve/scripts/evolve-eval run`

`evolve-eval run` uses the preflight timeout from `evaluation.timeout_secs` by default. `--timeout` is only a manual override; the canonical value still belongs in the run spec.
Allowed helper scripts here are things like an evaluator or a user-requested visualization tool. Do not add a project-local evolve controller or optimizer script.

### Wrap-up

- `python skills/evolve/scripts/evolve-summary final`

## Round protocol

Every round should follow this order:

1. `python skills/evolve/scripts/evolve-db sample`
2. Design from the sampled parent instead of relying on transient chat context alone.
3. If the next move is not already obvious, run `python skills/evolve/scripts/evolve-cognition search`.
4. If local cognition is insufficient or freshness matters, do targeted external research and write the distilled findings back with `python skills/evolve/scripts/evolve-cognition add`.
5. `python skills/evolve/scripts/evolve-eval run`
6. `python skills/evolve/scripts/evolve-db record`

The per-round database sample is mandatory. Cognition lookup is conditional, but durable memory must come from the database or cognition store rather than from raw conversation context.
Experimental takeaways from the round belong in the recorded node analysis, not in cognition.
`evolve-db sample` does not accept a per-call algorithm override. Set the sampling algorithm in preflight instead.

## Evaluator placeholders

`evolve-eval run` formats these placeholders inside `evaluation.command`:

- `{workspace_root}`
- `{run_dir}`
- `{step_dir}`
- `{code_path}`
- `{results_path}`
- `{script_path}`
- `{timeout_secs}`
- `{quoted_workspace_root}`
- `{quoted_run_dir}`
- `{quoted_step_dir}`
- `{quoted_code_path}`
- `{quoted_results_path}`
- `{quoted_script_path}`
- `{quoted_timeout_secs}`

For robust shell execution, prefer the quoted placeholders in command templates.
Evaluators should use the configured timeout rather than embedding an unrelated hard-coded limit.

## Candidate path note

- `evolve-eval run` materializes the candidate at `steps/<step-name>/code`.
- That path does not get a forced extension or language-specific filename pattern.
- Evaluators should load the candidate by explicit file path, not by assuming suffix-based discovery or import behavior.
- If an evaluator currently depends on a particular filename convention, add a compatibility layer before using it with the skill.

## Cognition seed format

`cognition_seed.md` is a human-readable file that may contain fenced `json` blocks.

Only put reusable external insights in this file.

- Good fits: paper takeaways, benchmark heuristics, geometric tricks, failure patterns found in approved web research, and distilled notes from approved external search.
- Keep out: problem statements, function signatures, evaluator commands, score definitions, writable paths, and lessons learned from your own local experiment rounds.

Example:

````markdown
```json
[
  {
    "content": "Use variable radii and preserve validity checks.",
    "source": "user",
    "metadata": {"kind": "heuristic"}
  }
]
```
````

`evolve-cognition init` loads all JSON blocks and turns them into cognition items.
Those items should help future design decisions, not restate the run spec.

## Recording expectations

When calling `evolve-db record`, provide:

- `--step-name` for the round identifier
- `--name` for the candidate label
- `--code-path` for the evaluated file
- `--motivation` for why this branch existed
- `--analysis` or `--analysis-file` for the lesson from the run
- `--results-file` or `--score` so the database can rank the candidate

Per-round analyses and experimental lessons should stay attached to the node record rather than being copied into cognition.
