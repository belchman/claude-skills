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
#   CLAUDE_CMD       command to invoke claude  (default: claude)
#   LOOP_SH_CMD      command to invoke loop.sh (default: ../../work-issues/bin/loop.sh)
#   FEATURE_RUNS_DIR root of run state         (default: .feature_runs)
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
runs_dir="${FEATURE_RUNS_DIR:-$repo_root/.feature_runs}"
claude_cmd="${CLAUDE_CMD:-claude}"
loop_sh_cmd="${LOOP_SH_CMD:-$script_dir/../../work-issues/bin/loop.sh}"

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Slugify a brief into an id: lowercase, alnum-and-dash only, truncated.
slugify() {
  local raw="$1"
  printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-40
}

next_id() {
  # 4-digit numeric prefix + slug. Numeric increments based on existing runs.
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

cmd_status() {
  local id="$1"
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
  local id="$1"
  local run_dir="$runs_dir/$id"
  if [[ ! -d "$run_dir" ]]; then
    echo "feature.sh abort: no run found at $run_dir" >&2
    return 1
  fi
  release_lock "$run_dir/LOCK"
  local target="$runs_dir/$id.aborted"
  # If a previous aborted run shares the slug, suffix with timestamp
  if [[ -d "$target" ]]; then
    target="$runs_dir/$id.aborted.$(date +%s)"
  fi
  mv "$run_dir" "$target"
  echo "Run $id aborted. Artifacts at: $target"
}

# Refuse to start if any other active run holds a live LOCK.
refuse_if_active_run_exists() {
  if [[ ! -d "$runs_dir" ]]; then
    return 0
  fi
  local d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    local pidfile="$d/LOCK"
    [[ -f "$pidfile" ]] || continue
    local held_pid
    held_pid=$(cat "$pidfile" 2>/dev/null)
    if [[ -n "$held_pid" ]] && kill -0 "$held_pid" 2>/dev/null; then
      echo "feature.sh start: another run is in progress at $d (LOCK held by PID $held_pid)." >&2
      echo "  Run 'feature.sh abort $(basename "$d")' to release it, or wait for it to finish." >&2
      return 1
    fi
  done < <(find "$runs_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  return 0
}

cmd_start() {
  local brief="$1"
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
  printf '%s\n' "$brief" > "$run_dir/brief.md"

  local now
  now=$(iso_now)
  # Initial state.json — fields populated incrementally as steps complete.
  state_write "$run_dir/state.json" "$(cat <<EOF
{
  "id": "$id",
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

  # Steps 1-3 (refresh map, researcher, story) — each calls $claude_cmd -p
  # and writes its artifact. On any non-zero, we exit non-zero leaving state
  # at the last successful step so 'continue' can pick up.
  step_refresh_map "$id" "$run_dir" || return 3
  step_researcher  "$id" "$run_dir" || return 3
  step_story       "$id" "$run_dir" || return 3

  # Checkpoint 1
  cat <<EOF

=== CHECKPOINT 1: approve story ===
Run id:     $id
Story:      $run_dir/issue.md (sidecar at issues/$id.md if pipeline writes there)

To accept and continue:    bin/feature.sh continue $id --accept
To request a redo:         bin/feature.sh continue $id --redo "<feedback>"
To abort:                  bin/feature.sh abort $id
EOF
}

# ---- chain steps (call \$claude_cmd; tests can stub via CLAUDE_CMD) ------

# Each step:
#  - reads inputs from state / run_dir
#  - dispatches $claude_cmd -p with the right skill prompt
#  - writes its artifact (file path) and updates state.json
#  - returns 0 on success, non-zero on failure

update_state_step() {
  local state="$1" step="$2"
  local current
  current=$(state_read "$state")
  local now
  now=$(iso_now)
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$current" | jq --arg s "$step" --arg t "$now" \
      '.last_completed_step = $s | .updated_at = $t' > "$state"
  else
    # Naive sed fallback; relies on the field appearing once on its own line.
    sed -i.bak -E "s|\"last_completed_step\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"last_completed_step\": \"$step\"|" "$state"
    sed -i.bak -E "s|\"updated_at\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"updated_at\": \"$now\"|" "$state"
    rm -f "${state}.bak"
  fi
}

step_refresh_map() {
  local id="$1" run_dir="$2"
  # Cheap version: if ARCHITECTURE.md exists, skip; else invoke /map.
  if [[ -f "$repo_root/ARCHITECTURE.md" ]]; then
    update_state_step "$run_dir/state.json" "map_fresh"
    return 0
  fi
  # Dispatch /map via $claude_cmd -p with the skill prompt.
  "$claude_cmd" -p "Use the /map skill to generate ARCHITECTURE.md at the repo root." \
    > "$run_dir/map.log" 2>&1 || return 1
  update_state_step "$run_dir/state.json" "map_fresh"
}

step_researcher() {
  local id="$1" run_dir="$2"
  local research_path="$repo_root/issues/research/$id.md"
  mkdir -p "$(dirname "$research_path")"
  local brief
  brief=$(cat "$run_dir/brief.md")
  "$claude_cmd" -p "Dispatch an Explore subagent to research this feature brief against the codebase. Read ARCHITECTURE.md if present. Output a structured research dump.

Brief:
$brief

Write the research dump to: $research_path" \
    > "$run_dir/research.log" 2>&1 || return 1
  # Update state with research_path; mark step complete.
  local current
  current=$(state_read "$run_dir/state.json")
  printf '%s' "$current" | jq --arg p "$research_path" '.research_path = $p' > "$run_dir/state.json"
  update_state_step "$run_dir/state.json" "research_done"
}

step_story() {
  local id="$1" run_dir="$2"
  local issue_path="$repo_root/issues/$id.md"
  mkdir -p "$(dirname "$issue_path")"
  local brief research
  brief=$(cat "$run_dir/brief.md")
  research=$(cat "$(state_field "$run_dir/state.json" research_path)" 2>/dev/null || echo "")
  "$claude_cmd" -p "Use the prd-to-issues issue template. Produce ONE issue (single-feature mode) at: $issue_path

Brief:
$brief

Research:
$research" \
    > "$run_dir/story.log" 2>&1 || return 1
  local current
  current=$(state_read "$run_dir/state.json")
  printf '%s' "$current" | jq --arg p "$issue_path" '.issue_path = $p' > "$run_dir/state.json"
  update_state_step "$run_dir/state.json" "story_drafted"
}

step_spec() {
  local id="$1" run_dir="$2"
  local spec_path="$repo_root/issues/$id.spec.md"
  local issue_path
  issue_path=$(state_field "$run_dir/state.json" issue_path)
  local research_path
  research_path=$(state_field "$run_dir/state.json" research_path)
  "$claude_cmd" -p "Use the write-a-spec skill. Inputs:
- Issue: $issue_path
- Research: $research_path

Write the spec to: $spec_path" \
    > "$run_dir/spec.log" 2>&1 || return 1
  # Validate that the spec contains at least one ```paths fence.
  if [[ -f "$spec_path" ]] && ! grep -qE '^```paths[[:space:]]*$' "$spec_path"; then
    echo "step_spec: spec at $spec_path is missing fenced \`\`\`paths blocks under H3 lane headings. Expected format: see write-a-spec/SKILL.md." >&2
    update_state_step "$run_dir/state.json" "spec_invalid"
    return 1
  fi
  local current
  current=$(state_read "$run_dir/state.json")
  printf '%s' "$current" | jq --arg p "$spec_path" '.spec_path = $p' > "$run_dir/state.json"
  update_state_step "$run_dir/state.json" "spec_drafted"
}

step_rubric() {
  local id="$1" run_dir="$2"
  local rubric_path="$repo_root/issues/$id.rubric.md"
  local issue_path spec_path
  issue_path=$(state_field "$run_dir/state.json" issue_path)
  spec_path=$(state_field "$run_dir/state.json" spec_path)
  # RB-1: concatenate issue + spec into the prompt
  local issue_body spec_body
  issue_body=$(cat "$issue_path" 2>/dev/null || echo "")
  spec_body=$(cat "$spec_path" 2>/dev/null || echo "")
  "$claude_cmd" -p "Use the write-a-rubric skill. Inputs are the story and the spec (both shown below); the rubric must cover behaviors from both.

== STORY ==
$issue_body

== SPEC ==
$spec_body

Write the rubric to: $rubric_path" \
    > "$run_dir/rubric.log" 2>&1 || return 1
  local current
  current=$(state_read "$run_dir/state.json")
  printf '%s' "$current" | jq --arg p "$rubric_path" '.rubric_path = $p' > "$run_dir/state.json"
  update_state_step "$run_dir/state.json" "rubric_drafted"
}

# Build the lane preamble file + invoke loop.sh with WORK_ISSUES_PROMPT set.
step_lane() {
  local id="$1" run_dir="$2" lane="$3"
  local spec_path
  spec_path=$(state_field "$run_dir/state.json" spec_path)
  local allowlist
  allowlist=$(allowlist_for "$spec_path" "$lane")
  if [[ -z "$allowlist" ]]; then
    echo "step_lane($lane): no allowlist found in spec; skipping lane" >&2
    return 0
  fi

  local lane_tmp="/tmp/feature-runs/$id"
  mkdir -p "$lane_tmp"
  local lane_prompt="$lane_tmp/lane-${lane}.prompt.md"
  {
    echo "# Lane constraint"
    echo
    echo "You are operating in the **$lane** lane. You may only edit files in this Allowlist:"
    echo
    echo "## Allowlist"
    echo
    printf '%s\n' "$allowlist" | sed 's/^/- /'
    echo
    echo "If implementation requires editing a file outside the allowlist, append an \`## Allowlist additions requested\` section to the issue file (path + one-sentence reason per bullet), then stop and exit. The orchestrator surfaces these requests at the next checkpoint."
    echo
    echo "---"
    echo
    strip_frontmatter "$repo_root/plugins/agentic-engineering/skills/work-issues/SKILL.md"
  } > "$lane_prompt"

  # Invoke loop.sh with the lane prompt + extended commit log
  WORK_ISSUES_PROMPT="$lane_prompt" WORK_ISSUES_COMMIT_LOG=20 \
    "$loop_sh_cmd" > "$run_dir/lane-${lane}.log" 2>&1
  local rc=$?

  # Update state.lanes.<lane>.status and last_commit
  local current
  current=$(state_read "$run_dir/state.json")
  local head
  head=$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo "")
  local status="complete"; [[ $rc -ne 0 ]] && status="partial"
  printf '%s' "$current" | jq \
    --arg lane "$lane" --arg s "$status" --arg c "$head" --arg a "$allowlist" \
    '.lanes[$lane] = {"allowlist": ($a | split("\n")), "status": $s, "last_commit": $c}' \
    > "$run_dir/state.json"
  update_state_step "$run_dir/state.json" "${lane}_complete"
  return $rc
}

# Dispatch /adversarial-review with the env-var hooks; capture findings.
step_validator() {
  local id="$1" run_dir="$2" round="$3"  # round = "inter-lane" or "final"
  local spec_path
  spec_path=$(state_field "$run_dir/state.json" spec_path)
  local findings_path="$run_dir/validator-${round}.md"
  # Build TARGETS from all lane allowlists in the spec.
  local lanes targets
  lanes=$(awk '/^### / { line=substr($0,5); sub(/[[:space:]]+$/,"",line); print line }' "$spec_path")
  targets=""
  while IFS= read -r lane; do
    [[ -z "$lane" ]] && continue
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      targets+="$p:"
    done < <(allowlist_for "$spec_path" "$lane")
  done <<< "$lanes"
  targets="${targets%:}"

  ADVERSARIAL_REVIEW_REPORT_ONLY=1 ADVERSARIAL_REVIEW_TARGETS="$targets" \
    "$claude_cmd" -p "Use the /adversarial-review skill with --diff. Print the merged findings report." \
    > "$findings_path" 2>&1 || true

  local current
  current=$(state_read "$run_dir/state.json")
  printf '%s' "$current" | jq --arg p "$findings_path" '.validator_findings = $p' > "$run_dir/state.json"
  update_state_step "$run_dir/state.json" "${round}_validated"
  echo "$findings_path"
}

# ---- continue (resume after a checkpoint) -------------------------------

cmd_continue() {
  local id="$1"; shift
  local mode="--accept" feedback=""
  while (( $# > 0 )); do
    case "$1" in
      --accept) mode="--accept"; shift ;;
      --redo)   mode="--redo"; feedback="${2:-}"; shift 2 ;;
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

  # --redo: re-run the last step with feedback prepended. The orchestrator
  # writes feedback to a sibling file so step functions can pick it up.
  if [[ "$mode" == "--redo" ]]; then
    printf '%s\n' "$feedback" > "$run_dir/redo-feedback.md"
    case "$step" in
      story_drafted|spec_invalid)
        # Re-run story (CP1 redo) or spec (CP2 spec_invalid redo)
        [[ "$step" == "story_drafted" ]] && step_story "$id" "$run_dir"
        [[ "$step" == "spec_invalid" ]] && step_spec "$id" "$run_dir"
        ;;
      spec_drafted|rubric_drafted)
        # CP2 redo — re-run from spec step (and rubric follows)
        step_spec "$id" "$run_dir" && step_rubric "$id" "$run_dir"
        ;;
      validated|frontend_complete|backend_validated)
        # CP3 redo — rerun the most-recent lane based on context (best-guess).
        echo "feature.sh continue --redo at $step: re-running final validator" >&2
        step_validator "$id" "$run_dir" "final"
        ;;
      *)
        echo "feature.sh continue --redo: no defined redo at step '$step'" >&2
        return 1
        ;;
    esac
    return $?
  fi

  # --accept: advance to the next step in the chain.
  case "$step" in
    story_drafted)
      step_spec "$id" "$run_dir" && step_rubric "$id" "$run_dir" && echo "
