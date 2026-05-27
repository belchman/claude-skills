# PRD — Feature Factory

**Source-of-truth for technical decisions:** [`docs/plans/feature-factory.md`](../docs/plans/feature-factory.md) (rev. 2). This PRD captures the user/business framing the plan doesn't.

**Status:** v1 — dogfood-only, no public docs.
**Primary user:** engineers who have `agentic-engineering` installed.
**Validator:** matt (sole v1 user — feeds back via `docs/lessons-learned/feature-factory-build.md`).

## Problem Statement

A single Claude session asked to "build feature X" collapses six distinct jobs — product analyst, architect, backend engineer, frontend engineer, test engineer, code reviewer — into one chat with one context window. As the chat grows, wrong assumptions made early (e.g., "store IDs in memory") become wrong database models, wrong APIs, wrong UIs. By the time a real bug surfaces, the mistake has spread across many files. The engineer ends up supervising AI more than they would have spent writing the code themselves.

The `agentic-engineering` plugin already solves *parts* of this — `/work-issues` runs autonomous TDD, `/adversarial-review` finds gaps after the fact, `write-a-rubric` defines what done looks like. But there's no orchestrator that **chains these together with human checkpoints in the right places**, and there's no clean separation between "backend lane" and "frontend lane" so one mistake can't bleed across.

## Solution

A single user-facing command — `/feature "<brief>"` — that drives the whole pipeline and pauses for the human at exactly three load-bearing moments: **after the story is drafted, after the spec is drafted, before the PR is opened**. Everything in between runs autonomously through existing skills (`/map`, an `Explore` subagent for research, `write-a-spec` (new), `write-a-rubric`, `/work-issues` per lane, `/adversarial-review` as validator).

State persists in `.feature_runs/<id>/state.json`, so the engineer can close the terminal between checkpoints and resume with `feature.sh continue <id>`. Lane scoping (backend vs frontend) is enforced by injecting an allowlist into `/work-issues`'s prompt via the existing `WORK_ISSUES_PROMPT` env hook — no fork of the shell wrappers.

The engineer stays in the loop where their judgment matters (is this the right problem, the right design, safe to ship) and the agents handle everything in between.

## User Stories

1. As an engineer with `agentic-engineering` installed, I want to run `/feature "build invoice reminders for invoices unpaid >7 days"` and have the chain auto-produce a research dump, a draft story, and pause for me to approve the story, so that I don't have to manage seven separate prompts and remember where the work is.

2. As an engineer, after approving the story I want the chain to auto-produce a technical spec (data model + API shape + file-by-file change list) and a gradeable rubric, then pause for my approval, so that I catch wrong architectural assumptions BEFORE any code is written.

3. As an engineer, after approving the spec I want the chain to autonomously build the backend, run a validator pass, then build the frontend, then run a final validator — without me babysitting each iteration — so that I can step away and come back to a working diff.

