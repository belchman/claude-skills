# The goal spec: GOAL.md + goal.json

The goal spec is the loop's external contract — what "done" means, decided by
a human, stored on disk, re-read from disk at the top of every iteration
(never trusted from context). It has two halves:

- **`GOAL.md`** — human markdown. Prose goal, done-means checklist,
  decisions, out-of-scope. No frontmatter, ever.
- **`goal.json`** — machine fields. Validated against
  `templates/goal.schema.json` by `al-goal`. JSON (not YAML) because JSON is
  the only format all three `al-json` engines (python3/node/jq) parse without
  third-party dependencies.

Both live in `.claude/agent-loop/`. Both are **human-owned**: the loop may
tick checkboxes in GOAL.md (via `al-state tick` only) but may never otherwise
edit either file while a run is active — `guard-destructive.sh` enforces this.

## GOAL.md sections

| Section | Rules |
|---|---|
| `# Goal` | One-paragraph statement of the outcome. |
| `# Done means` | Slugged checkboxes: `- [ ] slug: description`. Slugs are `[a-z0-9-]+`, unique, stable — they key `state.json.done_means` and are ticked mechanically by `al-state tick <slug>` after a passing verify. |
| `# Decisions` | **Mandatory, non-empty** (doctor D06 fails otherwise). Each line locks in a choice the loop must not re-litigate. "Without those decisions locked in, the loop guesses. When the loop guesses, it fabricates." |
| `# Out of scope` | Explicit exclusions; the planner treats these as hard boundaries. |

## goal.json fields

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Goal identifier, e.g. `2026-07-04-search-api`. Matches `state.json.goal_id`. |
| `status` | `active\|paused\|done\|abandoned` | Only `active` goals run. Humans set this; the stall detector pauses via `state.json.paused_by_stall` instead (it may not edit this file). |
| `max_iterations` | int ≥ 1 | Absolute iteration ceiling (default 25). |
| `context_budget` | int | Advisory per-iteration token budget (default 120000). See failure-modes.md Guard 2. |
| `root` | string\|null | Optional subdirectory scoping the loop (monorepos). |
| `verify` | `[{cmd, expect: "exit0"}]` | Deterministic layer of the verify contract. ALL must exit 0. Empty ⇒ doctor D07 warns. |
| `verifier_rubric` | `[string]` | Judgment layer: criteria the fresh-context verifier subagent checks that exit codes can't. |
| `deep_verify` | bool (optional) | When true and the `agentic-engineering` plugin is installed, an `adversarial-review` report-only pass is added after the verifier. |
| `optimize` | bool (optional) | Absent/true: each iteration ends with an OPTIMIZE pass — the `loop-optimizer` agent proposes spec Decisions and `verify[]` entries (report-only; humans apply) and feeds planner guidance into MEMORY.md. `false`: skip the pass entirely. |
| `tdd` | bool (optional; the `new` template defaults it to `true`) | TDD enforced at the state layer: plans declare task `kind` with tests before the impl they drive (`plan-propose` refuses violations); `al-state tdd-red` must observe each driving test FAIL before impl work; `record-iter` refuses a pass with impl tasks unless a red was journaled this iteration and every red command now exits 0. Absent/`false`: gates off. |
| `critic` | bool (optional; the `new` template defaults it to `true`) | Every plan is pressure-tested before the human sees it: the runner dispatches `loop-critic` and journals its verdict as a `plan_critique` event; `plan-propose` refuses proposals with no critique on record this iteration. `revise` verdicts loop back to the planner (max 2 rounds); unresolved blockers travel to the human. Absent/`false`: gate off. |
| `critic_model` | string (optional; template `"opus"`) | Model for the critic dispatch — deliberately different from the loop's own model, so the critic's errors don't correlate with the planner's. |
| `budget_tokens` | int ≥ 1 (optional) | Hard cumulative token ceiling for the goal: `al-loop.sh` refuses to tick (and WAKE refuses to run) once `state.tokens_total` reaches it. Org policy's `budget_tokens` applies when smaller. |

