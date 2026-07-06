#!/bin/sh
# lib.sh — worktree lifecycle + claude runner for agent-loop evals.
# Sourced by run-eval.sh and scenario scripts.
#
# Isolation contract (hard requirements):
#   - every scenario runs in a throwaway checkout, never the fixture itself
#   - git fixtures: detached worktree (git worktree add --detach) — --detach
#     avoids the same-branch refusal; removal via worktree remove --force +
#     prune, in a trap so failures still clean up  [git-scm.com/docs/git-worktree]
#   - NOTHING is ever committed: AGENT_LOOP_EVAL=1 makes guard-destructive.sh
#     deny git commit/push, and score-time asserts HEAD is unchanged
#   - built-in fixtures: 'sandbox' (generated throwaway git repo in mktemp;
#     git init in an eval-owned temp dir only) and 'sandbox-nogit' (plain dir)

EVAL_DIR=${EVAL_DIR:-$(cd "$(dirname "$0")" && pwd)}
REPO_ROOT=$(cd "$EVAL_DIR/../.." && pwd)
PLUGIN_DIR=${PLUGIN_DIR:-$REPO_ROOT/plugins/agent-loop}

# --- fixture resolution -----------------------------------------------------
fixture_path() { # $1=label -> echoes repo path, or empty for built-ins
  case "$1" in
    sandbox|sandbox-nogit) echo "" ;;
    *)
      [ -f "$EVAL_DIR/fixtures.local.json" ] || { echo ""; return 1; }
      "$PLUGIN_DIR/bin/al-json" get "$EVAL_DIR/fixtures.local.json" "$1.path" 2>/dev/null
      ;;
  esac
}

fixture_labels() { # all runnable labels: built-ins + configured
  echo "sandbox"
  echo "sandbox-nogit"
  if [ -f "$EVAL_DIR/fixtures.local.json" ]; then
    sed -n 's/^  "\([^_"][^"]*\)": {.*/\1/p' "$EVAL_DIR/fixtures.local.json"
  fi
}

# --- worktree lifecycle -----------------------------------------------------
# Globals set by wt_create: WT (worktree path), WT_FIXTURE (repo path or ""),
# WT_HEAD (fixture HEAD at creation, for the no-commit assertion)
wt_create() { # $1=fixture-label
  _label="$1"
  WT=$(mktemp -d "${TMPDIR:-/tmp}/al-eval-XXXXXX")
  # canonicalize (macOS /var -> /private/var): the model resolves symlinks, and
  # a cwd that differs from the canonical path makes every write look
  # out-of-workspace -> permission denials in headless runs
  WT=$(cd "$WT" && pwd -P)
  WT_FIXTURE=""
  WT_HEAD=""
  case "$_label" in
    sandbox)
      ( cd "$WT" && git init -q && \
        printf 'hello\n' > seed.txt && \
        printf '# sandbox\nA generated throwaway repo for agent-loop evals.\n' > README.md && \
        git add -A && \
        git -c user.email=eval@localhost -c user.name=al-eval commit -qm seed )
      WT_FIXTURE="$WT"
      WT_HEAD=$(git -C "$WT" rev-parse HEAD)
      ;;
    sandbox-nogit)
      printf 'hello\n' > "$WT/seed.txt"
      ;;
    *)
      _repo=$(fixture_path "$_label")
      [ -n "$_repo" ] && [ -d "$_repo" ] || { echo "lib.sh: fixture '$_label' not configured/found" >&2; return 1; }
      rmdir "$WT"
      git -C "$_repo" worktree add --detach "$WT" >/dev/null 2>&1 || return 1
      WT_FIXTURE="$_repo"
      WT_HEAD=$(git -C "$_repo" rev-parse HEAD)
      ;;
  esac
  export WT WT_FIXTURE WT_HEAD
}

wt_destroy() {
  [ -n "${WT:-}" ] || return 0
  if [ -n "$WT_FIXTURE" ] && [ "$WT_FIXTURE" != "$WT" ]; then
    git -C "$WT_FIXTURE" worktree remove --force "$WT" >/dev/null 2>&1 || true
    git -C "$WT_FIXTURE" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$WT" 2>/dev/null || true
  WT=""; WT_FIXTURE=""; WT_HEAD=""
}

# --- claude runner ----------------------------------------------------------
run_claude() { # $1=prompt-file $2=max-turns $3=output-json-path ; cwd=$WT
  # bypassPermissions is required: .claude/ is a built-in sensitive path that
  # headless --allowedTools/acceptEdits cannot cover (verified empirically),
  # and init's whole job is writing .claude/. Safe here because every run is
  # inside a throwaway worktree and guard-destructive.sh still denies
  # git commit/push under AGENT_LOOP_EVAL=1 even in bypass mode (verified:
  # hook exit-2 denials fire regardless of permission mode).
  ( cd "$WT" && \
    AGENT_LOOP_EVAL=1 claude \
      --plugin-dir "$PLUGIN_DIR" \
      -p "$(cat "$1")" \
      --permission-mode bypassPermissions \
      --max-turns "$2" \
      --output-format json ) > "$3" 2>"$3.stderr"
}

# --- assertion helpers (used by score.sh) ------------------------------------
SCORE_FAILS=0
assert() { # $1=description, $2...=command
  _desc="$1"; shift
  if _out=$("$@" 2>&1); then
    echo "  ok  - $_desc"
  else
    echo "  FAIL - $_desc"
    # show what the failing command said (first 10 lines) so failed
    # scenarios are debuggable without a rerun
    [ -n "$_out" ] && printf '%s\n' "$_out" | head -10 | sed 's/^/         > /'
    SCORE_FAILS=$((SCORE_FAILS + 1))
  fi
}
assert_file()     { assert "$1 exists" test -f "$1"; }
assert_dir()      { assert "$1/ exists" test -d "$1"; }
assert_grep()     { assert "$3" grep -q "$1" "$2"; }
assert_no_commit() { # uses WT_FIXTURE/WT_HEAD
  if [ -n "$WT_FIXTURE" ] && [ -n "$WT_HEAD" ]; then
    assert "no commits made (HEAD unchanged)" test "$(git -C "$WT_FIXTURE" rev-parse HEAD)" = "$WT_HEAD"
  fi
}
score_result() {
  if [ "$SCORE_FAILS" -eq 0 ]; then echo "  SCENARIO PASS"; return 0
  else echo "  SCENARIO FAIL ($SCORE_FAILS assertion(s))"; return 1; fi
}
