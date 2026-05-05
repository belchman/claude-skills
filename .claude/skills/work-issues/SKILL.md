---
name: work-issues
description: Autonomously work one task from an issues/ queue end-to-end — explore, implement (TDD when applicable), run feedback loops, commit, update the issue file. Use when the user invokes /work-issues, asks to "work the issue queue", "run an AFK iteration", or wants a single-task autonomous pass over markdown issues. Pairs with prd-to-issues (which produces the queue). Headless loop runner: bin/loop.sh in this skill.
---

# work-issues — one autonomous iteration

Do exactly **one** AFK task end-to-end, then stop. Headless wrappers (`bin/loop.sh`, `bin/once.sh`) read this same file as their prompt — keep instructions here and nowhere else.

## Inputs

You need two things in context before you start:

- **Issues**: every `*.md` under `issues/` (or whatever directory the project uses for an issue queue). AFK-eligible only — skip anything tagged HITL.
- **Recent commits**: last ~5 commits on the current branch, so you don't repeat or undo prior work.

If invoked headlessly via `bin/loop.sh` / `bin/once.sh`, both are pre-pasted into the prompt as `Previous commits: …  Issues: …`. If invoked interactively (e.g. via `/work-issues`), gather them yourself:

```bash
git log -n 5 --format="%H%n%ad%n%B---" --date=short
ls issues/*.md  # then read the relevant ones
```

If `issues/` doesn't exist, ask the user where the queue lives or whether they want `prd-to-issues` run first. Don't invent tasks.

## Done check

If there are no AFK tasks left, output exactly `<promise>NO MORE TASKS</promise>` and stop. The loop runner uses this string to exit cleanly.

## Task selection

Pick **one** task. Priority order:

1. Critical bugfixes
2. Development infrastructure (tests, types, dev scripts) — these unblock feature work
3. Tracer bullets — a thin end-to-end slice through all layers of a new feature, expanded later
4. Polish and quick wins
5. Refactors

## Exploration

Read before editing. Open the issue, the files it references, and adjacent code. Don't guess at structure.

## Implementation

If the task fits TDD (a behavior change with a testable outcome), use the `tdd` skill. Otherwise: smallest correct change, then verify.

Do not bundle unrelated work. If you discover a second problem, append a note to its issue file or create a new one — do not fix it in this iteration.

## Feedback loops

Detect the project's loops from the repo and run them before committing:

- **Node**: scripts in `package.json` (typically `npm test`, `npm run typecheck`, `npm run lint`)
- **Python**: `pytest`, `ruff`, `mypy` per `pyproject.toml` / `Makefile`
- **Go**: `go test ./...`, `go vet ./...`
- **Rust**: `cargo test`, `cargo clippy`
- **Other**: whatever the README or CI defines

Do not commit a red build. If a loop fails for reasons unrelated to your change, note it in the commit message and the issue file rather than suppressing it.

## Commit

One commit per iteration. The message must include:

1. Key decisions and why
2. Files changed (high-level summary, not a `--stat` dump)
3. Blockers or notes for the next iteration

Do **not** add Claude as a co-author.

## Issue file housekeeping

- Task complete → move the issue file to `issues/done/` (create the directory if it doesn't exist).
- Task incomplete → append a dated note to the issue file: what you did, what remains, any blocker.

## Hard rules

- One task per iteration. No exceptions.
- Never run destructive git ops (`reset --hard`, `push --force`, branch deletion) unless the issue explicitly authorizes them.
- If the repo is in an unexpected state (uncommitted changes you didn't make, detached HEAD, in-progress merge/rebase) — stop, write an issue describing what you found, and exit. Do not guess.
- If invoked from `bin/loop.sh`, the runner halts before this skill is entered when a `STOP` sentinel exists next to the script. You don't need to check it yourself.
