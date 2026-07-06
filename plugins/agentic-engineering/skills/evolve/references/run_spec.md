# Run Spec

The run spec is stored in `.evolve_runs/<run-name>/run_spec.yaml`.

## Required top-level fields

```yaml
objective: ""
evaluation:
  core_score: ""
  secondary_metrics: []
  command: ""
  script_path: ""
  timeout_secs: 0
  success_criteria: []
budget:
  max_rounds: 0
  patience: 0
stop_conditions: []
mutation_scope:
  writable_paths: []
  primary_targets: []
sampling:
  algorithm: "ucb1"
  sample_n: 3
  feature_dimensions: ["complexity", "diversity"]
  feature_bins: 10
  custom_sampler_path: ""
  custom_sampler_class: ""
cognition:
  source_mode: ""
  seed_files: []
  seed_notes: []
approval:
  confirmed: false
```

## Notes

- `evaluation.command` can use placeholders such as `{code_path}` and `{results_path}`.
- `evaluation.script_path` is for explicit script inspection and documentation.
- `evaluation.timeout_secs` is required. Set it during preflight and treat it as the canonical evaluator timeout for the run.
- `evaluation.command` can also use `{timeout_secs}` and `{quoted_timeout_secs}` so the evaluator script or wrapper can honor the same timeout internally.
- `approval.confirmed` must stay `false` until the user explicitly confirms the preflight summary.
- `mutation_scope.writable_paths` are enforced by `evolve-files`.
- `sampling.algorithm` is a run-level choice; do not change it after nodes have already been recorded.
- `sampling.feature_dimensions` and `sampling.feature_bins` are used by `island`. The defaults are `["complexity", "diversity"]` and `10`.
- `complexity` means code length, `diversity` means the built-in code-difference heuristic, and any other feature name must come from a numeric evaluator result field.
- `sampling.custom_sampler_path` and `sampling.custom_sampler_class` are required only when `sampling.algorithm=custom`.
- `cognition.seed_files` and `cognition.seed_notes` should contain reusable external insights, not task scaffolding or experimental analyses.
