# Attribution

Several skills in this directory are adapted or vendored from external repos. License terms below.

## mattpocock/skills

Source: https://github.com/mattpocock/skills
Commit at vendor time: `494e4b2699ea` (2026-05-06)
License: **MIT** © 2026 Matt Pocock — full text in `licenses/mattpocock-skills-LICENSE`.

### Vendored verbatim or near-verbatim

| File | Notes |
| --- | --- |
| `prototype/SKILL.md` | Verbatim. |
| `prototype/LOGIC.md` | Verbatim. |
| `prototype/UI.md` | Verbatim. |
| `zoom-out/SKILL.md` | Verbatim. |
| `grill-with-docs/CONTEXT-FORMAT.md` | Verbatim. |
| `grill-with-docs/ADR-FORMAT.md` | Verbatim. |
| `improve-codebase-architecture/SKILL.md` | Verbatim. Replaces an older repo-local version that used `REFERENCE.md`. |
| `improve-codebase-architecture/LANGUAGE.md` | Verbatim. |
| `improve-codebase-architecture/DEEPENING.md` | Verbatim. |
| `improve-codebase-architecture/INTERFACE-DESIGN.md` | Verbatim. |
| `diagnose/scripts/hitl-loop.template.sh` | Verbatim — referenced from `diagnose/SKILL.md` Phase 1 step 10 (HITL bash script). |

### Adapted

| File | Notes |
| --- | --- |
| `diagnose/SKILL.md` | Lightly compressed (preserved every actionable rule, phase, and checklist). |
| `grill-with-docs/SKILL.md` | Re-authored with three improvements over upstream: (1) explicit "what plan are we stress-testing?" anchor at session start, (2) explicit stop conditions, (3) closing summary block that lists CONTEXT.md edits, ADRs, open questions, and recommended next skill. Wired to this repo's `write-a-prd` / `prd-to-issues` / `improve-codebase-architecture` / `work-issues` skills instead of upstream's `to-prd` / `to-issues` / `triage` (which assume an external issue tracker). |

### Not vendored (and why)

| Upstream skill | Reason for skipping |
| --- | --- |
| `tdd` | This repo's existing `tdd` skill is functionally equivalent; ours is already compressed. |
| `to-issues` | Assumes an external issue tracker via `setup-matt-pocock-skills`. This repo's `prd-to-issues` works against local markdown in `issues/` — more portable. |
| `to-prd` | Same as above; this repo's `write-a-prd` writes local markdown. |
| `triage` | Tightly coupled to an external tracker's label vocabulary. Doesn't fit the local-markdown-issues convention. |
| `setup-matt-pocock-skills` | Meta-installer for upstream's framework. Not relevant here. |

## GAIR-NLP/ASI-Evolve

Source: https://github.com/GAIR-NLP/ASI-Evolve
Commit at vendor time: `fb8a67e552e25cf8b7144d4e7f1a17f665055130` (2026-05-13)
License: **Apache 2.0** — full text in `licenses/asi-evolve-LICENSE`.

The `evolve/` skill is a near-verbatim vendoring of `skills/evolve/` from upstream. Provides a single-agent, preflight-gated learn → design → experiment → analyze loop with cognition store, experiment database, and CLI toolbelt (`evolve-brief`, `evolve-cognition`, `evolve-db`, `evolve-eval`, `evolve-files`, `evolve-summary`) plus the vendored `evolve_core/` runtime (samplers: `ucb1`, `greedy`, `random`, `island`, optional `custom`).

### Vendored verbatim

| File | Notes |
| --- | --- |
| `evolve/agents/openai.yaml` | Verbatim. |
| `evolve/references/architecture.md` | Verbatim. |
| `evolve/references/operating_model.md` | Verbatim. |
| `evolve/references/preflight.md` | Verbatim. |
| `evolve/references/run_spec.md` | Verbatim. |
| `evolve/references/toolbelt.md` | Verbatim. |
| `evolve/scripts/evolve-brief` | Verbatim. |
| `evolve/scripts/evolve-cognition` | Verbatim. |
| `evolve/scripts/evolve-db` | Verbatim. |
| `evolve/scripts/evolve-eval` | Verbatim. |
| `evolve/scripts/evolve-files` | Verbatim. |
| `evolve/scripts/evolve-summary` | Verbatim. |
| `evolve/scripts/evolve_core/**` | Verbatim (every file under `evolve_core/`, including `algorithms/` subdir). |

### Adapted

| File | Notes |
| --- | --- |
| `evolve/SKILL.md` | One-word change: upstream `description` says "Codex needs to align…"; vendored as "Claude needs to align…" so the auto-router triggers correctly here. All body content is verbatim. |

### Locally added (not in upstream)

| File | Notes |
| --- | --- |
| `evolve/INSTALL.md` | Local README covering required (`pyyaml`, `numpy`) and optional (`sentence-transformers`, `faiss-cpu`) deps, CLI smoke commands, headless `claude -p` invocation, and the preflight-confirmation contract. |
| `evolve/agents/claude.yaml` | Mirror of upstream's `agents/openai.yaml` plus a `runtime` block documenting that the agent is Claude, no LLM API keys are required, and which Python deps are needed. |

## Other vendored skills (not from mattpocock/skills)

| Skill | Source | License | Notes |
| --- | --- | --- | --- |
| `audit-agent-overhead` | Built locally; methodology from [@mnilax thread, 2026](https://x.com/mnilax/status/2050261839653556522) | n/a (original work; methodology cited) | The 9 token-waste patterns and percentages come from @mnilax's 90-day instrumented study; cited inline in the SKILL.md and patterns.md. |
| `tdd`, `prd-to-issues`, `write-a-prd`, `grill-me` | Originally from `mattpocock/ai-engineer-workshop-2026-project` (no license at the time of vendoring); now compressed in this repo | Pre-MIT-era vendoring | These were taken before mattpocock/skills established an MIT licence. They have since been compressed and adapted. The newer mattpocock/skills repo is MIT and supersedes parts of the workshop content. |
| `work-issues` | Original to this repo | n/a | Includes `bin/loop.sh` and `bin/once.sh` headless wrappers around the same SKILL.md prompt. |
| `write-a-rubric` | Original to this repo | n/a | Discipline derived from Anthropic's Managed Agents [Define outcomes](https://platform.claude.com/docs/en/managed-agents/define-outcomes) docs (rubric structure, gradeability principles). |
