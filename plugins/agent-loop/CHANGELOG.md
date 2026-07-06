# Changelog — agent-loop

All notable changes to this plugin. Semver; the marketplace entry and
`.claude-plugin/plugin.json` must carry the same version (CI-enforced by
`tests/test_marketplace_sync.sh`).

## 0.3.0 — 2026-07-05

Enterprise wave — the gates become governable, auditable, and operable.

- **Org policy**: `.claude/agent-loop/policy.json` (+ `policy.schema.json`)
  sets floors the goal author cannot lower (tdd / critic / optimize /
  plan_approval / budget_tokens); enforced inside the gates via effective
  (strictest) values; doctor D15.
- **Run lease**: `al-state lease-acquire/lease-release` — atomic mkdir +
  TTL; stale takeover journaled; Stop hook releases a dying session's lease.
- **Tamper-evident journal**: every audit line carries `prev` (sha256 hash
  chain, verified by D14) and `actor`; a redaction filter masks
  secret-shaped strings before journaling.
- **Cost ledger**: `state.tokens_total` accumulates spend;
  `goal.json.budget_tokens` (or the policy's, if smaller) hard-stops the
  loop; enforced in `al-loop.sh` and at WAKE.
- **Circuit breaker**: `AL_LOOP_MAX_ERRORS` consecutive errored ticks
  silence the scheduler until re-armed.
- **Notifications**: `AL_LOOP_WEBHOOK` / `AL_LOOP_NOTIFY_CMD` fire once per
  blocking event (plan awaiting, stall, ceilings, breaker).
- **Fleet**: `al-fleet` one-line status per repo; exits nonzero when any
  loop needs a human. Doctor D16 bounds journal growth.
- **Interrupted-session recovery**: WAKE journals an `interrupted` event
  with the dirty-file count and feeds the tree state to the next plan.
- **Threat model**: design doc §15 (prompt injection, self-certification,
  history rewriting, secrets, gate shutoff, concurrency, runaway spend);
  all five agents carry the data-not-instructions rule.

## 0.2.0 — 2026-07-05

- **OPTIMIZE step**: iteration contract becomes WAKE → PLAN → ACT → VERIFY
  → RECORD → OPTIMIZE; fresh-context `loop-optimizer` proposes spec
  Decisions and verify[] entries (report-only) and feeds planner guidance
  into MEMORY.md Open threads (`al-state optimize`, capped + deduped).
- **TDD gates**: task `kind` with tests-before-impl plan shape;
  `al-state tdd-red` observes the failing test; record-iter requires
  red→green on the same command.
- **Cross-model plan critique**: `loop-critic` (per-goal `critic_model`)
  pressure-tests every plan before the human sees it; `plan-propose`
  refuses un-critiqued proposals.
- **`al-state audit-slice`**: deterministic journal-slice extractor (built
  by the loop itself, dogfooding the plan-approval + verify gates).
- **Compose-aware detection**: `al-detect` prefers the project's own test
  entry point (make test > compose test stack > language guess).

## 0.1.0 — 2026-07-04

- Initial release: 7-file harness `init`, goal-spec `new`, plan→act→verify
  `run` with human plan approval, `status`/`doctor`/`canonize`,
  deterministic bin layer (al-json/goal/state/verify/hash/doctor/detect),
  three self-gating hooks, scheduler runner `al-loop.sh`, eval harness.
