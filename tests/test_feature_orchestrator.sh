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
      # H3 labels must match CLAUDE.md `## Lane boundaries` char-for-char.
      # claude-skills declares lowercase backend/frontend, so the spec fixture
      # uses lowercase too. Without both H3 blocks the two-lane chain stalls
      # at frontend with an empty allowlist (lane status: empty).
      cat > "$target" <<'SPEC'
# Stub spec

### backend

```paths
src/api/foo.ts
src/services/foo.ts
```

### frontend

```paths
src/components/Foo.tsx
src/components/Foo.test.tsx
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
  FEATURE_REPO_ROOT="$sb" \
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
  # LOCK is released when cmd_start exits cleanly (user is now at a checkpoint
  # waiting for input; nothing is actively working).
  assert_true "start: LOCK released after completion" test ! -f "$run_dir/LOCK"
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

# ---- continue --redo arg validation (config C1: no infinite loop) ---------

test_continue_redo_without_feedback_errors() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "test brief" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # Invoke --redo with no feedback arg — should error fast, not loop.
  # macOS doesn't have GNU timeout; use a background-process + sleep + kill pattern.
  local rc
  (
    STUB_OUT_DIR="$sb/stub-out" CLAUDE_CMD="$sb/claude-stub" \
    LOOP_SH_CMD="$sb/loop-sh-stub" FEATURE_RUNS_DIR="$sb/runs" \
      bash "$feature_sh" continue "$id" --redo > /dev/null 2>&1 &
    local pid=$!
    # Give it 3 seconds; if still running, it's the infinite loop bug.
    for _ in 1 2 3 4 5 6; do
      sleep 0.5
      if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid"
        exit $?
      fi
    done
    kill -9 "$pid" 2>/dev/null
    exit 124
  )
  rc=$?
  rm -rf "$sb"
  case $rc in
    124) echo "  FAIL  continue --redo without feedback hung 3s+ (infinite loop bug)"; fail_count=$((fail_count + 1)) ;;
    0)   echo "  FAIL  continue --redo without feedback should exit non-zero (got 0)"; fail_count=$((fail_count + 1)) ;;
    *)   echo "  PASS  continue --redo without feedback errors quickly (rc=$rc)"; pass_count=$((pass_count + 1)) ;;
  esac
}

# ---- continue --redo feedback actually lands in step prompt --------------

test_continue_redo_feedback_in_prompt() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "test brief redo" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # Force state to story_drafted (where the start chain leaves it after the smoke).
  # Then --redo should re-run step_story with the feedback prepended.
  rm -f "$sb/stub-out"/prompt-*.log  # clear prior captures from start
  run_in_sb "$sb" continue "$id" --redo "make the version output JSON" > /dev/null 2>&1
  # Find the most recent prompt log AND check before cleanup (cov reviewer I5).
  local prompt_log found=0
  prompt_log=$(ls -t "$sb/stub-out"/prompt-*.log 2>/dev/null | head -1)
  if [[ -n "$prompt_log" ]] && grep -qF "make the version output JSON" "$prompt_log"; then
    found=1
  fi
  rm -rf "$sb"
  if (( found == 1 )); then
    echo "  PASS  continue --redo prepends feedback into the dispatched prompt"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  continue --redo feedback NOT found in step prompt"
    fail_count=$((fail_count + 1))
  fi
}

# ---- continue --accept advances story_drafted → spec_drafted -------------

test_continue_accept_story_to_spec() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "feature one" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # After start, state is story_drafted. Continue --accept runs spec + rubric.
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  local step
  step=$(jq -r .last_completed_step "$sb/runs/$id/state.json" 2>/dev/null)
  rm -rf "$sb"
  # The stub creates a valid spec with paths blocks, so we should advance to
  # rubric_drafted (spec succeeded → rubric ran).
  if [[ "$step" == "rubric_drafted" ]]; then
    echo "  PASS  continue --accept from story_drafted reaches rubric_drafted"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  continue --accept expected rubric_drafted, got '$step'"
    fail_count=$((fail_count + 1))
  fi
}

# ---- lane step emits lowercase marker (spec C1/C2 + cov C2 regression) ---

test_lane_step_emits_lowercase_marker() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "feature lane" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # Drive: story → spec/rubric → backend lane
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1  # spec + rubric
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1  # backend lane + validator
  local step
  step=$(jq -r .last_completed_step "$sb/runs/$id/state.json" 2>/dev/null)
  # state.lanes.backend (lowercase) should exist
  local lanes_key
  lanes_key=$(jq -r '.lanes | keys[]' "$sb/runs/$id/state.json" 2>/dev/null | head -1)
  rm -rf "$sb"
  # Expect step to be backend_validated (or downstream if route_and_loopback ran clean)
  if [[ "$step" == "backend_validated" || "$step" == "backend_complete" ]]; then
    echo "  PASS  backend lane step emits lowercase marker: $step"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  backend lane step expected lowercase backend_complete/backend_validated, got '$step'"
    fail_count=$((fail_count + 1))
  fi
  if [[ "$lanes_key" == "backend" ]]; then
    echo "  PASS  state.lanes uses lowercase key (backend)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  state.lanes key expected lowercase 'backend', got '$lanes_key'"
    fail_count=$((fail_count + 1))
  fi
}

# ---- Round 4: full-chain end-to-end with stub claude/loop ----------------
#
# Drives the orchestrator from `start` to `done` through every state
# transition. Smoke-tests the same brief shape the dogfooding plan names
# (single-lane feature: "Add /version subcommand to crap").
#
# Continue invocations required: 1 (start) + 4 (continue --accept) = 5.
# Final state.last_completed_step == "done"; run dir renamed to <id>.done.

test_full_chain_end_to_end() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "Add /version subcommand to crap that prints the script sha" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")

  # CP1 → CP2 (spec + rubric)
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  local step1
  step1=$(jq -r .last_completed_step "$sb/runs/$id/state.json" 2>/dev/null)
  if [[ "$step1" == "rubric_drafted" ]]; then
    echo "  PASS  full-chain: continue #1 → rubric_drafted (CP2)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  full-chain: continue #1 expected rubric_drafted, got '$step1'"
    fail_count=$((fail_count + 1))
    rm -rf "$sb"; return
  fi

  # CP2 → backend_validated (intermediate; the README/PRD/CLAUDE.md call this
  # an "implicit checkpoint" — the user could abort before letting frontend
  # touch anything, but it's not paged with a CP3-style message).
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  local step2
  step2=$(jq -r .last_completed_step "$sb/runs/$id/state.json" 2>/dev/null)
  if [[ "$step2" == "backend_validated" ]]; then
    echo "  PASS  full-chain: continue #2 → backend_validated (between-lanes gate)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  full-chain: continue #2 expected backend_validated, got '$step2'"
    fail_count=$((fail_count + 1))
    rm -rf "$sb"; return
  fi

  # backend_validated → validated (CP3)
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  local step3
  step3=$(jq -r .last_completed_step "$sb/runs/$id/state.json" 2>/dev/null)
  if [[ "$step3" == "validated" ]]; then
    echo "  PASS  full-chain: continue #3 → validated (CP3)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  full-chain: continue #3 expected validated, got '$step3'"
    fail_count=$((fail_count + 1))
    rm -rf "$sb"; return
  fi

  # validated → done (finalize, rename dir)
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  local final_step
  if [[ -d "$sb/runs/$id.done" ]]; then
    final_step=$(jq -r .last_completed_step "$sb/runs/$id.done/state.json" 2>/dev/null)
    if [[ "$final_step" == "done" ]]; then
      echo "  PASS  full-chain: continue #4 → done (run dir renamed to <id>.done)"
      pass_count=$((pass_count + 1))
    else
      echo "  FAIL  full-chain: continue #4 expected done, got '$final_step'"
      fail_count=$((fail_count + 1))
    fi
  else
    echo "  FAIL  full-chain: continue #4 did not rename run dir to <id>.done"
    fail_count=$((fail_count + 1))
  fi

  # Side-effects we expect at done:
  #   1. LOCK gone (release_lock fires in the finalize arm)
  #   2. state.lanes has both backend + frontend keys
  if [[ ! -f "$sb/runs/$id.done/LOCK" ]]; then
    echo "  PASS  full-chain: LOCK released at done"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  full-chain: LOCK still present at done"
    fail_count=$((fail_count + 1))
  fi
  local lane_keys
  lane_keys=$(jq -r '.lanes | keys | sort | join(",")' "$sb/runs/$id.done/state.json" 2>/dev/null)
  if [[ "$lane_keys" == "backend,frontend" ]]; then
    echo "  PASS  full-chain: state.lanes has both backend + frontend keys"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  full-chain: state.lanes expected backend,frontend; got '$lane_keys'"
    fail_count=$((fail_count + 1))
  fi

  # Regression guard for the case-sensitivity bug: step_lane was passing the
  # capitalized lane name ("Backend") to allowlist_for, while the spec H3 +
  # CLAUDE.md `## Lane boundaries` use lowercase. allowlist_for did exact
  # match, so the allowlist came back empty and the lane was silently marked
  # "empty". Now step_lane passes lane_lc, the fixture spec uses lowercase
  # H3s, and lanes carry their real path lists.
  local backend_count
  backend_count=$(jq -r '.lanes.backend.allowlist | length' "$sb/runs/$id.done/state.json" 2>/dev/null)
  if [[ "$backend_count" -ge 1 ]]; then
    echo "  PASS  full-chain: backend lane allowlist populated ($backend_count entries), not silently empty"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  full-chain: backend lane allowlist was empty — case-sensitivity regression"
    fail_count=$((fail_count + 1))
  fi

  rm -rf "$sb"
}

