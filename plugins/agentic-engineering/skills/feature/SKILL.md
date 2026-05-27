---
name: feature
description: 'Orchestrate the full agentic-engineering chain on one brief — refresh /map, dispatch an Explore researcher, draft a story, write a spec, write a rubric, build the backend lane, run a validator pass, build the frontend lane, run a final validator, surface findings — with three human checkpoints (story, spec+rubric, PR). Resumable across sessions via .feature_runs/<id>/state.json. Use when the user says /feature, "build this feature", "run the full chain", "orchestrate this feature end-to-end". Slash-only — Claude should Bash-invoke bin/feature.sh, never replicate its logic in-conversation.'
disable-model-invocation: true
---

# /feature — the orchestrator

`/feature` is a thin user-facing wrapper around `bin/feature.sh`. When the user types `/feature "<brief>"`, the only thing you (Claude) need to do is **Bash-invoke** the script and surface its stdout to the user. Do NOT try to replicate the chain in conversation — that's exactly what the orchestrator exists to prevent (collapsed-context drift, see PRD).

## When this skill is the right tool

The chain has real overhead — three human checkpoints, six subagent dispatches, multiple file artifacts (`issues/NNN-*.md`, `*.spec.md`, `*.rubric.md`, `*.research.md`). It pays for itself when the work is **a real feature**: at least one data-model change, API change, or UI change, with multiple files touched across lanes, where catching architectural assumptions at the spec stage prevents downstream rework.

The chain is **overkill** when the work is:
- A one-file fix (typo, bug in a single function, dependency bump).
- A trivial CLI flag or subcommand (10-50 lines, no schema, no API contract).
- A doc edit or README sync.
- A test-only change.

For overkill cases, surface that to the user before Bash-invoking. Suggest the direct path ("I can edit `crap.py` directly — that's ~10 lines"). If the user confirms "just do it inline" — or if they were explicit upfront with phrasing like "just do this inline, the orchestrator is overkill" — comply per the standard user-instructions-override-defaults rule. Don't bureaucratize trivial work.

For real-feature cases, Bash-invoke without hedging. The whole point is to NOT pre-design in the calling context.

## Invocation

```bash
plugins/agentic-engineering/skills/feature/bin/feature.sh start "<the user's brief verbatim>"
```

The script handles everything from there: creates `.feature_runs/<id>/`, drafts research + story, exits at Checkpoint 1 with explicit resume instructions printed to stdout. Pass those instructions to the user.

When the user comes back with approval / feedback:

```bash
bin/feature.sh continue <id> --accept             # accept and continue
bin/feature.sh continue <id> --redo "<feedback>"  # rerun last step with feedback
bin/feature.sh abort <id>                          # give up; release LOCK
bin/feature.sh status <id>                         # print state.json in human form
```

## What the chain does

Three checkpoints (CP1 after story, CP2 after spec+rubric, CP3 before PR). Ten steps between them. See `docs/plans/feature-factory.md` §F for the full chain — don't restate it here. Lessons in `docs/lessons-learned/feature-factory-build.md`.

### Invocation count vs. checkpoint count

In practice the chain has **three named checkpoints (CP1/CP2/CP3) but four `continue --accept` invocations** before `done`. The fourth pause happens at `state = backend_validated` — the orchestrator pauses between the backend and frontend lanes so the user can abort if the backend's commit looked wrong before frontend touches the codebase. This is intentional (an inter-lane gate, not a UX oversight) but isn't paged with a "CHECKPOINT" banner. When you explain `/feature` to a user, tell them: "5 total invocations — start, then 4 × continue. The third pause is silent." See lessons-learned Round 4 for the design rationale.

## Dependencies

This skill assumes the following have been merged (issues 001, 002, 003, 004 of the feature-factory build):

