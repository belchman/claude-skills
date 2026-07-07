# agent-loop

A goal-driven loop harness for Claude Code. One command builds the full
harness from "Loop and Harness engineering: 7 files, 5 steps" in any repo;
then goal-spec-driven plan→act→verify loops run on top of it — interactively
or from a scheduler.

> "Most builders fight the loop. The loop is fine. The folder underneath
> isn't set up."

`/agent-loop` is the folder-underneath, packaged.

## Install

Marketplace (recommended):

```
/plugin marketplace add belchman/claude-skills      # or the local repo path
/plugin install agent-loop@belchman-claude-skills
```

Local development: `claude --plugin-dir path/to/plugins/agent-loop`
(SKILL.md edits hot-reload with `/reload-plugins`; agent/hook changes need a
restart). Fallback installer: `sh plugins/agent-loop/bin/install.sh`.

Requirements: a POSIX shell plus ONE of `python3`, `node`, or `jq` (all JSON
handling goes through the `al-json` shim; `/agent-loop doctor` check D13
verifies). That one-of claim covers the core loop tools only — `al-watch`
(the fleet console) is a python3 script, so it additionally requires
`python3`. Git is optional — without it, fan-out serializes and progress
hashing uses a file digest.

## Quickstart (5 minutes)

```
cd your-repo
/agent-loop init          # builds the harness plane; shows a settings diff first
/agent-loop new "add rate limiting to the public API"
                          # interview → GOAL.md + goal.json; refuses to finish
                          # until at least one Decision is locked in
/agent-loop run           # one plan→act→verify iteration
/agent-loop status        # is the loop converging?
```

The story is always: **install once per machine, `init` once per repo,
`new` once per goal.** Uninstall: `/plugin uninstall agent-loop`; everything
init created in a repo is a plain file you can delete.

## The two planes

```
harness plane (built once)          loop plane (runs forever)
──────────────────────────         ─────────────────────────
CLAUDE.md      standing context     GOAL.md + goal.json  the contract
settings.json  permissions+hooks    state.json           memory on disk
hooks/         determinism          plan → act → verify  the iteration
agents/        fresh contexts       MEMORY.md            what changes
skills/verify  how to check         vault/               what doesn't
.mcp.json      audited only
```

`/agent-loop doctor` checks the harness plane (D01–D16, exit-code friendly
for CI). `/agent-loop status` checks the loop plane. Different diseases,
different commands.

## How an iteration works

WAKE (re-read the contract from disk) → PLAN (loop-planner, read-only, JSON
task list) → ACT (loop-workers, one task each, minimal context, parallel
when independent) → VERIFY (two layers: `verify[]` commands must ALL exit 0,
then a fresh-context loop-verifier judges the diff against the rubric —
"rewarded for finding failures") → RECORD (tick done-means, append memory,
update state; failures recorded verbatim, never auto-reverted) → OPTIMIZE
(loop-optimizer, fresh context, report-only: each pass tunes the next).

**Plans are pressure-tested by a different model, then await human
approval.** The planner must declare every assumption (a choice the spec
doesn't force); the orchestrator validates them against the spec; then
`loop-critic` — dispatched with the model named in `goal.json.critic_model`
(default "opus"), deliberately NOT the loop's own model so blind spots
don't correlate — interrogates the plan against the repo and returns
blockers/risks/questions. `revise` verdicts loop back to the planner (max
2 rounds); the critique is journaled, and `al-state plan-propose` refuses
critic-enabled proposals with no critique on record. Only then does
`plan-propose` pause the loop as `awaiting-human` — by default
(`plan_approval: "always"`) for EVERY plan, and even in the relaxed
`"assumptions"` mode for iteration 1 and any surviving assumption. What
reaches you has already survived a cross-model adversary, with its
unresolved blockers attached. Scheduled operation alternates:
one tick proposes and pauses ($0 per tick until you act), you run
`/agent-loop approve` (or `reject "<reason>"`, ideally after turning the
assumptions into GOAL.md Decisions), the next tick executes the approved
plan. An iteration without an approved plan is unrecordable.

**Passes are verified at the state layer, not trusted.** `al-state
record-iter` re-runs the `verify[]` commands itself and refuses to record a
pass they don't support; ticks require a verified pass on record; refused
attempts are journaled. A loop cannot self-certify through the prescribed
interface — the audit trail carries the verify output the state layer
actually observed.

**Red before green, enforced.** Goals default to `tdd: true`: plans declare
each task's `kind`, and tests come before the impl they drive (the plan
gate refuses violations). Before any impl worker runs, `al-state tdd-red`
executes the driving test **itself** and journals the observed failure — a
test that passes on arrival is refused as vacuous. At record time,
record-iter re-runs every journaled red command and refuses the pass unless
each now exits 0. Red→green on the exact same command, both ends observed
by the state layer: code that no failing test ever demanded cannot enter
the ledger as a pass. Opt out per goal with `"tdd": false`.

