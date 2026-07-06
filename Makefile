# Canonical test entry points. The Stop hook (.claude/hooks/test-on-stop.sh)
# runs `test-fast` after every turn; CI (.github/workflows/ci.yml) runs
# `lint` + `test`.
.PHONY: test test-fast test-sync lint

# Shell lint over the agent-loop bin/hook layer. Skips gracefully when
# shellcheck isn't installed locally; CI installs it and fails on findings.
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -S error plugins/agent-loop/bin/al-loop.sh plugins/agent-loop/bin/install.sh plugins/agent-loop/hooks/*.sh .claude/hooks/*.sh && echo "lint: clean"; \
	else echo "lint: shellcheck not installed — skipped (CI runs it)"; fi

# Parity guard: marketplace.json ↔ plugins/*/plugin.json ↔ README.md.
test-sync:
	bash tests/test_marketplace_sync.sh

# Fast suite (~5s).
test-fast: test-sync
	python3 -m pytest -q
	bash tests/test_feature_helpers.sh
	bash tests/test_work_issues_lib.sh
	bash tests/test_agent_loop_wired.sh

# Everything (~4 min): fast suite + agent-loop bin/hook/loop/watch/fleet
# suites + the /feature orchestrator integration tests.
test: test-fast
	bash tests/test_agent_loop_loop.sh
	bash tests/test_agent_loop_hooks.sh
	bash tests/test_agent_loop_bin.sh
	bash tests/test_agent_loop_watch.sh
	bash tests/test_agent_loop_fleet_watch.sh
	bash tests/test_feature_orchestrator.sh
