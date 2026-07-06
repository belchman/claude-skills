#!/bin/sh
# test_agent_loop_bin.sh — model-free unit tests for plugins/agent-loop/bin/.
# Everything runs in a mktemp sandbox; no model calls, no network, no git
# writes outside the sandbox. Run: sh tests/test_agent_loop_bin.sh
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$REPO_ROOT/plugins/agent-loop/bin"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() { # $1=description, $2=exit code, $3=expected code
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (exit $2, wanted $3)"; fi
}

SANDBOX=$(mktemp -d)
export AL_FLEET_REGISTRY="$SANDBOX/fleet.list"   # keep make test away from the real registry
trap 'rm -rf "$SANDBOX"' EXIT
export CLAUDE_PROJECT_DIR="$SANDBOX"
unset AL_STATE_FILE AL_GOAL_FILE 2>/dev/null || true

echo "# al-json (same assertions per engine — AL_JSON_ENGINE parity)"
for ENG in python3 node jq; do
  command -v "$ENG" >/dev/null 2>&1 || { echo "  (skip $ENG — not installed)"; continue; }
  export AL_JSON_ENGINE="$ENG"
  echo '{"a":{"b":1},"arr":[1,2],"codes":{"0":"zero"}}' > "$SANDBOX/t.json"
  [ "$("$BIN/al-json" get "$SANDBOX/t.json" a.b)" = "1" ] && ok "[$ENG] get scalar" || bad "[$ENG] get scalar"
  "$BIN/al-json" get "$SANDBOX/t.json" a.zzz >/dev/null 2>&1; check "[$ENG] get absent path exits 1" $? 1
  "$BIN/al-json" len "$SANDBOX/t.json" a.zzz >/dev/null 2>&1; check "[$ENG] len absent path exits 1" $? 1
  # numeric-string OBJECT keys must not be coerced to array indices
  [ "$("$BIN/al-json" get "$SANDBOX/t.json" codes.0)" = "zero" ] && ok "[$ENG] numeric object key stays a key" || bad "[$ENG] numeric object key"
  "$BIN/al-json" set "$SANDBOX/t.json" a.c '"x"' >/dev/null
  [ "$("$BIN/al-json" get "$SANDBOX/t.json" a.c)" = "x" ] && ok "[$ENG] set then get" || bad "[$ENG] set then get"
  "$BIN/al-json" append "$SANDBOX/t.json" arr '3' >/dev/null
  [ "$("$BIN/al-json" len "$SANDBOX/t.json" arr)" = "3" ] && ok "[$ENG] append + len" || bad "[$ENG] append + len"
  [ "$("$BIN/al-json" get "$SANDBOX/t.json" arr.2)" = "3" ] && ok "[$ENG] array index path" || bad "[$ENG] array index path"
  "$BIN/al-json" append "$SANDBOX/t.json" a.b '1' >/dev/null 2>&1; check "[$ENG] append to non-array exits 1" $? 1
  "$BIN/al-json" del "$SANDBOX/t.json" a.c >/dev/null
  "$BIN/al-json" get "$SANDBOX/t.json" a.c >/dev/null 2>&1; check "[$ENG] del removes key" $? 1
  # array-index path segments must index, never clobber the array (regression pin)
  echo '{"verify":[{"cmd":"one"},{"cmd":"two"}]}' > "$SANDBOX/arr.json"
  "$BIN/al-json" set "$SANDBOX/arr.json" verify.1.cmd '"TWO"' >/dev/null
  [ "$("$BIN/al-json" get "$SANDBOX/arr.json" verify.1.cmd)" = "TWO" ] && ok "[$ENG] set into array element" || bad "[$ENG] set into array element"
  [ "$("$BIN/al-json" len "$SANDBOX/arr.json" verify)" = "2" ] && ok "[$ENG] array survives indexed set" || bad "[$ENG] array survives indexed set"
  "$BIN/al-json" set "$SANDBOX/arr.json" verify.9.cmd '"x"' >/dev/null 2>&1; check "[$ENG] out-of-range array set fails (no clobber)" $? 1
  echo 'not json' > "$SANDBOX/bad.json"
  "$BIN/al-json" check "$SANDBOX/bad.json" 2>/dev/null; check "[$ENG] check rejects invalid JSON" $? 1
done
unset AL_JSON_ENGINE   # rest of the suite runs on the default engine
AL_JSON_ENGINE=notreal "$BIN/al-json" engine >/dev/null 2>&1; check "invalid AL_JSON_ENGINE exits 4" $? 4

echo "# result-JSON shape pin (R1): headless claude -p --output-format json"
# Pinned empirically 2026-07-04 against the installed CLI. If a CLI upgrade
# changes these field names, al-loop.sh's usage backfill breaks — this test
# fails loudly instead. Shape sample kept inline (no live call in unit tests).
cat > "$SANDBOX/result-pin.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"num_turns":2,"result":"...","session_id":"x","total_cost_usd":0.1,"usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}
EOF
for path in is_error num_turns total_cost_usd usage.input_tokens usage.output_tokens usage.cache_read_input_tokens usage.cache_creation_input_tokens; do
  "$BIN/al-json" get "$SANDBOX/result-pin.json" "$path" >/dev/null 2>&1 \
    && ok "result pin has $path" || bad "result pin missing $path"
done

echo "# al-goal"
mkdir -p "$SANDBOX/.claude/agent-loop"
cat > "$SANDBOX/.claude/agent-loop/goal.json" <<'EOF'
{
  "id": "t-goal", "status": "active", "max_iterations": 5,
  "context_budget": 50000, "root": null,
  "verify": [{"cmd": "true", "expect": "exit0"}, {"cmd": "test -f README.does-not-exist", "expect": "exit0"}],
  "verifier_rubric": ["r1"]
}
EOF
"$BIN/al-goal" validate >/dev/null 2>&1; check "al-goal validate accepts valid spec" $? 0
[ "$("$BIN/al-goal" get id)" = "t-goal" ] && ok "al-goal get" || bad "al-goal get"
echo '{"id":"x"}' > "$SANDBOX/badgoal.json"
"$BIN/al-goal" --file "$SANDBOX/badgoal.json" validate >/dev/null 2>&1; check "al-goal rejects invalid spec (exit 3)" $? 3

echo "# al-verify"
OUT=$("$BIN/al-verify" 2>&1); RC=$?
check "al-verify fails when any cmd fails" $RC 1
echo "$OUT" | grep -q "^PASS true" && ok "al-verify reports PASS line" || bad "al-verify PASS line"
echo "$OUT" | grep -q "^FAIL test -f" && ok "al-verify reports FAIL line" || bad "al-verify FAIL line"
"$BIN/al-json" set "$SANDBOX/.claude/agent-loop/goal.json" verify '[{"cmd":"true","expect":"exit0"}]' >/dev/null
"$BIN/al-verify" >/dev/null 2>&1; check "al-verify passes when all pass" $? 0
cp "$SANDBOX/.claude/agent-loop/goal.json" "$SANDBOX/goal.bak"
echo '{"verify":{"2":{"cmd":"true"}}}' > "$SANDBOX/.claude/agent-loop/goal.json"
"$BIN/al-verify" >/dev/null 2>&1; check "al-verify refuses corrupt goal.json (exit 3)" $? 3
cp "$SANDBOX/goal.bak" "$SANDBOX/.claude/agent-loop/goal.json"

echo "# al-state"
cat > "$SANDBOX/.claude/agent-loop/GOAL.md" <<'EOF'
# Goal
Test goal.

# Done means
- [ ] alpha: first thing
- [ ] beta: second thing

# Decisions
- locked in