**Each pass optimizes the next.** Every iteration ends with a fresh-context
`loop-optimizer` reading the just-recorded journal evidence and proposing:
GOAL.md Decision lines (for assumptions that keep surviving), goal.json
`verify[]` entries (for what the judgment verifier caught that exit codes
missed), planner guidance (fed into MEMORY.md `## Open threads`, which the
next PLAN receives), and canon nominations. Spec and verify proposals are
**report-only** — the human applies them by editing the spec; the loop
never edits its own contract. Guidance writes go through `al-state
optimize` (≤3 dated, deduped lines per iteration; the raw proposal is
journaled). Opt out per goal with `"optimize": false` in goal.json.

Details: `skills/agent-loop/references/loop-contract.md`. Failure guards
(confident garbage / context rot / Ralph Wiggum loops):
`references/failure-modes.md`.

**Everything is journaled.** `.claude/agent-loop/audit.jsonl` is an
append-only JSONL record of every event — goal creation, each accepted plan
(raw), every worker report, every verdict (with evidence), ticks, memory
writes, stall pauses, close-out. `state.json` is the loop's sanitized
working memory; the journal is the auditable truth, checked by doctor D14
and archived with its goal. Query it with the shim, e.g.
`grep '"event":"iteration"' .claude/agent-loop/audit.jsonl`.

## Worked example: a feature from start to finish

A complete goal lifecycle on a small Express API (`~/projects/todo-api`).
Nothing here is specific to that project — the same six steps work on any
repo in any language.

### 1. Build the harness (once per repo)

```
cd ~/projects/todo-api
/agent-loop init
```

`init` detects the stack — and the project's own test entry point wins over
language guesses: a `Makefile` `test:` target beats a docker compose test
stack (`docker-compose.test.yml` / a `tests`-shaped compose service) beats
`npm test`/`pytest`, because a dockerized project's deps and services live in
the containers, not on the host. Anything ambiguous, the interview
cross-checks against the repo's CI workflows and README before asking you to
confirm. It then shows you the `.claude/settings.json` merge diff for
approval and writes the harness:
a `CLAUDE.md` stub (only if absent), the three hooks, the five agents, a
`verify` skill stub, and `.claude/agent-loop/`. It ends with `doctor`;
you're set when no check FAILs.

### 2. Define the goal (once per goal)

```
/agent-loop new "add cursor-based pagination to GET /todos"
```

The interview refuses to finish until you lock in at least one Decision —
the guard against the loop guessing. It writes two files. `GOAL.md`, the
human half:

```markdown
# Goal
Add cursor-based pagination to GET /todos.

# Done means
- [ ] cursor-param: GET /todos?cursor=&limit= returns a page + nextCursor
- [ ] stable-order: results are ordered by (created_at, id) so cursors are stable
- [ ] docs: docs/api.md documents the new query params
- [ ] tests-pass: the suite still passes

# Decisions
- Cursor is an opaque base64 of "created_at,id" — NOT a raw offset
- Default limit 20, max 100; over-max clamps (does not error)
- No change to the existing unpaginated response when no cursor/limit given

# Out of scope
- Pagination for any endpoint other than GET /todos
- Changing the todo schema
```

and `goal.json`, the machine half — this is where "done" becomes
mechanical:

```json
{
  "id": "2026-07-04-todos-pagination",
  "status": "active",
  "max_iterations": 10,
  "context_budget": 120000,
  "plan_approval": "always",
  "verify": [
    {"cmd": "npm test", "expect": "exit0"},
    {"cmd": "npm run lint", "expect": "exit0"},
    {"cmd": "sh -c 'grep -q cursor docs/api.md'", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "nextCursor round-trips: decoding it and passing it back yields the next page with no gaps or repeats",
    "the unpaginated response is byte-identical to before when no query params are given"
  ]
}
```

