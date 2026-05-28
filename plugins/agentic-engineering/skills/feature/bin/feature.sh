#!/usr/bin/env bash
# /feature orchestrator — runs the 7-agent factory chain end-to-end with
# three human checkpoints. See plugins/agentic-engineering/skills/feature/SKILL.md
# and docs/plans/feature-factory.md §A,F,G for the full design.
#
# Subcommands
#   feature.sh start <brief>                   begin a new run; exits at CP1
#   feature.sh continue <id> [--accept]        resume from last completed step
#   feature.sh continue <id> --redo "<text>"   re-run last step with feedback
#   feature.sh abort <id>                      mark a run aborted; release lock
#   feature.sh status <id>                     print state.json in human form
#   feature.sh help                            print this usage
#
# Env overrides (testing)
#   CLAUDE_CMD       command to invoke claude  (default: claude; supports flags
#                    when set as a space-separated string, e.g. "claude --model sonnet-4.7")
#   LOOP_SH_CMD      command to invoke loop.sh (default: ../../work-issues/bin/loop.sh)
#   FEATURE_RUNS_DIR root of run state         (default: <repo>/.feature_runs)
#   FEATURE_REDO_FEEDBACK
#                    set internally by `continue --redo`; step functions
#                    prepend this to their prompt when non-empty
#
# Exit codes
#   0  success
#   1  bad arguments / state-machine error
#   2  missing dependency
#   3  child dispatch failure
set -uo pipefail

# ---- bootstrap ------------------------------------------------------------

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./feature-helpers.sh
source "$script_dir/feature-helpers.sh"

repo_root="${FEATURE_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
runs_dir="${FEATURE_RUNS_DIR:-$repo_root/.feature_runs}"
# CLAUDE_CMD may contain flags; parse as array (matches loop.sh's pattern).
if [[ -n "${CLAUDE_CMD:-}" ]]; then
  # shellcheck disable=SC2206
  claude_cmd=(${CLAUDE_CMD})
else
  claude_cmd=(claude)
fi
loop_sh_cmd="${LOOP_SH_CMD:-$script_dir/../../work-issues/bin/loop.sh}"

# Resolve a per-step claude command. Precedence: CLAUDE_CMD_<STEP> → CLAUDE_CMD → claude.
# Recognized override env vars: CLAUDE_CMD_RESEARCH, CLAUDE_CMD_STORY,
# CLAUDE_CMD_SPEC, CLAUDE_CMD_RUBRIC, CLAUDE_CMD_VALIDATOR. Sets the global
# `step_cmd` array.
resolve_step_cmd() {
  local step="$1"
  local var="CLAUDE_CMD_${step}"
  local override="${!var:-}"
  if [[ -n "$override" ]]; then
    # shellcheck disable=SC2206
    step_cmd=(${override})
  elif [[ -n "${CLAUDE_CMD:-}" ]]; then
    # shellcheck disable=SC2206
    step_cmd=(${CLAUDE_CMD})
  else
    step_cmd=(claude)
  fi
}

# True (rc=0) if the per-step override does NOT already specify --effort,
# meaning the orchestrator should append its `--effort low` default. Only
# meaningful for RESEARCH and STORY steps; other steps never get the default.
step_override_has_effort() {
  local step="$1"
  local var="CLAUDE_CMD_${step}"
  local override="${!var:-}"
  [[ "$override" == *"--effort"* ]]
}

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

slugify() {
  local raw="$1"
  printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-40
}

# Normalize a lane label to lowercase for use in state markers, filenames,
# and case-statement matching. The spec H3 ("### Backend") is case-sensitive
# for the parser; this script only uses the lowercase form internally.
lane_normalize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