# Out of scope
- nothing
EOF
"$BIN/al-state" init t-goal >/dev/null 2>&1; check "al-state init" $? 0
[ "$("$BIN/al-state" get done_means.alpha)" = "false" ] && ok "done_means seeded from GOAL.md slugs" || bad "done_means seeding"
"$BIN/al-state" validate >/dev/null 2>&1; check "fresh state validates" $? 0
[ "$("$BIN/al-state" get plan.status)" = "none" ] && ok "init seeds plan (status none)" || bad "init seeds plan"

# helper: propose an assumption-free plan and approve it as the human —
# record-iter refuses without an approved plan (Guard 4)
approve_plan() {
  _plan="${1:-}"
  [ -n "$_plan" ] || _plan='{"tasks":[{"task":"t"}],"assumptions":[]}'
  "$BIN/al-state" plan-propose "$_plan" >/dev/null 2>&1
  "$BIN/al-state" plan-approve >/dev/null 2>&1
}

echo "# plan gate (Guard 4): unapproved plans are unrecordable"
"$BIN/al-state" record-iter '{"pass":false,"failures":["x"]}' >/dev/null 2>&1
check "record-iter refused with no plan at all" $? 1
grep -q 'plan.status=none' "$SANDBOX/.claude/agent-loop/audit.jsonl" && ok "no-plan refusal journaled" || bad "no-plan refusal journal"
"$BIN/al-state" plan-propose 'not json' >/dev/null 2>&1; check "invalid plan payload refused" $? 1
# default mode is "always": even a zero-assumption plan awaits the human
"$BIN/al-state" plan-propose '{"tasks":[{"task":"do x","files_hint":"f","parallel":false}],"assumptions":[]}' >/dev/null 2>&1
check "plan-propose accepted" $? 0
[ "$("$BIN/al-state" get plan.status)" = "awaiting-human" ] && ok "always-mode: zero-assumption plan still awaits human" || bad "always-mode gate"
"$BIN/al-state" record-iter '{"pass":false,"failures":["x"]}' >/dev/null 2>&1
check "record-iter refused while awaiting-human" $? 1
"$BIN/al-state" set plan.status '"approved"' >/dev/null 2>&1; check "raw set of plan.status refused (protected)" $? 1
"$BIN/al-state" plan-approve >/dev/null 2>&1; check "plan-approve (human)" $? 0
[ "$("$BIN/al-state" get plan.approved_by)" = "human" ] && ok "approval provenance recorded" || bad "approved_by"
grep -q '"event":"plan_approved"' "$SANDBOX/.claude/agent-loop/audit.jsonl" && ok "approval journaled" || bad "approval journal"
# reject path on a fresh proposal
"$BIN/al-state" plan-propose '{"tasks":[{"task":"other"}],"assumptions":["file name unpinned — spec silent"]}' >/dev/null 2>&1
"$BIN/al-state" plan-reject 'wrong direction' >/dev/null 2>&1; check "plan-reject (human)" $? 0
[ "$("$BIN/al-state" get plan.rejected_reason)" = "wrong direction" ] && ok "rejection reason kept for the re-plan" || bad "rejected_reason"
grep -q '"event":"plan_rejected"' "$SANDBOX/.claude/agent-loop/audit.jsonl" && ok "rejection journaled" || bad "rejection journal"
# assumptions-mode matrix (deterministic auto-approval rule)
"$BIN/al-json" set "$SANDBOX/.claude/agent-loop/goal.json" plan_approval '"assumptions"' >/dev/null
"$BIN/al-state" plan-propose '{"tasks":[{"task":"t"}],"assumptions":["a guess — unpinned"]}' >/dev/null 2>&1
[ "$("$BIN/al-state" get plan.status)" = "awaiting-human" ] && ok "assumptions-mode: surviving assumption awaits" || bad "assumption awaits"
"$BIN/al-state" plan-propose '{"tasks":[{"task":"t"}],"assumptions":[]}' >/dev/null 2>&1
[ "$("$BIN/al-state" get plan.status)" = "awaiting-human" ] && ok "assumptions-mode: iteration 1 still awaits (first-iter gate)" || bad "first-iter gate"
"$BIN/al-state" plan-propose '{"tasks":[],"assumptions":["nothing plannable"]}' >/dev/null 2>&1
[ "$("$BIN/al-state" get plan.status)" = "awaiting-human" ] && ok "empty plan always awaits (blocked loop = human problem)" || bad "empty plan gate"
"$BIN/al-json" set "$SANDBOX/.claude/agent-loop/goal.json" plan_approval '"always"' >/dev/null

echo "# verify gate (Guard 1 structural): unverified passes are unrepresentable"
"$BIN/al-state" tick alpha >/dev/null 2>&1; check "tick refused before any verified pass" $? 1
grep -q '^- \[ \] alpha:' "$SANDBOX/.claude/agent-loop/GOAL.md" && ok "refused tick leaves checkbox unflipped" || bad "refused tick checkbox"
grep -q '"event":"refused"' "$SANDBOX/.claude/agent-loop/audit.jsonl" && ok "refused tick journaled" || bad "refused tick journal"
# claim pass while the deterministic layer FAILS -> must refuse, state untouched
"$BIN/al-json" set "$SANDBOX/.claude/agent-loop/goal.json" verify '[{"cmd":"false","expect":"exit0"}]' >/dev/null
approve_plan
BEFORE=$(cat "$SANDBOX/.claude/agent-loop/state.json")
"$BIN/al-state" record-iter '{"pass":true,"failures":[]}' '["lie"]' >/dev/null 2>&1
check "record-iter REFUSES pass=true when al-verify fails" $? 1
[ "$BEFORE" = "$(cat "$SANDBOX/.claude/agent-loop/state.json")" ] && ok "refused pass leaves state untouched" || bad "refused pass atomicity"
grep -q '"op":"record-iter"' "$SANDBOX/.claude/agent-loop/audit.jsonl" && ok "refused pass journaled with verify output" || bad "refused pass journal"
"$BIN/al-state" record-iter '{"pass":false,"failures":["honest fail"]}' '[]' >/dev/null 2>&1
check "honest fail always recordable (no verify gate)" $? 0
[ "$("$BIN/al-state" get plan.status)" = "none" ] && ok "record consumes the approved plan (reset to none)" || bad "plan consumed"
# protected paths on set
"$BIN/al-state" set iteration 99 >/dev/null 2>&1; check "set iteration refused (protected)" $? 1
"$BIN/al-state" set last_verdict.pass true >/dev/null 2>&1; check "set last_verdict.pass refused (protected)" $? 1
"$BIN/al-state" set done_means.alpha true >/dev/null 2>&1; check "set done_means refused (protected)" $? 1
"$BIN/al-state" set paused_by_stall false >/dev/null 2>&1; check "set paused_by_stall allowed (human remedy path)" $? 0
"$BIN/al-state" set context_tokens_last_iter 123 >/dev/null 2>&1; check "set context_tokens_last_iter allowed (backfill path)" $? 0
# restore a passing verify layer for the rest of the suite
"$BIN/al-json" set "$SANDBOX/.claude/agent-loop/goal.json" verify '[{"cmd":"true","expect":"exit0"}]' >/dev/null

echo "tree moved" > "$SANDBOX/gate-progress.txt"
approve_plan '{"tasks":[{"task":"task-a"}],"assumptions":[]}'
"$BIN/al-state" record-iter '{"pass":true,"failures":[]}' >/dev/null 2>&1
check "record-iter (pass, verify green)" $? 0
"$BIN/al-json" get "$SANDBOX/.claude/agent-loop/state.json" history.1.planned.0 | grep -q "task-a" \
  && ok "history.planned taken from the APPROVED plan, not the caller" || bad "planned from plan"
