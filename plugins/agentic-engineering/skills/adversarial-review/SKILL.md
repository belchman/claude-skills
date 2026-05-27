---
name: adversarial-review
description: 'Three parallel reviewer agents find contradictions, config gaps, and coverage holes across a project''s docs, config, and tests — then fix what you approve. Heavyweight (dispatches parallel agents, can modify files). Supports env-var automation hooks (ADVERSARIAL_REVIEW_TARGETS, ADVERSARIAL_REVIEW_REPORT_ONLY) so an orchestrator can dispatch a programmatic validator pass without keyboard. Use only when explicitly asked: /adversarial-review, "adversarial review", "find gaps in my docs/config", OR when another skill (e.g. /feature) needs to dispatch a validator pass programmatically.'
allowed-tools: Glob Grep Read Bash Write Edit Agent AskUserQuestion
---

# /adversarial-review — Adversarial review of project documentation and configuration

You are orchestrating an adversarial review of this project. The goal is to find every gap, contradiction, and missing piece in the project's documentation and configuration — then fix what matters.

**Arguments:** $ARGUMENTS
- If the user provided a file path or glob, those are the primary targets to review.
- `--diff` scopes the review to changes since the last commit (or last `/map` run).
- If no arguments, auto-discover all project files.

---

## Phase 1: Discovery

Before launching any agents, YOU must understand the project. Discover what exists:

### Step 1: Check for ARCHITECTURE.md

Read `ARCHITECTURE.md` at the repo root if it exists.
- If found: extract the **Change Impact Map** (High-Coupling Zones), **Dependencies** (Mermaid graph + Key Interfaces), and **Conventions** sections. These enrich the reviewer context.
- If not found: print "No ARCHITECTURE.md found. Consider running `/map` first for richer context." Proceed with manual discovery.

### Step 2: Check for review config

Read `.claude/review-config.md` if it exists. It may contain:
- `## Focus Areas` — additional review priorities (append to all agent prompts)
- `## Ignore` — file globs to exclude from review
- `## Severity Overrides` — rules to reclassify finding severity

### Step 3: Auto-discover project files

1. **Project instruction files**: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `COPILOT.md`, `CURSOR.md`, `AIDER.md`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.github/copilot-instructions.md`, or any root-level markdown or dotfile that appears to contain AI assistant instructions
2. **Specs/plans**: Glob for `*.md` in the root — any file that looks like a specification, PRD, plan, or architecture doc
3. **Package manifests** (examples, not exhaustive): `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `mix.exs`, `build.sbt`. Also check the project root for any other build, package, or dependency files specific to the detected language.
4. **Project config** (examples, not exhaustive): `.eslintrc.*` (JS), `rustfmt.toml` (Rust), `.rubocop.yml` (Ruby), `mypy.ini` (Python), `.golangci.yml` (Go), `.formatter.exs` (Elixir). Also search root for dotfiles and YAML/TOML/JSON files that appear to be linter, formatter, or build tool configuration for the detected language.
5. **Hook scripts / CI config**: Glob `scripts/**/*`, `.github/workflows/**/*`, `.gitlab-ci.yml`, `.circleci/**/*`, `Jenkinsfile*`, `.buildkite/**/*`, `.travis.yml`, `azure-pipelines.yml`, `bitbucket-pipelines.yml`. Check for any other CI/automation configuration present.
6. **Source and tests**: Run `ls` on the project root and check the manifest to discover actual source and test directories. Do not assume `src/` is the only source directory — projects may use `src/`, `lib/`, `app/`, `cmd/`, `pkg/`, `internal/`, `Sources/`, `crates/`, `packages/`, or top-level package directories. For tests, check `tests/`, `test/`, `spec/`, `__tests__/`, `src/test/`, and language-specific conventions (examples: `*_test.go`, `test_*.py`, `*_spec.rb`, `t/*.t`). For any other language, check for its test naming conventions. If no language can be determined, treat all non-binary files as potential source and search broadly. Note the uncertainty in the output.
7. **Infrastructure and build**: `Dockerfile*`, `docker-compose*`, `.env*`, `Makefile`

