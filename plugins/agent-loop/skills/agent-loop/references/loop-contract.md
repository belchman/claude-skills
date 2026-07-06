# The iteration contract

Every `/agent-loop run` iteration has exactly this shape. The runner (the
skill) orchestrates; the five agents do bounded jobs; the bin layer does
everything deterministic. Deviating from this shape is how loops rot.

```
WAKE → PLAN → ACT → VERIFY → RECORD → OPTIMIZE
```

## WAKE

Read the contract and state FROM DISK — never trust context memory of them
(the spec may have been edited between sessions; that's a feature).

- `al-goal validate` — an invalid spec stops everything.
- Exit (with a clear report, not an error) when: `goal.json.status != active`,
  `state.json.paused_by_stall == true` (quote `stall_report`; a human must
  intervene — re-running a stalled loop burns money and changes nothing),
  `iteration >= max_iterations`, or `tokens_total >= budget_tokens`
  (goal's or org policy's, whichever is smaller).
- If `interrupted_at` is set, the previous session died mid-iteration:
  journal the recovery (`al-state audit interrupted` with the dirty-file
  count), clear the stamp, and hand the dirty tree to the planner as input.
  Never auto-revert — the tree is evidence.
- `al-state lease-acquire` — the atomic run lease (mkdir primitive; stale
  leases past TTL are taken over and journaled). A refusal means another
  session is driving the loop: stop, never race it. Every exit path after
  a successful acquire ends with `al-state lease-release`.
- `al-state set run_in_progress true` — the Stop hook uses this to detect a
  session that died mid-iteration (and releases the dead session's lease).

## PLAN — loop-planner (fresh context) + the approval gate (Guard 4)

May read anything; may write nothing. Receives the spec, the unchecked
done-means slugs, `last_verdict.failures` verbatim, any rejected-plan
reason, and MEMORY.md's `## Open threads` section (standing planner
guidance from prior OPTIMIZE passes). Returns `{"tasks":[{task, files_hint,
parallel, kind}], "assumptions": ["<choice — why the spec doesn't answer
it>"]}`, 0–4 tasks. On a tdd goal (`goal.json.tdd: true`) every task
declares `kind` (test|impl|docs|chore) and the test task that drives an
impl task precedes it — `plan-propose` refuses violations (journaled).

The orchestrator rejects a plan that: isn't valid JSON, contains work
outside Decisions/out-of-scope, or retries an approach the failures say
already failed. It then VALIDATES each declared assumption against the
spec/repo (resolvable ⇒ not an assumption; resolve it and keep the
evidence) and hunts for undeclared ones.

**Then the plan is pressure-tested before any human sees it** (skipped only
when `goal.json.critic` is false): `loop-critic` — dispatched with the
model named in `goal.json.critic_model`, deliberately a DIFFERENT model so
its blind spots don't correlate with the planner's — interrogates the plan
against the spec and the repo (does each task move a done-means? do the
files_hints exist? would verify[] catch a failure?) and returns
`{verdict, blockers, risks, questions}`. The critique is journaled
(`plan_critique`); `revise` verdicts loop back to the planner, at most 2
rounds; unresolved blockers travel to the human with the plan. **The gate
is mechanical**: `plan-propose` refuses a critic-enabled proposal with no
`plan_critique` journaled this iteration — an unpressure-tested plan cannot
reach the approval queue.

**The gate is deterministic** (`al-state plan-propose`): a plan
auto-approves ONLY when `goal.json.plan_approval == "assumptions"` AND zero
assumptions survived AND at least one iteration is already recorded AND no
rejection is pending AND the task list is non-empty. Everything else —
every plan under the default `"always"` mode, every first iteration, every
surviving assumption, every empty plan — sets `plan.status:
"awaiting-human"`: the loop stops, `al-loop.sh` ticks cost $0, and the
human approves (`al-state plan-approve` / `/agent-loop approve`), rejects
with a reason, or — the intended remedy — turns each assumption into a
GOAL.md Decision line so the next plan doesn't guess. An assumption is just
a Decision the spec is missing.

Work done outside an approved plan is unrecordable: `record-iter` refuses
without `plan.status == "approved"`, and `history.planned` is taken from
the approved plan verbatim, never from the caller.

## ACT — loop-worker(s)

One task per worker; workers receive only their task + files_hint + the
relevant decisions — minimal context is the point. Workers never touch the
contract or state, never commit. `parallel: true` tasks run concurrently
(worktree isolation only when git exists AND >1 parallel task mutates
files — without git, serialize). Workers never see each other's output; the
orchestrator synthesizes.

On a tdd goal, ACT is ordered: test workers first; after each, the runner
calls `al-state tdd-red '<the command the task names>'` — **the state layer
runs the command itself** and journals the observed failure. A command that
exits 0 is refused (journaled): a test that never failed proves nothing.
Impl workers dispatch only after red is on the record.

## VERIFY — two layers, both must pass

a. **Deterministic**: `al-verify` runs every `goal.json.verify[].cmd`. Any
   nonzero exit fails the iteration. No exceptions — this layer is the
   floor under "confident garbage".
b. **Judgment**: loop-verifier in a fresh context window, receiving ONLY the
   diff, GOAL.md, and the rubric — never the worker's narrative. "The
   reviewer that lives inside the maker's context always agrees with
   itself." Returns strict `{pass, failures, evidence}`.

Optional layer c (when `goal.json.deep_verify` and agentic-engineering is
installed): adversarial-review in report-only mode; confirmed findings count
as failures.

## RECORD

- First, always: `al-state record-iter '<verdict>' '<planned>'` — updates
  iteration/hash/history, clears `run_in_progress`, increments `stall_count`
  when the progress hash didn't move, and auto-pauses at 2 consecutive
  no-progress iterations. **The verify gate is here, not in prose**: for a
  pass=true verdict, record-iter runs `al-verify` itself and refuses the
  record when it fails — the caller's claim is never trusted, the observed
  PASS lines are journaled with the iteration, and refusals are journaled as
  `refused` events. A goal with empty `verify[]` can still record a pass,
  but the iteration event carries a `verify_warning` (and doctor D07 warns).
- **The TDD gate lives here too**: on a tdd goal, a pass whose approved plan
  contained impl work is accepted ONLY when at least one `tdd_red` event was
  journaled this iteration AND every journaled red command — re-run by
  record-iter itself — now exits 0. Red→green on the exact same command,
  both ends observed by the state layer; code-without-a-failing-test is
  unrepresentable as a pass. Docs/chore/test-only plans and honest fails
  skip the gate.
- Pass (after a successful record): `al-state tick <slug>` for each
  done-means item with verifier evidence — tick refuses unless the last
  recorded iteration was a verified pass; `al-state log '<line>'` for the
  session log; durable discoveries via `al-state canon '<line>'`. (Never the
  Edit tool: `.claude/` is permission-gated in headless runs; al-state is
  allowlisted.)
- Fail: record, don't revert. The verbatim failure is the next PLAN's most
  valuable input. Automatic reverts destroy the evidence.
- `al-state set` refuses the verdict-ledger paths (iteration, done_means,
  last_verdict, history, progress_hash) and journals the attempt — those
  fields only move through the gated commands above. Operational fields
  (paused_by_stall, run_in_progress, stall_report, interrupted_at,
  context_tokens_last_iter) stay settable for the human-remedy and backfill
  paths.

## OPTIMIZE — loop-optimizer (fresh context, report-only)

The last act of every iteration: this pass tunes the next one. Receives
ONLY the just-recorded iteration's journal slice (its `iteration`,
`plan_proposed`, and `worker_report` events), GOAL.md, goal.json, the
unchecked done-means slugs, and MEMORY.md's `## Open threads` — never the
workers' in-context reasoning. Returns four channels:
`{spec_gaps, verify_gaps, planner_guidance, canon}` (empty arrays are
honest answers).