next_id() {
  # 4-digit numeric prefix + slug. Includes .aborted / .done dirs in the
  # max-prefix calculation so numbering doesn't collide post-abort.
  local slug="$1" max=0 existing
  if [[ -d "$runs_dir" ]]; then
    while IFS= read -r existing; do
      existing="$(basename "$existing")"
      local n="${existing%%-*}"
      if [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n > max )); then
        max=$((10#$n))
      fi
    done < <(find "$runs_dir" -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null)
  fi
  printf '%04d-%s' "$((max + 1))" "$slug"
}

# ---- subcommands ----------------------------------------------------------

cmd_help() {
  awk '/^# / {sub(/^# ?/, ""); print; next} /^[^#]/ {exit}' "${BASH_SOURCE[0]}"
}

require_id() {
  local id="$1"
  if [[ -z "$id" ]]; then
    echo "feature.sh: <id> required" >&2
    return 1
  fi
}

cmd_status() {
  local id="${1:-}"
  require_id "$id" || return 1
  local run_dir="$runs_dir/$id"
  local state="$run_dir/state.json"
  if [[ ! -f "$state" ]]; then
    echo "feature.sh status: no run found at $run_dir" >&2
    return 1
  fi
  echo "Run: $id"
  echo "Directory: $run_dir"
  for k in id last_completed_step started_at updated_at brief_path issue_path research_path spec_path rubric_path validator_findings; do
    local v
    v=$(state_field "$state" "$k")
    [[ -n "$v" ]] && printf "  %-22s %s\n" "$k:" "$v"
  done
  if [[ -f "$run_dir/LOCK" ]]; then
    local pid
    pid=$(cat "$run_dir/LOCK")
    if kill -0 "$pid" 2>/dev/null; then
      echo "  LOCK:                   held by PID $pid (live)"
    else
      echo "  LOCK:                   stale (PID $pid not running)"
    fi
  else
    echo "  LOCK:                   none"
  fi
}

cmd_abort() {
  local id="${1:-}"
  require_id "$id" || return 1
  local run_dir="$runs_dir/$id"
  if [[ ! -d "$run_dir" ]]; then
    echo "feature.sh abort: no run found at $run_dir" >&2
    return 1
  fi
  release_lock "$run_dir/LOCK"
  local target="$runs_dir/$id.aborted"
  if [[ -d "$target" ]]; then
    target="$runs_dir/$id.aborted.$(date +%s)"
  fi
  mv "$run_dir" "$target"
  # Mark the run aborted for any post-mortem `status` calls.
  if [[ -f "$target/state.json" ]]; then
    update_state_step "$target/state.json" "aborted"
  fi
  echo "Run $id aborted. Artifacts at: $target"
}

# Refuse to start if any active run (not .aborted / .done) holds a live LOCK.
refuse_if_active_run_exists() {
  if [[ ! -d "$runs_dir" ]]; then
    return 0
  fi
  local d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    local base
    base="$(basename "$d")"
    # Skip finished / aborted dirs in the active-run scan.
    case "$base" in
      *.aborted|*.aborted.*|*.done) continue ;;
    esac
    local pidfile="$d/LOCK"
    [[ -f "$pidfile" ]] || continue
    local held_pid
    held_pid=$(cat "$pidfile" 2>/dev/null)
    if [[ -n "$held_pid" ]] && kill -0 "$held_pid" 2>/dev/null; then
      echo "feature.sh start: another run is in progress at $d (LOCK held by PID $held_pid)." >&2
      echo "  Run 'feature.sh abort $base' to release it, or wait for it to finish." >&2
      return 1
    fi
  done < <(find "$runs_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  return 0
}

cmd_start() {
  local brief="${1:-}"
  if [[ -z "$brief" ]]; then
    echo "feature.sh start: brief required" >&2
    return 1
  fi
  mkdir -p "$runs_dir"
  refuse_if_active_run_exists || return 1

  local slug id run_dir
  slug=$(slugify "$brief")
  [[ -z "$slug" ]] && slug="feature"
  id=$(next_id "$slug")
  run_dir="$runs_dir/$id"
  mkdir -p "$run_dir"

  acquire_lock "$run_dir/LOCK" "$$" || return 1
  # Release lock on signal so the run dir isn't booby-trapped.
  trap 'release_lock "$run_dir/LOCK"; exit 130' INT TERM

  printf '%s\n' "$brief" > "$run_dir/brief.md"

  local now
  now=$(iso_now)
  # Initial state.json — fields populated incrementally as steps complete.
  # `parent_session_id` is positioned right after `id` (ST-1); empty until
  # the primer dispatch succeeds and we capture the JSON `session_id`.
  state_write_atomic "$run_dir/state.json" "$(cat <<EOF
{
  "id": "$id",
  "parent_session_id": "",
  "brief_path": "$run_dir/brief.md",
  "issue_path": "",
  "research_path": "",
  "spec_path": "",
  "rubric_path": "",
  "lanes": {},
  "validator_findings": "",
  "last_completed_step": "init",
  "started_at": "$now",
  "updated_at": "$now"
}
EOF
)"

  # Primer: one cache-priming dispatch that loads brief.md (and ARCHITECTURE.md
  # when present). Every subsequent prompt-based step forks this session with
  # --resume + --fork-session so it inherits the cached context. See
  # ## Cost optimization in SKILL.md.
  step_primer "$id" "$run_dir"
  local primer_rc=$?
  if (( primer_rc != 0 )); then
    release_lock "$run_dir/LOCK"
    trap - INT TERM
    return 3
  fi

  # Steps 1-3 (refresh map, researcher, story). Each must succeed before the
  # next runs — chain with && so a failure halts the run cleanly.
  step_refresh_map "$id" "$run_dir" && \
    step_researcher "$id" "$run_dir" && \
    step_story      "$id" "$run_dir"
  local chain_rc=$?

  release_lock "$run_dir/LOCK"
  trap - INT TERM

  if (( chain_rc != 0 )); then
    echo "feature.sh start: chain halted before Checkpoint 1 — see $run_dir/*.log; resume with 'feature.sh continue $id --redo \"<feedback>\"' after fixing the cause" >&2
    return 3
  fi

  cat <<EOF

=== CHECKPOINT 1: approve story ===
Run id:     $id
Story:      $(state_field "$run_dir/state.json" issue_path)

To accept and continue:    feature.sh continue $id --accept
To request a redo:         feature.sh continue $id --redo "<feedback>"
To abort:                  feature.sh abort $id
EOF
}

