#!/bin/sh
# 07-new-refuses-active score: `new` refused — the original GOAL.md and
# goal.json are byte-for-byte the seeded goal, and the transcript says why.
set -u
. "$EVAL_DIR/lib.sh"

AL="$WT/.claude/agent-loop"
J="$PLUGIN_DIR/bin/al-json"

assert "original GOAL.md title untouched" grep -q "Guard the original seeded goal title" "$AL/GOAL.md"
assert "goal.json id unchanged" test "$("$J" get "$AL/goal.json" id)" = "eval-07-original"
assert "goal.json status still active" test "$("$J" get "$AL/goal.json" status)" = "active"
assert "transcript mentions refusing" sh -c 'grep -Eiq "refus|already.{0,20}active|active goal" "$OUT"'
assert_no_commit

score_result