=== CHECKPOINT 2: approve spec + rubric ===
Run id:     $id
Spec:       $(state_field "$state" spec_path)
Rubric:     $(state_field "$state" rubric_path)

To accept:  bin/feature.sh continue $id --accept
To redo:    bin/feature.sh continue $id --redo \"<feedback>\""
      ;;
    rubric_drafted)
      # Step 6 + 7: backend lane, inter-lane validator, frontend lane, final validator
      step_lane "$id" "$run_dir" "Backend"
      step_validator "$id" "$run_dir" "inter-lane"
      step_lane "$id" "$run_dir" "Frontend"
      step_validator "$id" "$run_dir" "final"
      echo "
=== CHECKPOINT 3: open PR ===
Run id:     $id
Validator:  $(state_field "$state" validator_findings)

To accept (mark run done, release LOCK):
  bin/feature.sh continue $id --accept
To redo:
  bin/feature.sh continue $id --redo \"<feedback>\""
      ;;
    validated|final_validated)
      # Step 10: finalize
      release_lock "$run_dir/LOCK"
      mv "$run_dir" "$runs_dir/$id.done"
      echo "Run $id done. Artifacts at: $runs_dir/$id.done"
      update_state_step "$runs_dir/$id.done/state.json" "done"
      ;;
    done)
      echo "feature.sh continue: run $id already done." >&2
      return 0
      ;;
    *)
      echo "feature.sh continue: no defined next step from '$step'" >&2
      return 1
      ;;
  esac
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

main "$@"