# ---- atomic state writes -------------------------------------------------

# Write json to <path> atomically: write to .tmp first, then rename. Prevents
# the truncate-then-write-fails scenario that wipes state.json.
state_write_atomic() {
  local path="$1" json="$2"
  local tmp="${path}.tmp.$$"
  if command -v jq >/dev/null 2>&1; then
    if ! printf '%s' "$json" | jq . > "$tmp"; then
      rm -f "$tmp"
      echo "state_write_atomic: jq parse failed; $path unchanged" >&2
      return 1
    fi
  else
    printf '%s\n' "$json" > "$tmp"
  fi
  mv -f "$tmp" "$path"
}

# Update a single top-level field via jq, atomically.
state_set_field() {
  local path="$1" key="$2" value="$3"
  local current
  current=$(state_read "$path")
  local tmp="${path}.tmp.$$"
  printf '%s' "$current" \
    | jq --arg k "$key" --arg v "$value" '.[$k] = $v' > "$tmp" && \
    mv -f "$tmp" "$path"
}

update_state_step() {
  local state="$1" step="$2"
  local current
  current=$(state_read "$state")
  local now
  now=$(iso_now)
  local tmp="${state}.tmp.$$"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$current" \
      | jq --arg s "$step" --arg t "$now" \
          '.last_completed_step = $s | .updated_at = $t' > "$tmp" \
      && mv -f "$tmp" "$state"
  else
    # No-jq fallback: sed substitution. Step values are alphanumeric +
    # underscore so they're regex-safe.
    printf '%s' "$current" \
      | sed -E "s|\"last_completed_step\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"last_completed_step\": \"$step\"|" \
      | sed -E "s|\"updated_at\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"updated_at\": \"$now\"|" \
      > "$tmp" \
      && mv -f "$tmp" "$state"
  fi
}

# ---- chain steps ---------------------------------------------------------

# Each step:
#  - reads inputs from state / run_dir
#  - dispatches "${claude_cmd[@]}" -p with the right skill prompt, prepending
#    FEATURE_REDO_FEEDBACK (if set) so --redo feedback actually lands
#  - writes its artifact (file path) and updates state.json atomically
#  - returns 0 on success, non-zero on failure

# Helper: build the prompt for a step, including any --redo feedback prefix.
build_prompt() {
  local body="$1"
  if [[ -n "${FEATURE_REDO_FEEDBACK:-}" ]]; then
    printf '%s\n\n%s\n\n%s\n' \
      "## Feedback from prior iteration (apply this before re-running):" \
      "${FEATURE_REDO_FEEDBACK}" \
      "$body"
  else
    printf '%s\n' "$body"
  fi
}

step_refresh_map() {
  local id="$1" run_dir="$2"
  if [[ -f "$repo_root/ARCHITECTURE.md" ]]; then
    update_state_step "$run_dir/state.json" "map_fresh"
    return 0
  fi
  local prompt
  prompt=$(build_prompt "Use the /map skill to generate ARCHITECTURE.md at the repo root.")
  # Slash-skill dispatch — does NOT use --resume/--fork-session (the /map skill
  # starts its own dispatchers and should not inherit primer context). See
  # SKILL.md ## Cost optimization for why this step is exempt.
  "${claude_cmd[@]}" -p "$prompt" > "$run_dir/map.log" 2>&1 || return 1
  update_state_step "$run_dir/state.json" "map_fresh"
}

