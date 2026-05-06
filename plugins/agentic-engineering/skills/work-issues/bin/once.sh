#!/usr/bin/env bash
# work-issues one-shot: run Claude Code a single time against the issues/
# queue. Use this for an interactive supervised pass; use loop.sh for AFK.
#
# Env overrides: same as loop.sh (WORK_ISSUES_CMD, WORK_ISSUES_PROMPT,
# WORK_ISSUES_DIR, WORK_ISSUES_COMMIT_LOG). Defaults to interactive
# `claude --permission-mode acceptEdits`.
#
# Exit codes:
#   0  claude ran (its own exit code is forwarded)
#   1  bad arguments / missing prompt
#   2  missing dependency
set -eo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  awk '/^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(dirname "$script_dir")"

cmd="${WORK_ISSUES_CMD:-claude --permission-mode acceptEdits}"
prompt_file="${WORK_ISSUES_PROMPT:-$skill_dir/SKILL.md}"
issues_dir="${WORK_ISSUES_DIR:-issues}"
commit_log="${WORK_ISSUES_COMMIT_LOG:-5}"

for dep in git; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Error: required dependency not found in PATH: $dep" >&2
    exit 2
  fi
done
if ! command -v "${cmd%% *}" >/dev/null 2>&1; then
  echo "Error: claude command not found: ${cmd%% *}" >&2
  echo "Set WORK_ISSUES_CMD to override." >&2
  exit 2
fi

if [[ ! -f "$prompt_file" ]]; then
  echo "Error: prompt file not found: $prompt_file" >&2
  exit 1
fi

strip_frontmatter() {
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { in_fm=0; next }
    in_fm { next }
    { print }
  ' "$1"
}

commits=$(git log -n "$commit_log" --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")
if compgen -G "$issues_dir/*.md" > /dev/null; then
  issues=$(cat "$issues_dir"/*.md)
else
  issues="No issues found in $issues_dir"
fi
prompt=$(strip_frontmatter "$prompt_file")

exec $cmd "Previous commits: $commits Issues: $issues $prompt"
