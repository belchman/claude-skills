#!/bin/sh
# install.sh — fallback installer for environments without marketplace
# access: copies this plugin into ~/.claude/plugins/agent-loop. Idempotent
# (versioned by .claude-plugin/plugin.json). Prefer the marketplace install:
#   /plugin marketplace add belchman/claude-skills
#   /plugin install agent-loop@belchman-claude-skills
set -eu

SRC=$(cd "$(dirname "$0")/.." && pwd)
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/agent-loop"

[ -f "$SRC/.claude-plugin/plugin.json" ] || { echo "install.sh: run me from inside the agent-loop plugin"; exit 1; }

if [ -f "$DEST/.claude-plugin/plugin.json" ]; then
  OLD=$(grep -o '"version": *"[^"]*"' "$DEST/.claude-plugin/plugin.json" | head -1)
  NEW=$(grep -o '"version": *"[^"]*"' "$SRC/.claude-plugin/plugin.json" | head -1)
  [ "$OLD" = "$NEW" ] && { echo "agent-loop $NEW already installed at $DEST"; exit 0; }
fi

mkdir -p "$DEST"
# copy plugin contents (portable; no rsync dependency)
( cd "$SRC" && tar -cf - .claude-plugin skills agents hooks templates bin README.md CHANGELOG.md ) | ( cd "$DEST" && tar -xf - )
chmod +x "$DEST"/bin/al-* "$DEST"/hooks/*.sh 2>/dev/null || true

echo "agent-loop installed to $DEST"
echo "Next: restart claude, then in any repo:  /agent-loop init"
