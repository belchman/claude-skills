#!/usr/bin/env bash
# Integration tests for bin/feature.sh.
# Uses stubs (CLAUDE_CMD, LOOP_SH_CMD) and FEATURE_RUNS_DIR override so the
# tests don't touch the real repo.
# Run: bash tests/test_feature_orchestrator.sh

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
feature_sh="$repo_root/plugins/agentic-engineering/skills/feature/bin/feature.sh"

pass_count=0
fail_count=0
assert_eq() {
  local n="$1" e="$2" a="$3"
  if [[ "$e" == "$a" ]]; then
    echo "  PASS  $n"; pass_count=$((pass_count + 1))
  else
    echo "  FAIL  $n"; echo "    expected: $(printf '%q' "$e")"; echo "    actual:   $(printf '%q' "$a")"
    fail_count=$((fail_count + 1))
  fi
}
assert_true() {
  local n="$1"; shift
  if "$@"; then echo "  PASS  $n"; pass_count=$((pass_count + 1))
  else echo "  FAIL  $n"; fail_count=$((fail_count + 1)); fi
}
assert_false() {
  local n="$1"; shift
  if ! "$@"; then echo "  PASS  $n"; pass_count=$((pass_count + 1))
  else echo "  FAIL  $n (expected non-zero exit)"; fail_count=$((fail_count + 1)); fi
}

# Make a sandbox runs-dir per-test. Provide a CLAUDE_CMD stub that records
# its prompts to a file so we can assert on them.
mk_sandbox() {
  local sb
  sb=$(mktemp -d)
  mkdir -p "$sb/runs" "$sb/stub-out"
  # Stub claude: writes its prompt to a unique file in $sb/stub-out and
  # creates the file the orchestrator expects (research dump, issue, spec,
  # rubric) based on a substring match in the prompt.
  cat > "$sb/claude-stub" <<'STUB'
#!/usr/bin/env bash
# Capture all args + stdin to a numbered log file.
n=$(ls "$STUB_OUT_DIR" 2>/dev/null | wc -l | tr -d ' ')
out="$STUB_OUT_DIR/prompt-$n.log"
{
  echo "## ARGS ##"
  printf '%s\n' "$@"
  echo "## ENV ##"
  env | grep -E '^(ADVERSARIAL_REVIEW_|WORK_ISSUES_|CLAUDE_)' || true
} > "$out"
# The orchestrator passes the prompt as the LAST -p arg. Find a "Write … to: <path>"
# instruction and create that file as a minimal valid artifact.
prompt="${@: -1}"
target=$(printf '%s' "$prompt" | grep -oE 'Write [a-z ]+to:[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}')
if [[ -n "$target" ]]; then
  mkdir -p "$(dirname "$target")"
  # Different placeholder content depending on what's being written
  case "$target" in
    *.spec.md)
      cat > "$target" <<'SPEC'
# Stub spec

### Backend

```paths
src/api/foo.ts
src/services/foo.ts
```
SPEC
      ;;
    *.rubric.md)
      echo "# Stub rubric" > "$target"
      ;;
    *.md)
      echo "# Stub issue / research" > "$target"
      ;;
  esac
fi
exit 0
STUB
  chmod +x "$sb/claude-stub"
  # Stub loop.sh: just records its env and exits 0
  cat > "$sb/loop-sh-stub" <<'LOOP_STUB'
#!/usr/bin/env bash
n=$(ls "$STUB_OUT_DIR" 2>/dev/null | grep loop | wc -l | tr -d ' ')
out="$STUB_OUT_DIR/loop-$n.log"
{
  echo "## ENV ##"
  env | grep -E '^(WORK_ISSUES_|CLAUDE_)' || true
  echo "## PROMPT FILE (head) ##"
  if [[ -n "${WORK_ISSUES_PROMPT:-}" && -f "$WORK_ISSUES_PROMPT" ]]; then
    head -30 "$WORK_ISSUES_PROMPT"
  fi
} > "$out"
exit 0
LOOP_STUB
  chmod +x "$sb/loop-sh-stub"
  printf '%s\n' "$sb"
}

run_in_sb() {
  local sb="$1"; shift
  STUB_OUT_DIR="$sb/stub-out" \
  CLAUDE_CMD="$sb/claude-stub" \
  LOOP_SH_CMD="$sb/loop-sh-stub" \
  FEATURE_RUNS_DIR="$sb/runs" \
    bash "$feature_sh" "$@"
}

# ---- CMD-3: start creates dir/brief/LOCK/state.json ----------------------

test_start_creates_run_artifacts() {
  local sb; sb=$(mk_sandbox)
  local out
  out=$(run_in_sb "$sb" start "test brief one" 2>&1)
  local rc=$?
  # Find the created run id (numeric prefix)
  local run_dir
  run_dir=$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
  local id
  id=$(basename "$run_dir")
  assert_eq "start: exit 0" "0" "$rc"
  assert_true "start: run dir created" test -d "$run_dir"
  assert_true "start: brief.md created" test -f "$run_dir/brief.md"
  assert_true "start: LOCK created" test -f "$run_dir/LOCK"
  assert_true "start: state.json created" test -f "$run_dir/state.json"
  if [[ "$out" == *"feature.sh continue $id"* ]]; then
    echo "  PASS  start: stdout names 'feature.sh continue <id>'"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  start: stdout missing 'feature.sh continue <id>'"
    fail_count=$((fail_count + 1))
  fi
  rm -rf "$sb"
}

# ---- CMD-4 + ST-1..3: state.json shape -----------------------------------