## Org policy (`policy.json`)

`AL_DIR/policy.json` (optional; validated against `policy.schema.json`) is
**org-managed and commit-worthy** — it sets floors the goal author cannot
lower. `tdd`/`critic`/`optimize: true` force those gates on regardless of
goal.json; `plan_approval: "always"` defeats the auto-approve path;
`budget_tokens` caps spend when smaller than the goal's. Enforcement lives
in the gates themselves (`al-state` computes the effective, strictest
value), not in prose; doctor D15 reports misalignment.

## Worked example 1 — feature

`GOAL.md`:

```markdown
# Goal
Add full-text search to the /api/items endpoint.

# Done means
- [ ] search-endpoint: GET /api/items?q= returns ranked matches
- [ ] p95-latency: p95 under 200ms on the seed dataset
- [ ] docs: docs/api.md documents the q parameter

# Decisions
- Use Postgres tsvector, NOT Elasticsearch (no new infra)
- Ranking: ts_rank, no custom weighting in v1

# Out of scope
- Fuzzy/typo matching
- Search analytics
```

`goal.json`:

```json
{
  "id": "2026-07-04-search-api",
  "status": "active",
  "max_iterations": 25,
  "context_budget": 120000,
  "root": null,
  "verify": [
    {"cmd": "npm test", "expect": "exit0"},
    {"cmd": "npm run lint", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "GET /api/items?q= returns results ordered by rank",
    "No breaking change to the existing /api/items response shape"
  ]
}
```

## Worked example 2 — bugfix

```markdown
# Goal
Fix the double-charge on retried checkout webhooks.

# Done means
- [ ] idempotent: replaying the same webhook event id charges at most once
- [ ] regression-test: a test reproduces the double-charge and now passes

# Decisions
- Dedup by provider event id in the existing webhook_events table (no new store)
- Do NOT change the provider retry configuration

# Out of scope
- Refund handling for charges that already doubled
```

```json
{
  "id": "2026-07-04-webhook-double-charge",
  "status": "active",
  "max_iterations": 10,
  "context_budget": 120000,
  "root": null,
  "verify": [
    {"cmd": "pytest tests/webhooks -q", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "The new test fails when the dedup check is reverted",
    "No charge path exists that bypasses the dedup check"
  ]
}
```

## Worked example 3 — migration (monorepo, scoped)

```markdown
# Goal
Migrate services/billing from requests to httpx (async-ready).

# Done means
- [ ] no-requests: no `import requests` remains under services/billing
- [ ] behavior: all billing tests pass unchanged
- [ ] timeouts: every httpx call sets an explicit timeout

# Decisions
- httpx sync client in this pass; async conversion is a later goal
- Timeout default 10s, overridable per call site

# Out of scope
- Other services in the monorepo
- Retry policy changes
```

```json
{
  "id": "2026-07-04-billing-httpx",
  "status": "active",
  "max_iterations": 15,
  "context_budget": 120000,
  "root": "services/billing",
  "verify": [
    {"cmd": "sh -c '! grep -rn \"import requests\" services/billing'", "expect": "exit0"},
    {"cmd": "pytest services/billing -q", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "Every httpx call passes an explicit timeout",
    "No call sites outside services/billing were modified"
  ]
}
```

## Authoring rules for `/agent-loop new`

1. Refuse to run if an `active` goal already exists (archive or pause first).
2. Interview order: goal → done-means (with slugs) → **decisions (must
   capture at least one before anything is written)** → out-of-scope →
   verify commands (offer `al-detect` findings and the repo's verify skill as
   defaults; never fabricate a command that wasn't confirmed).
3. Delegate the interview to `grill-with-docs` and rubric authoring to
   `write-a-rubric` when the `agentic-engineering` plugin is installed.
4. Write GOAL.md + goal.json from the templates, run `al-goal validate`,
   then `al-state init <id>`.
