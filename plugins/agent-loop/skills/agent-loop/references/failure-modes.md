# Failure modes and their guards

The three ways loops die, per the source article — plus a fourth this
plugin adds — each with a named, testable countermeasure. When a loop
misbehaves, identify WHICH disease first; the remedies don't overlap.

## Guard 1 — Confident garbage (weak verify)

**Symptom:** iterations "pass" but the work is wrong; the loop reports
success on goals it hasn't met.

**Detection:** `al-verify` exit codes disagree with the loop's claims;
verifier verdicts pass with empty `evidence`.

**Countermeasures (structural, not vibes):**
- Deterministic layer: `goal.json.verify[]` commands, human-owned, ALL must
  exit 0 (`al-verify`). The loop cannot edit them mid-run via the Edit/Write
  tools (guard hook).
- **The verify gate**: `al-state record-iter` runs `al-verify` ITSELF before
  accepting a pass=true record, and refuses (journaling the attempt as a
  `refused` event) when it fails. `tick` refuses without a verified pass on
  record; `set` refuses the verdict-ledger paths. A model that skips VERIFY
  and claims success cannot make the state say so — the pass is
  unrepresentable, not just forbidden by prose.
- Judgment layer: loop-verifier runs in a FRESH context with only the diff,
  the contract, and the rubric — never the worker's narrative — and its
  prompt rewards finding failures. Absence of evidence = failure.
- Doctor D07 warns when `verify[]` is empty: that's the deterministic half
  switched off — passes then rest on the judgment layer alone and each such
  iteration is journaled with a `verify_warning`.
- TDD gate (goals with `tdd: true`, the `new` default): a pass whose plan
  contained impl work is unrepresentable unless `al-state tdd-red` observed
  the driving test FAIL first and record-iter observes the same command
  pass at record time. Code that no failing test ever demanded cannot enter
  the ledger as a pass — green-from-birth tests are refused as vacuous.

**Remedy when it fires:** strengthen `verify[]` (add a command that would
have caught the garbage) before re-running. Don't argue with the verifier.

## Guard 2 — Context rot (the 200K+ token session)

**Symptom:** late-session iterations degrade — forgotten constraints,
re-reading the same files, fabricated recall of the spec.

**Countermeasures:**
- One iteration per session is the default (`/agent-loop run` = run 1).
  Long goals converge across many short contexts, never one long one; every
  WAKE re-reads the contract from disk.
- `goal.json.context_budget` is ADVISORY in v1 — honest limitation: no
  in-session token telemetry exists (no hook event exposes counts). What
  exists, verified against official docs:
  - headless: `al-loop.sh` backfills `state.json.context_tokens_last_iter`
    from `claude -p --output-format json` usage fields
  - interactive: statusline stdin provides `context_window.used_percentage`
    et al. (see README for a snippet)
  - fleet: OpenTelemetry `claude_code.token.usage` via
    `CLAUDE_CODE_ENABLE_TELEMETRY=1`
- The OPTIMIZE step's guidance cap: `al-state optimize` appends at most 3
  dated, deduped planner_guidance lines per iteration to MEMORY.md `## Open
  threads` — the raw proposal survives in the journal, but memory growth
  stays linear and prunable. Self-improvement must not become context rot.

**Remedy:** more sessions, smaller tasks. If a single iteration can't fit
the budget, the planner's tasks are too big — that's a spec problem.

## Guard 3 — Ralph Wiggum loops (state not capturing progress)

**Symptom:** the loop cheerfully redoes identical work every iteration;
tokens burn, nothing changes.

**Detection (mechanical):** `al-hash` digests done_means + the tree.
`al-state record-iter` compares hashes across iterations: unchanged →
`stall_count++`; two consecutive no-progress iterations → automatic
`pause-stall` (sets `state.json.paused_by_stall` + a human-readable
`stall_report`).

**Why pause lives in state.json, not goal.json:** the guard hook forbids
the loop editing its own contract; state is the loop's ledger, so the loop
may pause itself there. `al-loop.sh` and `/agent-loop status` gate on it —
a stalled loop costs zero tokens per scheduler tick.

**Remedy:** read `stall_report` and `last_verdict.failures`. Usually one of:
a decision is missing (the loop is guessing), verify[] is impossible to
satisfy, or the goal needs decomposing. Fix the spec, set
`paused_by_stall` back to false (`al-state set paused_by_stall false`),
re-run. `max_iterations` is the absolute ceiling behind this guard.

## Guard 4 — Silent assumptions (the fabrication rule made mechanical)

**Symptom:** plausible work that answers questions nobody asked — the spec
was ambiguous, the loop picked silently, and the pick is wrong in a way no
verify command can see.

**Detection (mechanical):** the planner must declare every choice not
forced by Decisions/out-of-scope/repo evidence; the orchestrator validates
them (resolvable ⇒ resolved with evidence) and `al-state plan-propose`
routes anything that survives to `plan.status: "awaiting-human"`. Under the
default `plan_approval: "always"` EVERY plan awaits the human; in
`"assumptions"` mode, iteration 1 and any surviving assumption still do.
`al-loop.sh` ticks cost $0 while awaiting. Undeclared assumptions that
surface later (verifier failures, human review of `plan_proposed` journal
events) are planning failures — the incentive points at declaring.

**Why it's a gate, not advice:** `record-iter` refuses without an approved
plan, `history.planned` is copied from the approved plan verbatim, and
`plan.*` is immune to raw `al-state set`. Unapproved work cannot enter the
ledger. And on critic-enabled goals (the `new` default) the plan the human
is asked to approve has already been pressure-tested by `loop-critic` — a
different model, decorrelated blind spots — with the critique journaled;
`plan-propose` refuses proposals with no `plan_critique` on record this
iteration, so an unchallenged plan never reaches the approval queue.

**Remedy when it fires:** read the assumptions in `/agent-loop status` (or
the `plan_proposed` journal event). For each one, either add the missing
Decision line to GOAL.md (the pause is the system asking for exactly what
D06 exists to capture) and reject so the loop re-plans without guessing, or
approve if the plan is right as proposed.
