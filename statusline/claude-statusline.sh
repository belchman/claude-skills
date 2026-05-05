#!/usr/bin/env bash
# ~/.claude/statusline.sh — two-line Claude Code statusline.
# Reads JSON from stdin (schema: https://code.claude.com/docs/en/statusline).
#
# Line 1: [model] dir@branch | effort | (warnings)
# Line 2: [bar] ctx% | turn ↓in ↑out (cache) | session ↓In ↑Out | $cost
#
# All field accesses use `// fallback` to handle nulls (current_usage is null
# before the first API call and after /compact).
set -euo pipefail

INPUT=$(cat)

# --- helpers ----------------------------------------------------------------
fmt_tok() {
  # 8500 → 8.5K, 1200000 → 1.2M, 0 → 0
  awk -v n="${1:-0}" 'BEGIN{
    if (n >= 1000000) printf "%.1fM", n/1000000;
    else if (n >= 1000) printf "%.1fK", n/1000;
    else printf "%d", n;
  }'
}

color_pct() {
  local p="${1:-0}"
  if   (( p >= 90 )); then printf "\033[31m%s%%\033[0m" "$p"
  elif (( p >= 70 )); then printf "\033[33m%s%%\033[0m" "$p"
  else                    printf "\033[32m%s%%\033[0m" "$p"
  fi
}

bar() {
  local p="${1:-0}" w=10
  local filled=$(( p * w / 100 ))
  (( filled > w )) && filled=$w
  local empty=$(( w - filled ))
  local b=""
  (( filled > 0 )) && b=$(printf '█%.0s' $(seq 1 $filled))
  (( empty  > 0 )) && b="${b}$(printf '░%.0s' $(seq 1 $empty))"
  printf '%s' "$b"
}

# --- extract ----------------------------------------------------------------
MODEL=$(jq -r '.model.display_name // "?"' <<<"$INPUT")
DIR=$(jq -r '.workspace.current_dir // .cwd // "?"' <<<"$INPUT")
DIR_SHORT="${DIR##*/}"
WORKTREE=$(jq -r '.workspace.git_worktree // empty' <<<"$INPUT")
BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null || echo "")
LOC="$DIR_SHORT"
[[ -n "$BRANCH"   ]] && LOC="$LOC@$BRANCH"
[[ -n "$WORKTREE" ]] && LOC="$LOC (wt:$WORKTREE)"

EFFORT=$(jq -r '.effort.level // empty' <<<"$INPUT")
THINKING=$(jq -r '.thinking.enabled // false' <<<"$INPUT")

PCT=$(jq -r '.context_window.used_percentage // 0' <<<"$INPUT" | cut -d. -f1)
CTX_BAR=$(bar "$PCT")
CTX_LABEL=$(color_pct "$PCT")

TURN_IN=$(jq -r '.context_window.current_usage.input_tokens // 0' <<<"$INPUT")
TURN_OUT=$(jq -r '.context_window.current_usage.output_tokens // 0' <<<"$INPUT")
CACHE_R=$(jq -r '.context_window.current_usage.cache_read_input_tokens // 0' <<<"$INPUT")
CACHE_W=$(jq -r '.context_window.current_usage.cache_creation_input_tokens // 0' <<<"$INPUT")
SESS_IN=$(jq -r '.context_window.total_input_tokens // 0' <<<"$INPUT")
SESS_OUT=$(jq -r '.context_window.total_output_tokens // 0' <<<"$INPUT")

COST=$(jq -r '.cost.total_cost_usd // 0' <<<"$INPUT")

# rate limits (Pro/Max only — absent otherwise)
RL5=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$INPUT")
RL7=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$INPUT")

# --- compose ----------------------------------------------------------------
LINE1="\033[1m[$MODEL]\033[0m $LOC"
[[ -n "$EFFORT"     ]] && LINE1="$LINE1 | effort:$EFFORT"
[[ "$THINKING" == "true" ]] && LINE1="$LINE1 \033[36m+thinking\033[0m"

# Cache info (only show when meaningful, i.e. after first API call)
CACHE_STR=""
if (( CACHE_R + CACHE_W > 0 )); then
  CACHE_STR=" \033[2m(cache r:$(fmt_tok "$CACHE_R") w:$(fmt_tok "$CACHE_W"))\033[0m"
fi

LINE2="$CTX_BAR $CTX_LABEL"
LINE2="$LINE2 | turn ↓$(fmt_tok "$TURN_IN") ↑$(fmt_tok "$TURN_OUT")$CACHE_STR"
LINE2="$LINE2 | sess ↓$(fmt_tok "$SESS_IN") ↑$(fmt_tok "$SESS_OUT")"
LINE2="$LINE2 | \$$(printf '%.4f' "$COST")"

# Optional 3rd line for rate limits, only if Pro/Max data is present
LINE3=""
if [[ -n "$RL5" || -n "$RL7" ]]; then
  L=""
  [[ -n "$RL5" ]] && L="$L 5h:${RL5%.*}%"
  [[ -n "$RL7" ]] && L="$L 7d:${RL7%.*}%"
  LINE3="\033[2m⟳$L\033[0m"
fi

printf "%b\n" "$LINE1"
printf "%b\n" "$LINE2"
[[ -n "$LINE3" ]] && printf "%b\n" "$LINE3"