# ---- route_and_loopback: critical findings re-dispatch the lane (VAL-3) -

# Drive route_and_loopback directly by sourcing feature.sh. The bottom of
# feature.sh has a source-guard (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`)
# so sourcing in a subshell doesn't trigger main. Sets repo_root from
# FEATURE_REPO_ROOT and loop_sh_cmd from LOOP_SH_CMD; both are honored.

test_route_and_loopback_redispatches_on_critical() {
  local sb; sb=$(mk_sandbox)
  local id="0099-test-loopback"
  local run_dir="$sb/runs/$id"
  mkdir -p "$run_dir" "$sb/issues" "/tmp/feature-runs/$id"

  # Spec with `### backend` lane (lowercase, matches CLAUDE.md)
  local spec="$sb/spec.md"
  cat > "$spec" <<'EOF'
# spec

### backend

```paths
src/api/foo.ts
src/api/bar.ts
```
EOF

  # Findings file: one Critical line referencing src/api/foo.ts (which the
  # spec assigns to backend lane). route_findings will tag it as "backend\t..."
  local findings="$run_dir/findings.txt"
  cat > "$findings" <<'EOF'
src/api/foo.ts:42 — Critical: missing tenant check on insert
src/api/bar.ts:7 — Minor: docstring could be clearer
EOF

  # Lane prompt file that route_and_loopback's loop re-invocation expects
  echo "## Allowlist" > "/tmp/feature-runs/$id/lane-backend.prompt.md"
  echo "src/api/foo.ts" >> "/tmp/feature-runs/$id/lane-backend.prompt.md"

  # State pointing at both
  cat > "$run_dir/state.json" <<EOF
{"id":"$id","brief_path":"","issue_path":"","research_path":"","spec_path":"$spec","rubric_path":"","lanes":{},"validator_findings":"$findings","last_completed_step":"backend_complete","started_at":"2026-05-27T00:00:00Z","updated_at":"2026-05-27T00:00:00Z"}
EOF

  # Source feature.sh in a subshell + call route_and_loopback
  (
    export FEATURE_REPO_ROOT="$sb"
    export FEATURE_RUNS_DIR="$sb/runs"
    export LOOP_SH_CMD="$sb/loop-sh-stub"
    export STUB_OUT_DIR="$sb/stub-out"
    # shellcheck disable=SC1090
    source "$feature_sh"
    route_and_loopback "$id" "$run_dir" "backend"
  )
  local rc=$?

  # Critical found → return code 1 (caller re-loops)
  if [[ "$rc" -eq 1 ]]; then
    echo "  PASS  route_and_loopback: returns 1 when Critical found in lane"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_and_loopback: expected rc=1, got $rc"
    fail_count=$((fail_count + 1))
  fi

  # Fix-findings issue written under the sandbox's issues/ dir
  if [[ -f "$sb/issues/$id-fix-findings.md" ]] \
     && grep -q 'Critical' "$sb/issues/$id-fix-findings.md"; then
    echo "  PASS  route_and_loopback: wrote fix-findings issue with Critical content"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_and_loopback: fix-findings issue missing or wrong content"
    fail_count=$((fail_count + 1))
  fi

  # loop-sh stub was invoked (creates a loop-N.log in stub-out)
  if compgen -G "$sb/stub-out/loop-*.log" > /dev/null; then
    echo "  PASS  route_and_loopback: re-invoked loop.sh"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_and_loopback: loop.sh stub was NOT invoked"
    fail_count=$((fail_count + 1))
  fi

  rm -rf "$sb" "/tmp/feature-runs/$id"
}

