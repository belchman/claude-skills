---
name: agent-loop
description: Goal-driven loop harness. Subcommands — init (build the 7-file harness in this repo), new (interview → goal spec), run (plan→act→verify iterations; plans await human approval), approve/reject (act on a pending plan), status (loop health), doctor (harness health), watch (live dashboard), canonize (promote memory to vault). Slash-only.
argument-hint: "<init|new|run|approve|reject|status|doctor|watch|canonize> [args]"
disable-model-invocation: true
---

# agent-loop

Route on the first argument (`$0` — skill arguments are 0-indexed in Claude
Code, so `$0` IS the first argument; do not "fix" it to `$1`). If it is
missing or not one of
`init|new|run|approve|reject|status|doctor|watch|canonize`, print the command table
below and stop.

| Subcommand | Purpose |
| --- | --- |
| `init` | Build the harness plane (7 files, hooks, agents, merged settings) |
| `new <one-liner>` | Interview → GOAL.md + goal.json + state.json |
| `run [n]` | Execute up to n loop iterations (default 1); stops at any plan awaiting approval |
| `approve` | Approve the pending plan (shows it + assumptions first) |
| `reject <reason>` | Reject the pending plan; next run re-plans around the reason |
| `status` | Loop health: iteration, done-means, verdict, stall reading |
| `doctor` | Harness health: checks D01–D16 |
| `watch` | Live fleet console: every registered repo at a glance; streams state + journals |
| `canonize` | Promote MEMORY.md "Candidate canon" entries into vault/ |

Ground rules for every subcommand:

- The plugin's `bin/` is on PATH: call `al-json`, `al-goal`, `al-state`,
  `al-hash`, `al-verify`, `al-doctor`, `al-detect`, `al-detect-skills`,
  `al-merge-settings` directly. Deterministic work goes through them —
  never hand-roll JSON edits or state math.
- Per-repo files live under `.claude/agent-loop/` (called AL_DIR below).
- Skill delegation (detect + fallback): run `al-detect-skills` once per
  session. When it reports `agentic_engineering: true`, delegate the steps
  marked ⤷ below via the Skill tool; otherwise use the inline fallback.
  Every subcommand must complete without any external plugin.

## init

Builds the harness plane. Idempotent; never overwrites user content.

1. `al-doctor` first — show the user the before picture.
2. `al-detect` — show findings; ask the user to confirm/correct test, lint,
   and format commands. Detection prefers the project's own entry points
   over language guesses (`make test` > a test-variant compose file > a
   test-shaped compose service > `pytest`/`npm test`). When it reports
   compose files, nulls, or anything ambiguous, read the project's sources
   of truth before proposing — the compose files themselves, `Makefile`,
   `.github/workflows/*.yml`, and the README's testing section — so the
   command you offer is how this project actually runs its tests (e.g.
   `docker compose -f docker-compose.test.yml run --rm tests`), not a
   host-side guess that fails because the deps live in containers. Never
   proceed with a fabricated command: anything the user doesn't confirm
   stays null / "(fill me in)".
3. Create AL_DIR structure: `MEMORY.md` (from `templates/MEMORY.md.tmpl`),
   `vault/decisions.md` (from `templates/decisions.md.tmpl`), `archive/`,
   `logs/` — each only if absent. Fill `{{PLACEHOLDERS}}` from detection
   (`{{PROJECT_NAME}}` = the repo directory basename, unless package
   metadata — package.json name, pyproject `[project].name`, etc. — names
   it).
4. `CLAUDE.md` — ONLY if the repo has none: write from
   `templates/CLAUDE.md.tmpl` with detection values. If one exists, leave it
   alone (doctor D02 will flag it if oversized).
5. Settings: `al-merge-settings --dry-run`, show the diff, get explicit
   approval, then `al-merge-settings`. (Objects deep-merge, arrays set-union,
   existing values always win — see the script header.)
6. Copy the plugin's three hook scripts (`hooks/*.sh`, not hooks.json) to
   `.claude/hooks/`, `chmod +x` them. Repo copies take precedence — the
   plugin-registered copies self-gate when repo copies exist.
