#!/bin/sh
# run-eval.sh — eval driver for the agent-loop plugin.
#
#   sh evals/agent-loop/run-eval.sh [--fixtures a,b] [--trials N] [scenario...]
#
#   scenario     scenario number(s) or names (default: all in scenarios/)
#   --fixtures   comma-separated fixture labels (default: sandbox; use
#                'all' for every configured fixture + built-ins)
#   --trials     repeat each scenario N times; pass = all trials pass
#                (Anthropic eval guidance: handle nondeterminism with trials)
#
# Preamble gates (run before ANY scenario; each is a hard fail):
#   1. privacy grep  — fixture identities from fixtures.local.json must appear
#                      nowhere in tracked or new repo files
#   2. leakage grep  — fixture labels must not appear inside plugins/agent-loop/
#                      (portability gate: the plugin knows no fixture)
#   3. model-free tests — tests/test_agent_loop_bin.sh (+ hooks when present)
#   4. docs-link lint — every D## the doctor emits has an anchor in
#                      references/doctor-checks.md
set -u

EVAL_DIR=$(cd "$(dirname "$0")" && pwd)
. "$EVAL_DIR/lib.sh"

FIXTURES="sandbox"
FIXTURES_EXPLICIT=0
TRIALS=1
SCENARIOS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fixtures) FIXTURES="$2"; FIXTURES_EXPLICIT=1; shift 2 ;;
    --trials)   TRIALS="$2"; shift 2 ;;
    *)          SCENARIOS="$SCENARIOS $1"; shift ;;
  esac
done
case "$TRIALS" in
  ''|*[!0-9]*|0) echo "run-eval.sh: --trials must be a positive integer (got '$TRIALS')"; exit 2 ;;
esac

echo "=== preamble gates ==="

# 1. privacy grep — identifying strings live ONLY in gitignored fixtures.local.json.
# Identifying = the absolute path and the "parent/base" compound fragment.
# Bare basenames are often dictionary words (false positives on unrelated
# code), so repo-wide we gate on the unambiguous forms; the plugin dir gets
# the stricter bare-word gate below.
PRIVATE_PATHS=""
PRIVATE_WORDS=""
if [ -f "$EVAL_DIR/fixtures.local.json" ]; then
  PRIVATE_PATHS=$(sed -n 's/.*"path": *"\([^"]*\)".*/\1/p' "$EVAL_DIR/fixtures.local.json" | grep -v '^/path/to' || true)
  PRIV_HITS=""
  for p in $PRIVATE_PATHS; do
    COMPOUND="$(basename "$(dirname "$p")")/$(basename "$p")"
    PRIVATE_WORDS="$PRIVATE_WORDS $(basename "$p") $(basename "$(dirname "$p")")"
    for s in "$p" "$COMPOUND"; do
      HITS=$(cd "$REPO_ROOT" && { git ls-files; git ls-files --others --exclude-standard; } \
        | grep -v '^evals/agent-loop/fixtures.local.json$' \
        | xargs grep -l -i -- "$s" 2>/dev/null || true)
      [ -n "$HITS" ] && PRIV_HITS="$PRIV_HITS [$s]: $HITS"
    done
  done
  if [ -n "$PRIV_HITS" ]; then
    echo "PRIVACY GATE FAIL: fixture identity found in repo files:$PRIV_HITS"
    exit 1
  fi
  echo "privacy grep: clean"
else
  echo "privacy grep: no fixtures.local.json (built-ins only)"
fi

# 2. leakage grep — the plugin must know no fixture: even bare fixture-path
# words are forbidden inside plugins/agent-loop/ (portability gate)
for s in $PRIVATE_WORDS; do
  if grep -r -l -i -- "$s" "$PLUGIN_DIR" >/dev/null 2>&1; then
    echo "LEAKAGE GATE FAIL: '$s' appears inside plugins/agent-loop/"
    exit 1
  fi
done
echo "leakage grep: clean"

# 3. model-free tests
for t in "$REPO_ROOT/tests/test_agent_loop_bin.sh" "$REPO_ROOT/tests/test_agent_loop_hooks.sh" "$REPO_ROOT/tests/test_agent_loop_loop.sh"; do
  [ -f "$t" ] || continue
  if ! sh "$t" > /tmp/al-eval-unit.$$ 2>&1; then
    echo "UNIT TEST GATE FAIL: $t"
    tail -20 /tmp/al-eval-unit.$$
    rm -f /tmp/al-eval-unit.$$
    exit 1
  fi
  echo "unit tests: $(basename "$t") green"
done
rm -f /tmp/al-eval-unit.$$ 2>/dev/null || true

# 4. docs-link lint
DOCTOR_IDS=$(grep -o 'report D[0-9][0-9]' "$PLUGIN_DIR/bin/al-doctor" | sort -u | awk '{print $2}')
DOC="$PLUGIN_DIR/skills/agent-loop/references/doctor-checks.md"
if [ -f "$DOC" ]; then
  MISSING_DOC=""
  for id in $DOCTOR_IDS; do
    anchor=$(echo "$id" | tr 'A-Z' 'a-z')
    grep -qi "^#* *$id\|{#$anchor}" "$DOC" || MISSING_DOC="$MISSING_DOC $id"
  done
  if [ -n "$MISSING_DOC" ]; then
    echo "DOCS-LINK GATE FAIL: doctor IDs without anchors in doctor-checks.md:$MISSING_DOC"
    exit 1
  fi
  echo "docs-link lint: all $(echo "$DOCTOR_IDS" | wc -w | tr -d ' ') doctor IDs anchored"
