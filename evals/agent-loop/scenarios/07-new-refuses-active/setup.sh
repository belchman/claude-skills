#!/bin/sh
# 07-new-refuses-active setup: a full harness with an ACTIVE goal. `new`
# must refuse to write a second goal over it.
set -u
WT="${1:?worktree path required}"
AL="$WT/.claude/agent-loop"
PLUGIN=$(cd "$(dirname "$0")/../../../../plugins/agent-loop" && pwd)
mkdir -p "$AL/vault" "$AL/archive" "$AL/logs" "$WT/.claude/agents" "$WT/.claude/hooks"

cat > "$AL/GOAL.md" <<'EOF'
# Goal
Guard the original seeded goal title.

# Done means
- [ ] seeded-goal: the original goal remains the only goal

# Decisions
- One active goal per repo; new goals wait for this one

# Out of scope
- Replacing or archiving this goal
EOF

cat > "$AL/goal.json" <<'EOF'
{
  "id": "eval-07-original",
  "status": "active",
  "max_iterations": 5,
  "context_budget": 120000,
  "root": null,
  "verify": [
    {"cmd": "true", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "the original goal spec is untouched"
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

env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN/bin/al-state" init eval-07-original >/dev/null
exit 0
