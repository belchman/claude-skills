#!/bin/sh
# test_agent_loop_wired.sh — static wiring guard for the `watch` subcommand.
# Asserts SKILL.md routes/documents `watch` and the Makefile runs the watch
# suite under `test` (never `test-fast`). Pure grep/awk — no servers, no tmp.
# Run: sh tests/test_agent_loop_wired.sh
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SKILL="$REPO_ROOT/plugins/agent-loop/skills/agent-loop/SKILL.md"
README="$REPO_ROOT/plugins/agent-loop/README.md"
MAKEFILE="$REPO_ROOT/Makefile"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() { # $1=description, $2=exit code, $3=expected code
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (exit $2, wanted $3)"; fi
}

# Recipe block of one Makefile target: from `^<target>:` to the next
# non-indented line (recipe lines are tab-indented).
recipe() { # $1=target name
  awk -v tgt="$1" '
    $0 ~ "^" tgt ":" { in_recipe=1; next }
    /^[^\t]/         { in_recipe=0 }
    in_recipe' "$MAKEFILE"
}

echo "# SKILL.md routes the watch subcommand"
[ -f "$SKILL" ] || { bad "SKILL.md missing at $SKILL"; echo; echo "wired tests: $PASS passed, $FAIL failed"; exit 1; }

grep 'init|new|run' "$SKILL" | grep -q 'watch' \
  && ok "route list includes watch" \
  || bad "route list (init|new|run|...) does not include watch"

grep -q '^| `watch`' "$SKILL" \
  && ok "command table has a watch row" \
  || bad "command table has no | \`watch\` row"

grep -q '^## watch' "$SKILL" \
  && ok "## watch H2 section exists" \
  || bad "no ## watch H2 section"

WATCH_SECTION=$(awk '/^## watch/{f=1; next} /^## /{f=0} f' "$SKILL")
printf '%s' "$WATCH_SECTION" | grep -qi 'background' \
  && ok "watch section mentions backgrounding" \
  || bad "watch section does not mention backgrounding"
printf '%s' "$WATCH_SECTION" | grep -q -- '--allow-actions' \
  && ok "watch section mentions --allow-actions" \
  || bad "watch section does not mention --allow-actions"

echo "# Makefile wires the watch suite into the right budget"
recipe test | grep -q 'tests/test_agent_loop_watch\.sh' \
  && ok "test: recipe runs tests/test_agent_loop_watch.sh" \
  || bad "test: recipe does not run tests/test_agent_loop_watch.sh"

recipe test-fast | grep -q 'tests/test_agent_loop_watch\.sh' \
  && bad "test-fast: recipe runs the watch server suite (must stay out of the Stop-hook budget)" \
  || ok "test-fast: recipe excludes the watch server suite"

recipe test-fast | grep -q 'tests/test_agent_loop_wired\.sh' \
  && ok "test-fast: recipe runs tests/test_agent_loop_wired.sh (this guard)" \
  || bad "test-fast: recipe does not run tests/test_agent_loop_wired.sh"

echo "# Makefile wires the fleet-watch suite into the right budget"
recipe test | grep -q 'tests/test_agent_loop_fleet_watch\.sh' \
  && ok "test: recipe runs tests/test_agent_loop_fleet_watch.sh" \
  || bad "test: recipe does not run tests/test_agent_loop_fleet_watch.sh"

recipe test-fast | grep -q 'tests/test_agent_loop_fleet_watch\.sh' \
  && bad "test-fast: recipe runs the fleet-watch suite (must stay out of the Stop-hook budget)" \
  || ok "test-fast: recipe excludes the fleet-watch suite"

echo "# SKILL.md watch section documents the fleet probe"
printf '%s' "$WATCH_SECTION" | grep -q '/api/fleet' \
  && ok "watch section mentions the /api/fleet probe" \
  || bad "watch section does not mention /api/fleet"
printf '%s' "$WATCH_SECTION" | grep -qi '404' \
  && ok "watch section mentions the 404 / single-repo case" \
  || bad "watch section does not mention the 404 / single-repo case"

echo "# README documents the standing-server recipes"
[ -f "$README" ] \
  && ok "README exists at plugins/agent-loop/README.md" \
  || bad "README missing at $README"
grep -q 'KeepAlive' "$README" 2>/dev/null \
  && ok "README mentions KeepAlive (launchd recipe)" \
  || bad "README does not mention KeepAlive"
grep -q 'Restart=always' "$README" 2>/dev/null \
  && ok "README mentions Restart=always (systemd recipe)" \
  || bad "README does not mention Restart=always"

echo
echo "wired tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