else
  echo "docs-link lint: SKIPPED (doctor-checks.md not written yet)"
fi

# --- scenario matrix ---------------------------------------------------------
[ -n "$SCENARIOS" ] || SCENARIOS=$(ls "$EVAL_DIR/scenarios" 2>/dev/null)
if [ "$FIXTURES" = "all" ]; then
  FIXTURE_LIST=$(fixture_labels)
else
  FIXTURE_LIST=$(echo "$FIXTURES" | tr ',' ' ')
fi

RUNS_DIR="$EVAL_DIR/runs/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUNS_DIR"
TOTAL=0; FAILED=0

for spec in $SCENARIOS; do
  # allow "01" shorthand for "01-init-cold"
  SCEN_DIR=$(ls -d "$EVAL_DIR/scenarios/$spec"* 2>/dev/null | head -1)
  [ -n "$SCEN_DIR" ] && [ -d "$SCEN_DIR" ] || { echo "unknown scenario: $spec"; exit 2; }
  SCEN=$(basename "$SCEN_DIR")
  MAX_TURNS=$("$PLUGIN_DIR/bin/al-json" get "$SCEN_DIR/scenario.json" max_turns 2>/dev/null || echo 40)
  SKIP_NOGIT=$("$PLUGIN_DIR/bin/al-json" get "$SCEN_DIR/scenario.json" skip_nogit 2>/dev/null || echo false)

  for fixture in $FIXTURE_LIST; do
    [ "$fixture" = "sandbox-nogit" ] && [ "$SKIP_NOGIT" = "true" ] && continue
    trial=1
    while [ "$trial" -le "$TRIALS" ]; do
      TOTAL=$((TOTAL + 1))
      TAG="$SCEN/$fixture${TRIALS:+.t$trial}"
      echo ""
      echo "=== $TAG (max_turns=$MAX_TURNS) ==="
      if ! wt_create "$fixture"; then
        if [ "$FIXTURES_EXPLICIT" = "1" ] && [ "$FIXTURES" != "all" ]; then
          # explicitly requested fixture must exist — silent skips hide misconfig
          echo "  FAIL - explicitly requested fixture '$fixture' unavailable"
          FAILED=$((FAILED + 1)); break
        fi
        echo "  SKIP - fixture '$fixture' unavailable"
        TOTAL=$((TOTAL - 1)); break
      fi
      trap 'wt_destroy' EXIT INT TERM
      OUT="$RUNS_DIR/$SCEN.$fixture.t$trial.json"

      sh "$SCEN_DIR/setup.sh" "$WT" || { echo "  setup failed"; FAILED=$((FAILED+1)); wt_destroy; trial=$((trial+1)); continue; }
      run_claude "$SCEN_DIR/prompt.txt" "$MAX_TURNS" "$OUT" || true
      # two-phase scenarios (plan-approval flow): leg 1 proposes and pauses,
      # between.sh acts as the human (deterministic, no model), leg 2
      # executes the approved plan. OUT1 = leg-1 transcript, OUT = final.
      OUT1=""
      TWO_PHASE=$("$PLUGIN_DIR/bin/al-json" get "$SCEN_DIR/scenario.json" two_phase 2>/dev/null || echo false)
      if [ "$TWO_PHASE" = "true" ]; then
        OUT1="$OUT"
        OUT="$RUNS_DIR/$SCEN.$fixture.t$trial.leg2.json"
        sh "$SCEN_DIR/between.sh" "$WT" || { echo "  between.sh failed"; FAILED=$((FAILED+1)); wt_destroy; trial=$((trial+1)); continue; }
        run_claude "$SCEN_DIR/prompt2.txt" "$MAX_TURNS" "$OUT" || true
      fi
      # score.sh runs in its own shell; it sources lib.sh for assert helpers.
      # Env contract: WT, WT_FIXTURE, WT_HEAD, OUT (final transcript),
      # OUT1 (leg-1 transcript, two-phase only), PLUGIN_DIR.
      if WT="$WT" WT_FIXTURE="$WT_FIXTURE" WT_HEAD="$WT_HEAD" OUT="$OUT" OUT1="$OUT1" \
         PLUGIN_DIR="$PLUGIN_DIR" EVAL_DIR="$EVAL_DIR" sh "$SCEN_DIR/score.sh"; then
        :
      else
        FAILED=$((FAILED + 1))
      fi
      wt_destroy
      trap - EXIT INT TERM
      trial=$((trial + 1))
    done
  done
done

echo ""
echo "=== eval summary: $((TOTAL - FAILED))/$TOTAL passed ==="
if [ "$TOTAL" -eq 0 ]; then
  echo "run-eval.sh: no scenarios ran"
  exit 1
fi
[ "$FAILED" -eq 0 ]
