---
name: feature
description: 'Orchestrate the full agentic-engineering chain on one brief — map → research → story → spec → rubric → backend lane → validator → frontend lane → final validator → PR — with three human checkpoints (story, spec+rubric, PR). Default path is in-conversation: each step runs as a forked Agent subagent so output is visible inline and per-step model selection is possible (Haiku for read-heavy steps, Sonnet/parent for writers, parent for code). Headless escape hatch: bash-invoke ${CLAUDE_SKILL_DIR}/bin/feature.sh for true AFK runs that survive terminal close. Triggers: /feature, "build this feature", "run the full chain", "orchestrate this feature end-to-end".'
disable-model-invocation: true
allowed-tools: Read Write Edit Bash Grep Glob Agent AskUserQuestion TaskCreate TaskUpdate
---

# /feature — orchestrator

Two ways `/feature` can run, picked by **how it was invoked**:

| Invocation | Mode | Use when |
| --- | --- | --- |
| User types `/feature "<brief>"` in a Claude session | **in-conversation** (default) | You want to watch it happen, steer mid-flight, and pay cheaper per-step models |
| User runs `${CLAUDE_SKILL_DIR}/bin/feature.sh start "<brief>"` from a shell | **headless** (the bash script) | True AFK — terminal will close, week-long pause expected, no Claude session running |

You (Claude reading this SKILL.md) are in-conversation mode. That's the default. **Only fall back to bash-invoking `feature.sh`** if the user explicitly says "run this AFK", "overnight", "I'm closing my laptop", "headless", or similar — then strip the trigger phrase from the brief and exit the in-conversation flow with a single bash-invoke. Example: user says `/feature Add a /version flag. Run this AFK, I'm closing my laptop.` → brief passed to feature.sh is `"Add a /version flag."` (trigger sentence dropped).

Both modes produce the same artifacts on disk (`issues/NNN-*.md`, `issues/NNN-*.spec.md`, `issues/NNN-*.rubric.md`, `issues/research/NNN-*.md`) and the same `.feature_runs/<id>/state.json` schema, so a mid-run handoff between modes is supported.

## When `/feature` is the right tool

The chain has real overhead — three checkpoints, ~8 subagent dispatches, multiple file artifacts. It pays for itself when the work is **a real feature**: at least one data-model change, API change, or UI change, with multiple files touched across lanes, where catching architectural assumptions at the spec stage prevents downstream rework.

**Overkill** when the work is:
- A one-file fix (typo, bug in a single function, dependency bump).
- A trivial CLI flag or subcommand (10-50 lines, no schema, no API contract).
- An isolated doc edit or single-file README sync (NOT a cross-cutting docs restructure).
- An isolated test-only change (NOT a coverage backfill spanning many modules).

For overkill cases, surface that to the user and suggest the direct path ("I can edit `crap.py` directly — that's ~10 lines"). If the user confirms "just do it inline" — or was explicit upfront — comply per the user-instructions-override-defaults rule. Don't bureaucratize trivial work.

---

## In-conversation orchestration (default)

### Invocation forms

- `/feature "<brief>"` — start a new run.
- `/feature <id>` (no brief) or "continue feature run \<id\>" — **resume** an existing run from `.feature_runs/<id>/state.json`. See "Resuming a run" below before doing anything else.

### Setup (new run)

1. Compute a run id: `printf '%04d-%s' "$next" "$slug"` where `next = max numeric prefix in issues/*.md + 1` and `slug = brief lowercased, stop words (a, an, the, this, that, to, for, of, on, in, and, or) stripped, non-alphanum runs collapsed to `-`, trimmed to ≤40 chars, no leading/trailing dash`. **Empty-slug fallback**: if the brief leaves nothing after stop-word stripping (very rare — e.g. all-stop-words input, or a one-word brief that IS a stop word), use the short hash of the brief: `printf '%s' "$brief" | shasum -a 256 | cut -c1-8`. Final id example: `0042-a3f17d2c`.
2. `TaskCreate` a parent task "feature/<id>" with subtasks for each step below, so the user sees a checklist.
3. Write the brief to `.feature_runs/<id>/brief.md` (create the dir).
4. Write the initial `state.json` (see schema in "State persistence") with `last_completed_step: "init"`.