# Prime the prompt cache with brief.md (and ARCHITECTURE.md when present).
# Dispatches one `claude -p ... --output-format json`, parses the returned
# session_id from stdout JSON, and writes it to state.parent_session_id via
# state_set_field. Fails loud if the dispatch errors, the output is not JSON,
# or session_id is missing/empty — better to abort than continue with an empty
# parent_session_id and silently lose the cache benefit.
step_primer() {
  local id="$1" run_dir="$2"
  local brief
  brief=$(cat "$run_dir/brief.md")
  local primer_prompt="Primer for feature run $id. The following materials are loaded into context so subsequent steps (forked from this session) can reuse the cache.

Brief (from brief.md):
$brief"
  if [[ -f "$repo_root/ARCHITECTURE.md" ]]; then
    primer_prompt+="

Architecture map (from ARCHITECTURE.md):
$(cat "$repo_root/ARCHITECTURE.md")"
  fi
  primer_prompt+="

Acknowledge that you have loaded this context. No other action needed."

  local primer_json primer_rc
  primer_json=$("${claude_cmd[@]}" --output-format json -p "$primer_prompt" 2>"$run_dir/primer.err")
  primer_rc=$?
  printf '%s\n' "$primer_json" > "$run_dir/primer.log"
  if (( primer_rc != 0 )); then
    echo "feature.sh start: primer dispatch failed (exit $primer_rc); see $run_dir/primer.err" >&2
    return 1
  fi
  local parent_sid=""
  if command -v jq >/dev/null 2>&1; then
    parent_sid=$(printf '%s' "$primer_json" | jq -r '.session_id // empty' 2>/dev/null)
  else
    parent_sid=$(printf '%s' "$primer_json" \
      | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | sed -E 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  fi
  if [[ -z "$parent_sid" ]]; then
    echo "feature.sh start: primer JSON missing session_id key; refusing to continue with empty parent_session_id" >&2
    return 1
  fi
  state_set_field "$run_dir/state.json" parent_session_id "$parent_sid"
}

step_researcher() {
  local id="$1" run_dir="$2"
  local research_path="$repo_root/issues/research/$id.md"
  mkdir -p "$(dirname "$research_path")"
  local brief
  brief=$(cat "$run_dir/brief.md")
  local prompt
  prompt=$(build_prompt "Dispatch an Explore subagent to research this feature brief against the codebase. Read ARCHITECTURE.md if present. Output a structured research dump.

Brief:
$brief

Write the research dump to: $research_path")
  local step_cmd
  resolve_step_cmd RESEARCH
  local parent_sid
  parent_sid=$(state_field "$run_dir/state.json" parent_session_id)
  local -a argv=("${step_cmd[@]}" --resume "$parent_sid" --fork-session --output-format json)
  if ! step_override_has_effort RESEARCH; then
    argv+=(--effort low)
  fi
  argv+=(-p "$prompt")
  "${argv[@]}" > "$run_dir/research.log" 2>&1 || return 1
  state_set_field "$run_dir/state.json" research_path "$research_path"
  update_state_step "$run_dir/state.json" "research_done"
}

step_story() {
  local id="$1" run_dir="$2"
  local issue_path="$repo_root/issues/$id.md"
  mkdir -p "$(dirname "$issue_path")"
  local brief research
  brief=$(cat "$run_dir/brief.md")
  research=$(cat "$(state_field "$run_dir/state.json" research_path)" 2>/dev/null || echo "")
  local prompt
  prompt=$(build_prompt "Use the prd-to-issues issue template. Produce ONE issue (single-feature mode) at: $issue_path

Brief:
$brief

Research:
$research")
  local step_cmd
  resolve_step_cmd STORY
  local parent_sid
  parent_sid=$(state_field "$run_dir/state.json" parent_session_id)
  local -a argv=("${step_cmd[@]}" --resume "$parent_sid" --fork-session --output-format json)
  if ! step_override_has_effort STORY; then
    argv+=(--effort low)
  fi
  argv+=(-p "$prompt")
  "${argv[@]}" > "$run_dir/story.log" 2>&1 || return 1
  state_set_field "$run_dir/state.json" issue_path "$issue_path"
  update_state_step "$run_dir/state.json" "story_drafted"
}

step_spec() {
  local id="$1" run_dir="$2"
  local spec_path="$repo_root/issues/$id.spec.md"
  local issue_path research_path
  issue_path=$(state_field "$run_dir/state.json" issue_path)
  research_path=$(state_field "$run_dir/state.json" research_path)
  local prompt
  prompt=$(build_prompt "Use the write-a-spec skill. Inputs:
- Issue: $issue_path
- Research: $research_path

Write the spec to: $spec_path")
  local step_cmd
  resolve_step_cmd SPEC
  local parent_sid
  parent_sid=$(state_field "$run_dir/state.json" parent_session_id)
  "${step_cmd[@]}" --resume "$parent_sid" --fork-session --output-format json \
    -p "$prompt" > "$run_dir/spec.log" 2>&1 || return 1
  # Validate that the spec contains at least one ```paths fence.
  if [[ -f "$spec_path" ]] && ! grep -qE '^```paths[[:space:]]*$' "$spec_path"; then
    echo "step_spec: spec at $spec_path is missing fenced \`\`\`paths blocks under H3 lane headings. Expected format: see write-a-spec/SKILL.md." >&2
    update_state_step "$run_dir/state.json" "spec_invalid"
    return 1
  fi
  state_set_field "$run_dir/state.json" spec_path "$spec_path"
  update_state_step "$run_dir/state.json" "spec_drafted"
}

step_rubric() {
  local id="$1" run_dir="$2"
  local rubric_path="$repo_root/issues/$id.rubric.md"
  local issue_path spec_path
  issue_path=$(state_field "$run_dir/state.json" issue_path)
  spec_path=$(state_field "$run_dir/state.json" spec_path)
  local issue_body spec_body
  issue_body=$(cat "$issue_path" 2>/dev/null || echo "")
  spec_body=$(cat "$spec_path" 2>/dev/null || echo "")
  # RB-1: concatenate issue + spec into the prompt
  local prompt
  prompt=$(build_prompt "Use the write-a-rubric skill. Inputs are the story and the spec (both shown below); the rubric must cover behaviors from both.

== STORY ==
$issue_body

== SPEC ==
$spec_body

Write the rubric to: $rubric_path")
  local step_cmd
  resolve_step_cmd RUBRIC
  local parent_sid
  parent_sid=$(state_field "$run_dir/state.json" parent_session_id)
  "${step_cmd[@]}" --resume "$parent_sid" --fork-session --output-format json \
    -p "$prompt" > "$run_dir/rubric.log" 2>&1 || return 1
  state_set_field "$run_dir/state.json" rubric_path "$rubric_path"
  update_state_step "$run_dir/state.json" "rubric_drafted"
}

# step_lane <id> <run_dir> <lane>
# <lane> is the lane label as it appears in the spec's H3 (case-sensitive
# for the parser). Internally we normalize to lowercase for filenames and
# state markers so the case-statement in cmd_continue can match.
step_lane() {
  local id="$1" run_dir="$2" lane="$3"
  local lane_lc
  lane_lc=$(lane_normalize "$lane")
  local spec_path
  spec_path=$(state_field "$run_dir/state.json" spec_path)
  # The spec H3 is the canonical lane label per CLAUDE.md ## Lane boundaries,
  # which declares lowercase labels (backend/frontend). Pass the normalized
  # form to allowlist_for so the exact-match parser succeeds regardless of
  # what case the caller used to invoke step_lane.
  local allowlist
  allowlist=$(allowlist_for "$spec_path" "$lane_lc")
  if [[ -z "$allowlist" ]]; then
    echo "step_lane($lane): no allowlist found in spec; marking lane empty" >&2
    # Record the empty lane in state so route_findings and CP3 can see it.
    local current
    current=$(state_read "$run_dir/state.json")
    local tmp="$run_dir/state.json.tmp.$$"
    printf '%s' "$current" \
      | jq --arg lane "$lane_lc" \
          '.lanes[$lane] = {"allowlist": [], "status": "empty"}' \
      > "$tmp" && mv -f "$tmp" "$run_dir/state.json"
    update_state_step "$run_dir/state.json" "${lane_lc}_complete"
    return 0
  fi

  local lane_tmp="/tmp/feature-runs/$id"
  mkdir -p "$lane_tmp"
  local lane_prompt="$lane_tmp/lane-${lane_lc}.prompt.md"
  {
    echo "# Lane constraint"
    echo
    echo "You are operating in the **$lane** lane. You may only edit files in this Allowlist:"
    echo
    echo "## Allowlist"
    echo
    printf '%s\n' "$allowlist" | sed 's/^/- /'
    echo
    # If --redo feedback is set, surface it inside the lane preamble too.
    if [[ -n "${FEATURE_REDO_FEEDBACK:-}" ]]; then
      echo "## Feedback from prior iteration (apply before continuing):"
      echo
      printf '%s\n' "${FEATURE_REDO_FEEDBACK}"
      echo
    fi
    echo "If implementation requires editing a file outside the allowlist, append an \`## Allowlist additions requested\` section to the issue file (path + one-sentence reason per bullet), then stop and exit. The orchestrator surfaces these requests at the next checkpoint."
    echo
    echo "---"
    echo
    strip_frontmatter "$repo_root/plugins/agentic-engineering/skills/work-issues/SKILL.md"
  } > "$lane_prompt"

  # Invoke loop.sh with the lane prompt + extended commit log
  WORK_ISSUES_PROMPT="$lane_prompt" WORK_ISSUES_COMMIT_LOG=20 \
    "$loop_sh_cmd" > "$run_dir/lane-${lane_lc}.log" 2>&1
  local rc=$?

  # Update state.lanes.<lane_lc> with status + last commit; mark the step
  # marker matching plan §F (lowercase + "_complete").
  local current
  current=$(state_read "$run_dir/state.json")
  local head
  head=$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo "")
  local status="complete"
  (( rc != 0 )) && status="partial"
  local tmp="$run_dir/state.json.tmp.$$"
  printf '%s' "$current" \
    | jq --arg lane "$lane_lc" --arg s "$status" --arg c "$head" --arg a "$allowlist" \
        '.lanes[$lane] = {"allowlist": ($a | split("\n")), "status": $s, "last_commit": $c}' \
    > "$tmp" && mv -f "$tmp" "$run_dir/state.json"
  update_state_step "$run_dir/state.json" "${lane_lc}_complete"
  return $rc
}

# step_validator <id> <run_dir> <round>
# <round> is "backend" (after Step 6), "frontend" (after Step 8), or "final"
# (after Step 8 + Step 9 final pass). The step marker emitted matches plan §F:
# backend → "backend_validated"; frontend → "frontend_validated"; final → "validated".
step_validator() {
  local id="$1" run_dir="$2" round="$3"
  local spec_path
  spec_path=$(state_field "$run_dir/state.json" spec_path)
  local findings_path="$run_dir/validator-${round}.md"

  # Build TARGETS from all lane allowlists in the spec.
  local lanes targets=""
  lanes=$(awk '/^### / { line=substr($0,5); sub(/[[:space:]]+$/,"",line); print line }' "$spec_path")
  while IFS= read -r lane; do
    [[ -z "$lane" ]] && continue
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      targets+="$p:"
    done < <(allowlist_for "$spec_path" "$lane")
  done <<< "$lanes"
  targets="${targets%:}"

  local step_cmd
  resolve_step_cmd VALIDATOR
  local parent_sid
  parent_sid=$(state_field "$run_dir/state.json" parent_session_id)
  ADVERSARIAL_REVIEW_REPORT_ONLY=1 ADVERSARIAL_REVIEW_TARGETS="$targets" \
    "${step_cmd[@]}" --resume "$parent_sid" --fork-session --output-format json \
    -p "Use the /adversarial-review skill with --diff. Print the merged findings report." \
    > "$findings_path" 2>&1
  local rc=$?

  if (( rc != 0 )); then
    # Dispatch crash — record DISPATCH_FAILED per plan §G.
    state_set_field "$run_dir/state.json" validator_findings "DISPATCH_FAILED:$findings_path"
  else
    state_set_field "$run_dir/state.json" validator_findings "$findings_path"
  fi

  case "$round" in
    backend)  update_state_step "$run_dir/state.json" "backend_validated" ;;
    frontend) update_state_step "$run_dir/state.json" "frontend_validated" ;;
    final)    update_state_step "$run_dir/state.json" "validated" ;;
    *)        update_state_step "$run_dir/state.json" "${round}_validated" ;;
  esac
  return 0
}

