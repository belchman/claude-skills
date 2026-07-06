# Install & invoke

This skill is a vendoring of `GAIR-NLP/ASI-Evolve@fb8a67e:skills/evolve/`. The Python CLI under `scripts/` is **deterministic** — it does not call any LLM. The LLM is the agent that loads `SKILL.md` and drives the loop (e.g. Claude). No OpenAI API key is required.

## Required runtime deps

The bundled CLI imports `yaml` (PyYAML) and `numpy`. Both must be available on whatever `python3` the agent shells out to.

```bash
pip install pyyaml numpy
```

That's enough for the full preflight gate, run-spec normalization, cognition seed/init, experiment database (record/sample/best/stats), file scope enforcement, evaluator runner, and final summary.

## Optional deps

Cognition vector search and semantic similarity inside the experiment database fall back to a deterministic local heuristic if these aren't installed:

```bash
pip install sentence-transformers faiss-cpu
```

Per `references/architecture.md`, the embedding and vector-index modules ship "graceful local fallbacks" — installing these only improves retrieval quality on large cognition stores. They're not required for correctness.

## Verifying install

```bash
python plugins/agentic-engineering/skills/evolve/scripts/evolve-brief --help
python plugins/agentic-engineering/skills/evolve/scripts/evolve-db    --help
python plugins/agentic-engineering/skills/evolve/scripts/evolve-eval  --help
```

All three should print subcommand help. If you see `ModuleNotFoundError: yaml` or `numpy`, install the required deps above.

## How the loop runs

The agent (Claude in this plugin) reads `SKILL.md` on invocation and orchestrates the round loop itself, calling the CLIs as deterministic helpers:

```
preflight  →  evolve-brief normalize                  (build run_spec.yaml)
             evolve-eval inspect                      (sanity-check evaluator)
             ── pause for user confirmation ──
cognition  →  evolve-cognition init / add / search
each round →  evolve-db sample                        (mandatory parent draw)
             [evolve-cognition search]
             [agent does web research → evolve-cognition add]
             agent edits files inside mutation_scope.writable_paths
             evolve-eval run                          (materializes candidate at steps/<step>/code)
             evolve-db record                         (persist node + analysis)
wrap-up    →  evolve-summary final
```

## Headless invocation (`claude -p`)

The skill is auto-routable (no `disable-model-invocation`), so a headless one-shot works:

```bash
claude -p "use the evolve skill to optimize <your objective> against <your evaluator script>"
```

Claude will draft the preflight, **pause for confirmation** (per the skill's preflight rule), then drive rounds. In interactive mode, just say "use evolve to ..." and the auto-router will load `SKILL.md`.

> The skill's preflight gate refuses to mutate files, run the evaluator, or write the final summary until `approval.confirmed=true`. Headless runs need an `--auto-approve` posture from you (a follow-up message confirming the preflight) — there's no implicit auto-approval.

## Where things live

```
.evolve_runs/<run-name>/
├── run_spec.yaml           (preflight contract)
├── cognition_seed.md       (reusable external insights only)
├── preflight_summary.md
├── round_log.jsonl
├── cognition_data/         (cognition store)
├── database_data/          (experiment database)
├── steps/<step-name>/      (per-round: code, results.json, analysis.md, node.json, eval.stdout/stderr)
└── best/                   (best snapshot, maintained by evolve-db record)
```

See `references/architecture.md` for full layout and `references/toolbelt.md` for per-CLI usage.

## About `agents/openai.yaml`

This file is an upstream Codex-style **interface manifest** (display name, default prompt blurb, implicit-invocation policy). It's not consumed by the Python code and has no effect when the skill runs under Claude Code. It's kept for byte-equivalence with upstream. A mirror manifest for Claude lives at `agents/claude.yaml`.