4. As an engineer, I want the backend builder physically scoped to backend paths and the frontend builder scoped to frontend paths (per the spec's file list), so that a confused agent can't accidentally edit the other lane and break it.

5. As an engineer, I want the validator (adversarial-review) to run in report-only mode without prompting me for fix-mode, so that the orchestrator can dispatch it programmatically without my keyboard.

6. As an engineer, if the validator finds Critical issues, I want them auto-routed to the correct lane (by classifying each finding's file path against the lane allowlists) and the relevant lane's loop re-invoked — without my intervention — so that small issues self-heal.

7. As an engineer, if a finding's file path doesn't match any lane (config file, hook, infra), I want it surfaced to me at the final checkpoint with an explicit "validator found N findings in unmapped paths" message, so that the orchestrator doesn't silently grow the spec without my approval.

8. As an engineer, I want to close my terminal between checkpoints and resume the run on another machine with `feature.sh continue <id>`, so that interruptions (meetings, end-of-day, machine reboots) don't restart the chain.

9. As an engineer, I want to reject a checkpoint with `feature.sh continue <id> --redo "<feedback>"` and have the relevant step re-run with my feedback prepended, so that mid-stream course correction doesn't require manual editing of intermediate artifacts.

10. As an engineer, I want a precursor fix that stops `/work-issues` from cat'ing every `*.md` under `issues/` (including new sidecar types like `*.spec.md`/`*.research.md`/`*.rubric.md`) into the prompt as if they were tasks, so that the chain's new sidecar artifacts don't pollute the work-issues task selector.

11. As an engineer dogfooding the factory by building the factory, I want each round captured in `docs/lessons-learned/feature-factory-build.md` and translated into skill edits at the end, so that the existing skills get better as a side effect of building the new one.

12. As the validator system, I want a way to be invoked programmatically by another orchestrator skill (not just by user slash command), so that `/feature` can dispatch me without losing the existing interactive UX for direct `/adversarial-review` users.

13. As the spec-writing system, I want a fenced `paths` block convention inside the spec so that `bin/feature.sh`'s parser can extract per-lane allowlists deterministically without natural-language ambiguity.

14. As an engineer mid-implementation, when I discover I need a file outside the spec's allowlist, I want to write an `## Allowlist additions requested` section to the issue file and have the lane loop exit gracefully so the orchestrator surfaces this at the next checkpoint, so that the spec doesn't silently grow.

15. As an engineer, if two `/feature` runs are accidentally started at once, I want the second one to refuse with a clear message rather than colliding on `issues/` numbering or lane settings, so that I don't have to debug interleaved state.

## Implementation Decisions

All technical decisions are documented in [`docs/plans/feature-factory.md`](../docs/plans/feature-factory.md) (rev. 2) which is the source of truth. PRD-level summary:

**New skills:**
- `write-a-spec` (read-only) — produces `issues/NNN-*.spec.md` with fenced `paths` blocks per lane.
- `/feature` (slash-only) — orchestrator skill bundling `bin/feature.sh` + `bin/feature-helpers.sh`.

**Modifications:**
- `/work-issues` SKILL.md — single-paragraph addition: honor a lane preamble if the prompt prepends one; never silently expand the allowlist.
- `/adversarial-review` SKILL.md — new `ADVERSARIAL_REVIEW_REPORT_ONLY=1` env var for Phase 3 auto-D; new `ADVERSARIAL_REVIEW_TARGETS=<glob>` env var for Phase 1 auto-targets. `disable-model-invocation` already removed (Round 0).
- `work-issues/bin/work-issues-lib.sh` — already exists (Round 0). Add allowlist-parsing helper that `bin/feature-helpers.sh` will use.

**Reused as-is:** `write-a-prd`, `prd-to-issues`, `write-a-rubric`, `tdd`, `grill-with-docs`, `crap`, `/map`, the built-in `Explore` agent type.

**State model:** `.feature_runs/<run-id>/state.json` mirrors `evolve`'s `.evolve_runs/` convention. Resumable via shell-exit + `feature.sh continue <id> --accept|--redo "<feedback>"|abort`.

**Architecture decisions are deferred to the plan.** Anything that turns out to be a hard-to-reverse choice with surprising trade-offs (per `CLAUDE.md`'s ADR threshold) will get an ADR at `docs/adr/`.

## Testing Decisions

Two test surfaces:

1. **Unit / function-level (shell tests at `tests/test_*.sh`)**: the lib helpers — `strip_frontmatter`, `list_issue_files` (already done in Round 0), `allowlist_for`, `route_findings`. Test edge cases that adversarial review would otherwise catch (sort stability, missing-dir handling, malformed input).

2. **End-to-end smoke (`/feature/evals/evals.json`)**: at least 2 fixture briefs run through `/feature start` → checkpoint → resume → final commit. Asserts `state.json` reaches terminal step; asserts no out-of-lane edits.

**Test the *behavior* of `/feature` (does it pause correctly, resume correctly, route findings correctly) rather than the implementation details of any single phase.** The phases themselves are tested by their owning skills.

**Prior art in this repo:**
- `tests/test_work_issues_lib.sh` — the Round 0 shell test that pinned strip_frontmatter + list_issue_files.
- `plugins/agentic-engineering/skills/prd-to-issues/evals/evals.json` — the existing evals format used by skills in this plugin.
- `plugins/agentic-engineering/skills/crap/` — example of a Python-tested skill with full mutation testing (overkill for `/feature`, but shows the bar).

## Out of Scope

- **Hard-mode lane enforcement** via `.claude/settings.local.json` write/restore. v1 is soft-mode only (prompt instruction). Future iteration if soft mode proves leaky.
- **Wiring rubric criteria to Anthropic Managed Agents `user.define_outcome` API** — `write-a-rubric`'s closing one-liner already points at this; not in v1.
- **Multi-feature flow inside `/feature`** — for multi-feature work, users run `/write-a-prd` + `/prd-to-issues` separately, then `/feature` on each issue.
- **Modifying `prd-to-issues`** — orchestrator uses an inline subagent prompt for the single-feature story step instead of forking the skill.
- **A `commands/` directory in any plugin** — `/feature` follows the existing convention (slash-only skill in `skills/feature/SKILL.md`).
- **Renaming to a separate `feature-factory` plugin** — this is workflow on top of `agentic-engineering`.
- **Semantic lane-enforcement validation in this repo** — `claude-skills` has no real backend/frontend split. Round 4 lane tests are parser-only smoke tests; semantic validation deferred to first downstream user with a polyglot repo. Tracked as `issues/0099-validate-lane-semantics-in-polyglot-repo.md` (open when Round 4 runs).
- **`/work-issues`, `/map`, `/zoom-out`, `/audit-agent-overhead`** retain `disable-model-invocation: true` until a build round explicitly needs to dispatch them programmatically. The Round 0 fix is precedent, not blanket policy.

## Further Notes

**Success metric (v1):** matt ships one real feature through `/feature` end-to-end without bailing to manual midway. Single binary signal. If that works, v2 might add quantitative tracking; v1 doesn't bother.

**Rollout:** dogfood only. No `README.md` update, no marketplace polish, no public announcement until the factory has shipped 3+ real features. If it doesn't survive contact with reality, no harm done — the lessons doc and ADRs capture why.

**Timeline:** active sessions for a few weeks. No hard deadline. Stop when v1 works OR after ~3 weeks if it doesn't. The dogfooding plan in `docs/plans/feature-factory.md` is the work breakdown (Rounds 0–6).

**Lesson loop:** every round captures observations in `docs/lessons-learned/feature-factory-build.md`. Round 6 explicitly translates lessons into skill edits (or ADRs, or just-doc). The skills get better as a side effect of building the new one.

**Risk this is overkill:** if soft-mode lane enforcement leaks badly (the model edits frontend files from the backend lane despite the preamble), v1 fails at its core thesis. Mitigation: Round 4 parser-smoke-tests catch the orchestration mechanics; the semantic-leak risk lands on the first downstream user with a real polyglot repo. Open issue `0099-...` tracks this.

---

## Next

Run `prd-to-issues` to break this PRD into vertical-slice issue files at `issues/NNN-*.md`.