# Route validator findings by lane and re-dispatch the failing lane (Step 7
# loop-back per plan §E). Returns 0 if no Critical findings need re-dispatch,
# 1 if a lane was re-invoked (caller should loop again).
route_and_loopback() {
  local id="$1" run_dir="$2" lane_being_validated="$3"
  local findings_path spec_path
  findings_path=$(state_field "$run_dir/state.json" validator_findings)
  spec_path=$(state_field "$run_dir/state.json" spec_path)
  # Skip routing if dispatch failed or no findings file.
  [[ "$findings_path" == DISPATCH_FAILED:* ]] && return 0
  [[ -f "$findings_path" ]] || return 0

  # Use route_findings to classify by lane.
  local routed
  routed=$(route_findings "$findings_path" "$spec_path" 2>/dev/null) || return 0

  # Filter for Critical findings in the target lane.
  local critical_in_lane
  critical_in_lane=$(printf '%s\n' "$routed" \
    | grep -E "^${lane_being_validated}\s" \
    | grep -iE 'critical' \
    || true)
  if [[ -z "$critical_in_lane" ]]; then
    return 0
  fi

  # Write a fix-findings issue, append to issues/<id>-fix-findings.md
  local fix_issue="$repo_root/issues/$id-fix-findings.md"
  {
    echo "# Fix critical validator findings (auto-generated)"
    echo
    echo "Generated by feature.sh::route_and_loopback after $lane_being_validated lane validation."
    echo
    printf '%s\n' "$critical_in_lane" | sed 's/^/- /'
  } > "$fix_issue"

  # Re-invoke the lane's loop.sh. The orchestrator's lane preamble file
  # from the previous run is still on disk; loop.sh will pick it up via
  # WORK_ISSUES_PROMPT if we re-export the same value.
  local lane_lc
  lane_lc=$(lane_normalize "$lane_being_validated")
  local lane_prompt="/tmp/feature-runs/$id/lane-${lane_lc}.prompt.md"
  WORK_ISSUES_PROMPT="$lane_prompt" WORK_ISSUES_COMMIT_LOG=20 \
    "$loop_sh_cmd" >> "$run_dir/lane-${lane_lc}.log" 2>&1 || true
  echo "route_and_loopback: re-invoked $lane_being_validated lane on Critical findings; see $fix_issue" >&2
  return 1
}

