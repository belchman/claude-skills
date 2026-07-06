#!/bin/sh
# 02-doctor-broken score: the model surfaced the seeded harness defects.
# Per-check binary assertions (D02/D04/D06/D07/D08/D10 against the same
# synthetic defects) live in tests/test_agent_loop_bin.sh — model-free, so
# they are not re-scored here; one sanity line keeps the eval honest about
# the seeded state.
set -u
. "$EVAL_DIR/lib.sh"

DOC_RC=0
env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN_DIR/bin/al-doctor" "$WT" >/dev/null 2>&1 || DOC_RC=$?
assert "al-doctor exits nonzero on seeded defects" test "$DOC_RC" -ne 0

# transcript (result JSON) mentions the hard failures by ID and points the
# user at a fix (doctor-checks anchors, or at least the empty-Decisions fix)
assert "transcript cites D04" grep -q "D04" "$OUT"
assert "transcript cites D06" grep -q "D06" "$OUT"
assert "transcript links doctor-checks or explains the Decisions fix" \
  sh -c 'grep -q "doctor-checks" "$OUT" || { grep -q "D06" "$OUT" && grep -qi "Decisions" "$OUT"; }'
assert_no_commit

score_result
