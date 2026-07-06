#!/bin/sh
# 05-fanout score: all three docs exist with the right content, one iteration
# with >=2 planned tasks, no leaked worker worktrees, contract respected.
set -u
. "$EVAL_DIR/lib.sh"

AL="$WT/.claude/agent-loop"
S="$AL/state.json"
J="$PLUGIN_DIR/bin/al-json"

for m in alpha beta gamma; do
  assert "al_eval_docs/$m/OVERVIEW.md non-empty" test -s "$WT/al_eval_docs/$m/OVERVIEW.md"
done
assert "alpha doc mentions parsing" grep -qi 'pars' "$WT/al_eval_docs/alpha/OVERVIEW.md"
assert "beta doc mentions storage" grep -qi 'stor' "$WT/al_eval_docs/beta/OVERVIEW.md"
assert "gamma doc mentions rendering" grep -qi 'render' "$WT/al_eval_docs/gamma/OVERVIEW.md"
assert "verify layer passes" env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN_DIR/bin/al-verify"
assert "leg 1 journaled plan_proposed" grep -q '"event":"plan_proposed"' "$AL/audit.jsonl"
assert "plan was human-approved" grep -q '"event":"plan_approved"' "$AL/audit.jsonl"
assert "one iteration recorded" test "$("$J" get "$S" iteration)" -ge 1
NPLANNED=$("$J" len "$S" history.0.planned 2>/dev/null || echo 0)
assert "iteration planned >=2 tasks (fan-out)" test "$NPLANNED" -ge 2
assert "last_verdict.pass true" test "$("$J" get "$S" last_verdict.pass)" = "true"
for slug in alpha-doc beta-doc gamma-doc; do
  assert "done_means.$slug ticked" test "$("$J" get "$S" done_means.$slug)" = "true"
done
assert "state validates" env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN_DIR/bin/al-state" validate
# no leaked worker worktrees in the fixture (git fixtures only)
if [ -n "$WT_FIXTURE" ] && [ "$WT_FIXTURE" != "$WT" ]; then
  LEAKED=$(git -C "$WT_FIXTURE" worktree list | grep -c al-eval || true)
  assert "exactly 1 eval worktree (no worker leaks)" test "$LEAKED" -le 1
fi
# sandbox-applicable leak check: when WT is itself a git repo, its worktree
# list must be just itself (workers cleaned up their own worktrees)
if git -C "$WT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  WT_COUNT=$(git -C "$WT" worktree list | wc -l | tr -d ' ')
  assert "no leaked worker worktrees in sandbox" test "$WT_COUNT" -eq 1
fi
assert_no_commit

score_result