# ---- continue (resume after a checkpoint) -------------------------------

cmd_continue() {
  local id="${1:-}"
  require_id "$id" || return 1
  shift
  local mode="--accept" feedback=""
  while (( $# > 0 )); do
    case "$1" in
      --accept) mode="--accept"; shift ;;
      --redo)
        mode="--redo"
        if (( $# < 2 )); then
          echo "feature.sh continue --redo: feedback text required" >&2
          return 1
        fi
        feedback="$2"
        if [[ -z "$feedback" ]]; then
          echo "feature.sh continue --redo: feedback text must not be empty" >&2
          return 1
        fi
        shift 2
        ;;
      *) echo "feature.sh continue: unknown flag $1" >&2; return 1 ;;
    esac
  done

  local run_dir="$runs_dir/$id"
  local state="$run_dir/state.json"
  if [[ ! -f "$state" ]]; then
    echo "feature.sh continue: no run found at $run_dir" >&2
    return 1
  fi
  local step
  step=$(state_field "$state" last_completed_step)

  # Export feedback so step functions' build_prompt picks it up.
  if [[ "$mode" == "--redo" ]]; then
    export FEATURE_REDO_FEEDBACK="$feedback"
  else
    unset FEATURE_REDO_FEEDBACK
  fi

  # Re-acquire lock for the duration of this resume.
  acquire_lock "$run_dir/LOCK" "$$" || return 1
  trap 'release_lock "$run_dir/LOCK"; exit 130' INT TERM

  local rc=0
  if [[ "$mode" == "--redo" ]]; then
    # --redo: re-run whatever step the run is currently parked at.
    case "$step" in
      story_drafted)    step_story    "$id" "$run_dir"; rc=$? ;;
      spec_invalid|spec_drafted)
                        step_spec     "$id" "$run_dir" && step_rubric "$id" "$run_dir"; rc=$? ;;
      rubric_drafted)   step_rubric   "$id" "$run_dir"; rc=$? ;;
      backend_complete|backend_validated)
                        step_lane     "$id" "$run_dir" "Backend"; rc=$? ;;
      frontend_complete|frontend_validated)
                        step_lane     "$id" "$run_dir" "Frontend"; rc=$? ;;
      validated)        step_validator "$id" "$run_dir" "final"; rc=$? ;;
      *)
        echo "feature.sh continue --redo: no defined redo at step '$step'" >&2
        rc=1
        ;;
    esac
  else
    # --accept: advance to the next step. Every reachable state value has an arm.
    case "$step" in
      init|map_fresh|research_done)
        # Run still inside the start-phase chain — resume from where it died.
        case "$step" in
          init)          step_refresh_map "$id" "$run_dir" && step_researcher "$id" "$run_dir" && step_story "$id" "$run_dir"; rc=$? ;;
          map_fresh)     step_researcher "$id" "$run_dir" && step_story "$id" "$run_dir"; rc=$? ;;
          research_done) step_story "$id" "$run_dir"; rc=$? ;;
        esac
        if (( rc == 0 )); then
          cat <<EOF

