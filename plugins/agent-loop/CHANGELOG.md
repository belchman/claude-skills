# Changelog — agent-loop

All notable changes to this plugin. Semver; the marketplace entry and
`.claude-plugin/plugin.json` must carry the same version (CI-enforced by
`tests/test_marketplace_sync.sh`).

## 0.4.1 — 2026-07-07

Hardening wave — audit-driven: enforcement holes closed, concurrency made
mechanical instead of model-trusted.

- **al-json write bypass closed**: the settings fragment now allowlists only
  read verbs (`get`/`len`/`check`/`validate`); guard-destructive denies raw
  `al-json set/append/del/merge` on GOAL.md/goal.json/state.json mid-run
  (backstop for installs that merged the old `al-json:*` allowlist). The
  "an unverified pass is unrepresentable" guarantee holds again.
- **rm guard hardened**: recursive+force rm is now blocked on ANY absolute
  path, `~`/`$HOME`, parent dirs (`..`) and quoted targets — `/*`,
  `/etc/x`, and `"$HOME/x"` were verified bypasses. Repo-relative subdirs
  (`build/`, `./build`) stay allowed.
- **Ownership-aware Stop hook**: loop-checkpoint clears the run flag and
  releases the lease only for runs it owns (session match) or dead owners —
  a bystander session in the same repo can no longer yank a live headless
  run's lease mid-iteration.
- **Harness-level run lease**: al-loop.sh itself acquires the lease for the
  whole tick (`AL_LEASE_PID`, inherited so the skill's own acquire is a
  re-entrant refresh), releases it on exit, and clears a phantom
  `run_in_progress` after the run. Overlapping cron/launchd ticks are now
  mutually exclusive at the harness level, not by model behavior.
- **Dead-owner lease takeover**: a durable owner pid that no longer exists
  on this host is taken over immediately (journaled) instead of locking the
  repo for the remaining TTL (default up to 1h).
- **al-fleet**: repo paths with spaces survive (newline-delimited
  enumeration end to end); `AL_LOOP_MAX_ERRORS` is honored by al-fleet and
  al-watch's breaker-open flag (both hard-coded 3 before, disagreeing with
  the scheduler when tuned).
- **jq engine parity**: `al-json validate` on the jq engine now implements
  the same draft-07 subset as python3/node (it checked `required` only —
  type/enum mismatches passed silently on jq-only machines, weakening every
  schema gate).
- goal.json.tmpl's `_comment` no longer embeds literal `{{...}}` tokens
  (mechanical substitution corrupted the JSON).
- Docs: README worked-example goal.json validates again (`context_budget`);
  `plan_approval` documented in goal-spec; the `optimize` policy floor is
  correctly described as advisory (doctor D15) rather than gate-enforced;
  `GOAL_STATE_WRITE`, `AL_LOOP_PLUGIN_DIR`, `AL_WATCH_DEBUG`, `AL_ACTOR`
  documented; paused-goal-blocks-`new` contradiction resolved; design doc
  synced to the 0.4.0 reality (9 subcommands, D01–D16, fleet/watch shipped);
  manifests mention `watch`.
- Evals/CI: the nightly workflow uploads `runs/` transcripts as artifacts
  (red nightlies were undebuggable); trial tags only suffix multi-trial runs.
- ~60 new model-free tests: rm/al-json guard cases, Stop-hook ownership,
  tick lease + post-run backstop, durable-lease semantics, al-fleet
  spaces/breaker, `/api/reject` success paths in both watch modes,
  `GET /api/state?repo=`, template↔schema validation, and
  `validate`/`merge` in the 3-engine parity loop.
- **al-detect pylint fix**: `.pylintrc` alone never triggered pylint
  detection (`ls a b` exits nonzero when any argument is missing) — caught
  by the new branch tests; JS/TS (npm/pnpm/yarn, prettier), rust, and
  django branches now pinned too, plus al-detect-skills' real filesystem
  probe (env overrides bypassed it entirely).
- **Atomic multi-field writes**: `plan-approve`, `plan-reject`, and
  `pause-stall` stage on a work copy, schema-validate, then one `mv` —
  matching `record-iter`; a crash mid-command can no longer leave
  half-approved state.
- **`al-fleet --prune`**: opt-in atomic registry GC (keep existing dirs,
  drop dead paths) — the append-only registry finally has a cleanup path.
- **install.sh tested**: copy set, executable bits, version idempotence,
  stale-version re-copy, stray-copy refusal.
- `make lint` shellchecks all 12 shell scripts in `bin/` + hooks (was 2);
  everything passes at `-S error` and `-S warning`.
- Nightly evals: `workflow_dispatch` gains a `trials` input for multi-trial
  runs on demand (scheduled runs stay single-trial).

## 0.4.0 — 2026-07-06

The console wave — built through the loop itself (three goals, every gate).

- **al-watch**: python3-stdlib local dashboard (`al-watch <repo>`), 127.0.0.1
  only. Phosphor flight-deck app shell: Overview / Telemetry (filter chips,
  search, pause, click-to-inspect raw journal lines with chain links) /
  Contract / Memory / Archive views, loop-phase pipeline strip with the
  human-gate diamond, toasts + alert bar + tab-title/favicon status,
  approve/reject modal (403 without `--allow-actions`; actor `*@al-watch`).
- **Fleet mode**: bare `al-watch` = one standing machine-wide console.
  Repos auto-register on init/lease/tick (append-only grep-deduped
  `~/.claude/agent-loop/fleet.list`, `AL_FLEET_REGISTRY` override,
  `AL_NO_FLEET_REGISTER=1` opt-out); needs-human-sorted repo cards with
  gate/stall/breaker lamps and lifetime archive stats; slim `/api/fleet` +
  `event: fleet` SSE; drill-down to the full console via `?repo=`.
- **Past loops stay visible**: `/api/archive` (both modes) + the ARCHIVE
  view — archived goals with their contracts, final state, and full journal
  timelines. Convergence is a first-class UI state (CONVERGED ✓ awaiting
  close-out; the loop never closes its own contract).
- **Action hardening**: POST requires `Content-Type: application/json` and a
  port-stripped localhost Host header (CSRF/DNS-rebinding); fleet actions
  realpath-allowlist the target repo against the registry.
- **SKILL `watch` subcommand**: three-way probe (200 report / refused launch
  / 404 single-repo conflict). README: standing-server recipes (launchd
  KeepAlive, systemd Restart=always). `al-fleet` falls back to the default
  registry when bare.
- 100+ new model-free tests (watch 19, fleet 43, wired 15) + registry
  sandboxing across every suite and the eval harness.

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
