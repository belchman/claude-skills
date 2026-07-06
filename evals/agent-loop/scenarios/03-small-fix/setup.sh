#!/bin/sh
# 03-small-fix setup: plant a broken pure-python file + a ready-made goal
# spec whose verify is stdlib-only (works on any repo, no docker, offline).
# Harness plane is pre-built (this scenario tests the LOOP plane).
set -u
WT="${1:?worktree path required}"
AL="$WT/.claude/agent-loop"
PLUGIN=$(cd "$(dirname "$0")/../../../../plugins/agent-loop" && pwd)
mkdir -p "$AL/vault" "$AL/archive" "$AL/logs" "$WT/.claude/agents" "$WT/.claude/hooks"

# the broken target: syntax error a worker must fix
cat > "$WT/agent_loop_eval_target.py" <<'EOF'
def greet(name):
    return f"hello {name"
EOF

cat > "$AL/GOAL.md" <<'EOF'
# Goal
Fix the syntax error in agent_loop_eval_target.py so it compiles.

# Done means
- [ ] compiles: python3 -m py_compile agent_loop_eval_target.py exits 0

# Decisions
- Minimal fix only: correct the broken f-string; do not rewrite the function
- No new dependencies

# Out of scope
- Any file other than agent_loop_eval_target.py
- Tests, docs, refactors
EOF

cat > "$AL/goal.json" <<'EOF'
{
  "id": "eval-03-small-fix",
  "status": "active",
  "max_iterations": 3,
  "context_budget": 120000,
  "root": null,
  "verify": [
    {"cmd": "python3 -m py_compile agent_loop_eval_target.py", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "agent_loop_eval_target.py contains a single greet function returning an f-string",
    "no other repo file was modified"
  ]
}
EOF

# harness plane: agents + hooks + memory (init already proven by scenario 01)
for a in loop-planner loop-worker loop-verifier loop-optimizer loop-critic; do
  cp "$PLUGIN/agents/$a.md" "$WT/.claude/agents/$a.md"
done
cp "$PLUGIN"/hooks/*.sh "$WT/.claude/hooks/" && chmod +x "$WT/.claude/hooks/"*.sh
printf '# memory\n\n## Session log\n\n## Open threads\n\n## Candidate canon\n' > "$AL/MEMORY.md"
printf '# decisions\n' > "$AL/vault/decisions.md"
printf '# eval repo\n' > "$WT/CLAUDE.md"
"$PLUGIN/bin/al-merge-settings" --target "$WT/.claude/settings.json" >/dev/null

env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN/bin/al-state" init eval-03-small-fix >/dev/null
exit 0
