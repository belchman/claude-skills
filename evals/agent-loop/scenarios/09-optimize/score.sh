#!/bin/sh
# 09-optimize score: the iteration recorded a pass WITHOUT converging, the
# OPTIMIZE tail fired (optimize event journaled, after the iteration event),
# and the proposals stayed report-only (goal.json byte-identical, Decisions
# untouched, deferred docs not created).
set -u
. "$EVAL_DIR/lib.sh"

AL="$WT/.claude/agent-loop"
S="$AL/state.json"
J="$PLUGIN_DIR/bin/al-json"

# the work itself
assert "target actually compiles" python3 -m py_compile "$WT/agent_loop_eval_target.py"
assert "iteration >= 1" test "$("$J" get "$S" iteration)" -ge 1
assert "last_verdict.pass true" test "$("$J" get "$S" last_verdict.pass)" = "true"
assert "done_means.compiles true" test "$("$J" get "$S" done_means.compiles)" = "true"

# non-convergence by construction: docs deferred, so OPTIMIZE must have run
assert "done_means.docs still false (deferred)" test "$("$J" get "$S" done_means.docs)" = "false"
assert "docs/usage.md NOT created (deferral respected)" test ! -f "$WT/docs/usage.md"

# the OPTIMIZE tail
assert_grep '"event":"iteration"' "$AL/audit.jsonl" "iteration journaled"
assert_grep '"event":"optimize"' "$AL/audit.jsonl" "optimize event journaled"
assert_grep '"proposal"' "$AL/audit.jsonl" "raw optimize proposal carried in the journal"
I_LINE=$(grep -n '"event":"iteration"' "$AL/audit.jsonl" | head -1 | cut -d: -f1)
O_LINE=$(grep -n '"event":"optimize"' "$AL/audit.jsonl" | head -1 | cut -d: -f1)
assert "causal order: iteration < optimize" test "$I_LINE" -lt "$O_LINE"

# report-only: the loop never edits its own contract
assert "goal.json byte-identical (report-only)" cmp -s "$AL/goal.json" "$WT/.goal.json.orig"
assert "GOAL.md decisions untouched" grep -q 'explicitly deferred to a later iteration' "$AL/GOAL.md"

# hygiene
assert "run_in_progress cleared" test "$("$J" get "$S" run_in_progress)" = "false"
assert "state validates" env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN_DIR/bin/al-state" validate
AUDIT_BAD=0
while IFS= read -r line; do
  printf '%s' "$line" > "$WT/.al-line.json"
  "$PLUGIN_DIR/bin/al-json" check "$WT/.al-line.json" 2>/dev/null || AUDIT_BAD=$((AUDIT_BAD+1))
done < "$AL/audit.jsonl"
rm -f "$WT/.al-line.json"
assert "every audit line parses (D14 clean)" test "$AUDIT_BAD" -eq 0
assert_no_commit

score_result
