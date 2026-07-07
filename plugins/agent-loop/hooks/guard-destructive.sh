#!/bin/sh
# guard-destructive.sh — agent-loop PreToolUse hook (matcher: Bash|Edit|Write).
# Denies (exit 2 + permissionDecision "deny"):
#   - recursive+force rm (any flag order) on any absolute path, ~/$HOME
#     paths, parent dirs (..), the cwd (. ./ ./*) or a bare glob (*) —
#     quoted targets included; rm --no-preserve-root, git clean -f*,
#     find -delete, git push --force/-f (--force-with-lease passes),
#     git reset --hard
#   - git commit / git push entirely when AGENT_LOOP_EVAL=1 (eval no-commit rule)
#   - Edit/Write to the goal contract (GOAL.md/goal.json/state.json) while a
#     run is in progress — the loop may not rewrite its own contract; state
#     changes go through al-state. Raw `al-json set/append/del/merge` on the
#     same files is the equivalent Bash-shaped bypass and is denied mid-run
#     too. Human override for both: GOAL_STATE_WRITE=1.
# Self-gates: exits 0 instantly when the repo has no .claude/agent-loop/, or
# when a repo-owned copy of this script exists (repo copy wins; hooks from
# different paths are NOT deduplicated by Claude Code — dedup is by identical
# command string [hooks docs]).
set -u

AL_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/agent-loop"
[ -d "$AL_DIR" ] || [ "${AGENT_LOOP_EVAL:-0}" = "1" ] || exit 0

# plugin-copy self-gate: skip when the repo owns a copy (unless we ARE it).
# Identity is by inode: -ef is not POSIX but is supported by bash/dash/zsh/
# BusyBox `[` — a plain string compare of $0 is defeated by relative
# invocation. If -ef errors on an exotic shell, fall back to comparing
# canonicalized paths.
REPO_COPY="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/guard-destructive.sh"
if [ -f "$REPO_COPY" ] && ! [ "$0" -ef "$REPO_COPY" ] 2>/dev/null; then
  SELF_CANON="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)/$(basename "$0")"
  COPY_CANON="$(cd "$(dirname "$REPO_COPY")" 2>/dev/null && pwd -P)/$(basename "$REPO_COPY")"
  [ "$SELF_CANON" = "$COPY_CANON" ] || exit 0
fi

# Parse stdin with the al-json shim when one is reachable (grep truncates at
# the first escaped quote — a verified deny bypass). Fallback order: the
# plugin's own bin/, then PATH; with no shim at all, degrade to the old grep
# extraction (better than failing closed on every Bash call).
INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

ALJSON=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "$CLAUDE_PLUGIN_ROOT/bin/al-json" ]; then
  ALJSON="$CLAUDE_PLUGIN_ROOT/bin/al-json"
elif [ -x "$(dirname "$0")/../bin/al-json" ]; then
  ALJSON="$(dirname "$0")/../bin/al-json"       # plugin layout
elif command -v al-json >/dev/null 2>&1; then
  ALJSON=$(command -v al-json)                  # repo copies at .claude/hooks/
fi

deny() { # $1=reason
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 2
}

# Field extraction: shim when available (parsing fidelity), grep otherwise
# (coarse; truncates at escaped quotes — degraded but fail-open).
if [ -n "$ALJSON" ]; then
  TOOL=$("$ALJSON" get "$INPUT_FILE" tool_name 2>/dev/null || echo "")
  CMD=$("$ALJSON" get "$INPUT_FILE" tool_input.command 2>/dev/null || echo "")
  FILE=$("$ALJSON" get "$INPUT_FILE" tool_input.file_path 2>/dev/null || echo "")
else
  TOOL=$(grep -o '"tool_name" *: *"[^"]*"' "$INPUT_FILE" | head -1 | sed 's/.*: *"//; s/"$//')
  CMD=$(grep -o '"command" *: *"[^"]*' "$INPUT_FILE" | head -1 | sed 's/.*: *"//')
  FILE=$(grep -o '"file_path" *: *"[^"]*"' "$INPUT_FILE" | head -1 | sed 's/.*: *"//; s/"$//')
fi

