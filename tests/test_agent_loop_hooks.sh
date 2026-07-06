#!/bin/sh
# test_agent_loop_hooks.sh — model-free unit tests for agent-loop hooks.
# Pipes crafted stdin JSON into each hook and asserts exit codes / output.
# Run: sh tests/test_agent_loop_hooks.sh
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOKS="$REPO_ROOT/plugins/agent-loop/hooks"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() { if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (exit $2, wanted $3)"; fi; }

SANDBOX=$(mktemp -d); SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT
export CLAUDE_PROJECT_DIR="$SANDBOX"
unset AGENT_LOOP_EVAL GOAL_STATE_WRITE 2>/dev/null || true

bash_event() { printf '{"hook_event_name":"PreToolUse","session_id":"t1","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
write_event() { printf '{"hook_event_name":"PreToolUse","session_id":"t1","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1"; }
edit_event() { printf '{"hook_event_name":"PreToolUse","session_id":"t1","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$1"; }

echo "# guard-destructive.sh — self-gate"
bash_event "rm -rf /" | "$HOOKS/guard-destructive.sh"
check "no .claude/agent-loop -> gate out (even rm -rf ignored)" $? 0

mkdir -p "$SANDBOX/.claude/agent-loop"

echo "# guard-destructive.sh — destructive patterns"
bash_event "rm -rf /" | "$HOOKS/guard-destructive.sh" >/dev/null
check "rm -rf / denied (exit 2)" $? 2
OUT=$(bash_event "rm -rf /" | "$HOOKS/guard-destructive.sh")
echo "$OUT" | grep -q '"permissionDecision":"deny"' && ok "deny JSON emitted" || bad "deny JSON emitted"
bash_event "git push --force origin main" | "$HOOKS/guard-destructive.sh" >/dev/null
check "force-push denied" $? 2
bash_event "git reset --hard HEAD~3" | "$HOOKS/guard-destructive.sh" >/dev/null
check "reset --hard denied" $? 2
bash_event "ls -la" | "$HOOKS/guard-destructive.sh" >/dev/null
check "benign command allowed" $? 0
bash_event "git commit -m x" | "$HOOKS/guard-destructive.sh" >/dev/null
check "git commit allowed outside evals" $? 0

echo "# guard-destructive.sh — rm/clean/find variants"
bash_event "rm -fr /" | "$HOOKS/guard-destructive.sh" >/dev/null
check "rm -fr / denied (swapped flags)" $? 2
bash_event "rm -rf ." | "$HOOKS/guard-destructive.sh" >/dev/null
check "rm -rf . denied (relative recursive nuke)" $? 2
bash_event "rm -r -f ~" | "$HOOKS/guard-destructive.sh" >/dev/null
check "rm -r -f ~ denied (split flags)" $? 2
bash_event "rm --no-preserve-root /tmp/x" | "$HOOKS/guard-destructive.sh" >/dev/null
check "rm --no-preserve-root denied" $? 2
bash_event "git clean -fdx" | "$HOOKS/guard-destructive.sh" >/dev/null
check "git clean -fdx denied" $? 2
bash_event "find . -name x -delete" | "$HOOKS/guard-destructive.sh" >/dev/null
check "find . -delete denied" $? 2
bash_event "rm build/output.txt" | "$HOOKS/guard-destructive.sh" >/dev/null
check "plain rm of a file allowed" $? 0
bash_event "git push --force-with-lease origin main" | "$HOOKS/guard-destructive.sh" >/dev/null
check "git push --force-with-lease ALLOWED (safe force)" $? 0

echo "# guard-destructive.sh — adversarial quoting (shim parsing, not grep)"
# grep extraction truncated at the first escaped quote — verified bypass
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo \"x\" && rm -rf /"}}' \
  | "$HOOKS/guard-destructive.sh" >/dev/null
check "rm -rf / behind an escaped quote denied" $? 2
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo \"x\" && git commit -m y"}}' \
  | AGENT_LOOP_EVAL=1 "$HOOKS/guard-destructive.sh" >/dev/null
check "eval-mode git commit behind an escaped quote denied" $? 2

echo "# guard-destructive.sh — malformed stdin"
# pinned intentionally: unparseable input fails OPEN (exit 0) — the guard is
# a safety net for known-destructive patterns, not a JSON validator; failing
# closed would break every Bash call on any hook-input schema change
printf 'not json at all' | "$HOOKS/guard-destructive.sh" >/dev/null
check "malformed stdin -> exit 0 (fail-open, pinned)" $? 0

echo "# guard-destructive.sh — eval no-commit rule"
bash_event "git commit -m x" | AGENT_LOOP_EVAL=1 "$HOOKS/guard-destructive.sh" >/dev/null
check "git commit denied under AGENT_LOOP_EVAL=1" $? 2
bash_event "git push origin main" | AGENT_LOOP_EVAL=1 "$HOOKS/guard-destructive.sh" >/dev/null
check "git push denied under AGENT_LOOP_EVAL=1" $? 2

