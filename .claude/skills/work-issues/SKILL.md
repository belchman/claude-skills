---
name: work-issues
description: Autonomously work one task from an issues/ queue end-to-end — explore, implement (TDD when applicable), run feedback loops, commit, update the issue file. Use when the user invokes /work-issues, asks to "work the issue queue", "run an AFK iteration", or wants a single-task autonomous pass over markdown issues. Pairs with prd-to-issues (which produces the queue). Headless loop runner: bin/loop.sh in this skill.
---

# work-issues — one autonomous iteration

Do exactly **one** AFK task end-to-end, then stop. Headless wrappers (`bin/loop.sh`, `bin/once.sh`) read this same file as their prompt — keep workflow rules here only.

## Inputs

You need two things in context:

- **Issues**: every `*.md` under `issues/` (or whatever the project uses). AFK-eligible only — skip anything tagged HITL.
- **Recent commits**: last ~5 commits, so you don't repeat or undo prior work.

Headless mode pre-pastes both into the prompt. Interactive mode (e.g. `/work-issues`) — gather them yourself:

```bash
git log -n 5 --format="%H%n%ad%n%B---" --date=short
ls issues/*.md  # then read the relevant ones
```

If `issues/` doesn't exist, ask the user where the queue lives or whether to run `prd-to-issues` first. Don't invent tasks.

## Done check

If no AFK tasks remain, output exactly `<promise>NO MORE TASKS</promise>` and stop. The loop runner uses this string to exit cleanly.

## Task selection — pick **one**, in priority order

1. Critical bugfixes
2. Dev infrastructure (tests, types, dev scripts) — unblocks feature work
3. Tracer bullets — thin end-to-end slice through every layer of a new feature
4. Polish and quick wins
5. Refactors

## Exploration

Read before editing. Open the issue, files it references, and adjacent code. Don't guess at structure.

## Implementation

If the task fits TDD (testable behavior change), use the `tdd` skill. Otherwise: smallest correct change, then verify.

Don't bundle unrelated work. If you find a second problem, append a note to its issue file or open a new one — don't fix it now.

## Feedback loops

Detect and run the project's loops before committing:

- **Node**: scripts in `package.json` (e.g. `npm test`, `npm run typecheck`, `npm run lint`)
- **Python**: `pytest`, `ruff`, `mypy` per `pyproject.toml` / `Makefile`
- **Go**: `go test ./...`, `go vet ./...`
- **Rust**: `cargo test`, `cargo clippy`
- **Other**: whatever the README or CI uses

Don't commit a red build. If a loop fails for reasons unrelated to your change, note it in the commit message and the issue file — don't suppress.

## Commit

One commit per iteration. Message must include:

1. Key decisions and why
2. Files changed (high-level summary)
3. Blockers or notes for next iteration

Do **not** add Claude as a co-author.

## Issue housekeeping

- Complete → move to `issues/done/` (create if missing).
- Incomplete → append a dated note: what you did, what remains, blockers.

## Hard rules

- One task per iteration.
- No destructive git ops (`reset --hard`, `push --force`, branch deletion) unless the issue explicitly authorizes them.
- Unexpected repo state (uncommitted work you didn't make, detached HEAD, in-progress merge/rebase) → stop, write an issue describing it, exit. Don't guess.
- The runner halts before this skill is entered when a `STOP` sentinel exists; no need to check yourself.