If `.claude/review-config.md` has an `## Ignore` section, filter out matching files.

### Step 4: Apply --diff scoping (if requested)

If `--diff` was passed:
1. Determine the base reference:
   - If `ARCHITECTURE.md` has a `last-mapped` SHA (not `0000000`): use it
   - Otherwise: use `HEAD~1`. Print a warning: "No valid `/map` baseline found. Diffing against HEAD~1 only. Consider running `/map` first for a comprehensive baseline."
2. Gather changed files:
   - `git diff <base>..HEAD --name-status`
   - `git diff HEAD --name-status`
   - `git ls-files --others --exclude-standard` (untracked, treat as `A`)
   - Merge results (uncommitted status wins on conflict)
3. If ARCHITECTURE.md's dependency graph is available, expand to include files that import the changed files (blast radius)
4. Always keep `CLAUDE.md` and project instruction files in context (even if unchanged)
5. If no changes detected, print "No changes detected since last review baseline." and stop.

### Step 5: Summarize for the user

Print 3-5 bullets before proceeding:
- What kind of project this is (language, framework, purpose)
- Which files are the primary review targets
- What supporting context was found (ARCHITECTURE.md, review-config, etc.)
- If `--diff`: which files changed and how many dependents were included

### Step 6: Classify files into three domains

- **Spec domain**: specs, plans, PRDs, architecture docs, type definitions
- **Config domain**: settings files, hook scripts, CI config, permissions, env vars
- **Coverage domain**: test behaviors/requirements, coverage thresholds, test framework config, feature files

### Automation: `ADVERSARIAL_REVIEW_TARGETS` env-var

When dispatched by another orchestrator skill (e.g. `/feature`), the interactive auto-discovery + summary above isn't useful — the caller already knows which files to review. If the env var `ADVERSARIAL_REVIEW_TARGETS` is set to a colon-separated list of globs (PATH-style separator), use that list as the file set for Phase 2 and **skip Steps 3 and 5 entirely** (auto-discovery and user summary). Steps 1, 2, 4, 6 still run so ARCHITECTURE.md context, review-config, diff scoping, and domain classification still apply.

Example value: `ADVERSARIAL_REVIEW_TARGETS="src/api/**/*.ts:src/services/**/*.ts:tests/api/**/*.ts"`. Split on `:`, expand each glob (`shopt -s globstar` or equivalent), dedupe, then proceed to domain classification at Step 6.

**If unset (default):** auto-discover as documented in Step 3 and summarize at Step 5 — interactive UX is unchanged.

---

## Phase 2: Parallel Adversarial Review (use agent teams)

Launch **three reviewer agents in parallel** using separate Agent tool calls (`subagent_type: "general-purpose"`) in a single message. Each agent focuses on one domain but reads ALL files for cross-reference context.

If the discovered file list exceeds 50 files, pass at most 30 file paths to each reviewer agent. Group remaining files by directory and pass directory-level summaries instead of individual paths.

**IMPORTANT: Launch all three agents simultaneously in a single response.**

If a domain has no relevant files (e.g., no config files), skip that agent and note it in the summary.

### ARCHITECTURE.md Context Preamble

If ARCHITECTURE.md was found, prepend this to EVERY agent prompt:

```
## Project Context (from ARCHITECTURE.md)

### High-Coupling Zones (changes here have wide blast radius):
[paste the High-Coupling Zones table]

### Key Interfaces:
[paste the Key Interfaces list]

### Conventions:
[paste the Conventions section]

Use this context to:
- Flag findings as higher severity when they affect high-coupling zones
- Cross-reference dependency relationships when checking for contradictions
- Evaluate code/config against established conventions
```

### Diff-Scope Preamble

If `--diff` was used, prepend this to EVERY agent prompt:

```
This is a diff-scoped review. Focus on changes in these files: [list changed files].
Also review these context files for cross-reference: [list unchanged context files].
Flag issues in changed files at normal severity. Flag issues in context files only if they directly contradict the changed files.
```

### Agent 1: `spec-reviewer` — Spec Consistency

Launch with `subagent_type: "general-purpose"`.

```
You are an adversarial SPEC CONSISTENCY reviewer. Focus on:
- Internal contradictions within spec/plan documents
- Cross-references between docs that don't match (phases, numbering, naming)
- Missing definitions referenced elsewhere
- Ambiguities where an AI agent could go either way
- Prose behaviors that contradict code examples
- Type definitions that don't match what tests reference

[ARCHITECTURE.MD CONTEXT PREAMBLE if available]
[DIFF-SCOPE PREAMBLE if --diff]
[FOCUS AREAS from review-config.md if available]

Read ALL files: [LIST ALL DISCOVERED FILES WITH ABSOLUTE PATHS]

Return ONLY findings as numbered markdown. Each finding must have: number, file+line reference, what's wrong, evidence (quoted text), suggested fix. Categorize as CRITICAL / IMPORTANT / MINOR.
```

### Agent 2: `config-reviewer` — Config & Hooks

Launch with `subagent_type: "general-purpose"`.

```
You are an adversarial CONFIG & HOOKS reviewer. Focus on:
- Hook scripts that won't work for the file paths described in specs
- Permission gaps (commands the spec requires but permissions don't allow)
- Settings that contradict documented behavior
- Hook logic errors (wrong grep patterns, path resolution issues, race conditions)
- Environment variables that are missing or wrong
- Slash commands that reference paths or behaviors incorrectly

[ARCHITECTURE.MD CONTEXT PREAMBLE if available]
[DIFF-SCOPE PREAMBLE if --diff]
[FOCUS AREAS from review-config.md if available]

Read ALL files: [LIST ALL DISCOVERED FILES WITH ABSOLUTE PATHS]

Return ONLY findings as numbered markdown. Each finding must have: number, file+line reference, what's wrong, evidence (quoted text), suggested fix. Categorize as CRITICAL / IMPORTANT / MINOR.
```

### Agent 3: `coverage-reviewer` — Test Coverage & Completeness

Launch with `subagent_type: "general-purpose"`.

```
You are an adversarial TEST COVERAGE reviewer. Focus on:
- Exported functions/classes that appear to lack test coverage (check the project's coverage config for threshold)
- Test behaviors that can't be implemented as described
- Check for specialized testing paradigms (BDD/Gherkin `.feature` files, property-based testing, snapshot testing, contract testing) and validate against their framework requirements. For all other tests, evaluate against the project's actual testing patterns.
- Coverage config that excludes too much or too little
- Interfaces, abstract definitions, or contracts that declare behavior but lack implementations or tests. Skip if the language doesn't use explicit type/interface declarations.

[ARCHITECTURE.MD CONTEXT PREAMBLE if available]
[DIFF-SCOPE PREAMBLE if --diff]
[FOCUS AREAS from review-config.md if available]

Read ALL files: [LIST ALL DISCOVERED FILES WITH ABSOLUTE PATHS]

Return ONLY findings as numbered markdown. Each finding must have: number, file+line reference, what's wrong, evidence (quoted text), suggested fix. Categorize as CRITICAL / IMPORTANT / MINOR.
```

**Wait for all three agents to finish.** Then:
1. Merge all findings into a single report
2. De-duplicate (if two reviewers found the same issue, keep the more detailed one)
3. Re-number findings sequentially
4. If ARCHITECTURE.md context was available, annotate findings affecting high-coupling zones with `[HIGH RISK]`
5. Apply severity overrides from `.claude/review-config.md` if present
6. Print the merged report for the user

---

## Phase 3: User Checkpoint

After showing the merged findings, ask the user:

> Here are the findings from 3 parallel reviewers. Which should I fix?
> - **A)** All critical + important findings
> - **B)** Only critical findings
> - **C)** Let me pick specific ones (list the finding numbers)
> - **D)** Skip fixes — I just wanted the review

