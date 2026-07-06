#!/bin/sh
# 05-fanout setup: three independent, repo-agnostic doc tasks in
# scenario-created subdirectories. Verify = test -s per file (offline).
set -u
WT="${1:?worktree path required}"
AL="$WT/.claude/agent-loop"
PLUGIN=$(cd "$(dirname "$0")/../../../../plugins/agent-loop" && pwd)
mkdir -p "$AL/vault" "$AL/archive" "$AL/logs" "$WT/.claude/agents" "$WT/.claude/hooks"
mkdir -p "$WT/al_eval_docs/alpha" "$WT/al_eval_docs/beta" "$WT/al_eval_docs/gamma"
printf 'module alpha: parses input\n'  > "$WT/al_eval_docs/alpha/notes.txt"
printf 'module beta: stores records\n' > "$WT/al_eval_docs/beta/notes.txt"
printf 'module gamma: renders output\n' > "$WT/al_eval_docs/gamma/notes.txt"

cat > "$AL/GOAL.md" <<'EOF'
# Goal
Write a one-paragraph OVERVIEW.md for each of the three eval doc modules,
derived from that module's notes.txt.

# Done means
- [ ] alpha-doc: al_eval_docs/alpha/OVERVIEW.md exists, non-empty, mentions parsing
- [ ] beta-doc: al_eval_docs/beta/OVERVIEW.md exists, non-empty, mentions storage
- [ ] gamma-doc: al_eval_docs/gamma/OVERVIEW.md exists, non-empty, mentions rendering

# Decisions
- Each OVERVIEW.md is derived only from its own module's notes.txt
- The three modules are independent: plan them as parallel tasks
- Plain markdown, one paragraph each, no front-matter

# Out of scope
- Any file outside al_eval_docs/
- Cross-module references
EOF

cat > "$AL/goal.json" <<'EOF'
{
  "id": "eval-05-fanout",
  "status": "active",
  "max_iterations": 3,
  "context_budget": 120000,
  "root": null,
  "verify": [
    {"cmd": "test -s al_eval_docs/alpha/OVERVIEW.md", "expect": "exit0"},
    {"cmd": "test -s al_eval_docs/beta/OVERVIEW.md", "expect": "exit0"},
    {"cmd": "test -s al_eval_docs/gamma/OVERVIEW.md", "expect": "exit0"}
  ],
  "verifier_rubric": [
    "each OVERVIEW.md describes its own module's purpose from notes.txt",
    "no file outside al_eval_docs/ was modified"
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

env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN/bin/al-state" init eval-05-fanout >/dev/null
exit 0
