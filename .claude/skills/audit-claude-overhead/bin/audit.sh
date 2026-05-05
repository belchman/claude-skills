#!/usr/bin/env bash
# audit-claude-overhead — score a Claude Code setup against the nine
# token-waste patterns. Inspects:
#   - Global  ~/.claude/        (settings, hooks, CLAUDE.md, ad-hoc skills)
#   - Project ./.claude/        (same, scoped to current repo)
#   - Plugin scope (the big one): ~/.claude/plugins/installed_plugins.json
#                                 cross-referenced with .enabledPlugins from
#                                 ~/.claude/settings.json
# Read-only — does not modify anything.
#
# Usage: ./bin/audit.sh
#
# Exit codes:
#   0  audit completed (regardless of how many patterns over threshold)
#   2  jq not installed
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq (mac) or apt install jq (linux)" >&2
  exit 2
fi

GLOBAL_DIR="${HOME}/.claude"
PROJECT_DIR="./.claude"
PLUGINS_DB="$GLOBAL_DIR/plugins/installed_plugins.json"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }
over() { printf "  \033[31mOVER\033[0m %s\n" "$*"; }
dim()  { printf "  \033[2m%s\033[0m\n" "$*"; }

words_to_tokens() { awk -v w="$1" 'BEGIN{ printf "%d", w * 1.25 }'; }

count_words() {
  local f="$1"
  [[ -f "$f" ]] || { echo 0; return; }
  wc -w < "$f" | tr -d ' '
}

count_jq_array() {
  local f="$1" expr="$2"
  [[ -f "$f" ]] || { echo 0; return; }
  jq -r "($expr // []) | length" "$f" 2>/dev/null || echo 0
}

count_jq_keys() {
  local f="$1" expr="$2"
  [[ -f "$f" ]] || { echo 0; return; }
  jq -r "($expr // {}) | keys | length" "$f" 2>/dev/null || echo 0
}

# Get install paths for plugins enabled in user settings.json.
enabled_plugin_paths() {
  [[ -f "$GLOBAL_DIR/settings.json" && -f "$PLUGINS_DB" ]] || return 0
  local enabled
  enabled=$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value==true) | .key' "$GLOBAL_DIR/settings.json" 2>/dev/null) || return 0
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    jq -r --arg p "$p" '.plugins[$p][]? | .installPath' "$PLUGINS_DB" 2>/dev/null
  done <<< "$enabled" | sort -u
}

# Count distinct skill *names* in a plugin install path. Plugins often ship
# the same skill under .claude/skills/, .opencode/skills/, claude-plugin/skills/
# — only one runtime is loaded, so dedupe by parent directory name.
count_unique_skills_in_plugin() {
  local install_path="$1"
  [[ -d "$install_path" ]] || { echo 0; return; }
  find "$install_path" -name SKILL.md 2>/dev/null \
    | sed 's|/SKILL\.md$||' \
    | awk -F/ '{print $NF}' \
    | sort -u \
    | wc -l \
    | tr -d ' '
}

bold "=== audit-claude-overhead ==="
echo "Global  : $GLOBAL_DIR"
echo "Project : $PROJECT_DIR"
echo "Plugins : $PLUGINS_DB"
echo

# ── Pattern 1: CLAUDE.md bloat ──────────────────────────────────────────────
bold "1. CLAUDE.md bloat (target combined < 1,500 tokens / ~1,200 words)"
g_words=$(count_words "$GLOBAL_DIR/CLAUDE.md")
p_words=$(count_words "$PROJECT_DIR/CLAUDE.md")
combined=$((g_words + p_words))
combined_tok=$(words_to_tokens "$combined")
echo "  global  : $g_words words ($(words_to_tokens "$g_words") tokens)"
echo "  project : $p_words words ($(words_to_tokens "$p_words") tokens)"
echo "  combined: $combined words (~$combined_tok tokens)"
if (( combined > 1200 )); then
  over "combined > 1,200 words — extract to project-level / skills, drop dead rules"
else
  ok "within target"
fi
echo