- **001** — `write-a-spec` skill exists at `plugins/agentic-engineering/skills/write-a-spec/SKILL.md`. The orchestrator's Step 4 dispatches `claude -p` with the `write-a-spec` skill prompt to produce the technical brief sidecar.
- **002** — `/adversarial-review` honors `ADVERSARIAL_REVIEW_REPORT_ONLY=1` and `ADVERSARIAL_REVIEW_TARGETS=<colon-globs>` env vars. The orchestrator's Steps 7 and 9 set both before dispatching the validator.
- **003** — `/work-issues` honors a lane preamble prepended to its prompt (`## Allowlist` + escape valve). The orchestrator's Steps 6 and 8 build the preamble at `/tmp/feature-runs/<id>/lane-<lane>.prompt.md` and invoke `bin/loop.sh` with `WORK_ISSUES_PROMPT=$lane_prompt`.
- **004** — `work-issues-lib.sh` exposes `allowlist_for <spec> <lane>` and `route_findings <findings> <spec>`. The orchestrator sources `bin/feature-helpers.sh`, which sources `work-issues-lib.sh` for both functions.

If any of these aren't merged yet, the chain will fail at the corresponding step. Check before running.

## CLAUDE.md `## Lane boundaries`

The orchestrator's Steps 6 and 8 build per-lane `WORK_ISSUES_PROMPT` files from the spec's `### <Lane>` H3 headings. Those labels must match names defined in `CLAUDE.md`'s `## Lane boundaries` section. If `CLAUDE.md` has no such section, `write-a-spec` (Step 4) will surface this in the Risks section of the spec; review at Checkpoint 2 before continuing.

## Failure modes

See `docs/plans/feature-factory.md` §G. Summary:

- Any `claude -p` non-zero → orchestrator exits non-zero; `last_completed_step` unchanged; user reruns `continue <id>`.
- `write-a-spec` returns no `paths` blocks → `last_completed_step = "spec_invalid"`; user runs `continue <id> --redo "<feedback about format>"`.
- `bin/loop.sh` hits iteration cap → lane status = `partial`; surface at Checkpoint 3.
- Validator dispatch crashes → `validator_findings = "DISPATCH_FAILED"`; surface at the next checkpoint.
- Builder writes `## Allowlist additions requested` to the issue file → lane stops; surface at Checkpoint 3.
- Concurrent `start` → second invocation refuses with a clear message naming the active run dir.

## State persistence

`.feature_runs/<id>/state.json` is the source of truth. Fields: `id`, `brief_path`, `issue_path`, `research_path`, `spec_path`, `rubric_path`, `lanes`, `validator_findings`, `last_completed_step`, `started_at`, `updated_at`. The script reads it on every `continue`, dispatches the next step based on `last_completed_step`, and writes it back atomically before exiting any step. Resumable across terminal close, machine reboot, week-long pauses.

## Env overrides (for testing / advanced use)

- `CLAUDE_CMD` — command invoked for child dispatches. Default: `claude`. Set to a stub in tests.
- `LOOP_SH_CMD` — command invoked for lane builds. Default: `../../work-issues/bin/loop.sh` (relative to `bin/feature.sh`).
- `FEATURE_RUNS_DIR` — root of run state. Default: `.feature_runs` at the repo root.
- `FEATURE_REPO_ROOT` — where the orchestrator writes spec/rubric/issue/research files. Default: `git rev-parse --show-toplevel` (or `$PWD` if not a git repo). Override in tests so artifacts don't leak into the real `issues/` dir.

## Hard rules

- Slash-only. `disable-model-invocation: true` in frontmatter — the model must not auto-invoke this skill based on conversational context. Only fire on explicit `/feature` (or another orchestrator skill calling it intentionally).
- Don't replicate the chain in conversation. The whole point of the orchestrator is that each step runs in a fresh `claude -p` context so it doesn't drift. Bash-invoke `bin/feature.sh`.
- Never modify `bin/feature.sh` / `bin/feature-helpers.sh` mid-chain. If the orchestrator is broken, abort the run, fix the script, start a new run.
- Don't add Claude as a co-author to any commit `bin/feature.sh` makes via `/work-issues`.