[ "$("$BIN/al-state" get iteration)" = "2" ] && ok "iteration incremented" || bad "iteration increment"
[ "$("$BIN/al-state" get last_verdict.pass)" = "true" ] && ok "last_verdict recorded" || bad "last_verdict"
[ "$("$BIN/al-state" get stall_count)" = "0" ] && ok "hash moved -> stall_count 0" || bad "stall_count after progress"
grep -q '"verify_output":"PASS true' "$SANDBOX/.claude/agent-loop/audit.jsonl" && ok "iteration event carries observed verify output" || bad "verify_output in journal"
"$BIN/al-state" tick alpha >/dev/null 2>&1; check "tick allowed after verified pass" $? 0
grep -q '^- \[x\] alpha:' "$SANDBOX/.claude/agent-loop/GOAL.md" && ok "tick flips GOAL.md checkbox" || bad "tick checkbox flip"
"$BIN/al-state" tick nope >/dev/null 2>&1; check "tick unknown slug exits 1" $? 1
# verdict sanitization: extra keys (evidence) are dropped, not rejected;
# a bad record must leave state untouched (atomicity pin)
echo "tree change 0" > "$SANDBOX/pin-atomic.txt"
approve_plan
"$BIN/al-state" record-iter '{"pass":true,"failures":[],"evidence":["file:1"]}' '["t"]' >/dev/null 2>&1
check "record-iter accepts verdict with extra keys" $? 0
"$BIN/al-state" validate >/dev/null 2>&1; check "state valid after sanitized verdict" $? 0
BEFORE=$(cat "$SANDBOX/.claude/agent-loop/state.json")
"$BIN/al-state" record-iter '{"pass":"not-a-bool"}' '[]' >/dev/null 2>&1
check "record-iter rejects non-boolean pass" $? 1
[ "$BEFORE" = "$(cat "$SANDBOX/.claude/agent-loop/state.json")" ] && ok "rejected record leaves state untouched" || bad "atomicity on rejection"
# planned normalization: approved-plan task objects collapse to task strings (schema pin)
echo "tree change" > "$SANDBOX/pin-progress.txt"   # keep the stall sequence below unaffected
approve_plan '{"tasks":[{"task":"obj task","files_hint":"f","parallel":true}],"assumptions":[]}'
"$BIN/al-state" record-iter '{"pass":false,"failures":["x"]}' >/dev/null 2>&1
"$BIN/al-json" get "$SANDBOX/.claude/agent-loop/state.json" history.3.planned.0 | grep -q "obj task" \
  && ok "record-iter normalizes object planned to strings" || bad "planned normalization"
"$BIN/al-state" validate >/dev/null 2>&1; check "state validates after object planned" $? 0

# no file changes between iterations -> hash unchanged -> stall accumulates -> auto-pause at 2
approve_plan
"$BIN/al-state" record-iter '{"pass":false,"failures":["same"]}' '[]' >/dev/null 2>&1
[ "$("$BIN/al-state" get stall_count)" = "1" ] && ok "no progress -> stall_count 1" || bad "stall_count 1 (got $("$BIN/al-state" get stall_count))"
approve_plan
"$BIN/al-state" record-iter '{"pass":false,"failures":["same"]}' '[]' >/dev/null 2>&1
[ "$("$BIN/al-state" get stall_count)" = "2" ] && ok "no progress -> stall_count 2" || bad "stall_count 2"
[ "$("$BIN/al-state" get paused_by_stall)" = "true" ] && ok "auto pause-stall at 2" || bad "auto pause-stall"
"$BIN/al-state" get stall_report | grep -q "No progress" && ok "stall_report written" || bad "stall_report"
[ "$("$BIN/al-json" len "$SANDBOX/.claude/agent-loop/state.json" history)" = "6" ] && ok "history has 6 entries" || bad "history entries"
"$BIN/al-state" validate >/dev/null 2>&1; check "state still validates after full cycle" $? 0

echo "# al-state log/canon"
printf '# memory\n\n## Session log\n\n## Open threads\n\n## Candidate canon\n' > "$SANDBOX/.claude/agent-loop/MEMORY.md"
"$BIN/al-state" log "iter 1: pass, fixed the thing" >/dev/null 2>&1; check "al-state log" $? 0
grep -q "fixed the thing" "$SANDBOX/.claude/agent-loop/MEMORY.md" && ok "log line lands in MEMORY.md" || bad "log line lands"
"$BIN/al-state" canon "uses tabs not spaces" >/dev/null 2>&1; check "al-state canon" $? 0
awk '/## Candidate canon/{f=1} f && /uses tabs/{found=1} END{exit !found}' "$SANDBOX/.claude/agent-loop/MEMORY.md" \
  && ok "canon line lands under Candidate canon" || bad "canon line placement"
# awk -v interprets backslash escapes — lines with \n / \t must land verbatim
BSLINE='grep \t and printf "a\nb"'
"$BIN/al-state" log "$BSLINE" >/dev/null 2>&1; check "al-state log (backslash line)" $? 0
grep -qF -- "$BSLINE" "$SANDBOX/.claude/agent-loop/MEMORY.md" \
  && ok "backslashes survive log verbatim" || bad "backslash mangling in log"