# ── Pattern 3: UserPromptSubmit hooks ───────────────────────────────────────
bold "3. UserPromptSubmit hooks (target ≤ 1 justified hook)"
g_ups=$(count_jq_array "$GLOBAL_DIR/settings.json" ".hooks.UserPromptSubmit")
p_ups=$(count_jq_array "$PROJECT_DIR/settings.json" ".hooks.UserPromptSubmit")
total_ups=$((g_ups + p_ups))
echo "  global : $g_ups hook entries"
echo "  project: $p_ups hook entries"
if (( total_ups > 1 )); then
  over "$total_ups UserPromptSubmit hooks total — audit each, kill what's not load-bearing"
  jq -r '.hooks.UserPromptSubmit // [] | .[] | "    - " + (.command // .matcher // (. | tostring))' "$GLOBAL_DIR/settings.json" 2>/dev/null || true
  jq -r '.hooks.UserPromptSubmit // [] | .[] | "    - " + (.command // .matcher // (. | tostring))' "$PROJECT_DIR/settings.json" 2>/dev/null || true
else
  ok "within target"
fi
echo

# ── Pattern 9: SessionStart hook noise ──────────────────────────────────────
bold "9. SessionStart hooks (kill announcement-only entries)"
g_ss=$(count_jq_array "$GLOBAL_DIR/settings.json" ".hooks.SessionStart")
p_ss=$(count_jq_array "$PROJECT_DIR/settings.json" ".hooks.SessionStart")
echo "  global : $g_ss hook entries"
echo "  project: $p_ss hook entries"
total_ss=$((g_ss + p_ss))
if (( total_ss > 2 )); then
  warn "$total_ss SessionStart hooks — review for 'loaded successfully' style noise"
  jq -r '.hooks.SessionStart // [] | .[] | "    - " + (.command // .matcher // (. | tostring))' "$GLOBAL_DIR/settings.json" 2>/dev/null || true
  jq -r '.hooks.SessionStart // [] | .[] | "    - " + (.command // .matcher // (. | tostring))' "$PROJECT_DIR/settings.json" 2>/dev/null || true
else
  ok "within target"
fi
echo

# ── Pattern 5: skill bloat (LOCAL + PLUGIN scope) ───────────────────────────
bold "5. Skill inventory (local + plugin-provided)"
g_local=$(ls -1 "$GLOBAL_DIR/skills" 2>/dev/null | wc -l | tr -d ' ')
p_local=$(ls -1 "$PROJECT_DIR/skills" 2>/dev/null | wc -l | tr -d ' ')
echo "  ad-hoc skills (~/.claude/skills/) : $g_local"
echo "  ad-hoc skills (./.claude/skills/) : $p_local"

plugin_skill_total=0
plugin_skill_breakdown=""
while IFS= read -r install_path; do
  [[ -n "$install_path" && -d "$install_path" ]] || continue
  n=$(count_unique_skills_in_plugin "$install_path")
  if (( n > 0 )); then
    name=$(basename "$(dirname "$install_path")")  # e.g. superpowers
    plugin_skill_breakdown+="    - $name: $n skills"$'\n'
    plugin_skill_total=$((plugin_skill_total + n))
  fi
done < <(enabled_plugin_paths)

echo "  plugin-provided (enabled plugins) : $plugin_skill_total"
if [[ -n "$plugin_skill_breakdown" ]]; then
  printf "%s" "$plugin_skill_breakdown"
fi

total_skills=$((g_local + p_local + plugin_skill_total))
echo "  ────"
echo "  TOTAL skills addressable to the orchestrator: $total_skills"
# Thresholds: ad-hoc skills should be ≤5; plugin skills are bundled so a
# soft threshold of 30 total is realistic.
if (( g_local + p_local > 5 )); then
  over "ad-hoc skills > 5 — disable any not invoked in the last 7 days"
fi
if (( total_skills > 30 )); then
  over "total skills > 30 — each adds description tokens to the orchestrator's matching pool; disable plugins you don't reach for weekly"
elif (( total_skills > 15 )); then
  warn "total skills > 15 — review whether every enabled plugin earns its keep"
else
  ok "skill count within healthy range"
fi
echo

# ── Pattern 6: MCP servers (settings + plugin-bundled) ──────────────────────
bold "6. MCP servers (target ≤ 3 always-on)"
g_mcp=$(count_jq_keys "$GLOBAL_DIR/settings.json" ".mcpServers")
p_mcp=$(count_jq_keys "$PROJECT_DIR/settings.json" ".mcpServers")
echo "  global  settings.json : $g_mcp MCP servers"
echo "  project settings.json : $p_mcp MCP servers"

