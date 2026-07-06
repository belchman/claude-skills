#!/bin/sh
# 03-small-fix score: the loop converged in one iteration and recorded it.
set -u
. "$EVAL_DIR/lib.sh"

AL="$WT/.claude/agent-loop"
S="$AL/state.json"
J="$PLUGIN_DIR/bin/al-json"

assert "target actually compiles" python3 -m py_compile "$WT/agent_loop_eval_target.py"
assert "iteration >= 1" test "$("$J" get "$S" iteration)" -ge 1
assert "last_verdict.pass true" test "$("$J" get "$S" last_verdict.pass)" = "true"
assert "done_means.compiles true" test "$("$J" get "$S" done_means.compiles)" = "true"
assert_grep '^- \[x\] compiles:' "$AL/GOAL.md" "GOAL.md checkbox ticked"
assert "run_in_progress cleared" test "$("$J" get "$S" run_in_progress)" = "false"
assert "history recorded" test "$("$J" len "$S" history)" -ge 1
assert_grep 'Session log' "$AL/MEMORY.md" "MEMORY.md intact"
assert "state validates" env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN_DIR/bin/al-state" validate
assert "GOAL.md decisions untouched" grep -q 'Minimal fix only' "$AL/GOAL.md"

# plan-approval flow: leg 1 proposed and paused without touching the repo;
# the journal shows propose -> approve -> iteration in causal order
assert "leg 1 journaled plan_proposed" grep -q '"event":"plan_proposed"' "$AL/audit.jsonl"
assert "plan was human-approved" grep -q '"event":"plan_approved"' "$AL/audit.jsonl"
P_LINE=$(grep -n '"event":"plan_proposed"' "$AL/audit.jsonl" | head -1 | cut -d: -f1)
A_LINE=$(grep -n '"event":"plan_approved"' "$AL/audit.jsonl" | head -1 | cut -d: -f1)
I_LINE=$(grep -n '"event":"iteration"' "$AL/audit.jsonl" | head -1 | cut -d: -f1)
assert "causal order: proposed < approved < iteration" test "$P_LINE" -lt "$A_LINE" -a "$A_LINE" -lt "$I_LINE"
assert "leg 1 did not fix the file prematurely (transcript exists)" test -s "$OUT1"

# auditable record: the journal captured the iteration's raw payloads
assert_file "$AL/audit.jsonl"
assert_grep '"event":"worker_report"' "$AL/audit.jsonl" "worker report journaled"
assert_grep '"event":"iteration"' "$AL/audit.jsonl" "iteration journaled"
assert_grep '"event":"tick"' "$AL/audit.jsonl" "tick journaled"
AUDIT_BAD=0
while IFS= read -r line; do
  printf '%s' "$line" > "$WT/.al-line.json"
  "$PLUGIN_DIR/bin/al-json" check "$WT/.al-line.json" 2>/dev/null || AUDIT_BAD=$((AUDIT_BAD+1))
done < "$AL/audit.jsonl"
rm -f "$WT/.al-line.json"
assert "every audit line parses (D14 clean)" test "$AUDIT_BAD" -eq 0
assert_no_commit

score_result
