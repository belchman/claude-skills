#!/usr/bin/env bash
# Tests for plugins/agentic-engineering/skills/feature/bin/feature-helpers.sh.
# Run directly: bash tests/test_feature_helpers.sh
# Exit code 0 = all tests pass; non-zero = at least one failure.

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$repo_root/plugins/agentic-engineering/skills/feature/bin/feature-helpers.sh"
work_issues_lib="$repo_root/plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh"

pass_count=0
fail_count=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS  $name"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  $name"
    echo "    expected: $(printf '%q' "$expected")"
    echo "    actual:   $(printf '%q' "$actual")"
    fail_count=$((fail_count + 1))
  fi
}

assert_true() {
  local name="$1"; shift
  if "$@"; then
    echo "  PASS  $name"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  $name (exit $?)"
    fail_count=$((fail_count + 1))
  fi
}

assert_false() {
  local name="$1"; shift
  if ! "$@"; then
    echo "  PASS  $name"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  $name (expected failure but exit was 0)"
    fail_count=$((fail_count + 1))
  fi
}

# ---- HLP-1: lib exposes required functions -------------------------------

test_lib_exposes_required_functions() {
  # shellcheck disable=SC1090
  source "$lib"
  local fns
  fns=$(declare -F | awk '{print $3}')
  for fn in state_read state_write state_field acquire_lock release_lock route_findings; do
    if grep -qFx "$fn" <<< "$fns"; then
      echo "  PASS  helpers expose function: $fn"
      pass_count=$((pass_count + 1))
    else
      echo "  FAIL  helpers missing function: $fn"
      fail_count=$((fail_count + 1))
    fi
  done
}

# ---- HLP-2: lib sources work-issues-lib (no redefinitions) ---------------

test_lib_sources_work_issues_lib() {
  if grep -qE 'source.*work-issues-lib\.sh|\. .*work-issues-lib\.sh' "$lib"; then
    echo "  PASS  helpers sources work-issues-lib.sh"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  helpers does NOT source work-issues-lib.sh"
    fail_count=$((fail_count + 1))
  fi
  if grep -qE '^[[:space:]]*(allowlist_for|strip_frontmatter|list_issue_files)\(\)' "$lib"; then
    echo "  FAIL  helpers redefines a work-issues-lib function"
    fail_count=$((fail_count + 1))
  else
    echo "  PASS  helpers does NOT redefine work-issues-lib functions"
    pass_count=$((pass_count + 1))
  fi
}

# ---- state_read / state_write / state_field ------------------------------

test_state_write_and_read_roundtrip() {
  # shellcheck disable=SC1090
  source "$lib"
  local tmpdir
  tmpdir=$(mktemp -d)
  state_write "$tmpdir/state.json" '{"id":"0042-foo","last_completed_step":"init"}'
  local got
  got=$(state_read "$tmpdir/state.json")
  rm -rf "$tmpdir"
  # JSON should round-trip with the same content
  if [[ "$got" == *'"id"'* && "$got" == *'"0042-foo"'* && "$got" == *'"last_completed_step"'* && "$got" == *'"init"'* ]]; then
    echo "  PASS  state_write/state_read round-trip preserves content"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  state_write/state_read round-trip lost content: $got"
    fail_count=$((fail_count + 1))
  fi
}

test_state_field_extracts() {
  # shellcheck disable=SC1090
  source "$lib"
  local tmpdir
  tmpdir=$(mktemp -d)
  state_write "$tmpdir/state.json" '{"id":"0042-foo","last_completed_step":"spec_drafted","nested":{"key":"val"}}'
  local id step nested
  id=$(state_field "$tmpdir/state.json" id)
  step=$(state_field "$tmpdir/state.json" last_completed_step)
  rm -rf "$tmpdir"
  assert_eq "state_field extracts top-level string (id)" "0042-foo" "$id"
  assert_eq "state_field extracts top-level string (last_completed_step)" "spec_drafted" "$step"
}

