#!/usr/bin/env bash
# work-issues loop: run Claude Code repeatedly against an issues/ queue until
# it signals completion, hits the iteration cap, or a STOP sentinel appears.
#
# Usage: loop.sh [iterations]
#   iterations  max number of Claude runs (default: 10, range: 1-1000)
#
# Env overrides:
#   WORK_ISSUES_CMD          command used to launch Claude (default: "claude")
#   WORK_ISSUES_PROMPT       path to SKILL.md (default: ../SKILL.md next to script)
#   WORK_ISSUES_DIR          issues directory (default: issues)
#   WORK_ISSUES_COMMIT_LOG   recent commits to include (default: 5)
#   WORK_ISSUES_STOP_FILE    sentinel path (default: <script_dir>/STOP)
#
# Stop conditions (whichever comes first):
#   - Claude's final result contains "<promise>NO MORE TASKS</promise>"
#   - The STOP sentinel file exists (touch it to halt between iterations)
#   - Iteration cap reached
#
# Exit codes:
#   0  loop completed (sentinel, NO MORE TASKS, or cap hit)
#   1  bad arguments
#   2  missing dependency (claude, jq, git)
#   3  claude exited non-zero on an iteration
set -eo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  awk '/^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
  exit 0
fi

iterations="${1:-10}"
if ! [[ "$iterations" =~ ^[0-9]+$ ]] || (( iterations < 1 || iterations > 1000 )); then
  echo "Error: iterations must be an integer in 1..1000 (got: $iterations)" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(dirname "$script_dir")"

cmd="${WORK_ISSUES_CMD:-claude}"
prompt_file="${WORK_ISSUES_PROMPT:-$skill_dir/SKILL.md}"
issues_dir="${WORK_ISSUES_DIR:-issues}"
commit_log="${WORK_ISSUES_COMMIT_LOG:-5}"
stop_file="${WORK_ISSUES_STOP_FILE:-$script_dir/STOP}"

for dep in jq git; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Error: required dependency not found in PATH: $dep" >&2
    exit 2
  fi
done
# Validate the claude command (first word only, in case user set flags).
if ! command -v "${cmd%% *}" >/dev/null 2>&1; then
  echo "Error: claude command not found: ${cmd%% *}" >&2
  echo "Set WORK_ISSUES_CMD to override." >&2
  exit 2
fi

if [[ ! -f "$prompt_file" ]]; then
  echo "Error: prompt file not found: $prompt_file" >&2
  exit 1
fi

# Strip YAML frontmatter from SKILL.md so the body is usable as a raw prompt.
strip_frontmatter() {
  awk '
    BEGIN { in_fm=0; done_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { in_fm=0; done_fm=1; next }
    in_fm { next }
    { print }
  ' "$1"
}

prompt=$(strip_frontmatter "$prompt_file")

stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
final_result='select(.type == "result").result // empty'

cleanup_tmp() { [[ -n "${tmpfile:-}" && -f "$tmpfile" ]] && rm -f "$tmpfile"; }
trap cleanup_tmp EXIT INT TERM

for (( i=1; i<=iterations; i++ )); do
  if [[ -f "$stop_file" ]]; then
    echo "work-issues: STOP sentinel present ($stop_file) — halting before iteration $i."
    exit 0
  fi

  echo "=== work-issues iteration $i / $iterations ==="

  tmpfile=$(mktemp)

  commits=$(git log -n "$commit_log" --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")
  if compgen -G "$issues_dir/*.md" > /dev/null; then
    issues=$(cat "$issues_dir"/*.md)
  else
    issues="No issues found in $issues_dir"
  fi

  set +e
  $cmd \
    --verbose \
    --print \
    --output-format stream-json \
    "Previous commits: $commits Issues: $issues $prompt" \
    | grep --line-buffered '^{' \
    | tee "$tmpfile" \
    | jq --unbuffered -rj "$stream_text"
  status=${PIPESTATUS[0]}
  set -e

  if (( status != 0 )); then
    echo "work-issues: claude exited with status $status on iteration $i — stopping." >&2
    exit 3
  fi

  result=$(jq -r "$final_result" "$tmpfile")
  rm -f "$tmpfile"
  tmpfile=""

  if [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]; then
    echo "work-issues: queue drained after $i iteration(s)."
    exit 0
  fi
done

echo "work-issues: iteration cap ($iterations) reached without completion signal."