### Step 1: refresh map (skip if ARCHITECTURE.md exists)

`Read ARCHITECTURE.md`. If missing, dispatch a `general-purpose` Agent with `model: haiku` and the `/map` skill's instructions. Wait for it; if the file was written, continue. If not, ask the user to invoke `/map` manually and abort.

After this step completes (file exists, whether pre-existing or just created): update `state.json` with `last_completed_step: "map_fresh"`.

### Step 2: research

Dispatch the `Agent` tool with `subagent_type: "Explore"` (read-only, fast — Explore type only has Read/Grep/Glob):
- prompt: brief + read `ARCHITECTURE.md` + glob the dirs the brief references, produce a structured research dump
- model: `haiku`
- have it write to `issues/research/<id>.md`

After this step completes: update `state.json` with `last_completed_step: "research_done"` and `research_path`.

### Step 3: story (`prd-to-issues` in single-issue mode)

Dispatch a `general-purpose` Agent:
- skill: `plugins/agentic-engineering/skills/prd-to-issues/SKILL.md` (pass full body in prompt)
- prompt: "Treat this brief as a single-feature PRD. Apply the AFK fallback (no quiz). Produce ONE issue at `issues/<id>.md` with a `### Slice rationale` sub-section."
- inputs: `.feature_runs/<id>/brief.md` + `issues/research/<id>.md`
- model: `sonnet`

### ⏸️ Checkpoint 1 — approve story

Before pausing: write `state.json` with `last_completed_step: "story_drafted"` and `issue_path`.

`AskUserQuestion` with question "Approve the story?" and options:
- **Approve** (continue to spec)
- **Redo with feedback** (collect feedback, re-dispatch step 3 with feedback prepended)
- **Abort** (write `state.json` with `last_completed_step: "aborted"` and stop)

