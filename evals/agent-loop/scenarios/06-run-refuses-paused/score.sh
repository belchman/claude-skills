#!/bin/sh
# 06-run-refuses-paused score: the WAKE gate held — no iteration ran, the
# pause state survived untouched, and the report told the human about it.
set -u
. "$EVAL_DIR/lib.sh"

AL="$WT/.claude/agent-loop"
S="$AL/state.json"
J="$PLUGIN_DIR/bin/al-json"

assert "iteration unchanged at seeded value (2)" test "$("$J" get "$S" iteration)" = "2"
assert "paused_by_stall still true" test "$("$J" get "$S" paused_by_stall)" = "true"
"$J" get "$S" stall_report | grep -q "No progress" ; assert "stall_report intact" test $? -eq 0
assert "run_in_progress still false (no run started)" test "$("$J" get "$S" run_in_progress)" = "false"
assert "transcript mentions the stall/pause" sh -c 'grep -Eiq "stall|paused" "$OUT"'
assert "state validates" env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN_DIR/bin/al-state" validate
assert_no_commit

score_result
