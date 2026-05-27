#!/usr/bin/env bash
# Shared helpers for the /feature orchestrator (bin/feature.sh).
# Sourced, not executed. Requires bash 4+ (associative arrays from
# work-issues-lib.sh::route_findings).
#
# Functions:
#   state_read <path>         Print the JSON state file contents.
#   state_write <path> <json> Write the JSON string to the state file
#                             (overwrites). Pretty-prints via jq if jq
#                             is available; otherwise writes raw.
#   state_field <path> <key>  Print the value of a top-level field. Uses
#                             jq when available, falls back to grep/sed
#                             for simple string fields.
#   acquire_lock <pidfile> <pid>
#                             Try to claim a pidfile-based lock. Success
#                             writes <pid> to <pidfile> and exits 0.
#                             Refuses (exit 1) when an existing pidfile
#                             names a still-live process. Steals a stale
#                             pidfile (PID not running) — see DEP-3.
#   release_lock <pidfile>    Remove the pidfile (no-op if missing).
#   route_findings <findings> <spec>
#                             Re-exported from work-issues-lib.sh via the
#                             source line below. See that lib for full
#                             semantics.

# Resolve the work-issues lib relative to this file so the orchestrator
# can be relocated without breaking the source.
__feature_helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__work_issues_lib="$__feature_helpers_dir/../../work-issues/bin/work-issues-lib.sh"
if [[ ! -f "$__work_issues_lib" ]]; then
  echo "feature-helpers: cannot find work-issues-lib.sh at $__work_issues_lib" >&2
  return 1 2>/dev/null || exit 1
fi
# shellcheck source=../../work-issues/bin/work-issues-lib.sh
source "$__work_issues_lib"

# ---- state I/O ------------------------------------------------------------

state_read() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  cat "$path"
}

state_write() {
  local path="$1" json="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq . > "$path"
  else
    printf '%s\n' "$json" > "$path"
  fi
}

state_field() {
  local path="$1" key="$2"
  [[ -f "$path" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$path"
  else
    # Fallback: extract a simple string value `"<key>": "<value>"` with
    # no nested escaping. Good enough for the fields we use.
    grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$path" \
      | head -1 \
      | sed -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
  fi
}

# ---- locking --------------------------------------------------------------

acquire_lock() {
  local pidfile="$1" mypid="$2"
  if [[ -f "$pidfile" ]]; then
    local held_pid
    held_pid=$(cat "$pidfile" 2>/dev/null)
    # Stale lock: PID empty or no longer running → steal it.
    if [[ -z "$held_pid" ]] || ! kill -0 "$held_pid" 2>/dev/null; then
      : # fall through to acquire
    else
      echo "acquire_lock: lock at $pidfile is held by live PID $held_pid" >&2
      return 1
    fi
  fi
  printf '%s\n' "$mypid" > "$pidfile"
}

release_lock() {
  local pidfile="$1"
  rm -f "$pidfile"
}

# route_findings is sourced from work-issues-lib.sh above. Re-asserted here
# for the test that checks the function is reachable from this lib.