=== CHECKPOINT 1: approve story ===
Run id:     $id
Story:      $(state_field "$state" issue_path)

To accept and continue:    feature.sh continue $id --accept
To request a redo:         feature.sh continue $id --redo "<feedback>"
To abort:                  feature.sh abort $id
EOF
        fi
        ;;

      story_drafted)
        step_spec "$id" "$run_dir" && step_rubric "$id" "$run_dir"; rc=$?
        if (( rc == 0 )); then
          cat <<EOF

=== CHECKPOINT 2: approve spec + rubric ===
Run id:     $id
Spec:       $(state_field "$state" spec_path)
Rubric:     $(state_field "$state" rubric_path)

To accept:  feature.sh continue $id --accept
To redo:    feature.sh continue $id --redo "<feedback>"
EOF
        fi
        ;;

      spec_invalid)
        echo "feature.sh continue: run is at spec_invalid; use --redo to retry the spec step" >&2
        rc=1
        ;;

      spec_drafted)
        # spec succeeded but rubric crashed; resume from rubric.
        step_rubric "$id" "$run_dir"; rc=$?
        if (( rc == 0 )); then
          echo
          echo "=== CHECKPOINT 2: approve spec + rubric ==="
          echo "To accept:  feature.sh continue $id --accept"
          echo "To redo:    feature.sh continue $id --redo \"<feedback>\""
        fi
        ;;

      rubric_drafted)
        # Steps 6 + 7: backend lane, inter-lane validator.
        step_lane "$id" "$run_dir" "Backend" && \
          step_validator "$id" "$run_dir" "backend" && \
          route_and_loopback "$id" "$run_dir" "backend"
        rc=$?
        if (( rc == 0 )); then
          echo "Backend lane + validator complete. Run 'feature.sh continue $id --accept' to start the Frontend lane."
        fi
        ;;

      backend_complete)
        # Step 6 completed but validator didn't run.
        step_validator "$id" "$run_dir" "backend" && \
          route_and_loopback "$id" "$run_dir" "backend"
        rc=$?
        ;;

      backend_validated)
        # Step 8 + 9: frontend lane + final validator.
        step_lane "$id" "$run_dir" "Frontend" && \
          step_validator "$id" "$run_dir" "final" && \
          route_and_loopback "$id" "$run_dir" "frontend"
        rc=$?
        if (( rc == 0 )); then
          cat <<EOF