The `verify[]` commands are the deterministic floor; the rubric is what the
fresh-context verifier checks that exit codes can't.

### 3. First run — the loop proposes, then stops for you

```
/agent-loop run
```

Under the default `plan_approval: "always"`, the loop plans but does **not**
touch code — it stops at the approval gate and reports:

```
Plan awaiting human approval (iteration 1). 2 tasks:
  1. Add cursor encode/decode + paginated query to the GET /todos handler
  2. Document the cursor & limit params in docs/api.md
Assumptions needing your decision:
  - "cursor encodes created_at,id as base64" is pinned by Decisions — resolved, not an assumption
  - The DB layer is Knex (found knexfile.js) — repo evidence, resolved
  - Tie-breaking when created_at collides: ordering by id is implied but the
    spec doesn't state id is unique — SURVIVING ASSUMPTION
Approve: /agent-loop approve   Reject: /agent-loop reject "<reason>"
```

The planner declared everything it wasn't sure about; the orchestrator
resolved what the spec/repo answered and surfaced the one real gap. You have
two good moves:

```
# Option A — the assumption is fine as stated:
/agent-loop approve

# Option B — better: turn it into a Decision so the loop never guesses again.
# Edit GOAL.md, add:  "- id is the unique primary key; it is the final tie-breaker"
/agent-loop reject "id uniqueness now pinned in Decisions — replan"
```

Option B is the intended habit: **an assumption is a Decision the spec is
missing.** After it, the next plan comes back assumption-free.

### 4. Second run — execute, verify, record

```
/agent-loop run
```

Now WAKE finds an approved plan and executes it: workers make the changes
(in parallel, isolated git worktrees, since both tasks touch files), then
VERIFY runs both layers. Say the first attempt has a bug — an off-by-one
that repeats the boundary row across pages. `npm test` passes but the
verifier catches it from the rubric:

```
Iteration 1 recorded: FAIL
  verify (commands): all passed
  verifier: FAIL — "nextCursor repeats the last row of the previous page
    (boundary is inclusive on both sides)"
Recorded verbatim; not reverted. Next plan will address it.
```

Nothing is ticked — a fail can't tick. The next `run` plans *around* the
recorded failure (it's the planner's input), the fix lands, and this time:

```
Iteration 2 recorded: PASS
  verify (commands): npm test ✓  npm run lint ✓  grep cursor docs/api.md ✓
  verifier: PASS — cursor round-trips cleanly; unpaginated response unchanged
  ticked: cursor-param, stable-order, docs, tests-pass
```

`record-iter` re-ran `npm test`/`npm run lint` **itself** before accepting
the pass — the loop can't report success the scanners don't support.

### 5. Check convergence any time

```
/agent-loop status
```

```
Goal 2026-07-04-todos-pagination — iteration 2/10
Done means: cursor-param ✓  stable-order ✓  docs ✓  tests-pass ✓  (4/4)
Last verdict: pass. Stall: 0. Converged — all done-means met.
```

### 6. Close out

The loop never marks its own contract done — you do:

```
al-json set .claude/agent-loop/goal.json status '"done"'
mkdir -p .claude/agent-loop/archive/2026-07-04-todos-pagination
mv .claude/agent-loop/{GOAL.md,goal.json,state.json,audit.jsonl} \
   .claude/agent-loop/archive/2026-07-04-todos-pagination/
```

The audit journal travels with the goal. Reviewing what actually happened
is one grep:

```
grep '"event"' .claude/agent-loop/archive/2026-07-04-todos-pagination/audit.jsonl
# goal_init → plan_proposed → plan_rejected → plan_proposed → plan_approved
# → worker_report ×2 → iteration(FAIL) → plan_proposed → plan_approved
# → worker_report → iteration(PASS, with the verify output it observed) → tick ×4
```

Every decision you made, every plan, every worker's report, every verdict
with its evidence — the record of *what the loop did and why*.

### Running it unattended