Two hard lines:

- **spec_gaps and verify_gaps are proposals only.** They live in the
  journal and the end-of-run report as paste-ready GOAL.md Decision lines
  and goal.json `verify[]` entries; the human applies them by editing the
  spec. "An assumption is a Decision the spec is missing" extends to: a
  verifier catch is a `verify[]` entry the spec is missing. The loop never
  edits its own contract.
- **All MEMORY.md writes go through `al-state optimize`** — it appends at
  most 3 dated, deduped planner_guidance lines per iteration to `## Open
  threads` (truncation is journaled; the raw proposal is never lost) and
  routes canon entries through the `al-state canon` path.

Skipped when: `goal.json.optimize == false`, RECORD journaled no iteration
this pass, or the goal just converged. A stall-pause during RECORD does NOT
skip it — the pause gates the next WAKE, not this iteration's tail, and the
optimizer's spec proposals are precisely what the stalled-loop human needs.
An optimizer that returns garbage is skipped (`optimize_skipped` journaled)
— OPTIMIZE never blocks the loop.

## Who may write what

| File | Writer |
|---|---|
| GOAL.md prose, goal.json | humans only (guard-enforced during runs) |
| policy.json | the ORG only (commit it); goals may be stricter, never weaker — gates enforce the strictest value |
| GOAL.md checkboxes | `al-state tick` only |
| state.json | `al-state` only (Stop hook backstop; al-loop.sh backfills context_tokens_last_iter) |
| MEMORY.md | `al-state log` / `al-state canon` (RECORD step); `al-state optimize` (OPTIMIZE step — Open threads + Candidate canon); `/agent-loop canonize` (removes promoted entries) |
| audit.jsonl | `al-state` only (auto on every mutation + `al-state audit` for runner events); append-only, never rewritten |
| vault/ | `/agent-loop canonize` only |
| repo code | loop-worker only |

## The audit trail

Two layers, deliberately different:

- **state.json** — working memory. Summarized and sanitized (planner objects
  → task strings, verdicts → pass/failures) so the schema stays strict and
  the loop stays honest with itself.
- **audit.jsonl** — the record. Append-only JSONL; one object per event with
  `event`, `at`, `goal_id` plus the RAW payload: `goal_init`, `plan` (full
  planner JSON), `worker_report` (files changed, self-assessment),
  `iteration` (full verdict incl. evidence + raw plan + the al-verify
  output record-iter itself observed), `tick`, `memory_log`/`memory_canon`,
  `plan_proposed` (raw tasks + assumptions + the gate's decision),
  `plan_approved` (by human or auto), `plan_rejected` (with reason),
  `plan_critique` (the cross-model critic's raw verdict — blockers, risks,
  questions), `tdd_red` (the failing command + rc + observed output — the
  red half of the TDD gate), `optimize` (the raw four-channel proposal +
  append/dedupe/truncate counts), `stall_pause`, `refused` (blocked
  self-certification attempts — unverified passes, ungated ticks,
  unapproved-plan records, protected-path sets, invalid optimize payloads,
  never-red tests, red-that-never-went-green passes), `lease_takeover`
  (stale run lease claimed), `interrupted` (session died mid-iteration;
  dirty-file count), `goal_closed`. Every line carries `actor` (who caused
  it) and `prev` (sha256 of the previous line — the tamper-evidence chain),
  and passes a redaction filter so secret-shaped strings never persist.
  Doctor D14
  checks its integrity; it archives with its goal. When someone asks "what
  did the loop actually do and why," this file is the answer.
