# `/feature` skill + orchestrator — Rubric

Source-of-truth for technical decisions: `docs/plans/feature-factory.md` §A (architecture), §F (chain), §G (failure modes).

## Deliverable

- Three artifacts plus evals JSON exist at these exact paths:
  - `plugins/agentic-engineering/skills/feature/SKILL.md`
  - `plugins/agentic-engineering/skills/feature/bin/feature.sh`
  - `plugins/agentic-engineering/skills/feature/bin/feature-helpers.sh`
  - `plugins/agentic-engineering/skills/feature/evals/evals.json`

## Skill file (SK)

- **SK-1**: `SKILL.md` has valid YAML frontmatter with at least `name`, `description`, and `disable-model-invocation: true` fields. _Check: `head -20 SKILL.md` shows `---` block; `grep -E '^name:|^description:|^disable-model-invocation:' SKILL.md` returns three matches._
- **SK-2**: `description` field of the frontmatter contains the literal substrings `/feature` and `build this feature` as triggers. _Check: `grep -E '^description:' SKILL.md` includes both phrases._
- **SK-3**: Body contains the literal instruction to Bash-invoke `bin/feature.sh start "<brief>"` (or equivalent that names the script and the `start` subcommand together in one line). _Check: `grep -F 'bin/feature.sh start' SKILL.md` returns at least one match._

## Orchestrator subcommands (CMD)

- **CMD-1**: `bin/feature.sh` is executable (`-rwxr-xr-x` or equivalent). _Check: `test -x bin/feature.sh`._
- **CMD-2**: `bin/feature.sh help` (or `--help` or no-args) prints usage listing all 5 subcommands: `start`, `continue`, `abort`, `status`, `help`. _Check: `bin/feature.sh help` stdout contains each of the five subcommand names._
- **CMD-3**: `bin/feature.sh start <brief>` creates a directory matching `.feature_runs/<id>/`, writes `brief.md` containing the brief text, creates a `LOCK` pidfile containing the current PID, and exits 0 with resume instructions on stdout naming `feature.sh continue <id>`. _Check: after invocation, `test -d .feature_runs/<id> && test -f .feature_runs/<id>/brief.md && test -f .feature_runs/<id>/LOCK && grep "feature.sh continue" <captured_stdout>`._
- **CMD-4**: After `start`, `state.json` exists at `.feature_runs/<id>/state.json` and parses as valid JSON. _Check: `jq . .feature_runs/<id>/state.json` exits 0._
- **CMD-5**: `bin/feature.sh status <id>` prints `state.json` contents in human-readable form (not raw JSON dump) and exits 0. _Check: stdout includes at least the `id`, `last_completed_step`, and one path field on separate lines or labeled rows._
- **CMD-6**: `bin/feature.sh abort <id>` renames `.feature_runs/<id>/` to `.feature_runs/<id>.aborted/` and removes the LOCK. _Check: after abort, `test ! -d .feature_runs/<id> && test -d .feature_runs/<id>.aborted && test ! -f .feature_runs/<id>.aborted/LOCK`._

## state.json schema (ST)

- **ST-1**: `state.json` after a completed `start` contains all of: `id`, `brief_path`, `issue_path`, `research_path`, `spec_path`, `rubric_path`, `lanes`, `validator_findings`, `last_completed_step`, `started_at`, `updated_at`. _Check: `jq -e 'has("id") and has("brief_path") and has("issue_path") and has("research_path") and has("spec_path") and has("rubric_path") and has("lanes") and has("validator_findings") and has("last_completed_step") and has("started_at") and has("updated_at")' state.json` returns true._
- **ST-2**: `started_at` and `updated_at` are ISO-8601 strings parsable by `date -d` (or equivalent). _Check: `date -d "$(jq -r .started_at state.json)"` exits 0._
- **ST-3**: `last_completed_step` after a successful `start` (steps 0–3) equals one of the documented step markers from `docs/plans/feature-factory.md` §F (e.g., `story_drafted` if all four steps completed). _Check: `jq -r .last_completed_step state.json` returns a value listed in §F._

## Concurrency / locking (LK)

- **LK-1**: A second `bin/feature.sh start <brief2>` invoked while another run holds a valid LOCK exits non-zero. _Check: exit code != 0._
- **LK-2**: The refusal message names the in-progress run directory (`.feature_runs/<other-id>/`). _Check: stderr/stdout `grep -F ".feature_runs/"` matches and contains the prior run's id._
- **LK-3**: After `abort <id>`, a new `start` succeeds (LOCK is released). _Check: subsequent `start` exits 0 and creates a new `.feature_runs/<new-id>/`._

## Resume flow (RES)

- **RES-1**: `bin/feature.sh continue <id> --accept` dispatches the step immediately after `state.last_completed_step` (does not re-run completed steps). _Check: a fixture with `last_completed_step = "story_drafted"` advances to `spec_drafted` (or later) without rewriting `issues/<id>.md`._
- **RES-2**: `bin/feature.sh continue <id>` with no flag behaves identically to `--accept`. _Check: same state transition as RES-1 under the same fixture._
- **RES-3**: `bin/feature.sh continue <id> --redo "<feedback>"` re-runs the step at `state.last_completed_step` with the feedback string prepended to the prompt handed to the child dispatch. _Check: child invocation captured via a stubbed `claude` shim contains the literal feedback string in its prompt input; `state.last_completed_step` value is unchanged in `state.json` until the redo completes._

## Spec parsing / failure mode (SP)