Steps 3–4 are exactly what `bin/al-loop.sh` does per scheduler tick. With
`plan_approval: "always"`, an unattended loop alternates: one tick proposes
and pauses (costing $0 until you act), you approve out-of-band, the next
tick executes. Set `plan_approval: "assumptions"` in `goal.json` to let
assumption-free iterations (after the first) flow without stopping — the
loop then only pauses when it genuinely needs a decision. See
[Scheduling](#scheduling-the-loop-that-runs-while-you-sleep) below.

## Scheduling (the loop that runs while you sleep)

`bin/al-loop.sh <repo>` runs one headless iteration — and costs zero tokens
when the goal isn't active or the loop stall-paused itself.

cron (every 30 min):

```
*/30 * * * * /path/to/plugins/agent-loop/bin/al-loop.sh /path/to/repo
```

launchd (macOS) — `~/Library/LaunchAgents/com.agent-loop.tick.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.agent-loop.tick</string>
  <key>ProgramArguments</key><array>
    <string>/path/to/plugins/agent-loop/bin/al-loop.sh</string>
    <string>/path/to/repo</string>
  </array>
  <key>StartInterval</key><integer>1800</integer>
</dict></plist>
```

systemd timer — `agent-loop.service` + `agent-loop.timer`:

```ini
# agent-loop.service
[Service]
Type=oneshot
ExecStart=/path/to/plugins/agent-loop/bin/al-loop.sh /path/to/repo

# agent-loop.timer
[Timer]
OnUnitActiveSec=30min
[Install]
WantedBy=timers.target
```

GitHub Actions (CI-hosted loop):

```yaml
on:
  schedule: [{cron: "*/30 * * * *"}]
jobs:
  tick:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm install -g @anthropic-ai/claude-code
      - run: git clone https://github.com/belchman/claude-skills /tmp/cs && sh /tmp/cs/plugins/agent-loop/bin/install.sh
      - run: ~/.claude/plugins/agent-loop/bin/al-loop.sh "$PWD"
        env: {ANTHROPIC_API_KEY: "${{ secrets.ANTHROPIC_API_KEY }}"}
```

Env knobs: `AL_LOOP_PERMISSION_MODE` (default `acceptEdits` — allowlist your
build/test commands in `.claude/settings.json`, or set a broader mode for
sandboxed environments), `AL_LOOP_MAX_TURNS` (default 80),
`AL_LOOP_PLUGIN_DIR` (the `--plugin-dir` passed to the headless run — a
path, or `"none"` to rely on a globally installed plugin).

## Fleet console (standing server)

One machine-wide `al-watch` in **fleet mode**: run it bare (no repo arg) and
it serves a grid of every repo that has ever run the loop on this machine —
repos auto-register into the fleet on each loop tick, and archived goals
stay browsable after close-out. Drill into any repo from the grid.

Quickstart:

```
al-watch          # fleet mode, http://127.0.0.1:4177
```

The SKILL's `/agent-loop watch` probes `GET /api/fleet` on 4177 before
spawning — if a fleet console is already up it just hands you the URL, so
running one standing server and letting every session reuse it is the
intended shape. Service recipes, alongside the loop-tick ones above
(`al-watch` is a standing server, so it's supervised with keep-alive, not
fired on an interval):

launchd (macOS) — `~/Library/LaunchAgents/com.agent-loop.watch.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.agent-loop.watch</string>
  <key>ProgramArguments</key><array>
    <string>/path/to/plugins/agent-loop/bin/al-watch</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
```

systemd — `agent-loop-watch.service`:

```ini
[Service]
Type=simple
ExecStart=/path/to/plugins/agent-loop/bin/al-watch
Restart=always
[Install]
WantedBy=default.target
```

cron cannot supervise a standing server (it fires jobs, it doesn't restart
them) — at most use `@reboot` with a small wrapper script, and prefer
launchd/systemd above.

The fleet registry lives at `~/.claude/agent-loop/fleet.list`. Set
`AL_NO_FLEET_REGISTER=1` to keep a repo out of it; set `AL_WATCH_DEBUG=1`
for request logging (the server is quiet by default). As with the single-repo
dashboard, the server binds 127.0.0.1 only — it is never reachable from the
network.

## Watching context burn (statusline)

Claude Code's statusline stdin includes documented `context_window.*`
fields. A minimal loop-aware statusline:

```sh
#!/bin/sh
# ~/.claude/statusline.sh — show context % + loop state
input=$(cat)
pct=$(printf '%s' "$input" | grep -o '"used_percentage":[0-9.]*' | head -1 | cut -d: -f2)
s=".claude/agent-loop/state.json"
loop=""
[ -f "$s" ] && loop=" | loop iter $(grep -o '"iteration": *[0-9]*' "$s" | grep -o '[0-9]*')"
printf 'ctx %s%%%s' "${pct:-?}" "$loop"
```

Headless runs backfill `state.json.context_tokens_last_iter` automatically;
fleets can enable OpenTelemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, metric
`claude_code.token.usage`).

