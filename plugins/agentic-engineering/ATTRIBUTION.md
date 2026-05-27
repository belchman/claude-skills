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

## Other vendored skills (not from mattpocock/skills)

| Skill | Source | License | Notes |
| --- | --- | --- | --- |
| `audit-agent-overhead` | Built locally; methodology from [@mnilax thread, 2026](https://x.com/mnilax/status/2050261839653556522) | n/a (original work; methodology cited) | The 9 token-waste patterns and percentages come from @mnilax's 90-day instrumented study; cited inline in the SKILL.md and patterns.md. |
| `tdd`, `prd-to-issues`, `write-a-prd`, `grill-me` | Originally from `mattpocock/ai-engineer-workshop-2026-project` (no license at the time of vendoring); now compressed in this repo | Pre-MIT-era vendoring | These were taken before mattpocock/skills established an MIT licence. They have since been compressed and adapted. The newer mattpocock/skills repo is MIT and supersedes parts of the workshop content. |
| `work-issues` | Original to this repo | n/a | Includes `bin/loop.sh` and `bin/once.sh` headless wrappers around the same SKILL.md prompt. |
| `write-a-rubric` | Original to this repo | n/a | Discipline derived from Anthropic's Managed Agents [Define outcomes](https://platform.claude.com/docs/en/managed-agents/define-outcomes) docs (rubric structure, gradeability principles). |