- **SP-1**: When `write-a-spec` returns content without any fenced ` ```paths ` blocks, `bin/feature.sh` exits non-zero and sets `state.last_completed_step = "spec_invalid"`. _Check: with stubbed spec missing `paths` blocks, `jq -r .last_completed_step state.json` returns `"spec_invalid"` and the run exit code != 0._
- **SP-2**: The Step-4 error message names the expected format (mentions `paths` and `H3` lane headings, or equivalent). _Check: stderr `grep -E 'paths|H3|lane'` returns matches._

## Rubric step prompt (RB)

- **RB-1**: Step 5 concatenates both `$ISSUE` (issue contents) and `$SPEC` (spec contents) into the prompt handed to `write-a-rubric`. _Check: with a stubbed `claude` shim that records prompts, the recorded prompt contains substrings from both the issue file body and the spec file body._

## Lane preamble construction (LN)

- **LN-1**: For each lane, `bin/feature.sh` writes a prompt file at `/tmp/feature-runs/<id>/lane-<name>.prompt.md`. _Check: after Step 6 dispatch, `test -f /tmp/feature-runs/<id>/lane-backend.prompt.md`._
- **LN-2**: The lane prompt file contains the allowlist returned by `allowlist_for <lane>` and the body of `work-issues/SKILL.md` with frontmatter stripped (no leading `---` block). _Check: the file contains every path returned by `allowlist_for` AND does not start with `---` AND contains a substring unique to the work-issues SKILL.md body (e.g., a sentence from its body)._
- **LN-3**: `bin/feature.sh` invokes `bin/loop.sh` with `WORK_ISSUES_PROMPT` set to the lane prompt path. _Check: with a stubbed `loop.sh` recording its env, captured env contains `WORK_ISSUES_PROMPT=/tmp/feature-runs/<id>/lane-<name>.prompt.md`._

## Validator dispatch + routing (VAL)

- **VAL-1**: When the orchestrator dispatches `/adversarial-review` (Steps 7 and 9), the environment includes `ADVERSARIAL_REVIEW_REPORT_ONLY=1`. _Check: a stubbed `claude` shim recording env shows the variable set to `1` for those calls._
- **VAL-2**: The same dispatch sets `ADVERSARIAL_REVIEW_TARGETS` to the lane allowlist for the lane just built. _Check: recorded env value equals the allowlist string `allowlist_for <lane>` returned._
- **VAL-3**: Critical findings classified into a lane via `route_findings` cause that lane's loop to be re-invoked (Step 6 or 8 reruns). _Check: with a stub validator producing a Critical finding on a known backend path, the orchestrator dispatches `bin/loop.sh` a second time before reaching Checkpoint 3; `state.lanes.backend.status` is updated accordingly._
- **VAL-4**: Findings with paths matching no lane allowlist are appended to `state.validator_findings` and surfaced at Checkpoint 3 (not auto-routed). _Check: after a run with an unmapped-path finding, `state.validator_findings` file/field contains the finding and stdout at Checkpoint 3 contains "validator found" with a count and "unmapped" wording._

## Helpers library (HLP)

- **HLP-1**: `bin/feature-helpers.sh` defines functions `state_read`, `state_write`, `state_field`, lock management (e.g. `acquire_lock` / `release_lock`), and `route_findings` (consumer of `work-issues-lib.sh::allowlist_for`). _Check: `bash -c 'source bin/feature-helpers.sh; declare -F'` lists at least: `state_read`, `state_write`, `state_field`, one lock function, `route_findings`._
- **HLP-2**: `bin/feature-helpers.sh` sources `work-issues/bin/work-issues-lib.sh` (does not redefine `allowlist_for` or `strip_frontmatter`). _Check: `grep -E 'source.*work-issues-lib\.sh|\. .*work-issues-lib\.sh' bin/feature-helpers.sh` returns a match; `grep -E '^[[:space:]]*(allowlist_for|strip_frontmatter)\(\)' bin/feature-helpers.sh` returns no matches._

## Evals (EV)

- **EV-1**: `evals/evals.json` parses as valid JSON. _Check: `jq . evals/evals.json` exits 0._
- **EV-2**: `evals.json` contains at least 2 fixture brief entries. _Check: `jq 'length' evals.json` (or appropriate path) returns >= 2._
- **EV-3**: Each fixture asserts the run reaches a terminal `state.last_completed_step` (one of `done`, `validated`, or other documented terminal step). _Check: each fixture's expectation field references a terminal step._
- **EV-4**: At least one fixture asserts no out-of-lane edits during the smoke run. _Check: `grep -E 'out-of-lane|lane.*violat|allowlist' evals.json` returns at least one match in an assertion field._

## Constraints / dependencies (DEP)

- **DEP-1**: `bin/feature.sh` and `bin/feature-helpers.sh` do not redefine functions named `strip_frontmatter`, `allowlist_for`, or `list_issue_files`. _Check: `grep -E '^[[:space:]]*(strip_frontmatter|allowlist_for|list_issue_files)\(\)' bin/feature.sh bin/feature-helpers.sh` returns no matches._
- **DEP-2**: `SKILL.md` notes the dependency on issues 001, 002, 003, 004 being merged (named explicitly). _Check: `grep -E '00[1234]' SKILL.md` returns matches naming each of the four issue numbers._
- **DEP-3**: `bin/feature.sh` checks the LOCK pidfile against a live process before refusing a new `start` (stale-lock handling). _Check: a `.feature_runs/<old-id>/LOCK` containing a non-existent PID does not cause a fresh `start` to refuse; if the PID exists, refusal occurs._

Next: pass as `{type:'text', content:...}` to `user.define_outcome`, or upload via Files API.