echo "# guard-destructive.sh — contract write-guard"
cat > "$SANDBOX/.claude/agent-loop/state.json" <<'EOF'
{"run_in_progress": true}
EOF
write_event "$SANDBOX/.claude/agent-loop/GOAL.md" | "$HOOKS/guard-destructive.sh" >/dev/null
check "GOAL.md write denied while run_in_progress" $? 2
write_event "$SANDBOX/.claude/agent-loop/goal.json" | "$HOOKS/guard-destructive.sh" >/dev/null
check "goal.json write denied while run_in_progress" $? 2
edit_event "$SANDBOX/.claude/agent-loop/GOAL.md" | "$HOOKS/guard-destructive.sh" >/dev/null
check "GOAL.md Edit denied while run_in_progress (Edit-shaped event)" $? 2
write_event "$SANDBOX/.claude/agent-loop/GOAL.md" | GOAL_STATE_WRITE=1 "$HOOKS/guard-destructive.sh" >/dev/null
check "GOAL_STATE_WRITE sentinel bypasses (al-state tick path)" $? 0
write_event "$SANDBOX/somefile.py" | "$HOOKS/guard-destructive.sh" >/dev/null
check "normal file write allowed mid-run" $? 0
cat > "$SANDBOX/.claude/agent-loop/state.json" <<'EOF'
{"run_in_progress": false}
EOF
write_event "$SANDBOX/.claude/agent-loop/GOAL.md" | "$HOOKS/guard-destructive.sh" >/dev/null
check "GOAL.md write allowed when no run in progress (humans edit specs)" $? 0

echo "# double-registration: repo copy wins, plugin copy gates out"
mkdir -p "$SANDBOX/.claude/hooks"
cp "$HOOKS/guard-destructive.sh" "$SANDBOX/.claude/hooks/guard-destructive.sh"
chmod +x "$SANDBOX/.claude/hooks/guard-destructive.sh"
bash_event "rm -rf /" | "$HOOKS/guard-destructive.sh" >/dev/null
check "plugin copy exits 0 when repo copy exists (no double effect)" $? 0
bash_event "rm -rf /" | "$SANDBOX/.claude/hooks/guard-destructive.sh" >/dev/null
check "repo copy still denies" $? 2
rm -rf "$SANDBOX/.claude/hooks"

echo "# loop-checkpoint.sh"
printf '{}' | "$HOOKS/loop-checkpoint.sh"
check "no run_in_progress -> no-op" $? 0
cat > "$SANDBOX/.claude/agent-loop/state.json" <<'EOF'
{"goal_id":"g","iteration":1,"done_means":{},"last_verdict":null,"progress_hash":null,"stall_count":0,"paused_by_stall":false,"stall_report":null,"run_in_progress":true,"interrupted_at":null,"context_tokens_last_iter":null,"history":[]}
EOF
PATH="$REPO_ROOT/plugins/agent-loop/bin:$PATH" sh -c 'printf "{}" | "$0"' "$HOOKS/loop-checkpoint.sh"
check "checkpoint runs" $? 0
grep -q '"run_in_progress": false' "$SANDBOX/.claude/agent-loop/state.json" && ok "flag cleared by Stop backstop" || bad "flag cleared"
grep -q '"interrupted_at": "20' "$SANDBOX/.claude/agent-loop/state.json" && ok "interrupted_at stamped" || bad "interrupted_at stamped"

echo "# format-on-write.sh"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$SANDBOX/x.py" | "$HOOKS/format-on-write.sh"
check "always exits 0 (formatting never blocks)" $? 0
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$SANDBOX/does-not-exist.py" | "$HOOKS/format-on-write.sh"
check "nonexistent file_path -> exit 0" $? 0
mkdir -p "$SANDBOX/.claude/hooks"
cp "$HOOKS/format-on-write.sh" "$SANDBOX/.claude/hooks/format-on-write.sh"
chmod +x "$SANDBOX/.claude/hooks/format-on-write.sh"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$SANDBOX/x.py" | "$HOOKS/format-on-write.sh"
check "plugin copy exits 0 when repo copy exists (self-gate)" $? 0
rm -rf "$SANDBOX/.claude/hooks"

echo "# gate-path speed (<100ms budget; must be fast, Stop fires every session)"
EMPTY=$(mktemp -d)
START=$(python3 -c 'import time; print(int(time.time()*1000))')
i=0; while [ $i -lt 10 ]; do printf '{}' | CLAUDE_PROJECT_DIR="$EMPTY" "$HOOKS/loop-checkpoint.sh"; i=$((i+1)); done
END=$(python3 -c 'import time; print(int(time.time()*1000))')
PER=$(( (END - START) / 10 ))
if [ "$PER" -lt 100 ]; then ok "gated Stop hook ~${PER}ms per call" ; else bad "gated Stop hook too slow: ${PER}ms"; fi
rm -rf "$EMPTY"

echo
echo "hook tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
