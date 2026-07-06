# claude-skills

A marketplace of individually installable Claude Code plugins (repo: `belchman/claude-skills`). Each plugin under `plugins/` stands alone; the repo root carries the shared tests, tools, and eval harnesses that keep the marketplace consistent.

## Commands

- `make lint`: shellcheck over agent-loop bin/hook scripts (skips gracefully if shellcheck is missing; CI enforces)
- `make test-sync`: parity guard across `marketplace.json`, `plugins/*/plugin.json`, and `README.md`
- `make test-fast`: fast suite, about 5s (pytest, feature helpers, work-issues lib, agent-loop wired). The Stop hook (`.claude/hooks/test-on-stop.sh`) runs this after every turn.
- `make test`: full suite, about 4 min. Adds agent-loop bin/hook/loop/watch suites and the `/feature` orchestrator integration tests.
- `bash tools/lint-claude-md.sh`: lint this file (the claude-md-audit hook runs the same checks on write)

Distribution is the plugin marketplace, not a sync to `~/.claude/skills`:

```
/plugin marketplace add belchman/claude-skills
/plugin install agentic-engineering@belchman-claude-skills
```

`.claude/settings.json` registers this checkout as a local marketplace (`extraKnownMarketplaces`), so edits here are live for dogfooding.

## Architecture: how skills are organized

- `.claude-plugin/marketplace.json`: manifest listing the four plugins
- `plugins/<plugin>/`: standalone plugin. Skills live at `plugins/<plugin>/skills/<skill>/SKILL.md`, plus optional `bin/`, `hooks/`, `agents/`, `templates/`
- `tests/`: repo-level pytest + shell suites; `tools/`: CLAUDE.md linter/generator, benchmark and cost scripts
- `evals/agent-loop/`: eval harness; fixture paths come from gitignored `fixtures.local.json`
- `issues/`, `.feature_runs/`, `.claude/agent-loop/`: artifacts from dogfooding the pipeline skills on this repo
- Docs: `ARCHITECTURE.md` (map), `CONTEXT.md` (glossary), `docs/adr/` (decisions), `docs/agent-loop-design.md`

## Plugin catalog

- `agentic-engineering`: the build/review/debug pipeline, grouped by phase.
  - Pipeline: `write-a-prd`, `prd-to-issues`, `write-a-spec`, `write-a-rubric`, `work-issues`, `feature` (end-to-end orchestrator, three human checkpoints, state in `.feature_runs/<id>/state.json`)
  - Design: `grill-with-docs` (default), `grill-me` (no-codebase only), `prototype`
  - Implement: `tdd`, `improve-codebase-architecture`, `evolve` (vendored, score-driven search)
  - Debug: `diagnose`, `zoom-out`; Review: `adversarial-review`, `crap`; Document: `map`
  - Plus `*-workspace` helper skills. Per-skill detail table: `plugins/agentic-engineering/SKILLS.md`
- `agent-loop`: goal-driven loop harness. `/agent-loop init, new, run, approve, reject, status, doctor, canonize`; headless tick via `bin/al-loop.sh`; state in `.claude/agent-loop/`. For one durable goal in any repo, no `issues/` queue.
- `audit-agent-overhead`: audits a Claude Code setup (global, project, plugin scope) for overhead.
- `claude-md-audit`: no skills, just a PreToolUse hook that lints CLAUDE.md on every Edit/Write and blocks writes that fail lint errors.

Build pipeline: brief, then `write-a-prd` makes `issues/prd.md`, `prd-to-issues` makes `issues/NNN-*.md`, `write-a-spec` and `write-a-rubric` add sidecars, `work-issues` works AFK items to `issues/done/`. `/feature` runs the whole chain on one brief.

Heavyweight skills are slash-only: `/feature` and `/zoom-out` and `/agent-loop` via `disable-model-invocation: true` frontmatter (hard gate); `/work-issues`, `/adversarial-review`, `/map` via "Use only when explicitly asked" description prose (soft gate, so `/feature` can dispatch them programmatically).

## Current state (checked 2026-07-06)

- Branch `master`, remote `origin` = `belchman/claude-skills`, local master is 5 commits ahead of `origin/master` (last commit 2026-07-05: CI make targets, marketplace-sync guard, nightly eval workflows)
- 11 dirty files, two threads of WIP:
  - agent-loop watch feature: untracked `plugins/agent-loop/bin/al-watch`, `tests/test_agent_loop_watch.sh`, `tests/test_agent_loop_wired.sh`; modified `Makefile` and `plugins/agent-loop/skills/agent-loop/SKILL.md`
  - dogfood run of the pipeline on issue 0001 (optimize feature.sh for prompt cache): untracked `issues/0001-*.md` story/spec/rubric, `issues/research/`, `.claude/agent-loop/GOAL.md` + `goal.json`

## Conventions for writing or editing skills

- Every skill is `plugins/<plugin>/skills/<name>/SKILL.md` with YAML frontmatter; the `description:` field is the trigger, so include explicit trigger phrases, and gate heavyweight skills (frontmatter flag or description prose as above)
- Keep `marketplace.json`, each `plugins/*/plugin.json`, and the README plugin sections in sync; `make test-sync` fails otherwise
- Vendored skills (mattpocock/skills, MIT; GAIR-NLP/ASI-Evolve, Apache 2.0) need per-file entries in `plugins/agentic-engineering/ATTRIBUTION.md`
- Skills communicate through a small artifact contract: `issues/*.md`, `issues/NNN-*.spec.md` and `.rubric.md` sidecars, `issues/prd.md`, `issues/done/`, `rubrics/*.md`, `CONTEXT.md`, `docs/adr/NNNN-*.md`, `ARCHITECTURE.md`
- ADR threshold, offer one only when all three hold: hard to reverse, surprising without context, real trade-off

## Lane boundaries

Canonical lane vocabulary read by `write-a-spec` and the `/feature` orchestrator. Spec lane H3 headings must match these labels character for character, including case. This repo has no real backend/frontend split; the labels below are illustrative and exercised by `tests/test_feature_orchestrator.sh`.

- `backend`: patterns like `plugins/*/skills/*/bin/*.sh`, `plugins/*/skills/crap/*.py`, `tests/test_*.sh`
- `frontend`: patterns like `plugins/*/skills/*/SKILL.md`, `plugins/*/SKILLS.md`, `README.md`

## Do NOT (gotchas)

- Do NOT `git push`: it is denied in `.claude/settings.json`. Commit locally; the user pushes.
- The Stop hook runs `make test-fast` after every turn. Keep the fast suite green or every turn ends with hook noise.
- Editing this CLAUDE.md triggers the claude-md-audit lint hook; it blocks on errors (needs an H1 first heading, a Commands section, no secrets).
- Lane H3 labels in specs are case-sensitive exact matches against `## Lane boundaries`; a mismatch silently skips the lane with status `empty`.
- Never commit eval fixture identities; `evals/agent-loop` keeps them in gitignored `fixtures.local.json`.
- `.crap-cache/`, `.feature_runs/`, `mutants/`, `logs/`, `.pytest_cache/` are generated working state; do not hand-edit.
- Do NOT delete or rename the in-flight `issues/0001-*` artifacts or the untracked agent-loop watch files; they are active WIP.