echo "# audit journal"
AUDIT="$SANDBOX/.claude/agent-loop/audit.jsonl"
[ -f "$AUDIT" ] && ok "audit.jsonl created by state mutations" || bad "audit.jsonl exists"
grep -q '"event":"goal_init"' "$AUDIT" && ok "goal_init journaled" || bad "goal_init event"
grep -q '"event":"tick"' "$AUDIT" && ok "tick journaled" || bad "tick event"
grep -q '"event":"iteration"' "$AUDIT" && ok "iterations journaled" || bad "iteration event"
grep -q '"evidence"' "$AUDIT" && ok "raw verdict evidence preserved in journal" || bad "evidence preserved"
grep -q '"files_hint"' "$AUDIT" && ok "raw planner objects preserved in journal" || bad "raw plan preserved"
"$BIN/al-state" audit plan '[{"task":"x","parallel":false}]' >/dev/null 2>&1; check "al-state audit (array payload)" $? 0
tail -1 "$AUDIT" | grep -q '"payload":\[' && ok "array payloads wrapped as objects" || bad "array wrap"
"$BIN/al-state" audit note 'not json at all' >/dev/null 2>&1; check "al-state audit (invalid payload)" $? 0
tail -1 "$AUDIT" | grep -q '"raw":"not json at all"' && ok "invalid payloads stored as raw string" || bad "raw fallback"
"$BIN/al-state" audit ev >/dev/null 2>&1; check "al-state audit (no payload)" $? 0
tail -1 "$AUDIT" | grep -q '"event":"ev"' && ok "payload-less audit journaled" || bad "payload-less audit"
tail -1 "$AUDIT" | grep -q '"raw"' && bad "payload-less audit must not store a raw key" || ok "no raw key without payload ({} default)"
BAD=0
while IFS= read -r line; do printf '%s' "$line" > "$SANDBOX/.l.json"; "$BIN/al-json" check "$SANDBOX/.l.json" 2>/dev/null || BAD=$((BAD+1)); done < "$AUDIT"
[ "$BAD" -eq 0 ] && ok "every journal line is valid JSON" || bad "journal integrity ($BAD bad lines)"
OUT=$("$BIN/al-doctor" "$SANDBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D14 PASS" && ok "D14 passes on intact journal" || bad "D14 intact"
echo 'garbage line' >> "$AUDIT"
OUT=$("$BIN/al-doctor" "$SANDBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D14 FAIL" && ok "D14 fails on corrupt journal" || bad "D14 corrupt"
# remove the garbage so later checks see an intact journal
grep -v '^garbage line$' "$AUDIT" > "$AUDIT.t" && mv "$AUDIT.t" "$AUDIT"

echo "# al-state optimize"
MEMF="$SANDBOX/.claude/agent-loop/MEMORY.md"
STATEF="$SANDBOX/.claude/agent-loop/state.json"
GOALJ="$SANDBOX/.claude/agent-loop/goal.json"
GOALMD="$SANDBOX/.claude/agent-loop/GOAL.md"
cp "$STATEF" "$SANDBOX/.st.before"
cp "$GOALJ" "$SANDBOX/.gj.before"
cp "$GOALMD" "$SANDBOX/.gm.before"
OPT='{"spec_gaps":["- id is the unique primary key; final tie-breaker"],"verify_gaps":[{"cmd":"grep -q cursor docs/api.md","expect":"exit0","reason":"verifier caught missing docs the commands could not"}],"planner_guidance":["integration tests live in tests/integration, not tests/unit"],"canon":["DB layer is Knex; migrations in db/migrations"]}'
OPT_OUT=$("$BIN/al-state" optimize "$OPT" 2>&1); check "al-state optimize (valid proposal)" $? 0
awk '/## Open threads/{f=1} /## Candidate canon/{f=0} f && /tests\/integration/{found=1} END{exit !found}' "$MEMF" \
  && ok "guidance lands under Open threads" || bad "guidance placement"
awk '/## Candidate canon/{f=1} f && /Knex/{found=1} END{exit !found}' "$MEMF" \
  && ok "optimize canon routes to Candidate canon" || bad "optimize canon routing"
grep '"event":"memory_canon"' "$AUDIT" | grep -q "Knex" && ok "routed canon gets its own memory_canon event" || bad "canon event"
grep -q '"event":"optimize"' "$AUDIT" && ok "optimize event journaled" || bad "optimize event"
grep '"event":"optimize"' "$AUDIT" | grep -q "unique primary key" && ok "raw spec_gaps preserved in journal" || bad "raw proposal in journal"
echo "$OPT_OUT" | grep -q "PROPOSED Decisions" && ok "spec gaps echoed as paste-ready report" || bad "spec gap report"
echo "$OPT_OUT" | grep -q "PROPOSED verify" && ok "verify gaps echoed as paste-ready report" || bad "verify gap report"
# report-only invariant: the spec and the protected state are byte-identical
cmp -s "$GOALJ" "$SANDBOX/.gj.before" && ok "goal.json untouched (report-only)" || bad "goal.json mutated"
cmp -s "$GOALMD" "$SANDBOX/.gm.before" && ok "GOAL.md untouched (report-only)" || bad "GOAL.md mutated"
cmp -s "$STATEF" "$SANDBOX/.st.before" && ok "state.json untouched by optimize" || bad "state mutated"
# guidance cap: 5 in -> exactly 3 land, truncation journaled
OPT5='{"spec_gaps":[],"verify_gaps":[],"planner_guidance":["g-one","g-two","g-three","g-four","g-five"],"canon":[]}'
"$BIN/al-state" optimize "$OPT5" >/dev/null 2>&1; check "al-state optimize (5 guidance lines)" $? 0
NG=$(grep -cE 'g-(one|two|three|four|five)' "$MEMF")
[ "$NG" = "3" ] && ok "guidance capped at 3 per iteration" || bad "guidance cap (got $NG lines)"
tail -1 "$AUDIT" | grep -q '"guidance_truncated":2' && ok "truncation count journaled" || bad "truncation journal"
# dedupe: the same proposal again adds nothing
"$BIN/al-state" optimize "$OPT5" >/dev/null 2>&1; check "al-state optimize (repeat proposal)" $? 0
NG2=$(grep -cE 'g-(one|two|three|four|five)' "$MEMF")
[ "$NG2" = "3" ] && ok "dedupe: repeated guidance adds nothing" || bad "dedupe (got $NG2 lines)"
tail -1 "$AUDIT" | grep -q '"guidance_deduped":3' && ok "dedupe count journaled" || bad "dedupe journal"
# empty proposal: valid, journaled, MEMORY.md untouched
cp "$MEMF" "$SANDBOX/.mem.before"
OPT_OUT=$("$BIN/al-state" optimize '{"spec_gaps":[],"verify_gaps":[],"planner_guidance":[],"canon":[]}' 2>&1)
check "al-state optimize (empty proposal)" $? 0
cmp -s "$MEMF" "$SANDBOX/.mem.before" && ok "empty proposal leaves MEMORY.md untouched" || bad "empty proposal wrote memory"
tail -1 "$AUDIT" | grep -q '"event":"optimize"' && ok "empty proposal still journaled (honest emptiness)" || bad "empty proposal event"
echo "$OPT_OUT" | grep -q "no proposals" && ok "empty proposal reported as such" || bad "empty proposal report"
# malformed payloads are refused and journaled; nothing written
"$BIN/al-state" optimize 'not json' >/dev/null 2>&1; check "optimize (not json) -> exit 1" $? 1
tail -1 "$AUDIT" | grep -q '"op":"optimize"' && ok "invalid optimize payload journaled as refused" || bad "refused event"
"$BIN/al-state" optimize '{"spec_gaps":[]}' >/dev/null 2>&1; check "optimize (missing required keys) -> exit 1" $? 1
# MEMORY.md required only when guidance/canon are non-empty
mv "$MEMF" "$MEMF.aside"
"$BIN/al-state" optimize "$OPT" >/dev/null 2>&1; check "optimize with guidance but no MEMORY.md -> exit 1" $? 1
"$BIN/al-state" optimize '{"spec_gaps":["- x"],"verify_gaps":[],"planner_guidance":[],"canon":[]}' >/dev/null 2>&1
check "spec-only proposal works without MEMORY.md" $? 0
mv "$MEMF.aside" "$MEMF"

echo "# al-state audit-slice"
# cheap sanity against the live sandbox journal (it already has iteration events)
SLICE=$("$BIN/al-state" audit-slice 2>&1); check "audit-slice (no arg) on live journal" $? 0
echo "$SLICE" | tail -1 | grep -q '"event":"iteration"' && ok "live slice ends on an iteration event" || bad "live slice terminator"
# boundary tests against a hand-written journal in an ISOLATED state dir —
# never mutate the sandbox journal the rest of the suite relies on
ABOX=$(mktemp -d)
ASTATE="$ABOX/state.json"
cat > "$ABOX/audit.jsonl" <<'EOF'
{"event":"goal_init","goal_id":"g1"}
{"event":"plan_proposed","plan":"p1"}
{"event":"worker_report","report":"w1"}
{"event":"iteration","iter":1,"pass":false}
{"event":"plan_proposed","plan":"p2"}
{"event":"worker_report","report":"w2"}
{"event":"iteration","iter":2,"pass":true}
EOF
cp "$ABOX/audit.jsonl" "$ABOX/.audit.before"
S1=$("$BIN/al-state" --state "$ASTATE" audit-slice 1 2>&1); check "audit-slice 1 (explicit n)" $? 0
[ "$(echo "$S1" | wc -l | tr -d ' ')" = "4" ] && ok "slice 1 spans file start..iteration 1 (4 lines)" || bad "slice 1 line count"
echo "$S1" | head -1 | grep -q '"event":"goal_init"' && ok "slice 1 starts at file start (n=1 lower bound)" || bad "slice 1 start"
echo "$S1" | tail -1 | grep -q '"iter":1' && ok "slice 1 ends with iteration event 1" || bad "slice 1 terminator"
S2=$("$BIN/al-state" --state "$ASTATE" audit-slice 2 2>&1); check "audit-slice 2 (explicit n)" $? 0
[ "$(echo "$S2" | wc -l | tr -d ' ')" = "3" ] && ok "slice 2 has 3 lines (after iter 1, through iter 2)" || bad "slice 2 line count"
echo "$S2" | grep -q '"plan":"p2"' && ok "slice 2 includes this iteration's plan_proposed" || bad "slice 2 plan_proposed"
echo "$S2" | grep -q '"report":"w2"' && ok "slice 2 includes this iteration's worker_report" || bad "slice 2 worker_report"
echo "$S2" | grep -qE '"event":"goal_init"|"plan":"p1"|"report":"w1"|"iter":1,' \
  && bad "prior iteration's events leak into slice 2" || ok "prior iteration's events excluded"
echo "$S2" | tail -1 | grep -q '"iter":2' && ok "target iteration event is the last line" || bad "slice 2 terminator"
SDEF=$("$BIN/al-state" --state "$ASTATE" audit-slice 2>&1); check "audit-slice (no arg) defaults to last" $? 0
[ "$SDEF" = "$S2" ] && ok "default slice = highest iteration, verbatim" || bad "default slice mismatch"
"$BIN/al-state" --state "$ASTATE" audit-slice 3 >/dev/null 2>&1; check "requested n absent -> exit 1" $? 1
cmp -s "$ABOX/audit.jsonl" "$ABOX/.audit.before" && ok "journal byte-identical after slicing (read-only)" || bad "slicing mutated the journal"
# journal exists but has no iteration events at all
NOITER=$(mktemp -d)
printf '{"event":"goal_init"}\n{"event":"plan_proposed","plan":"p"}\n' > "$NOITER/audit.jsonl"
"$BIN/al-state" --state "$NOITER/state.json" audit-slice >/dev/null 2>&1; check "no iteration events -> exit 1" $? 1
# no journal at all
NOJRNL=$(mktemp -d)
"$BIN/al-state" --state "$NOJRNL/state.json" audit-slice >/dev/null 2>&1; check "missing journal -> exit 1" $? 1
rm -rf "$ABOX" "$NOITER" "$NOJRNL"

echo "# tdd gates (red before green, enforced at the state layer)"
TBOX=$(mktemp -d)
mkdir -p "$TBOX/.claude/agent-loop"
TS="$TBOX/.claude/agent-loop/state.json"
TAUDIT="$TBOX/.claude/agent-loop/audit.jsonl"
cat > "$TBOX/.claude/agent-loop/GOAL.md" <<'EOF'
# Goal
TDD test goal.

# Done means
- [ ] thing: the thing works

# Decisions
- locked
EOF
cat > "$TBOX/.claude/agent-loop/goal.json" <<'EOF'
{
  "id": "t-tdd", "status": "active", "max_iterations": 9,
  "context_budget": 50000, "root": null, "tdd": true,
  "verify": [{"cmd": "true", "expect": "exit0"}],
  "verifier_rubric": ["r1"]
}
EOF
"$BIN/al-state" --state "$TS" init t-tdd >/dev/null 2>&1; check "tdd: init" $? 0
# plan-shape gate
"$BIN/al-state" --state "$TS" plan-propose '{"tasks":[{"task":"code it"}],"assumptions":[]}' >/dev/null 2>&1
check "tdd: task without kind refused" $? 1
tail -1 "$TAUDIT" | grep -q 'missing kind' && ok "tdd: missing-kind refusal journaled" || bad "missing-kind journal"
"$BIN/al-state" --state "$TS" plan-propose '{"tasks":[{"task":"code it","kind":"impl"},{"task":"test it","kind":"test"}],"assumptions":[]}' >/dev/null 2>&1
check "tdd: impl before test refused" $? 1
tail -1 "$TAUDIT" | grep -q 'precedes any test task' && ok "tdd: ordering refusal journaled" || bad "ordering journal"
"$BIN/al-state" --state "$TS" plan-propose '{"tasks":[{"task":"test it","kind":"test"},{"task":"code it","kind":"impl"}],"assumptions":[]}' >/dev/null 2>&1
check "tdd: test-then-impl plan accepted" $? 0
"$BIN/al-state" --state "$TS" plan-approve >/dev/null 2>&1; check "tdd: plan approved" $? 0
# red gate: a passing command is not red
"$BIN/al-state" --state "$TS" tdd-red 'true' >/dev/null 2>&1; check "tdd-red refuses a passing command" $? 1
tail -1 "$TAUDIT" | grep -q '"op":"tdd-red"' && ok "tdd-red refusal journaled" || bad "tdd-red refusal journal"
# record gate: pass with impl but no red is unrepresentable
"$BIN/al-state" --state "$TS" record-iter '{"pass":true,"failures":[]}' >/dev/null 2>&1
check "tdd: pass without red refused" $? 1
tail -1 "$TAUDIT" | grep -q 'no tdd_red journaled' && ok "tdd: no-red refusal journaled" || bad "no-red journal"
# observe a real red
RED_CMD="test -f $TBOX/flag.txt"
"$BIN/al-state" --state "$TS" tdd-red "$RED_CMD" >/dev/null 2>&1; check "tdd-red journals a failing command" $? 0
tail -1 "$TAUDIT" | grep -q '"event":"tdd_red"' && ok "tdd_red event journaled" || bad "tdd_red event"
tail -1 "$TAUDIT" | grep -qF "$RED_CMD" && ok "tdd_red carries the exact command" || bad "tdd_red cmd"
# record gate: red that never went green is unrepresentable
"$BIN/al-state" --state "$TS" record-iter '{"pass":true,"failures":[]}' >/dev/null 2>&1
check "tdd: pass refused while red command still fails" $? 1
tail -1 "$TAUDIT" | grep -q 'red never went green' && ok "tdd: still-red refusal journaled" || bad "still-red journal"
# green the red -> the pass records
touch "$TBOX/flag.txt"
"$BIN/al-state" --state "$TS" record-iter '{"pass":true,"failures":[]}' >/dev/null 2>&1
check "tdd: pass records after red went green" $? 0
[ "$("$BIN/al-state" --state "$TS" get iteration)" = "1" ] && ok "tdd: iteration recorded" || bad "tdd iteration"
# docs-only plans need no red (iteration 2)
"$BIN/al-state" --state "$TS" plan-propose '{"tasks":[{"task":"write docs","kind":"docs"}],"assumptions":[]}' >/dev/null 2>&1
"$BIN/al-state" --state "$TS" plan-approve >/dev/null 2>&1
"$BIN/al-state" --state "$TS" record-iter '{"pass":true,"failures":[]}' >/dev/null 2>&1
check "tdd: docs-only pass needs no red" $? 0
# honest fails skip the gate entirely (iteration 3)
"$BIN/al-state" --state "$TS" plan-propose '{"tasks":[{"task":"t","kind":"test"},{"task":"i","kind":"impl"}],"assumptions":[]}' >/dev/null 2>&1
"$BIN/al-state" --state "$TS" plan-approve >/dev/null 2>&1
"$BIN/al-state" --state "$TS" record-iter '{"pass":false,"failures":["not yet"]}' >/dev/null 2>&1
check "tdd: honest fail recordable without red" $? 0
rm -rf "$TBOX"

echo "# critique gate (cross-model pressure-test before the human)"
CBOX=$(mktemp -d)
mkdir -p "$CBOX/.claude/agent-loop"
CS="$CBOX/.claude/agent-loop/state.json"
CAUDIT="$CBOX/.claude/agent-loop/audit.jsonl"
cat > "$CBOX/.claude/agent-loop/goal.json" <<'EOF'
{
  "id": "t-critic", "status": "active", "max_iterations": 9,
  "context_budget": 50000, "root": null,
  "critic": true, "critic_model": "opus",
  "verify": [{"cmd": "true", "expect": "exit0"}],
  "verifier_rubric": ["r1"]
}
EOF
"$BIN/al-goal" --file "$CBOX/.claude/agent-loop/goal.json" validate >/dev/null 2>&1
check "critic: goal.json with critic fields validates" $? 0
"$BIN/al-state" --state "$CS" init t-critic >/dev/null 2>&1; check "critic: init" $? 0
# an unpressure-tested plan cannot reach the approval queue
"$BIN/al-state" --state "$CS" plan-propose '{"tasks":[{"task":"t"}],"assumptions":[]}' >/dev/null 2>&1
check "critic: propose without critique refused" $? 1
tail -1 "$CAUDIT" | grep -q 'no plan_critique journaled' && ok "critic: refusal journaled" || bad "critique refusal journal"
# journal a critique -> propose passes
"$BIN/al-state" --state "$CS" audit plan_critique '{"verdict":"approve","blockers":[],"risks":[],"questions":[]}' >/dev/null 2>&1
"$BIN/al-state" --state "$CS" plan-propose '{"tasks":[{"task":"t"}],"assumptions":[]}' >/dev/null 2>&1
check "critic: propose after critique accepted" $? 0
grep -q '"event":"plan_critique"' "$CAUDIT" && ok "critic: plan_critique event journaled" || bad "plan_critique event"
# a critique from a PREVIOUS iteration does not count
"$BIN/al-state" --state "$CS" plan-approve >/dev/null 2>&1
"$BIN/al-state" --state "$CS" record-iter '{"pass":false,"failures":["x"]}' >/dev/null 2>&1
check "critic: iteration recorded" $? 0
"$BIN/al-state" --state "$CS" plan-propose '{"tasks":[{"task":"t2"}],"assumptions":[]}' >/dev/null 2>&1
check "critic: stale critique (prior iteration) refused" $? 1
"$BIN/al-state" --state "$CS" audit plan_critique '{"verdict":"approve","blockers":[],"risks":[],"questions":[]}' >/dev/null 2>&1
"$BIN/al-state" --state "$CS" plan-propose '{"tasks":[{"task":"t2"}],"assumptions":[]}' >/dev/null 2>&1
check "critic: fresh critique unblocks the next proposal" $? 0
rm -rf "$CBOX"

echo "# enterprise: journal hash chain + actor + redaction"
tdigest() { # must mirror al-state's al_digest
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else cksum | cut -d' ' -f1; fi
}
EBOX=$(mktemp -d)
mkdir -p "$EBOX/.claude/agent-loop"
ES="$EBOX/.claude/agent-loop/state.json"
EAUDIT="$EBOX/.claude/agent-loop/audit.jsonl"
cat > "$EBOX/.claude/agent-loop/goal.json" <<'EOF'
{"id":"t-ent","status":"active","max_iterations":9,"context_budget":50000,"root":null,
 "plan_approval":"assumptions",
 "verify":[{"cmd":"true","expect":"exit0"}],"verifier_rubric":["r1"]}
EOF
"$BIN/al-state" --state "$ES" init t-ent >/dev/null 2>&1; check "ent: init" $? 0
"$BIN/al-state" --state "$ES" audit ev1 '{"n":1}' >/dev/null 2>&1
"$BIN/al-state" --state "$ES" audit ev2 '{"n":2}' >/dev/null 2>&1
head -1 "$EAUDIT" | grep -q '"prev":"genesis"' && ok "chain: first line anchored at genesis" || bad "genesis anchor"
tail -1 "$EAUDIT" | grep -q '"actor":"' && ok "actor stamped on every event" || bad "actor missing"
D1=$(head -1 "$EAUDIT" | tdigest)
sed -n 2p "$EAUDIT" | grep -qF "\"prev\":\"$D1\"" && ok "chain: prev matches predecessor digest" || bad "chain link"
OUT=$(env CLAUDE_PROJECT_DIR="$EBOX" "$BIN/al-doctor" "$EBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D14 PASS.*chain verified" && ok "D14 verifies an intact chain" || bad "D14 chain pass"
cp "$EAUDIT" "$EAUDIT.bak"
sed '2s/"n": *1/"n":999/' "$EAUDIT" > "$EAUDIT.t" && mv "$EAUDIT.t" "$EAUDIT"
OUT=$(env CLAUDE_PROJECT_DIR="$EBOX" "$BIN/al-doctor" "$EBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D14 FAIL.*chain broken" && ok "D14 fails on rewritten history" || bad "D14 tamper detection"
cp "$EAUDIT.bak" "$EAUDIT"
# redaction: secret-shaped strings never reach the journal
"$BIN/al-state" --state "$ES" audit leak '{"output":"push with ghp_abcdefghijklmnopqrstuv1234 and Bearer abcdef1234567890abcdef"}' >/dev/null 2>&1
tail -1 "$EAUDIT" | grep -q 'REDACTED' && ok "secrets redacted in journal" || bad "redaction"
tail -1 "$EAUDIT" | grep -q 'ghp_abcdef' && bad "raw token leaked to journal" || ok "raw token absent from journal"
"$BIN/al-state" --state "$ES" audit leak2 '{"output":"conn password=hunter22secret retried"}' >/dev/null 2>&1
tail -1 "$EAUDIT" | grep -q 'hunter22secret' && bad "password value leaked" || ok "password value redacted"
"$BIN/al-state" --state "$ES" audit benign '{"output":"tokens_total rose to 5000"}' >/dev/null 2>&1
tail -1 "$EAUDIT" | grep -q 'tokens_total rose to 5000' && ok "benign text untouched by redaction" || bad "over-redaction"

echo "# enterprise: org policy overrides the goal author"
printf '{"tdd":true,"critic":true,"plan_approval":"always"}' > "$EBOX/.claude/agent-loop/policy.json"
"$BIN/al-state" --state "$ES" plan-propose '{"tasks":[{"task":"x"}],"assumptions":[]}' >/dev/null 2>&1
check "policy: forces tdd gate (kind required) despite goal silence" $? 1
"$BIN/al-state" --state "$ES" plan-propose '{"tasks":[{"task":"t","kind":"test"}],"assumptions":[]}' >/dev/null 2>&1
check "policy: forces critique gate despite goal silence" $? 1
"$BIN/al-state" --state "$ES" audit plan_critique '{"verdict":"approve","blockers":[],"risks":[],"questions":[]}' >/dev/null 2>&1
"$BIN/al-state" --state "$ES" plan-propose '{"tasks":[{"task":"t","kind":"test"}],"assumptions":[]}' >/dev/null 2>&1
check "policy: compliant plan accepted" $? 0
tail -1 "$EAUDIT" | grep -q '"mode":"always"' && ok "policy: plan_approval pinned to always (goal wanted assumptions)" || bad "policy approval pin"
"$BIN/al-json" set "$EBOX/.claude/agent-loop/goal.json" tdd false >/dev/null
OUT=$(env CLAUDE_PROJECT_DIR="$EBOX" "$BIN/al-doctor" "$EBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D15 WARN.*weaken" && ok "D15 flags a goal weakening policy" || bad "D15 weaken warn"
printf 'not json' > "$EBOX/.claude/agent-loop/policy.json"
OUT=$(env CLAUDE_PROJECT_DIR="$EBOX" "$BIN/al-doctor" "$EBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D15 FAIL" && ok "D15 fails on invalid policy.json" || bad "D15 invalid policy"
rm -f "$EBOX/.claude/agent-loop/policy.json"

echo "# enterprise: run lease"
"$BIN/al-state" --state "$ES" lease-acquire 60 >/dev/null 2>&1; check "lease: acquire" $? 0
"$BIN/al-state" --state "$ES" lease-acquire 60 >/dev/null 2>&1; check "lease: concurrent acquire refused" $? 1
"$BIN/al-state" --state "$ES" lease-release >/dev/null 2>&1; check "lease: release" $? 0
"$BIN/al-state" --state "$ES" lease-acquire 60 >/dev/null 2>&1; check "lease: re-acquire after release" $? 0
printf '{"pid":1,"host":"x","acquired_at":"t","expires_epoch":1}' > "$EBOX/.claude/agent-loop/.lease/owner.json"
"$BIN/al-state" --state "$ES" lease-acquire 60 >/dev/null 2>&1; check "lease: stale lease taken over" $? 0
grep -q '"event":"lease_takeover"' "$EAUDIT" && ok "lease: takeover journaled" || bad "takeover journal"
"$BIN/al-state" --state "$ES" lease-release >/dev/null 2>&1

echo "# enterprise: D16 journal growth bound"
OUT=$(env CLAUDE_PROJECT_DIR="$EBOX" "$BIN/al-doctor" "$EBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D16 PASS" && ok "D16 passes within bound" || bad "D16 default pass"
OUT=$(env CLAUDE_PROJECT_DIR="$EBOX" AL_DOCTOR_JOURNAL_MB=0 "$BIN/al-doctor" "$EBOX" 2>&1)
echo "$OUT" | grep -q "CHECK D16 WARN" && ok "D16 warns past the bound (override respected)" || bad "D16 warn"

echo "# enterprise: al-fleet"
FA=$(mktemp -d); FB=$(mktemp -d)
mkdir -p "$FA/.claude/agent-loop" "$FB/.claude/agent-loop"
cp "$EBOX/.claude/agent-loop/goal.json" "$FA/.claude/agent-loop/goal.json"
"$BIN/al-state" --state "$FA/.claude/agent-loop/state.json" init t-ent >/dev/null 2>&1
"$BIN/al-json" set "$FA/.claude/agent-loop/state.json" plan.status '"awaiting-human"' >/dev/null
cp "$EBOX/.claude/agent-loop/goal.json" "$FB/.claude/agent-loop/goal.json"
"$BIN/al-state" --state "$FB/.claude/agent-loop/state.json" init t-ent >/dev/null 2>&1
FLEET_OUT=$("$BIN/al-fleet" "$FA" "$FB" 2>&1); FLEET_RC=$?
check "fleet: exit 1 when a repo needs a human" $FLEET_RC 1
echo "$FLEET_OUT" | grep -q "awaiting-approval" && ok "fleet: awaiting repo flagged" || bad "fleet flag"
echo "$FLEET_OUT" | grep -q " ok" && ok "fleet: healthy repo reads ok" || bad "fleet ok row"
"$BIN/al-fleet" >/dev/null 2>&1; check "fleet: no repos -> exit 2" $? 2
rm -rf "$FA" "$FB" "$EBOX"

echo "# al-hash"
H1=$("$BIN/al-hash"); H2=$("$BIN/al-hash")
[ "$H1" = "$H2" ] && ok "hash is deterministic" || bad "hash determinism"
echo "new content" > "$SANDBOX/newfile.txt"
H3=$("$BIN/al-hash")
[ "$H1" != "$H3" ] && ok "hash moves when tree changes (no-git path)" || bad "hash sensitivity"
# same-size edits must move the hash (were invisible when only size counted).
# non-git digests use mtime; pin distinct mtimes so the test can't race the
# 1-second stat resolution.
printf 'ab' > "$SANDBOX/samesize.txt"; touch -t 202001010000 "$SANDBOX/samesize.txt"
H4=$("$BIN/al-hash")
printf 'cd' > "$SANDBOX/samesize.txt"; touch -t 202101010000 "$SANDBOX/samesize.txt"
H5=$("$BIN/al-hash")
[ "$H4" != "$H5" ] && ok "same-size edit moves hash (no-git path)" || bad "same-size edit invisible (no-git)"
# git path: untracked files are content-hashed, so no mtime pinning needed
GITBOX=$(mktemp -d)
( cd "$GITBOX" && git init -q )
printf 'ab' > "$GITBOX/u.txt"
H6=$(env CLAUDE_PROJECT_DIR="$GITBOX" "$BIN/al-hash")
printf 'cd' > "$GITBOX/u.txt"
H7=$(env CLAUDE_PROJECT_DIR="$GITBOX" "$BIN/al-hash")
[ "$H6" != "$H7" ] && ok "same-size untracked edit moves hash (git path)" || bad "same-size edit invisible (git)"
rm -rf "$GITBOX"

echo "# al-detect"
DETECT_DIR=$(mktemp -d)
echo '[tool.pytest.ini_options]' > "$DETECT_DIR/pyproject.toml"
D=$("$BIN/al-detect" "$DETECT_DIR")
echo "$D" | grep -q '"language": *"python"' && ok "detects python" || bad "detect python"
echo "$D" | grep -q '"test_cmd": *"pytest"' && ok "detects pytest" || bad "detect pytest"
EMPTY_DIR=$(mktemp -d)
D2=$("$BIN/al-detect" "$EMPTY_DIR")
echo "$D2" | grep -q '"test_cmd": *null' && ok "unknown stack -> nulls (never fabricates)" || bad "null on unknown stack"
echo "$D" | grep -q '"compose_test_file": *null' && ok "no compose -> compose_test_file null" || bad "compose_test_file null default"

# compose-aware detection: a dockerized project's test entry point must win
# over the host-side language guess (deps/services live in the containers).
DC_DIR=$(mktemp -d)
echo '[tool.pytest.ini_options]' > "$DC_DIR/pyproject.toml"
cat > "$DC_DIR/docker-compose.test.yml" <<'EOF'
services:
  db:
    image: postgres:16
  tests:
    build: .
    command: pytest -q
EOF
D3=$("$BIN/al-detect" "$DC_DIR")
echo "$D3" | grep -q '"compose_test_file": *"docker-compose.test.yml"' && ok "reports test-variant compose file" || bad "compose_test_file"
echo "$D3" | grep -q '"test_cmd": *"docker compose -f docker-compose.test.yml run --rm tests"' \
  && ok "compose test service overrides pytest guess" || bad "compose override (got: $D3)"
echo "$D3" | grep -q '"language": *"python"' && ok "language guess survives compose override" || bad "language kept"

# Makefile test target is the curated entry point — wins over compose too
printf 'test:\n\tdocker compose -f docker-compose.test.yml run --rm tests\n' > "$DC_DIR/Makefile"
D4=$("$BIN/al-detect" "$DC_DIR")
echo "$D4" | grep -q '"test_cmd": *"make test"' && ok "Makefile test target wins over compose" || bad "make test priority"

# main compose file with a test-shaped service, no test-variant file
DC2=$(mktemp -d)
cat > "$DC2/compose.yaml" <<'EOF'
services:
  app:
    image: x
  integration-tests:
    image: x
EOF
D5=$("$BIN/al-detect" "$DC2")
echo "$D5" | grep -q '"compose_file": *"compose.yaml"' && ok "reports main compose file" || bad "compose_file"
echo "$D5" | grep -q '"test_cmd": *"docker compose run --rm integration-tests"' \
  && ok "test-shaped service in main compose detected" || bad "main compose service (got: $D5)"

# test-variant compose without a test-shaped service -> up --abort-on-container-exit
DC3=$(mktemp -d)
printf 'services:\n  app:\n    image: x\n' > "$DC3/docker-compose.ci.yml"
D6=$("$BIN/al-detect" "$DC3")
echo "$D6" | grep -q '"test_cmd": *"docker compose -f docker-compose.ci.yml up --build --abort-on-container-exit"' \
  && ok "test-variant compose w/o service -> up --abort-on-container-exit" || bad "ci compose fallback (got: $D6)"
echo "$D6" | grep -q 'confirm the exact invocation' && ok "ambiguous compose flagged for confirmation" || bad "confirm evidence"

# app-only compose must NOT override the language guess or fabricate
DC4=$(mktemp -d)
echo '[tool.pytest.ini_options]' > "$DC4/pyproject.toml"
printf 'services:\n  app:\n    image: x\n' > "$DC4/compose.yaml"
D7=$("$BIN/al-detect" "$DC4")
echo "$D7" | grep -q '"test_cmd": *"pytest"' && ok "app-only compose leaves language guess intact" || bad "no false compose override"
echo "$D7" | grep -q '"compose_file": *"compose.yaml"' && ok "app-only compose still reported as evidence" || bad "compose evidence"
rm -rf "$DETECT_DIR" "$EMPTY_DIR" "$DC_DIR" "$DC2" "$DC3" "$DC4"

echo "# al-detect-skills"
AGENT_LOOP_SKILLS=1 "$BIN/al-detect-skills" | grep -q '"agentic_engineering": true' && ok "env override true" || bad "skills override true"
AGENT_LOOP_SKILLS=0 "$BIN/al-detect-skills" | grep -q '"agentic_engineering": false' && ok "env override false" || bad "skills override false"

echo "# al-merge-settings"
mkdir -p "$SANDBOX/.claude"
cat > "$SANDBOX/.claude/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(docker:*)"]}, "custom": "keep-me"}
EOF
"$BIN/al-merge-settings" --dry-run >/dev/null 2>&1; check "dry-run exits cleanly" $? 0
"$BIN/al-merge-settings" >/dev/null 2>&1; check "merge applies" $? 0
"$BIN/al-json" get "$SANDBOX/.claude/settings.json" custom | grep -q keep-me && ok "existing keys survive merge" || bad "existing keys survive"
"$BIN/al-json" get "$SANDBOX/.claude/settings.json" permissions.allow | grep -q 'docker' && ok "existing allowlist survives (set-union)" || bad "allowlist union"
"$BIN/al-json" get "$SANDBOX/.claude/settings.json" permissions.allow | grep -q 'al-doctor' && ok "fragment allowlist added" || bad "fragment allowlist"
grep -q 'guard-destructive.sh' "$SANDBOX/.claude/settings.json" && ok "hooks registered by merge" || bad "hooks registered"

echo "# al-doctor"
OUT=$("$BIN/al-doctor" "$SANDBOX" 2>&1); RC=$?
check "doctor fails on broken sandbox (no CLAUDE.md/agents/vault)" $RC 1
echo "$OUT" | grep -q "CHECK D01 FAIL" && ok "D01 fires (no CLAUDE.md)" || bad "D01"
echo "$OUT" | grep -q "CHECK D05 FAIL" && ok "D05 fires (no agents)" || bad "D05"
echo "$OUT" | grep -q "CHECK D11 FAIL" && ok "D11 fires (no vault)" || bad "D11"
echo "$OUT" | grep -q "CHECK D13 PASS" && ok "D13 finds a JSON engine" || bad "D13"
# heal the sandbox
printf '# t\n' > "$SANDBOX/CLAUDE.md"
mkdir -p "$SANDBOX/.claude/agents" "$SANDBOX/.claude/agent-loop/vault"
for a in loop-planner loop-worker loop-verifier loop-optimizer loop-critic; do echo "---" > "$SANDBOX/.claude/agents/$a.md"; done
OUT=$("$BIN/al-doctor" "$SANDBOX" 2>&1); RC=$?
check "doctor passes on healed sandbox" $RC 0
echo "$OUT" | grep -q "INFO skill-reuse" && ok "doctor reports skill-reuse mode" || bad "skill-reuse INFO"
# empty Decisions must FAIL D06
sed 's/^- locked in//' "$SANDBOX/.claude/agent-loop/GOAL.md" > "$SANDBOX/.claude/agent-loop/GOAL.md.t" \
  && mv "$SANDBOX/.claude/agent-loop/GOAL.md.t" "$SANDBOX/.claude/agent-loop/GOAL.md"
OUT=$("$BIN/al-doctor" "$SANDBOX" 2>&1); RC=$?
check "doctor fails on empty Decisions" $RC 1
echo "$OUT" | grep -q "CHECK D06 FAIL" && ok "D06 fires (empty Decisions)" || bad "D06"

echo "# al-doctor — synthetic defects (mirrors evals/scenarios/02-doctor-broken/setup.sh)"
DOCBOX=$(mktemp -d)
mkdir -p "$DOCBOX/.claude/agent-loop/vault" "$DOCBOX/.claude/agents" "$DOCBOX/.claude/hooks"
# D02: oversized CLAUDE.md (900 lines of filler)
{ echo "# Bloated project brief"
  i=1; while [ $i -le 899 ]; do echo "- filler line $i: lorem ipsum dolor sit amet, agent-context filler."; i=$((i+1)); done
} > "$DOCBOX/CLAUDE.md"
# D06: goal with EMPTY Decisions
cat > "$DOCBOX/.claude/agent-loop/GOAL.md" <<'EOF'
# Goal
Do something vague.

# Done means
- [ ] vague-thing: it works

# Decisions

# Out of scope
- nothing
EOF
cat > "$DOCBOX/.claude/agent-loop/goal.json" <<'EOF'
{
  "id": "broken-goal", "status": "active", "max_iterations": 5,
  "context_budget": 50000, "root": null,
  "verify": [], "verifier_rubric": []
}
EOF
# D08: speculative MCP servers
cat > "$DOCBOX/.mcp.json" <<'EOF'
{"mcpServers": {"speculative-db": {"command": "npx", "args": ["some-mcp"]}, "never-used": {"command": "uvx", "args": ["another-mcp"]}}}
EOF
# D04: register only ONE of the three hooks (guard missing)
cat > "$DOCBOX/.claude/settings.json" <<'EOF'
{
  "permissions": {"allow": ["Bash(git status:*)"]},
  "hooks": {
    "PostToolUse": [{"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format-on-write.sh"}]}]
  }
}
EOF
# D10: local scope denies what project scope allows
cat > "$DOCBOX/.claude/settings.local.json" <<'EOF'
{"permissions": {"deny": ["Bash(git status:*)"]}}
EOF
# agents present so D05 stays quiet (isolate the seeded defects)
for a in loop-planner loop-worker loop-verifier loop-optimizer loop-critic; do
  printf -- '---\nname: %s\n---\nstub\n' "$a" > "$DOCBOX/.claude/agents/$a.md"
done
OUT=$(env CLAUDE_PROJECT_DIR="$DOCBOX" "$BIN/al-doctor" "$DOCBOX" 2>&1); RC=$?
check "doctor exits nonzero on synthetic defects" $RC 1
echo "$OUT" | grep -q "CHECK D02 WARN" && ok "D02 WARN (900-line CLAUDE.md)" || bad "D02 WARN"
echo "$OUT" | grep -q "CHECK D04 FAIL" && ok "D04 FAIL (unregistered hooks)" || bad "D04 FAIL"
echo "$OUT" | grep -q "CHECK D06 FAIL" && ok "D06 FAIL (empty Decisions)" || bad "D06 FAIL"
echo "$OUT" | grep -q "CHECK D07 WARN" && ok "D07 WARN (empty verify[])" || bad "D07 WARN"
echo "$OUT" | grep -q "CHECK D08 WARN" && ok "D08 WARN (speculative MCP servers)" || bad "D08 WARN"
echo "$OUT" | grep -q "CHECK D10 WARN" && ok "D10 WARN (allow/deny scope conflict)" || bad "D10 WARN"
rm -rf "$DOCBOX"

echo
echo "bin tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