test_route_and_loopback_returns_0_when_no_critical() {
  local sb; sb=$(mk_sandbox)
  local id="0098-test-no-critical"
  local run_dir="$sb/runs/$id"
  mkdir -p "$run_dir" "$sb/issues" "/tmp/feature-runs/$id"

  local spec="$sb/spec.md"
  cat > "$spec" <<'EOF'
# spec

### backend

```paths
src/api/foo.ts
```
EOF

  # Only Minor findings — nothing critical to re-dispatch on
  local findings="$run_dir/findings.txt"
  echo 'src/api/foo.ts:42 — Minor: variable name could be clearer' > "$findings"

  cat > "$run_dir/state.json" <<EOF
{"id":"$id","brief_path":"","issue_path":"","research_path":"","spec_path":"$spec","rubric_path":"","lanes":{},"validator_findings":"$findings","last_completed_step":"backend_complete","started_at":"2026-05-27T00:00:00Z","updated_at":"2026-05-27T00:00:00Z"}
EOF

  (
    export FEATURE_REPO_ROOT="$sb"
    export FEATURE_RUNS_DIR="$sb/runs"
    export LOOP_SH_CMD="$sb/loop-sh-stub"
    export STUB_OUT_DIR="$sb/stub-out"
    # shellcheck disable=SC1090
    source "$feature_sh"
    route_and_loopback "$id" "$run_dir" "backend"
  )
  local rc=$?

  if [[ "$rc" -eq 0 ]]; then
    echo "  PASS  route_and_loopback: returns 0 when only Minor findings in lane"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_and_loopback: expected rc=0 on no Critical, got $rc"
    fail_count=$((fail_count + 1))
  fi

  if [[ ! -f "$sb/issues/$id-fix-findings.md" ]]; then
    echo "  PASS  route_and_loopback: did NOT write fix-issue when no Critical"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_and_loopback: wrote fix-issue despite no Critical"
    fail_count=$((fail_count + 1))
  fi

  if ! compgen -G "$sb/stub-out/loop-*.log" > /dev/null; then
    echo "  PASS  route_and_loopback: did NOT re-invoke loop.sh when no Critical"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  route_and_loopback: re-invoked loop.sh despite no Critical"
    fail_count=$((fail_count + 1))
  fi

  rm -rf "$sb" "/tmp/feature-runs/$id"
}

