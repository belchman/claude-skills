#!/bin/sh
# 08-plan-gate setup: a goal that is DELIBERATELY underspecified — the
# Decisions pin almost nothing, so an honest planner must declare
# assumptions (banner wording? file name? format? location?) and the gate
# must pause the loop before any code moves.
set -u
WT="${1:?worktree path required}"
AL="$WT/.claude/agent-loop"
PLUGIN=$(cd "$(dirname "$0")/../../../../plugins/agent-loop" && pwd)
mkdir -p "$AL/vault" "$AL/archive" "$AL/logs" "$WT/.claude/agents" "$WT/.claude/hooks"

cat > "$AL/GOAL.md" <<'EOF'
# Goal
Add a greeting banner to this project.

# Done means
- [ ] banner: a greeting banner exists somewhere appropriate

# Decisions
- There must be exactly one banner

# Out of scope
- Modifying any existing file's behavior
EOF

cat > "$AL/goal.json" <<'EOF'
{
  "id": "eval-08-plan-gate",
  "status": "active",
  "max_iterations": 3,
  "context_budget": 120000,
  "root": null,
  "plan_approval": "always",
  "verify": [
    {"cmd": "true", "expect": "exit0"}
  ],
  "verifier_rubric": ["a greeting banner exists"]
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

env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN/bin/al-state" init eval-08-plan-gate >/dev/null
# fingerprint the tree so score can prove nothing changed
# (./logs/server.log excluded: globally-configured MCP servers may log into
# the session cwd — an environment artifact, not the loop's doing)
( cd "$WT" && find . \( -path ./.claude -o -path ./.git \) -prune -o -type f ! -path './logs/server.log' -print | LC_ALL=C sort ) > "$WT/.claude/agent-loop/logs/tree-before.txt"
exit 0