# ---- acquire_lock / release_lock -----------------------------------------

test_acquire_lock_creates_pidfile_with_self_pid() {
  # shellcheck disable=SC1090
  source "$lib"
  local tmpdir
  tmpdir=$(mktemp -d)
  acquire_lock "$tmpdir/LOCK" "$$"
  local pid
  pid=$(cat "$tmpdir/LOCK")
  rm -rf "$tmpdir"
  assert_eq "acquire_lock writes our PID" "$$" "$pid"
}

test_acquire_lock_refuses_when_held_by_live_pid() {
  # shellcheck disable=SC1090
  source "$lib"
  local tmpdir
  tmpdir=$(mktemp -d)
  # First acquire — succeeds
  acquire_lock "$tmpdir/LOCK" "$$"
  # Second acquire by a "different process" pointing at our PID — should refuse
  local exit_code
  acquire_lock "$tmpdir/LOCK" 99999 2>/dev/null; exit_code=$?
  rm -rf "$tmpdir"
  if (( exit_code != 0 )); then
    echo "  PASS  acquire_lock refuses second acquisition when held by live PID"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  acquire_lock should refuse second acquisition (got exit $exit_code)"
    fail_count=$((fail_count + 1))
  fi
}

test_acquire_lock_steals_stale_lock() {
  # shellcheck disable=SC1090
  source "$lib"
  local tmpdir
  tmpdir=$(mktemp -d)
  # Write a stale PID (very high number unlikely to exist)
  echo "987654321" > "$tmpdir/LOCK"
  # Fresh acquire should succeed — stale lock is stolen
  local exit_code
  acquire_lock "$tmpdir/LOCK" "$$"; exit_code=$?
  local pid
  pid=$(cat "$tmpdir/LOCK")
  rm -rf "$tmpdir"
  if (( exit_code == 0 )) && [[ "$pid" == "$$" ]]; then
    echo "  PASS  acquire_lock steals stale lock (DEP-3)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  acquire_lock should steal stale lock (exit=$exit_code pid=$pid)"
    fail_count=$((fail_count + 1))
  fi
}

test_release_lock_removes_pidfile() {
  # shellcheck disable=SC1090
  source "$lib"
  local tmpdir
  tmpdir=$(mktemp -d)
  acquire_lock "$tmpdir/LOCK" "$$"
  release_lock "$tmpdir/LOCK"
  if [[ ! -f "$tmpdir/LOCK" ]]; then
    echo "  PASS  release_lock removes pidfile"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  release_lock did NOT remove pidfile"
    fail_count=$((fail_count + 1))
  fi
  rm -rf "$tmpdir"
}

# ---- route_findings (consumer of work-issues-lib::allowlist_for) ---------
# Already tested in test_work_issues_lib.sh — the function itself lives in
# work-issues-lib.sh. Here we just verify the helpers re-export / can call it.

test_helpers_can_call_route_findings() {
  # shellcheck disable=SC1090
  source "$lib"
  if declare -F route_findings >/dev/null; then
    echo "  PASS  helpers expose route_findings (via work-issues-lib source)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL  helpers did NOT expose route_findings"
    fail_count=$((fail_count + 1))
  fi
}

# ---- run -----------------------------------------------------------------

if [[ ! -f "$lib" ]]; then
  echo "  SETUP FAIL  feature-helpers.sh not found at: $lib"
  fail_count=$((fail_count + 1))
fi

test_lib_exposes_required_functions
test_lib_sources_work_issues_lib
test_state_write_and_read_roundtrip
test_state_field_extracts
test_acquire_lock_creates_pidfile_with_self_pid
test_acquire_lock_refuses_when_held_by_live_pid
test_acquire_lock_steals_stale_lock
test_release_lock_removes_pidfile
test_helpers_can_call_route_findings

echo ""
echo "Results: $pass_count passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
