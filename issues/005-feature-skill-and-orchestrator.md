## Parent PRD

`issues/prd.md`

## Type

**AFK** (large but cohesive — the orchestrator is a deep module)

## What to build

The full `/feature` slash-only skill + shell orchestrator. Three files:

1. **`plugins/agentic-engineering/skills/feature/SKILL.md`** — body is documentation for the workflow + invocation instructions ("To use, Bash-invoke `bin/feature.sh start \"<brief>\"`"). Frontmatter has `name`, `description` with explicit triggers (`/feature`, "build this feature"), and (initially) `disable-model-invocation: true` until we hit the same need we hit for adversarial-review.

2. **`plugins/agentic-engineering/skills/feature/bin/feature.sh`** — main orchestrator. Subcommands:
   - `start <brief>` — Steps 0-3 (init → map → research → story); exits at Checkpoint 1.
   - `continue <id> [--accept|--redo "<feedback>"]` — resumes from `state.last_completed_step`.
   - `abort <id>` — moves `.feature_runs/<id>/` to `.feature_runs/<id>.aborted/`, releases LOCK.
   - `status <id>` — prints `state.json` in human form.

3. **`plugins/agentic-engineering/skills/feature/bin/feature-helpers.sh`** — sourced library with state I/O (`state_read`, `state_write`, `state_field`), LOCK management, and consumers of `work-issues-lib.sh::allowlist_for` / `route_findings`.

Plus an evals JSON at `plugins/agentic-engineering/skills/feature/evals/evals.json` with 2+ fixture briefs for end-to-end smoke (asserts `state.json` reaches terminal step; asserts no out-of-lane edits during smoke runs).

Full chain spec: `docs/plans/feature-factory.md` §F (10 steps from init to finalize) + §G (failure modes) + §A (architecture).

## Acceptance criteria

- [ ] `feature/SKILL.md` exists with valid frontmatter and clear "Bash-invoke `bin/feature.sh ...`" instructions.
- [ ] `bin/feature.sh` implements all 5 subcommands (start, continue, abort, status, plus help).
- [ ] `start <brief>` creates `.feature_runs/<id>/`, writes `brief.md`, takes a `LOCK` pidfile, runs steps 0-3, exits 0 with resume instructions printed.
- [ ] Concurrency: two simultaneous `feature.sh start` invocations — second one refuses with explicit "another run in progress at .feature_runs/<other-id>/" message.
- [ ] `state.json` schema matches `docs/plans/feature-factory.md` §A schema (id, brief_path, issue_path, research_path, spec_path, rubric_path, lanes, validator_findings, last_completed_step, started_at, updated_at).
- [ ] `continue <id> --accept` resumes from `state.last_completed_step`; `--redo "<feedback>"` reruns the last step with feedback prepended to the prompt.
- [ ] Step 4 (Spec): if `write-a-spec` returns output without parseable `paths` blocks, orchestrator exits at `state.last_completed_step = "spec_invalid"` with a clear error message naming the expected format.
- [ ] Step 5 (Rubric): orchestrator concatenates `$ISSUE` + `$SPEC` into the prompt it hands to `write-a-rubric` (rubric grades against both).
- [ ] Step 6/8 (Lanes): orchestrator builds the lane preamble (allowlist from `allowlist_for`) + appends frontmatter-stripped `work-issues/SKILL.md` body to a temp file at `/tmp/feature-runs/<id>/lane-<name>.prompt.md`; invokes `bin/loop.sh` with `WORK_ISSUES_PROMPT=$lane_prompt`.
- [ ] Step 7/9 (Validator): sets `ADVERSARIAL_REVIEW_REPORT_ONLY=1` and `ADVERSARIAL_REVIEW_TARGETS=<lane allowlist>` when dispatching `/adversarial-review`. Routes Critical findings via `route_findings` and re-invokes the correct lane.
- [ ] `feature/evals/evals.json` has at least 2 fixture briefs. At least one asserts no out-of-lane edit attempt during smoke.
- [ ] Documented: this skill depends on issues 001 (write-a-spec), 002 (adversarial-review env vars), 003 (work-issues lane preamble), 004 (lib helpers) all being merged.

## Blocked by

- `issues/001-write-a-spec-skill.md`
- `issues/002-adversarial-review-env-vars.md`
- `issues/003-work-issues-lane-preamble.md`
- `issues/004-work-issues-lib-allowlist-helpers.md`

## User stories addressed

- User stories 1, 2, 3, 6, 7, 8, 9, 15 (the bulk of the orchestrator-flow stories)
