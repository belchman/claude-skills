#!/bin/sh
# 09-optimize setup: like 03-small-fix, but the goal has TWO done-means and a
# Decision explicitly deferring the second — so the iteration records a pass
# WITHOUT converging, which is exactly the case where the OPTIMIZE tail must
# fire (convergence skips it; this scenario must not converge).
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
Fix the syntax error in agent_loop_eval_target.py so it compiles, then (in a
LATER iteration) document it.

# Done means
- [ ] compiles: python3 -m py_compile agent_loop_eval_target.py exits 0
- [ ] docs: docs/usage.md documents the greet function

# Decisions
- Minimal fix only: correct the broken f-string; do not rewrite the function
- This iteration fixes ONLY the compile error; the docs done-means is
  explicitly deferred to a later iteration — do NOT create docs/usage.md yet
- No new dependencies

# Out of scope
- Any file other than agent_loop_eval_target.py (this iteration)
- Tests, refactors
EOF

cat > "$AL/goal.json" <<'EOF'
{
  "id": "eval-09-optimize",
  "status": "active",
  "max_iterations": 3,
  "context_budget": 120000,
  "root": null,
  "verify": [
    {"cmd": "python3 -m py_compile agent_loop_eval_target.py", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "agent_loop_eval_target.py contains a single greet function returning an f-string",
    "docs/usage.md was NOT created (the docs done-means is deferred by Decision)"
  ]
}
EOF
# score.sh compares against this copy: the loop may never edit its contract
cp "$AL/goal.json" "$WT/.goal.json.orig"

# harness plane: all four agents + hooks + memory
for a in loop-planner loop-worker loop-verifier loop-optimizer loop-critic; do
  cp "$PLUGIN/agents/$a.md" "$WT/.claude/agents/$a.md"
done
cp "$PLUGIN"/hooks/*.sh "$WT/.claude/hooks/" && chmod +x "$WT/.claude/hooks/"*.sh
printf '# memory\n\n## Session log\n\n## Open threads\n\n## Candidate canon\n' > "$AL/MEMORY.md"
printf '# decisions\n' > "$AL/vault/decisions.md"
printf '# eval repo\n' > "$WT/CLAUDE.md"
"$PLUGIN/bin/al-merge-settings" --target "$WT/.claude/settings.json" >/dev/null

env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN/bin/al-state" init eval-09-optimize >/dev/null
exit 0