**Cap on redos**: 3 per checkpoint. Track via an in-session counter (do NOT need to persist to state.json — if the user resumes after closing the session, the cap resets, which is acceptable since "user closed and reopened" is itself a signal they're starting fresh on that checkpoint). After the 3rd "Redo" at the same checkpoint in a single session, ask the user whether to abort or accept-as-is. Don't redo silently forever.

### Step 4: spec

Dispatch a `general-purpose` Agent:
- skill: `plugins/agentic-engineering/skills/write-a-spec/SKILL.md` (pass full body)
- prompt: "Apply the path-format rule strictly — repo-root-relative paths. Lane labels from CLAUDE.md ## Lane boundaries verbatim (lowercase in claude-skills)."
- inputs: `issues/<id>.md` + `issues/research/<id>.md`
- model: `sonnet`
- output: `issues/<id>.spec.md`

Validate immediately — run `allowlist_for` for **every** H3 lane declared in the spec (don't just check backend; a malformed frontend lane would silently no-op at step 8):

```bash
bash -c 'source plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh && \
  for lane in $(awk "/^### / {sub(/^### /,\"\"); sub(/[[:space:]]+\$/,\"\"); print}" issues/<id>.spec.md); do
    echo "=== $lane ==="
    allowlist_for issues/<id>.spec.md "$lane" || echo "FAIL: $lane"
  done'
```

If any lane returns empty or non-zero, re-dispatch step 4 with feedback citing the malformed lane before continuing. If ALL declared lanes return empty, that's a malformed spec — re-dispatch with feedback about the paths-block fence/H3 contract.

After validation passes: update `state.json` with `last_completed_step: "spec_drafted"` and `spec_path`.

### Step 5: rubric

Dispatch a `general-purpose` Agent:
- skill: `plugins/agentic-engineering/skills/write-a-rubric/SKILL.md` (pass full body)
- prompt: "Defer contract concerns to /adversarial-review per the Rubric-vs-contract section."
- inputs: `issues/<id>.md` + `issues/<id>.spec.md`
- model: `sonnet`
- output: `issues/<id>.rubric.md`

### ⏸️ Checkpoint 2 — approve spec + rubric

Before pausing: write `state.json` with `last_completed_step: "rubric_drafted"` and `rubric_path`.

`AskUserQuestion`. Same three options as CP1 (Approve / Redo / Abort). Same redo cap (3).

### Step 6: backend lane

1. Extract allowlist:
   ```bash
   bash -c 'source plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh && allowlist_for issues/<id>.spec.md backend'
   ```
2. If empty, skip to step 8 (no backend lane). **If BOTH lanes' allowlists are empty** (you'll discover this at step 8 too), abort the run with a diagnostic — the spec has no work to dispatch, which means write-a-spec produced an empty plan. Surface that to the user and ask whether to redo CP2 or abort.
3. Build a lane preamble file at `/tmp/feature-runs/<id>/lane-backend.prompt.md`:
   ```
   ## Allowlist
   <paths from allowlist_for>

   ## Escape valve
   If you need to edit a file outside this allowlist, STOP and append a `## Allowlist additions requested` section to issues/<id>.md naming the file and why. Do NOT edit out-of-lane.

   <body of work-issues SKILL.md without frontmatter>
   ```
4. Dispatch a `general-purpose` Agent:
   - prompt: contents of the lane preamble + the issue + spec + rubric
   - model: parent (don't override — TDD work needs the user's choice)
   - the agent runs one work-issues iteration, commits, returns

### Step 7: backend validator

Dispatch a `general-purpose` Agent:
- skill: `plugins/agentic-engineering/skills/adversarial-review/SKILL.md`
- env (via prompt instruction): `ADVERSARIAL_REVIEW_REPORT_ONLY=1`, `ADVERSARIAL_REVIEW_TARGETS=<colon-globs from backend allowlist>`
- prompt: "Phase 3 option D — report only, no fixes. Review the diff from this commit."
- model: `sonnet`
- output: findings text returned by the agent

Parse findings:
- If contains "Critical" referencing a backend path → write `issues/<id>-fix-findings.md` with the Critical findings, then re-dispatch step 6 with the fix issue prepended to the lane preamble.
- Else → continue.

**Loopback cap: 2 iterations of step 6→7 per lane.** This is a per-validator budget (step 7 has its own 2, step 9 has its own 2). **Persist the counter to state.json** (in a `loopback_counts` object — e.g. `{"step_7_backend": 1, "step_9_backend": 0, "step_9_frontend": 0}`) so a resume after laptop close doesn't reset the budget and risk runaway loops across sessions. After the 2nd backend re-dispatch still surfaces Critical, mark `lanes.backend.status: "blocked"` in state.json and continue to step 8 (the user will see the unresolved findings at CP3). Don't loop forever.

### Step 8: frontend lane (skip if spec has no `### frontend`)

Same as step 6 with `frontend` lane.

### Step 9: final validator

Same as step 7 against the **full diff** (all commits this run produced, both lanes). Loopback semantics if Critical:

1. Use `route_findings` to classify each Critical finding by lane:
   ```bash
   bash -c 'source plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh && \
     route_findings <findings_file> issues/<id>.spec.md'
   ```
   Each line of output is `<lane>\t<finding>`.
2. For each lane that owns ≥1 Critical: re-dispatch that lane's step (step 6 for backend, step 8 for frontend). If a finding's path is `<unmapped>`, surface it at CP3 — don't auto-dispatch.
3. Independent loopback budget: step 9 gets its own 2 iterations, separate from step 7's budget. Tracked in `state.json.loopback_counts.step_9_<lane>` (one counter per lane that gets re-dispatched from step 9). After 2nd loop still Critical, mark the lane's status `"blocked"` and continue to CP3.

After step 9 passes (or budgets exhausted): update `state.json` with `last_completed_step: "validated"` and `validator_findings: "<findings_path>"`.

### ⏸️ Checkpoint 3 — open PR

`AskUserQuestion` with options:
- **Open PR** (suggest a title + body from the issue, run `gh pr create` if the user confirms; or just print the suggested PR text)
- **Redo lane work**
- **Done, no PR** (mark run done locally)

## Per-step model defaults

Hardcoded defaults below.

| Step | Model | Why |
| --- | --- | --- |
| 1 — map | `haiku` | File scans, no synthesis |
| 2 — research | `haiku` | Read-only Explore |
| 3 — story | `sonnet` | Light synthesis |
| 4 — spec | `sonnet` | Architecture decisions |
| 5 — rubric | `sonnet` | Sharp criteria need reasoning |
| 6 — backend lane | parent | TDD; user's parent-session model is respected by default |
| 7 — backend validator | `sonnet` | Coverage analysis |
| 8 — frontend lane | parent | Same as backend |
| 9 — final validator | `sonnet` | Coverage analysis |

### Honoring natural-language overrides

When the user says something like "use sonnet for everything" or "use opus for the spec", apply this normalization recipe **and then echo the resolved table back to the user before step 1 so they can correct it**:

1. **Phrase → step set**:
   - "everything" / "all steps" / "every step" → all 9 rows (including lanes — explicit "everything" wins over the "parent" default).
   - "everything else" / "the rest" / "everything not mentioned" → **all rows NOT already named in earlier clauses of the same user message**. Example: "use opus for the spec, haiku for the validators, sonnet for everything else" → spec=opus, validators (rows 7+9)=haiku, **all remaining rows (1, 2, 3, 5, 6, 8) = sonnet**. Process the user's clauses left-to-right; "everything else" applies last.
   - "the lanes" / "the builders" / "the work-issues steps" → rows 6 + 8.
   - "the validators" → rows 7 + 9.
   - "the writers" / "spec and rubric" → rows 3 + 4 + 5 (synthesis steps).
   - "the cheap steps" / "research and map" → rows 1 + 2.
   - A bare step name ("spec", "rubric", "research", "validator") → match the unique row containing that word in column 1; if ambiguous ("validator" → rows 7 AND 9), ask the user which one.
2. **Model name** (after "use" / "with" / "switch to"): accept `haiku`, `sonnet`, `opus`, or a full model id like `claude-opus-4-7`. If the name doesn't match a known model alias, ask the user.
3. **Explicit overrides beat `parent`-default rows** (rows 6 and 8) — "use sonnet for everything" sets lanes to `sonnet`, even though their default is parent.
4. **Echo back**: print the resolved 9-row table with the overridden cells highlighted (e.g. with `[overridden]` suffix) before dispatching step 1. If the user objects, accept a correction; otherwise proceed.

## Resuming a run

If invoked as `/feature <id>` (no brief) or the user says "continue feature run \<id\>" / "resume \<id\>":

1. Read `.feature_runs/<id>/state.json`. If missing, tell the user the run id wasn't found and ask if they meant to start a new run.
2. If `last_completed_step` is `"done"` → tell the user the run is already done; ask if they want to start a new run from the same brief or another action.
3. If `last_completed_step` is `"aborted"` → tell the user the run was aborted; ask if they want to start a new run.
4. Otherwise, map `last_completed_step` to the next step using this table — then dispatch from there. **Don't re-run completed steps.**

| `last_completed_step` | Resume at |
| --- | --- |
| `init` | Step 1 (map) |
| `map_fresh` | Step 2 (research) |
| `research_done` | Step 3 (story) |
| `story_drafted` | CP1 — re-show the AskUserQuestion |
| `spec_invalid` | Step 4 (spec) with feedback prepended ("the prior spec was malformed: …") |
| `spec_drafted` | Step 5 (rubric) |
| `rubric_drafted` | CP2 — re-show the AskUserQuestion |
| `backend_complete` | Step 7 (backend validator) |
| `backend_validated` | Step 8 (frontend lane) |
| `frontend_complete` | Step 9 (final validator) |
| `frontend_validated` | CP3 — re-show the AskUserQuestion |
| `validated` | CP3 — re-show the AskUserQuestion. This state is set after step 9 regardless of whether the frontend lane ran, so it's the canonical "ready for CP3" marker — `frontend_validated` is a synonym used only when frontend was the most recent lane. |

Before resuming, read the relevant artifacts that step needs (issue, spec, rubric, lane preambles) so the dispatched subagent has full context. If an artifact named in `state.json` is missing on disk, treat that as a corrupted run and ask the user whether to retry or abort.

## State persistence (for headless interop)

After every step, write `.feature_runs/<id>/state.json` with these fields (the same 11-field schema the bash script uses):

```json
{
  "id": "<id>",
  "brief_path": ".feature_runs/<id>/brief.md",
  "issue_path": "issues/<id>.md",
  "research_path": "issues/research/<id>.md",
  "spec_path": "issues/<id>.spec.md",
  "rubric_path": "issues/<id>.rubric.md",
  "lanes": { "backend": { "allowlist": [...], "status": "complete" } },
  "validator_findings": "",
  "last_completed_step": "rubric_drafted",
  "started_at": "<ISO-8601>",
  "updated_at": "<ISO-8601>"
}
```

This lets a user abort the in-conversation flow and pick up via `feature.sh continue <id>` later, and vice versa. **State documented step values** (use these exact strings): `init`, `map_fresh`, `research_done`, `story_drafted`, `spec_drafted`, `spec_invalid`, `rubric_drafted`, `backend_complete`, `backend_validated`, `frontend_complete`, `frontend_validated`, `validated`, `done`, `aborted`.

## Headless / AFK alternative

When the user explicitly says "AFK" / "headless" / "overnight" / "close the laptop" — exit the in-conversation flow and bash-invoke:

```bash
"${CLAUDE_SKILL_DIR}/bin/feature.sh" start "<brief>"
```

The script does its own orchestration with `claude -p` subprocesses (cache-hot via `--resume <parent_sid> --fork-session` after the c873e77 primer optimization) and pauses by exiting between steps. User resumes via `feature.sh continue <id> --accept`, `--redo`, `abort`, `status`.

## Failure modes

- **Subagent returns empty / malformed**: re-dispatch with a clearer prompt. Cap at 2 retries per step.
- **`allowlist_for` returns empty** on a step-6/8 invocation: spec is malformed. Re-dispatch step 4 with feedback about the paths-block format.
- **Critical validator findings in a lane**: dispatch the lane again with findings prepended. Cap at 2 loopback iterations; if still Critical, surface at the next checkpoint and let the user decide.
- **TaskCreate not available** (older Claude Code without TaskCreate): skip the checklist; orchestrate without progress tracking.

## Hard rules

- **Slash-only.** `disable-model-invocation: true` in frontmatter — the model must not auto-invoke. Only fire on explicit `/feature`.
- **Don't bash-invoke `feature.sh` from inside an in-conversation `/feature` run** unless the user explicitly opts into headless. The two modes are alternatives, not nested.
- **Don't replicate spec/rubric/work-issues skill logic inline.** Always dispatch the skill's own subagent so the skill's discipline (path rules, rubric < contract, lane preamble) applies.
- **Never edit files in step 6/8 yourself.** That work belongs to the lane subagent; you're only orchestrating.
- **Surface every Agent response inline.** That's the whole point of in-conversation mode — the user sees what each step did.