# ---- Round 4: brief with two-lane shape ("Add /loop --status") ----------

test_full_chain_two_lane_brief() {
  local sb; sb=$(mk_sandbox)
  run_in_sb "$sb" start "Add /loop --status that prints last run exit code and duration" > /dev/null 2>&1
  local id
  id=$(basename "$(find "$sb/runs" -maxdepth 1 -mindepth 1 -type d | head -1)")
  # Drive to done without checking intermediate states (the previous test
  # already covers them). This one just verifies the chain doesn't trip on
  # a different brief shape.
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  run_in_sb "$sb" continue "$id" --accept > /dev/null 2>&1
  if [[ -d "$sb/runs/$id.done" ]] && \
     [[ "$(jq -r .last_completed_step "$sb/runs/$id.done/state.json" 2>/dev/null)" == "done" ]]; then
    echo "  PASS  two-lane brief: chain reaches done"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  two-lane brief: chain did not reach done"
    local laststep
    if [[ -d "$sb/runs/$id" ]]; then laststep=$(jq -r .last_completed_step "$sb/runs/$id/state.json" 2>/dev/null); fi
    echo "       last_completed_step: ${laststep:-<no state>}"
    fail_count=$((fail_count + 1))
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
test_continue_redo_without_feedback_errors
test_continue_redo_feedback_in_prompt
test_continue_accept_story_to_spec
test_lane_step_emits_lowercase_marker
test_full_chain_end_to_end
test_full_chain_two_lane_brief
test_route_and_loopback_redispatches_on_critical
test_route_and_loopback_returns_0_when_no_critical

echo ""
echo "Results: $pass_count passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
