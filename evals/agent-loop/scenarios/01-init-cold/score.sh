#!/bin/sh
# 01-init-cold score: harness plane exists, settings valid + hooks registered,
# doctor exits 0 (WARNs allowed), nothing committed. Purely mechanical.
set -u
. "$EVAL_DIR/lib.sh"

AL="$WT/.claude/agent-loop"

assert_file "$WT/CLAUDE.md"
assert "CLAUDE.md under 200 lines" test "$(wc -l < "$WT/CLAUDE.md")" -le 200
assert_file "$AL/MEMORY.md"
assert_file "$AL/vault/decisions.md"
assert_dir  "$AL/archive"
assert_file "$WT/.claude/settings.json"
assert "settings.json valid" "$PLUGIN_DIR/bin/al-json" check "$WT/.claude/settings.json"
assert_grep 'guard-destructive.sh' "$WT/.claude/settings.json" "guard hook registered"
assert_grep 'format-on-write.sh'   "$WT/.claude/settings.json" "format hook registered"
assert_grep 'loop-checkpoint.sh'   "$WT/.claude/settings.json" "checkpoint hook registered"
assert "hook scripts copied+executable" test -x "$WT/.claude/hooks/guard-destructive.sh"
assert_file "$WT/.claude/agents/loop-planner.md"
assert_file "$WT/.claude/agents/loop-worker.md"
assert_file "$WT/.claude/agents/loop-verifier.md"
assert_file "$WT/.claude/skills/verify/SKILL.md"
assert "al-doctor exits 0 (no FAILs)" env CLAUDE_PROJECT_DIR="$WT" "$PLUGIN_DIR/bin/al-doctor" "$WT"
assert_no_commit

score_result
