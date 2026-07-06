#!/bin/sh
# 06-run-refuses-paused setup: a full harness whose loop already stall-paused
# itself (paused_by_stall=true + stall_report, iteration seeded at 2). The
# WAKE gate must refuse to run another iteration.
set -u
WT="${1:?worktree path required}"
AL="$WT/.claude/agent-loop"
PLUGIN=$(cd "$(dirname "$0")/../../../../plugins/agent-loop" && pwd)
mkdir -p "$AL/vault" "$AL/archive" "$AL/logs" "$WT/.claude/agents" "$WT/.claude/hooks"

cat > "$AL/GOAL.md" <<'EOF'
# Goal
Keep the paused loop paused.

# Done means
- [ ] unreachable: this goal never progresses while paused

# Decisions
- The loop is stall-paused; only a human may unpause it

# Out of scope
- Editing the goal spec or the loop state
EOF

cat > "$AL/goal.json" <<'EOF'
{
  "id": "eval-06-paused",
  "status": "active",
  "max_iterations": 5,
  "context_budget": 120000,
  "root": null,
  "verify": [
    {"cmd": "true", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "no work happens while the loop is stall-paused"
  ]
}
EOF

for a in loop-planner loop-worker loop-verifier loop-optimizer loop-critic; do
  cp "$PLUGIN/agents/$a.md" "$WT/.claude/agents/$a.md"
done
cp "$PLUGIN"/hooks/*.sh "$WT/.claude/hooks/" && chmod +x "$WT/.claude/hooks/"*.sh
printf '# memory\n\n## Session log\n\n## Open threads\n\n## Candidate canon\n' > "$AL/MEMORY.md"
printf '# decisions\n' > "$AL/vault/decisions.md"
printf '# eval repo\n' > "$WT/CLAUDE.md"
"$PLUGIN/bin/al-merge-settings" --target "$WT/.claude/settings.json" >/dev/null

env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN/bin/al-state" init eval-06-paused >/dev/null
# fixtures own their state files: seed the iteration directly (al-state set
# refuses the protected ledger paths by design)
"$PLUGIN/bin/al-json" set "$AL/state.json" iteration 2 >/dev/null
env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN/bin/al-state" pause-stall \
  "No progress for 2 consecutive iterations (seeded by eval 06). A human must inspect the spec." >/dev/null
exit 0