=== CHECKPOINT 3: open PR ===
Run id:     $id
Validator:  $(state_field "$state" validator_findings)

To accept (mark run done, release LOCK):
  feature.sh continue $id --accept
To redo:
  feature.sh continue $id --redo "<feedback>"
EOF
        fi
        ;;

      frontend_complete)
        step_validator "$id" "$run_dir" "final" && \
          route_and_loopback "$id" "$run_dir" "frontend"
        rc=$?
        ;;

      frontend_validated|validated)
        # Finalize.
        release_lock "$run_dir/LOCK"
        trap - INT TERM
        local done_dir="$runs_dir/$id.done"
        mv "$run_dir" "$done_dir"
        update_state_step "$done_dir/state.json" "done"
        echo "Run $id done. Artifacts at: $done_dir"
        return 0
        ;;

      done)
        echo "feature.sh continue: run $id already done." >&2
        rc=0
        ;;

      aborted)
        echo "feature.sh continue: run $id was aborted; start a new run." >&2
        rc=1
        ;;

      *)
        echo "feature.sh continue: no defined next step from '$step'" >&2
        rc=1
        ;;
    esac
  fi

  release_lock "$run_dir/LOCK"
  trap - INT TERM
  unset FEATURE_REDO_FEEDBACK
  return $rc
}

# ---- entry point ---------------------------------------------------------

main() {
  if (( $# == 0 )); then
    cmd_help
    exit 1
  fi
  local sub="$1"; shift
  case "$sub" in
    help|--help|-h) cmd_help ;;
    start)          cmd_start "${1:-}" ;;
    continue)       cmd_continue "$@" ;;
    abort)          cmd_abort "${1:-}" ;;
    status)         cmd_status "${1:-}" ;;
    *)
      echo "feature.sh: unknown subcommand: $sub" >&2
      cmd_help
      exit 1
      ;;
  esac
}

# Guard against accidental sourcing — only run main if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
