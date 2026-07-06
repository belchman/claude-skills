#!/bin/sh
# 01-init-cold setup: guarantee a cold start on ANY repo — remove any Claude
# harness the target happens to track, inside the throwaway worktree only.
set -u
WT="${1:?worktree path required}"
rm -rf "$WT/.claude" "$WT/CLAUDE.md" "$WT/.mcp.json" 2>/dev/null || true
exit 0
