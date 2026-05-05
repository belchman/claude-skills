# work-issues

Autonomous, single-task pass over a markdown issue queue. Pairs with `prd-to-issues` (produces the queue) — `work-issues` consumes it.

Two ways to invoke:

- **Inside a Claude Code session** — say `/work-issues` or describe the task ("work the issue queue", "run an AFK iteration"). Claude reads `SKILL.md` and does one task end-to-end.
- **Headless / AFK** — run `bin/loop.sh` (looped) or `bin/once.sh` (single shot) from your shell. Both read the same `SKILL.md` as their prompt, so behavior is identical to the in-session version.

## Install in another project

Copy the skill directory into the target repo's `.claude/skills/`:

```bash
cp -R path/to/claude-skills/.claude/skills/work-issues /your/project/.claude/skills/
```

That's it. The skill is self-contained: scripts, prompt, and metadata all live under `work-issues/`.

## Project requirements

The skill assumes:

1. A git repo (used for commit history and committing work).
2. An issue queue at `issues/*.md` (override with `WORK_ISSUES_DIR`). Each `.md` file is one task. Tag tasks `HITL` to exclude them; everything else is treated as AFK-eligible.
3. Some form of feedback loop the agent can detect (test runner, type checker, linter). Node, Python, Go, and Rust are auto-detected; for anything else, document the loop in the project README so the agent finds it.

## Headless usage

```bash
# Run up to 10 iterations (default). Stops when the queue drains, the cap is
# hit, or a STOP sentinel file appears next to loop.sh.
./.claude/skills/work-issues/bin/loop.sh

# Run up to 50 iterations.
./.claude/skills/work-issues/bin/loop.sh 50

# Single iteration, interactive (uses --permission-mode acceptEdits).
./.claude/skills/work-issues/bin/once.sh

# Halt the loop gracefully between iterations.
touch ./.claude/skills/work-issues/bin/STOP
```

### Environment variables

| Var | Default | Purpose |
| --- | --- | --- |
| `WORK_ISSUES_CMD` | `claude` (loop) / `claude --permission-mode acceptEdits` (once) | How to invoke Claude. Set to `docker sandbox run claude .` to sandbox, or wrap with any other launcher. |
| `WORK_ISSUES_PROMPT` | `<skill>/SKILL.md` | Override the prompt source. |
| `WORK_ISSUES_DIR` | `issues` | Directory containing `*.md` issue files. |
| `WORK_ISSUES_COMMIT_LOG` | `5` | How many recent commits to include in context. |
| `WORK_ISSUES_STOP_FILE` | `<script_dir>/STOP` | Sentinel file path. Touch it to halt the loop. |

### Dependencies

- `bash` 4+
- `git`
- `jq` (loop.sh only — used to parse stream-json output)
- `claude` CLI on `PATH` (or set `WORK_ISSUES_CMD`)

The scripts validate dependencies on startup and exit with a clear error if anything is missing.

## How it works

Each iteration:

1. Gather context: last N commits + every issue file.
2. Send context + the (frontmatter-stripped) `SKILL.md` body to Claude.
3. Claude picks one AFK task, implements it (TDD when applicable), runs feedback loops, commits, and updates the issue file.
4. The runner watches the streamed output. If Claude emits `<promise>NO MORE TASKS</promise>`, the loop exits cleanly.

The shell scripts are thin — all of the workflow logic lives in `SKILL.md`. Edit that file to change behavior; both interactive and headless modes pick up the change.

## Stop conditions (loop.sh)

- Claude's final message contains `<promise>NO MORE TASKS</promise>`.
- The STOP sentinel file exists at the start of an iteration.
- Iteration cap reached.
- Claude exited non-zero (treated as a hard error — exit 3).

## Customizing the workflow

`SKILL.md` is the source of truth. Common edits:

- Change task priorities (the numbered list under "Task selection").
- Add or remove feedback-loop detection rules.
- Loosen / tighten the "Hard rules" section.

Both the `Skill`-tool invocation and the shell scripts read the same file, so a single edit applies everywhere.
