# Doctor checks

`al-doctor` output format: `CHECK D## PASS|WARN|FAIL <message>`, exit 0 iff
no FAIL. Each check below: what it means, how to fix it. Harness plane only —
loop health is `/agent-loop status`.

## D01 — CLAUDE.md exists {#d01}
The standing context file read on every launch. FAIL: create one —
`/agent-loop init` writes a stub from stack detection (only when absent).

## D02 — CLAUDE.md length {#d02}
WARN above 200 lines (official guidance: longer files consume context and
reduce adherence). Prune: move stable facts to the vault, use `@file`
imports, delete stale sections.

## D03 — settings.json valid JSON {#d03}
FAIL: `.claude/settings.json` doesn't parse; nothing in it applies. Fix the
syntax (`al-json check .claude/settings.json` shows the error).

## D04 — hooks registered {#d04}
FAIL: one or more of guard-destructive / format-on-write / loop-checkpoint
is not registered in `.claude/settings.json`. Run `/agent-loop init` (its
settings merge is idempotent) or register manually.

## D05 — agents present {#d05}
FAIL: `.claude/agents/loop-{planner,worker,verifier,optimizer,critic}.md`
missing. The run loop cannot execute its PLAN (+pressure-test) / ACT /
VERIFY / OPTIMIZE steps without them. `/agent-loop init` copies them;
customize the copies freely. (Repos initialized before the OPTIMIZE and
critic steps will flag the newer agents until they re-run
`/agent-loop init`.)

## D06 — Decisions non-empty {#d06}
FAIL: the active GOAL.md has an empty `# Decisions` section. This is the
fabrication guard: without decisions locked in, the loop guesses. Add at
least one real, locked-in choice — or archive the goal.

## D07 — verify non-empty {#d07}
WARN: `goal.json.verify[]` is empty, so the deterministic verify layer is
off and only the judgment layer stands between you and confident garbage.
Add at least one command that exits 0 iff the work is right.

## D08 — speculative MCP servers {#d08}
WARN: `.mcp.json` declares servers. Keep only what this work needs — every
server adds context and attack surface. Delete what you don't use.

## D09 — state validates {#d09}
FAIL: `state.json` doesn't match `state.schema.json`; the loop can't trust
its own memory. Usually hand-editing drift. Inspect with `al-state
validate`; worst case re-init via `al-state init <goal-id>` (loses history).

## D10 — settings scope conflicts {#d10}
WARN: the same permission rule is allowed in one settings scope and denied
in another. Deny always wins (documented precedence), so the allow is dead —
delete one side to make intent visible.

## D11 — vault exists {#d11}
FAIL: `.claude/agent-loop/vault/` missing. The vault is project canon —
what does NOT change across sessions. `/agent-loop init` creates it.

## D12 — goal.json schema-valid {#d12}
FAIL: the machine half of the spec doesn't validate. `al-goal validate`
prints field-level errors; see `references/goal-spec.md` for the format.

## D13 — JSON engine present {#d13}
FAIL: none of python3 / node / jq is installed. Everything in the bin layer
does JSON through `al-json`, which needs one of them. Install any one
(macOS: `xcode-select --install` provides python3; or `brew install jq`).

## D14 — audit journal integrity {#d14}
`AL_DIR/audit.jsonl` is the append-only auditable record of everything the
loop did (raw plans, worker reports, verdicts with evidence, ticks, pauses,
memory writes). Every line carries `prev` — the sha256 of the line before
it (`genesis` for the first) — so rewriting history breaks every subsequent
link. WARN: state exists but no journal, or lines predate the hash chain.
FAIL: a line doesn't parse, or the chain is broken — the audit record is
corrupt or was rewritten; investigate before trusting the history. The loop
never rewrites this file; it travels to `archive/` with its goal.

## D15 — org policy respected {#d15}
`AL_DIR/policy.json` (optional, org-managed, commit it) sets floors the
goal author cannot lower: `tdd`/`critic`/`optimize` true, `plan_approval`
"always", `budget_tokens` ceiling. The gates enforce the effective
(strictest) value regardless — this check is visibility. FAIL: policy.json
doesn't parse or violate `policy.schema.json`; the gates cannot trust it.
WARN: the active goal tries to weaken policy (it's enforced anyway; align
goal.json to avoid confusion).

## D16 — journal growth bound {#d16}
WARN: `audit.jsonl` exceeds `AL_DOCTOR_JOURNAL_MB` (default 50). The
journal is append-only by design — the remedy is closing out the goal and
archiving it (`archive/<goal-id>/`), which starts a fresh journal, not
truncation.