## Enterprise controls

- **Org policy** — commit `.claude/agent-loop/policy.json` (see
  `templates/policy.schema.json`) to set floors the goal author cannot
  lower: `{"tdd": true, "critic": true, "plan_approval": "always",
  "budget_tokens": 2000000}`. Those four floors are mechanically enforced
  inside the gates (the effective value is the strictest of policy and
  goal); an `optimize` floor is advisory only — no gate consults it, and
  its backstop is doctor D15's WARN on drift.
- **Tamper-evident audit** — every journal line carries `actor` (who —
  `AL_ACTOR` when set, else the OS user) and
  `prev` (sha256 of the previous line); doctor D14 verifies the chain, so
  rewritten history is detectable. A redaction filter masks secret-shaped
  strings (tokens, keys, passwords) before anything is journaled.
- **Run lease** — `al-state lease-acquire` (atomic mkdir + TTL) makes
  concurrent sessions on one repo impossible instead of merely discouraged;
  stale leases are taken over and journaled; the Stop hook releases a dying
  session's lease.
- **Budgets & breakers** — `goal.json.budget_tokens` (or the policy's,
  whichever is smaller) hard-stops the loop when `state.tokens_total`
  reaches it; `AL_LOOP_MAX_ERRORS` (default 3) consecutive errored ticks
  trip a circuit breaker that silences the scheduler until re-armed —
  honored by `al-loop.sh`, `al-fleet`, and `al-watch` alike.
- **Notifications** — set `AL_LOOP_WEBHOOK` (curl POST) or
  `AL_LOOP_NOTIFY_CMD` (JSON on stdin) and `al-loop.sh` pages you exactly
  once per blocking event: plan awaiting approval, stall pause, iteration
  or budget ceiling, breaker trip. A healthy iteration re-arms the dedupe.
- **Fleet view** — `al-fleet repo1 repo2 …` (or `AL_FLEET_REPOS=a:b`)
  prints one status line per repo and exits nonzero when any loop needs a
  human — wire it to cron/CI as a fleet health probe.
- **Threat model** — `docs/agent-loop-design.md` §15 (prompt injection,
  self-certification, history rewriting, secrets, gate shutoff,
  concurrency, runaway spend).

## Skill reuse (detect + fallback)

When the `agentic-engineering` plugin is installed, agent-loop delegates:
the `new` interview → `grill-with-docs`, rubric authoring →
`write-a-rubric`, test-shaped worker tasks → `tdd`, optional deep verify
(`goal.json.deep_verify`) → `adversarial-review`, vault seeding → `map`.
Without it, built-in minimal procedures run — every subcommand works
standalone. `doctor` reports the active mode as INFO.

## Files this plugin ships vs. files init creates

Shipped (this directory): the skill + references, 5 agents, 3 self-gating
hooks, templates, and the `al-*` bin tools (on PATH when the plugin is
enabled). Created per-repo by `init` (all additive; existing files are
merged around, never overwritten): `CLAUDE.md` (only if absent),
`.claude/settings.json` (deep-merge, diff shown first), repo-owned copies of
hooks and agents (repo copies win — the shipped hooks self-gate), a verify
skill stub, and `.claude/agent-loop/{MEMORY.md,vault/,archive/,logs/}`.

## Known limitations (v1)

- One active goal per repo (queue finished goals in `archive/`).
- The context budget is advisory: no in-session token telemetry exists, so
  the runner defaults to one iteration per session (see
  `references/failure-modes.md`, Guard 2).
- Headless exit codes are not officially documented; al-loop.sh treats any
  parseable result JSON as the source of truth and logs everything else.
- The jq engine of `al-json` validates required keys only (python3/node do
  full subset validation).