plugin_mcp_total=0
while IFS= read -r install_path; do
  [[ -n "$install_path" && -d "$install_path" ]] || continue
  while IFS= read -r mf; do
    [[ -f "$mf" ]] || continue
    n=$(jq -r '(.mcpServers // {}) | keys | length' "$mf" 2>/dev/null || echo 0)
    plugin_mcp_total=$((plugin_mcp_total + n))
  done < <(find "$install_path" \( -name '.mcp.json' -o -name 'plugin.json' -o -name 'manifest.json' \) 2>/dev/null)
done < <(enabled_plugin_paths)
echo "  plugin-bundled MCPs   : $plugin_mcp_total"

total_mcp=$((g_mcp + p_mcp + plugin_mcp_total))
echo "  ────"
echo "  TOTAL always-on MCPs  : $total_mcp"
if (( total_mcp > 3 )); then
  over "$total_mcp always-on MCPs — keep 3 daily; disable plugins shipping unused MCPs"
  if (( g_mcp + p_mcp > 0 )); then
    jq -r '(.mcpServers // {}) | keys[] | "    - settings: " + .' "$GLOBAL_DIR/settings.json" 2>/dev/null || true
    jq -r '(.mcpServers // {}) | keys[] | "    - settings: " + .' "$PROJECT_DIR/settings.json" 2>/dev/null || true
  fi
else
  ok "within target"
fi
echo

# ── Pattern 7: extended thinking / effort level ─────────────────────────────
bold "7. Effort level / autoDream (extended thinking proxy)"
effort=$(jq -r '.effortLevel // "unset"' "$GLOBAL_DIR/settings.json" 2>/dev/null || echo "unset")
auto_dream=$(jq -r '.autoDreamEnabled // false' "$GLOBAL_DIR/settings.json" 2>/dev/null || echo "false")
echo "  effortLevel       : $effort"
echo "  autoDreamEnabled  : $auto_dream"
if [[ "$effort" == "high" ]]; then
  over "effortLevel=high burns extended thinking by default — set to 'medium' or 'low' globally; toggle per-task"
elif [[ "$effort" == "medium" ]]; then
  warn "effortLevel=medium — fine for most work; consider 'low' if you mostly do simple tasks"
else
  ok "low or unset"
fi
if [[ "$auto_dream" == "true" ]]; then
  warn "autoDreamEnabled=true — verify this matches how you actually work"
fi
echo

# ── Pattern 4: cache TTL ────────────────────────────────────────────────────
bold "4. Prompt cache TTL"
cache_setting=$(jq -r '.promptCacheTtl // .cacheControl // "unset"' "$GLOBAL_DIR/settings.json" 2>/dev/null || echo "unset")
echo "  setting: $cache_setting (Anthropic default 5m if unset)"
if [[ "$cache_setting" == "unset" || "$cache_setting" == "5m" ]]; then
  warn "5-minute default — every break > 5 min recomputes system prompt + CLAUDE.md + tools"
  dim "Fix: upgrade to 1h cache on paid plans, or ping before breaks"
else
  ok "non-default cache TTL set"
fi
echo

# ── Pattern 2 + 8: behavioral (no automatic check) ──────────────────────────
bold "2 & 8. Behavioral patterns (no automatic check)"
warn "Pattern 2: cap chats at ~20 messages; use /compact (not /clear) when continuity matters"
warn "Pattern 8: train Cmd+. (Mac) / Ctrl+. to kill wrong-direction generation in <5s; Esc-Esc for checkpoint rewind"
echo

# ── Recent token usage (best-effort) ────────────────────────────────────────
bold "Recent input tokens / prompt (last 7 days, if logs present)"
log_dir="$GLOBAL_DIR/logs"
if [[ -d "$log_dir" ]] && find "$log_dir" -mtime -7 -name "*.log" -print -quit 2>/dev/null | grep -q .; then
  find "$log_dir" -mtime -7 -name "*.log" -exec cat {} + 2>/dev/null \
    | grep -oE 'input_tokens["[:space:]]*:[[:space:]]*[0-9]+' \
    | grep -oE '[0-9]+$' \
    | awk '{ sum += $1; n++ } END { if (n) printf "  avg: %d tokens over %d prompts\n", sum/n, n; else print "  no parseable token counts in logs" }'
else
  warn "no logs in $log_dir from the last 7 days — skipping average"
fi
echo

bold "=== done ==="
echo "Re-read each OVER line above. For each, see patterns.md for the 30-second fix."
echo "Apply fixes one pattern at a time; re-run this script to confirm the metric moved."