7. Copy the plugin's five agents (`agents/loop-*.md`) to `.claude/agents/`,
   only if absent.
8. `.claude/skills/verify/SKILL.md` from `templates/verify-SKILL.md.tmpl`,
   only if absent.
9. ⤷ If agentic-engineering is present, offer (don't force) `/map` to seed
   `ARCHITECTURE.md` into the repo and note it in vault.
10. Finish with `al-doctor` — the after picture. Init is done only when no
    check FAILs.

## new

Writes the goal spec. HARD RULE: nothing is written until at least one
Decision is captured — without decisions locked in, the loop guesses, and
when it guesses, it fabricates.

1. Refuse if AL_DIR/goal.json exists with `status: "active"` OR `"paused"`
   (paused means a human intentionally halted it — clobbering it loses the
   goal); tell the user to finish, resume, or archive it first. Over
   `"done"`/`"abandoned"`, proceed only AFTER archiving them
   (`mv GOAL.md goal.json state.json audit.jsonl archive/<id>/`).
2. Interview, in order: goal statement → done-means (propose slugged
   checkboxes `- [ ] slug: text`, each independently checkable) →
   **decisions** (keep probing until ≥1 real choice is locked; "no
   preference" is not a decision) → out-of-scope → verify commands (offer
   `al-detect` output and `.claude/skills/verify/SKILL.md` as defaults —
   for dockerized projects that's the compose invocation al-detect found,
   cross-checked against the repo's CI workflows and README testing section;
   include only commands the user confirms) → verifier rubric (judgment
   checks that exit codes can't express).
   ⤷ Delegate the interview to `grill-with-docs` and rubric drafting to
   `write-a-rubric` when available; map their outputs into the spec.
3. Write `AL_DIR/GOAL.md` from `templates/GOAL.md.tmpl` and `AL_DIR/goal.json`
   from `templates/goal.json.tmpl` (defaults: max_iterations 25,
   context_budget 120000, root null, optimize true, **tdd true** — tests
   fail before code by default, **critic true** with critic_model "opus" —
   every plan is pressure-tested by a different model before the human
   sees it; the user can opt out of any of these per goal).
4. `al-goal validate` — must pass. Then `al-state init <id>`.
5. Show the spec and how to start: `/agent-loop run`, or schedule
   `al-loop.sh` (see README).

## run [n]

Runs the loop. Default n=1 — one iteration per session is the context-rot
guard; prefer more sessions over longer ones. Full contract:
`references/loop-contract.md`.

For each iteration:

1. **WAKE** — from disk, never from context: `al-goal validate`, read
   `al-goal get status`, `al-state get paused_by_stall`, `al-state get
   iteration`, `al-goal get max_iterations`. Exit with a clear report if:
   status ≠ active, paused_by_stall = true (quote `stall_report`), or
   iteration ≥ max_iterations, or `tokens_total` ≥ the goal's
   `budget_tokens` (or the org policy's, whichever is smaller). If
   `run_in_progress` is already true and `interrupted_at` is null, another
   session may be mid-run — stop and report instead of racing it; if
   `interrupted_at` is set, the last session died mid-iteration: journal
   the recovery — `al-state audit interrupted '{"interrupted_at":"<value>",
   "dirty_files":N}'` (N from `git status --porcelain | wc -l` when git
   exists) — clear it (`al-state set interrupted_at null`), report it, and
   hand the dirty-file list to the planner as input. Never auto-revert: the
   tree is evidence. Read `al-state get plan.status`: if `awaiting-human`,
   STOP and report the pending plan + assumptions (approval is the human's
   move, not yours); if `approved`, skip PLAN below and execute the
   approved `plan.tasks` exactly as written. Then `al-state lease-acquire`
   — if it refuses, another session holds the run lease: stop and report,
   never race a live lease — and `al-state set run_in_progress true`.
   Every exit path from the iteration after this point ends with
   `al-state lease-release`.
2. **PLAN** — skipped entirely when WAKE found an approved plan (execute
   that; never re-plan approved work). Otherwise:
   a. Task tool → `loop-planner` agent. Give it: GOAL.md text, goal.json,
      unchecked done-means slugs, `last_verdict.failures` verbatim,
      `plan.rejected_reason` if set, and the `## Open threads` section of
      AL_DIR/MEMORY.md (standing planner guidance from prior OPTIMIZE
      passes). It returns
      `{"tasks":[{task, files_hint, parallel, kind}], "assumptions":["…"]}`.
      Reject and re-request anything that isn't valid JSON or strays
      outside Decisions/out-of-scope. When goal.json `tdd` is true, tell
      the planner so: every task needs `kind` (test|impl|docs|chore), test
      tasks precede the impl they drive, and each test task names the exact
      runnable command that must fail — `al-state plan-propose` refuses
      plans that violate the shape.
   b. VALIDATE each declared assumption yourself against the spec and the
      repo: if GOAL.md/Decisions/repo evidence actually answers it, it is
      NOT an assumption — resolve it and note the evidence. Only
      assumptions that survive validation stay in the proposal. Also hunt
      for UNdeclared assumptions in the tasks (names, paths, formats the
      spec doesn't pin) and add them.
   c. **PRESSURE-TEST** (skip only when goal.json `critic` is false): Task
      tool → `loop-critic` agent, dispatched with the model named in
      goal.json `critic_model` (default "opus") — deliberately a DIFFERENT
      model from the loop's own, so the critic's blind spots don't
      correlate with the planner's. Give it: GOAL.md, goal.json, the
      validated plan + surviving assumptions, unchecked done-means slugs,
      `last_verdict.failures`, and MEMORY.md Open threads. It returns
      `{"verdict":"approve|revise","blockers":[],"risks":[],"questions":[]}`.
      Journal it verbatim: `al-state audit plan_critique '<the JSON>'` —
      plan-propose REFUSES critic-enabled proposals with no critique on
      record this iteration. If verdict is `revise`: hand the blockers to
      the planner verbatim for a revised plan, re-validate (b), and
      re-critique — at most 2 revise rounds; if blockers still stand,
      proceed to the gate and present the unresolved blockers alongside
      the plan (the critic advises; the human decides).
   d. `al-state plan-propose '<{"tasks":…,"assumptions":…}>'` — the
      deterministic gate decides: auto-approved only when the goal has
      `plan_approval: "assumptions"` AND zero assumptions survived AND at
      least one iteration is already recorded AND no rejection is pending.
      Everything else — including EVERY plan under the default
      `plan_approval: "always"`, every first iteration, and every empty
      plan — becomes `awaiting-human`.
   e. If awaiting-human: STOP (regardless of remaining n). Report to the
      human: the tasks, each surviving assumption, and for each one the
      Decision line that would resolve it (assumptions are just Decisions
      the spec is missing) — plus the critic's verdict, any unresolved
      blockers, and what changed between critique rounds. Tell them:
      `/agent-loop approve`, or `/agent-loop reject "<reason>"`, or edit
      GOAL.md Decisions first and then reject so the next plan is
      assumption-free. Do not proceed.
3. **ACT** — for each task: Task tool → `loop-worker` (one task per worker,
   include only that task + its files_hint + relevant decisions). Tasks with
   `parallel: true` dispatch concurrently — worktree isolation when git is
   present AND more than one parallel task mutates files; otherwise
   serialize. Execute ONLY the approved plan's tasks — inventing or
   reshaping tasks mid-ACT is re-planning without approval. Workers never
   see each other; synthesize their reports yourself afterwards, journaling
   each one:
   `al-state audit worker_report '{"task":"...","files_changed":[...],"assessment":"..."}'`.
   **TDD ordering** (goal.json `tdd: true`): dispatch `kind: "test"` tasks
   FIRST. After each test worker reports, run
   `al-state tdd-red '<the command the task names>'` — the state layer runs
   it itself and journals the observed red; it REFUSES if the command
   passes (a test that never failed proves nothing — stop, report, and
   re-plan: the test is vacuous or the behavior already exists). Only after
   red is journaled do `kind: "impl"` workers dispatch. record-iter will
   re-run every journaled red command at record time and refuse the pass
   unless each now exits 0 — red→green, both ends observed. ⤷ Test-shaped
   tasks delegate to the `tdd` skill when agentic-engineering is present.
4. **VERIFY** — both layers must pass:
   a. `al-verify` — deterministic commands. Any FAIL line ⇒ iteration fails.
   b. Task tool → `loop-verifier` with ONLY: the diff (`git diff` or changed
      file list), GOAL.md, and the rubric. Never include worker reasoning.
      It returns `{pass, failures, evidence}`.
   ⤷ If goal.json has `deep_verify: true` and agentic-engineering is
   present, also run `adversarial-review` in report-only mode; treat its
   confirmed findings as verifier failures.
5. **RECORD** — record-iter first; ticks and everything else are gated on it.
   - Always: `al-state record-iter '<verdict-json>'` — pass the verifier's
     FULL verdict including evidence (the journal keeps it raw; working
     state stores the sanitized summary; the planned task list is taken
     from the approved plan, never from the caller). This updates
     hash/stall/history, clears run_in_progress, auto-pauses after 2
     no-progress iterations, and journals the iteration. **The verify gate
     lives here**: for pass=true, record-iter re-runs `al-verify` itself and
     REFUSES the record if it fails — an unverified pass is unrepresentable,
     and the refusal is journaled. Honest fails are always recordable.
   - Pass: then `al-state tick <slug>` for each done-means item the
     verifier's evidence supports (ticks are refused unless the last
     recorded iteration was a verified pass), and `al-state log '<iter N:
     pass, what moved>'`; `al-state canon '<stable discovery>'` for durable
     facts.
   - Fail: do NOT revert; the failure recorded verbatim is the next
     iteration's planning input. Log it: `al-state log '<iter N: fail — why>'`.
   - Always use these commands, never the Edit tool — `.claude/` writes are
     permission-gated in headless runs, al-state is allowlisted. Direct
     `al-state set` on iteration/done_means/last_verdict/history/
     progress_hash/plan (or any subpath) is refused and journaled.
6. **OPTIMIZE** — the last act of every iteration: this pass tunes the next
   one. SKIP entirely (report `optimize: skipped — <reason>`) when goal.json
   `optimize` is `false`, when RECORD journaled no iteration this pass, or
   when the goal just converged (step 7 takes over). A stall-pause during
   RECORD does NOT skip it — the proposals are exactly what the stalled-loop
   human needs, and the pause gates the next WAKE, not this iteration's tail.
   a. `al-state audit-slice` (bare — right after RECORD, the last
      iteration IS the just-recorded one): prints this iteration's journal
      slice verbatim — every audit.jsonl line after the previous
      `iteration` event up to and including the just-recorded one.
   b. Task tool → `loop-optimizer` agent with ONLY: that slice, GOAL.md,
      goal.json, unchecked done-means slugs, and MEMORY.md's `## Open
      threads` section. Never the workers' in-context output. It returns
      `{"spec_gaps":[…],"verify_gaps":[…],"planner_guidance":[…],"canon":[…]}`.
      If the output isn't valid JSON of that shape: one re-request, then
      `al-state audit optimize_skipped '{"reason":"invalid optimizer
      output"}'` and move on — OPTIMIZE must never block the loop.
   c. `al-state optimize '<the JSON>'` — the gated write: journals the raw
      proposal as an `optimize` event, appends ≤3 dated, deduped
      planner_guidance lines to `## Open threads`, routes canon through the
      `al-state canon` path. spec_gaps and verify_gaps are journal-and-report
      only — the loop may NEVER edit GOAL.md prose or goal.json.
   d. In your end-of-run report, relay the proposals verbatim as paste-ready
      text: spec_gaps as GOAL.md Decision lines, verify_gaps as goal.json
      `verify[]` entries. Same habit as assumptions: a proposal is a
      Decision/check the spec is missing; the human applies it by editing
      the spec.
7. If all done-means are true and verify passes: tell the user the goal is
   complete and suggest the close-out — `al-json set AL_DIR/goal.json status
   '"done"'`, `al-state audit goal_closed '{"reason":"complete"}'`, then move
   GOAL.md, goal.json, state.json AND audit.jsonl into
   `archive/<goal-id>/` (the audit record travels with its goal). The loop
   never marks its own contract done.

## approve

1. `al-state get plan.status` — if not `awaiting-human`, say there is
   nothing to approve and stop.
2. Show the human the pending `plan.tasks` and `plan.assumptions` (from
   `al-state get plan`), plus your one-line read of the risk.
3. On their confirmation (interactive) or when invoked non-interactively as
   an explicit `/agent-loop approve`: `al-state plan-approve`. Then remind:
   `/agent-loop run` (or the next scheduler tick) executes it.

## reject <reason>

1. If no plan is awaiting, say so and stop.
2. `al-state plan-reject '<reason>'`. Suggest turning the rejection (and any
   assumptions) into GOAL.md Decision lines so the next plan doesn't guess.

## status

Loop health (harness health is `doctor`'s job).

1. If no goal: say so, point at `/agent-loop new`. Otherwise report, from
   `al-state get` / `al-goal get`: goal id + status; iteration /
   max_iterations; done-means checklist (which slugs true/false);
   last_verdict (quote failures verbatim); stall_count and paused_by_stall
   (if paused, quote stall_report and say plainly: a human needs to adjust
   the spec or the approach — re-running won't help); plan.status (if
   awaiting-human, list the tasks + assumptions and the approve/reject
   commands); context_tokens_last_iter. Pending optimize proposals: read the
   last `"event":"optimize"` line from AL_DIR/audit.jsonl; if its proposal
   carries non-empty `spec_gaps`/`verify_gaps`, list them as paste-ready
   GOAL.md Decision lines / goal.json `verify[]` entries for the human.
2. One-line convergence read: progressing / failing-but-moving / stalled.

## doctor

1. Run `al-doctor`, show its output verbatim (checks D01–D16).
2. Interpret: for each FAIL/WARN quote the check ID and say what to do,
   linking `references/doctor-checks.md#<id>`. FAILs must be fixed before
   `run`; WARNs are judgment calls.

## watch

Live fleet console: `al-watch` (in the plugin's `bin/`, on PATH) in fleet
mode serves every registered repo's state + audit journal to a local
browser. Binds 127.0.0.1 only. One console per machine is enough — probe
before spawning:

1. **Probe** for a running console:
   `curl -s -m 2 http://127.0.0.1:4177/api/fleet` and capture the HTTP
   status code (e.g. `-o /dev/null -w '%{http_code}'`).
2. **HTTP 200** — a fleet console is already running. Report
   `http://127.0.0.1:4177` verbatim to the user; do NOT spawn anything.
3. **Connection refused / no response** — nothing owns the port. Launch
   bare `al-watch` (FLEET mode — no repo arg) as a **background process**
   (`run_in_background: true` on the Bash tool — a foreground server never
   returns and would block the turn forever), read-only: pass
   `--allow-actions` ONLY when the user explicitly asked for approve/reject
   buttons; otherwise leave it off and the POST endpoints answer 403.
   `al-watch` prints the resolved URL on stdout
   (`… at http://127.0.0.1:<port>`) — relay it verbatim, then return; do
   not wait on the server. Remind the user how to stop it: kill the
   background task (via the task list / TaskStop, or `kill <pid>`).
4. **Any other HTTP status** (404 = an old single-repo `al-watch` owns the
   port) — say a single-repo server owns 4177; suggest launching the fleet
   console on another port (`al-watch --port N`). Never kill or relaunch
   the existing server.

Any repo that runs the loop auto-registers into the fleet
(`~/.claude/agent-loop/fleet.list`); drill into a repo from the grid.

## canonize

1. Read AL_DIR/MEMORY.md `## Candidate canon`. Empty → say so, stop.
2. For each entry, propose: promote (append to `vault/decisions.md` in its
   What/Why/When format) / keep as memory / delete. Apply what the user
   approves, removing promoted entries from MEMORY.md.
3. Vault discipline: only durable facts (architecture, locked decisions,
   invariants). What changes across sessions stays in MEMORY.md.
