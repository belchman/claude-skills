#!/bin/sh
# 02-doctor-broken setup: GENERATE defects synthetically (fixture-agnostic,
# nothing copied from any fixture):
#   D02: 900-line CLAUDE.md      D06: GOAL.md with empty Decisions
#   D08: speculative .mcp.json   D04: one hook left unregistered
#   D10: allow/deny conflict across settings scopes
set -u
WT="${1:?worktree path required}"
AL="$WT/.claude/agent-loop"
mkdir -p "$AL/vault" "$WT/.claude/agents" "$WT/.claude/hooks"

# D02: oversized CLAUDE.md (900 lines of filler)
{ echo "# Bloated project brief"
  i=1; while [ $i -le 899 ]; do echo "- filler line $i: lorem ipsum dolor sit amet, agent-context filler."; i=$((i+1)); done
} > "$WT/CLAUDE.md"

# D06: goal with EMPTY Decisions
cat > "$AL/GOAL.md" <<'EOF'
# Goal
Do something vague.

# Done means
- [ ] vague-thing: it works

# Decisions

# Out of scope
- nothing
EOF
cat > "$AL/goal.json" <<'EOF'
{
  "id": "broken-goal", "status": "active", "max_iterations": 5,
  "context_budget": 50000, "root": null,
  "verify": [], "verifier_rubric": []
}
EOF

# D08: speculative MCP servers
cat > "$WT/.mcp.json" <<'EOF'
{"mcpServers": {"speculative-db": {"command": "npx", "args": ["some-mcp"]}, "never-used": {"command": "uvx", "args": ["another-mcp"]}}}
EOF

# D04: register only ONE of the three hooks (guard missing)
cat > "$WT/.claude/settings.json" <<'EOF'
{
  "permissions": {"allow": ["Bash(git status:*)"]},
  "hooks": {
    "PostToolUse": [{"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format-on-write.sh"}]}]
  }
}
EOF

# D10: local scope denies what project scope allows
cat > "$WT/.claude/settings.local.json" <<'EOF'
{"permissions": {"deny": ["Bash(git status:*)"]}}
EOF

# agents present so D05 stays quiet (isolate the seeded defects)
for a in loop-planner loop-worker loop-verifier loop-optimizer loop-critic; do
  printf -- '---\nname: %s\n---\nstub\n' "$a" > "$WT/.claude/agents/$a.md"
done
exit 0