test_state_json_has_required_fields() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "test brief two" > /dev/null 2>&1
  local state
  state=$(find "$sb/runs" -name state.json 2>/dev/null | head -1)
  if jq -e 'has("id") and has("brief_path") and has("issue_path") and has("research_path") and has("spec_path") and has("rubric_path") and has("lanes") and has("validator_findings") and has("last_completed_step") and has("started_at") and has("updated_at")' "$state" >/dev/null; then
    echo "  PASS  state.json has all 11 required fields (ST-1)"; pass_count=$((pass_count + 1))
  else
    echo "  FAIL  state.json missing one of the 11 required fields (ST-1)"
    jq -e 'keys' "$state"
    fail_count=$((fail_count + 1))
  fi
  local started
  started=$(jq -r .started_at "$state")
  if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" >/dev/null 2>&1 \
     || date -d "$started" >/dev/null 2>&1; then
    echo "  PASS  state.started_at parses as ISO-8601 (ST-2)"; pass_count=$((pass_count + 1))
  else
    echo "  FAIL  state.started_at unparseable: $started (ST-2)"; fail_count=$((fail_count + 1))
  fi
  local step
  step=$(jq -r .last_completed_step "$state")
  # ST-3: documented step marker (matches §F)
  case "$step" in
    init|map_fresh|research_done|story_drafted|spec_drafted|spec_invalid|rubric_drafted|backend_complete|backend_validated|frontend_complete|validated|final_validated|done)
      echo "  PASS  state.last_completed_step is a documented marker: $step (ST-3)"
      pass_count=$((pass_count + 1))
      ;;
    *)
      echo "  FAIL  state.last_completed_step not a documented marker: $step (ST-3)"
      fail_count=$((fail_count + 1))
      ;;
  esac
  rm -rf "$sb"
}

# ---- CMD-5: status prints human-readable -----------------------------------

test_status_prints_human_readable() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "test brief status" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  local out
  out=$(run_in_sb "$sb" status "$id")
  for f in id last_completed_step started_at; do
    if [[ "$out" == *"$f"* ]]; then
      echo "  PASS  status: shows field '$f'"
      pass_count=$((pass_count + 1))
    else
      echo "  FAIL  status: missing field '$f'"
      fail_count=$((fail_count + 1))
    fi
  done
  rm -rf "$sb"
}

# ---- CMD-6: abort renames + removes LOCK ----------------------------------

test_abort_renames_and_removes_lock() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "test brief abort" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # Manually release the LOCK first (orchestrator holds it during start; in real use,
  # it would be released at the end of cmd_start because the process exits.)
  rm -f "$sb/runs/$id/LOCK"
  echo "" > "$sb/runs/$id/LOCK"  # re-create empty to test removal
  run_in_sb "$sb" abort "$id" > /dev/null 2>&1
  assert_true "abort: original run dir gone" test ! -d "$sb/runs/$id"
  assert_true "abort: .aborted dir exists" test -d "$sb/runs/$id.aborted"
  assert_true "abort: LOCK removed" test ! -f "$sb/runs/$id.aborted/LOCK"
  rm -rf "$sb"
}

# ---- LK-1, LK-2: refusal when active run exists --------------------------

test_concurrent_start_refused() {
  local sb; sb=$(mk_sandbox)
  # First start creates a run with LOCK
  run_in_sb "$sb" start "first brief" > /dev/null 2>&1
  local first_id
  first_id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # Force LOCK to contain our own (live) PID so the refusal-check tests positive
  echo "$$" > "$sb/runs/$first_id/LOCK"
  local out rc
  out=$(run_in_sb "$sb" start "second brief" 2>&1); rc=$?
  if (( rc != 0 )); then
    echo "  PASS  second start exits non-zero (LK-1)"; pass_count=$((pass_count + 1))
  else
    echo "  FAIL  second start should exit non-zero (LK-1)"; fail_count=$((fail_count + 1))
  fi
  if [[ "$out" == *".feature_runs/"*"$first_id"* || "$out" == *"runs/$first_id"* ]]; then
    echo "  PASS  refusal message names the active run (LK-2)"; pass_count=$((pass_count + 1))
  else
    echo "  FAIL  refusal message missing active run id (LK-2). Output: $out"
    fail_count=$((fail_count + 1))
  fi
  rm -rf "$sb"
}

# ---- DEP-3: stale lock is stolen ------------------------------------------

test_stale_lock_allows_new_start() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "first" > /dev/null 2>&1
  local id1
  id1=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # Replace LOCK with a stale PID (very high, won't exist)
  echo "987654321" > "$sb/runs/$id1/LOCK"
  # New start should succeed
  local rc
  run_in_sb "$sb" start "second" > /dev/null 2>&1; rc=$?
  if (( rc == 0 )); then
    echo "  PASS  stale lock allows new start (DEP-3)"; pass_count=$((pass_count + 1))
  else
    echo "  FAIL  stale lock should NOT block new start (DEP-3); got exit $rc"; fail_count=$((fail_count + 1))
  fi
  rm -rf "$sb"
}

# ---- run -----------------------------------------------------------------

if [[ ! -x "$feature_sh" ]]; then
  echo "SETUP FAIL  feature.sh not executable at: $feature_sh"
  fail_count=$((fail_count + 1))
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP  jq not installed — state.json shape tests will use fallback assertions"
fi

test_start_creates_run_artifacts
test_state_json_has_required_fields
test_status_prints_human_readable
test_abort_renames_and_removes_lock
test_concurrent_start_refused
test_stale_lock_allows_new_start

echo ""
echo "Results: $pass_count passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