**Wait for the user to respond before proceeding.** If they choose D, stop here.

**Automation: `ADVERSARIAL_REVIEW_REPORT_ONLY` env-var.** If `ADVERSARIAL_REVIEW_REPORT_ONLY=1` is set (e.g. by `/feature`'s orchestrator dispatching a validator pass), **skip the user prompt** above and behave as if the user chose option **D** — print the merged findings report, then stop without entering Phase 4. The findings are still useful for the caller to parse and route. **If unset (default):** ask the user A/B/C/D interactively as documented above — interactive UX is unchanged.

---

## Phase 4: Adversarial Product Manager Agent

Launch an agent with `subagent_type: "general-purpose"` named `adversarial-pm`.

Build the prompt dynamically. Include the full text of every selected finding. The template:

---

You are an **adversarial product manager**. You have a list of findings from a technical review. Your job is to make the **minimum** edits to fix each finding. Nothing more.

**Read the current state of every file you're about to edit BEFORE making changes.**

**Findings to fix:**
[PASTE THE FULL TEXT OF EVERY SELECTED FINDING HERE]

**General rules:**
- Fix exactly what the finding describes. No scope creep.
- If a section contradicts another, fix the one that's wrong (not both).
- If something is missing, add it in the most logical location near related content.
- Match the existing style, formatting, and voice of each file.

**Rules for project instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `COPILOT.md`, `CURSOR.md`, `AIDER.md`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.github/copilot-instructions.md`, or any root-level markdown or dotfile containing AI assistant instructions):**
- **ONLY ADD content, never remove** unless something is factually wrong or directly contradicts the spec/plan.
- If a section needs updating, append or clarify — don't rewrite.
- If nothing needs changing, don't touch it.

**Rules for specs, plans, and documentation:**
- Fix exactly what the finding identifies.
- Preserve the document's structure and organization.
- If fixing a contradiction, keep the version that's consistent with the rest of the document.

**Rules for config files:**
- Only change if a finding specifically identifies a config issue.
- Never change permissions, hooks, or security settings unless explicitly flagged as a finding.

**After each file edit, state:**
1. What finding this addresses (by number)
2. What you changed (1 sentence)
3. Why this is the minimum fix

**Do NOT:**
- Add features or new sections not identified in findings
- Refactor or reorganize existing content
- Add comments explaining your changes inside the files
- Touch files that aren't mentioned in the findings

---

**Wait for the PM agent to finish.** Then summarize what was changed for the user.

---

## Phase 5: Summary

After the PM agent finishes, present a summary:

```
## Adversarial Review Complete

### Reviewers: 3 parallel agents (spec, config, coverage)
### Findings: X critical, Y important, Z minor
### Fixed: N findings across M files

### Changes made:
- [file]: [1-line description of change] (finding #N)
- ...

### Not fixed (if any):
- Finding #N: [reason — user chose to skip, out of scope, etc.]
```

If any project instruction file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `COPILOT.md`, `CURSOR.md`, `AIDER.md`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.github/copilot-instructions.md`, or any other AI assistant instruction file) was modified, call it out explicitly so the user can review those changes.

Suggest running `/adversarial-review` again if critical fixes were made, to verify no regressions.

---

## Error Handling

| Condition | Behavior |
|-----------|----------|
| Not a git repo | Print warning: "Not a git repository. Running full review (--diff ignored if present)." Proceed without diff capability. |
| Git unavailable | Print warning: "Git not found. Running full review (--diff ignored if present)." Proceed without diff capability. |
| Shallow clone | Print warning: "Shallow clone detected. Diff history may be limited." Proceed with available history. |
| `git diff` fails with invalid revision | Print warning: "Base commit not found (possibly shallow clone). Running full review." Ignore --diff. |
| Single reviewer agent fails | Retry once. If it fails again, proceed with findings from the other reviewers. Note which reviewer was skipped. |
