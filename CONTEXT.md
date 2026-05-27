# claude-skills

This repo bundles AI-agent skills (mostly for Claude Code). The dominant domain is **agent orchestration**: how a single human + many specialized AI subagents collaborate to ship code.

## Language

**Skill**:
A self-contained directory under `plugins/<plugin>/skills/<name>/` containing at minimum a `SKILL.md` file. The `SKILL.md` body is the prompt loaded when the skill is invoked.
_Avoid_: prompt template, agent, persona.

**Plugin**:
A top-level grouping of skills + commands + hooks distributed as a unit (e.g. `agentic-engineering`, `audit-agent-overhead`).
_Avoid_: package, bundle, module.

**Lane**:
A project-defined scope label (e.g. `Backend`, `Frontend`, `CLI`) that constrains which files a subagent may edit. Defined per-project in `CLAUDE.md`'s `## Lane boundaries` section. Used by `/feature` to inject an allowlist into `/work-issues` via `WORK_ISSUES_PROMPT`.
_Avoid_: domain, tier, layer.

**Issue**:
A unit of work tracked as a markdown file at `issues/NNN-<slug>.md`. Tagged AFK (autonomously workable) or HITL (needs human in the loop). Produced by `prd-to-issues`; consumed by `/work-issues`.
_Avoid_: ticket, task, story.

**Sidecar**:
An artifact written next to a source file (same NNN, same slug, different extension) that adds discipline without modifying the source. The rubric, spec, and research dump for issue NNN are all sidecars to `issues/NNN-<slug>.md`.
_Avoid_: companion, supplement.

**Rubric**:
The gradeable success-criteria sidecar to an issue. At `issues/NNN-<slug>.rubric.md`. Produced by `write-a-rubric`. Walked by `/work-issues` after commit; consumed by `/adversarial-review`'s coverage reviewer.
_Avoid_: criteria, acceptance.

**Spec**:
The technical-brief sidecar to an issue. At `issues/NNN-<slug>.spec.md`. Produced by `write-a-spec`. Contains data model, API, per-lane file lists (as fenced `paths` blocks under H3 lane headings), tests required (behavior list), risks. Drives `/feature`'s lane allowlist.
_Avoid_: brief, design, technical doc.

**Research dump**:
A per-feature read-only summary produced by an `Explore` subagent dispatch in `/feature` step 2. At `issues/research/NNN-<slug>.md`. Read by `write-a-spec`; never modified.
_Avoid_: investigation, discovery.

**Lane preamble**:
The prompt prepended by `/feature`'s orchestrator before `bin/loop.sh` runs in a lane. Lives at `/tmp/feature-runs/<id>/lane-<name>.prompt.md`. Contains the allowlist + escape-valve instructions; concatenated in front of the frontmatter-stripped `work-issues/SKILL.md` body.
_Avoid_: lane prompt, allowlist preamble.

**AFK / HITL**:
Issue tags. AFK = "away from keyboard" — `/work-issues` can pick it up autonomously and ship to a commit. HITL = "human in the loop" — needs a person at design review or for an architectural call.
_Avoid_: auto / manual, headless / interactive.

**Paths block**:
A fenced code block tagged `paths` inside a spec. One literal file path per line; no globs (v1). Lives under an H3 lane heading. Parsed by `bin/feature-helpers.sh::allowlist_for` to derive the lane allowlist.
_Avoid_: file list, glob block, manifest.

## Relationships

- A **plugin** contains zero or more **skills**.
- A **skill** is invoked either by a user slash command, by the model (unless `disable-model-invocation` is set), or by another orchestrator skill via the Skill tool / Bash.
- An **issue** has at most one **rubric** sidecar, at most one **spec** sidecar, and at most one **research dump** sidecar — all sharing the issue's NNN-slug stem.
- A **spec** declares one or more **lanes** (matching `CLAUDE.md`'s `## Lane boundaries`), each with its own **paths block**.
- A **lane preamble** is built once per lane invocation by combining one **lane**'s **paths block** + an escape-valve sentence + the `work-issues` SKILL.md body.

## Example dialogue

> **Dev:** "When `/feature` runs, the orchestrator hands an **issue** to `write-a-spec`, then writes a **spec** sidecar next to it?"
> **Domain expert:** "Yes — and the **spec** must contain at least one **paths block** under an H3 **lane** heading, so the orchestrator can build the **lane preamble** for that lane's `/work-issues` invocation."
> **Dev:** "What if the feature is backend-only? Does the spec still need a Frontend lane?"
> **Domain expert:** "No — omit the empty **lane** entirely. The orchestrator's parser treats a missing lane as 'skip'."

## Flagged ambiguities

- "spec" was almost overloaded with the PRD's user stories. Resolved: **spec** = technical-brief sidecar to one issue; **PRD** (`issues/prd.md`) = product framing across all issues.
- "lane" was almost conflated with "domain". Resolved: **lane** is a *file-scope label* (which paths can I edit?); "domain" is reserved for DDD bounded-context discussion if it ever arises.
- "sidecar" vs "companion file" — picked **sidecar** because it's already used in `write-a-rubric/SKILL.md` and matches the existing `*.rubric.md` convention.