has() { printf '%s' "$CMD" | grep -Eq "$1"; }
run_active() {
  [ -f "$AL_DIR/state.json" ] && grep -q '"run_in_progress" *: *true' "$AL_DIR/state.json"
}

# rm target arm: absolute paths (incl. /* and /etc/x), ~..., $HOME..., parent
# dirs (../...), cwd (. ./ ./*), bare glob — allowing quote-wrapped targets
# ("$HOME/x", '/etc/x'). Deliberately NOT matched: repo-relative subpaths
# (build/, ./build) — those are the loop's legitimate workspace.
RM_TGT="([[:space:]]|[\"'=])((/|~|\\\$HOME|\\.\\.)[^[:space:]\"']*|\\./?|\\./\\*|\\*)[\"']*([[:space:]]|\$)"

case "$TOOL" in
  Bash)
    # rm with recursive+force in ANY flag order (-rf, -fr, -r -f, -Rf,
    # --recursive --force) targeting an absolute path, ~, $HOME, ., ..,
    # *, ./ or ./* — see RM_TGT above for the exact target arm
    if has '(^|[;&|[:space:]])rm[[:space:]]'; then
      if has '(^|[[:space:]])--no-preserve-root([[:space:]]|$)'; then
        deny "agent-loop guard: rm --no-preserve-root is blocked"
      fi
      if { has '(^|[[:space:]])-[[:alnum:]]*([rR][[:alnum:]]*f|f[[:alnum:]]*[rR])' || \
           { has '(^|[[:space:]])(-[[:alnum:]]*[rR]|--recursive)([[:space:]]|$)' && \
             has '(^|[[:space:]])(-[[:alnum:]]*f|--force)([[:space:]]|$)'; }; } && \
         has "$RM_TGT"; then
        deny "agent-loop guard: recursive+force rm on an absolute/home/parent/cwd path is blocked"
      fi
    fi
    # Raw al-json writes to the loop's contract files are the Bash-shaped
    # bypass of every al-state gate — deny them mid-run exactly like
    # Edit/Write on the same files (al-state itself is not affected: hooks
    # fire on the model's Bash call, not on al-state's internal subprocesses)
    if has '(^|[;&|[:space:]/])al-json[[:space:]]+(set|append|del|merge)[[:space:]]' && \
       has 'agent-loop/(GOAL\.md|goal\.json|state\.json)' && \
       run_active && [ "${GOAL_STATE_WRITE:-0}" != "1" ]; then
      deny "agent-loop guard: raw al-json writes to goal/state mid-run are blocked — use al-state"
    fi
    if has '(^|[;&|[:space:]])git[[:space:]]+clean[[:space:]][^;|&]*-[[:alnum:]]*f'; then
      deny "agent-loop guard: git clean -f is blocked"
    fi
    if has '(^|[;&|[:space:]])find[[:space:]][^;|&]*-delete'; then
      deny "agent-loop guard: find -delete is blocked"
    fi
    # --force-with-lease is the SAFE force-push: allow it through this deny
    if ! has 'git[[:space:]]+push[^;|&]*--force-with-lease'; then
      if has 'git[[:space:]]+push[^;|&]*(--force|[[:space:]]-f)([[:space:]]|$)'; then
        deny "agent-loop guard: force-push is blocked (use --force-with-lease)"
      fi
    fi
    case "$CMD" in
      *"git reset --hard"*)
        deny "agent-loop guard: git reset --hard is blocked" ;;
    esac
    if [ "${AGENT_LOOP_EVAL:-0}" = "1" ]; then
      case "$CMD" in
        *"git commit"*|*"git push"*)
          deny "agent-loop eval: commits/pushes are forbidden during eval runs" ;;
      esac
    fi
    ;;
  Edit|Write)
    case "$FILE" in
      */.claude/agent-loop/GOAL.md|*/.claude/agent-loop/goal.json|*/.claude/agent-loop/state.json)
        if run_active && [ "${GOAL_STATE_WRITE:-0}" != "1" ]; then
          deny "agent-loop guard: the loop may not edit its own contract/state mid-run — use al-state"
        fi
        ;;
    esac
    ;;
esac

exit 0
