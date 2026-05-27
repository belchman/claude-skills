# Plan: "Feature Factory" on top of `agentic-engineering`

## Context

We want the 7-agent "software factory" pipeline (Researcher → Story Writer → Spec Writer → Backend Builder → Frontend Builder → Test Verifier → Validator) so a single prompt produces a vertically-sliced feature with three human checkpoints: approve story, approve spec, approve PR.

After a reuse audit (see table) the gap is **smaller than the 7-agent narrative suggests** — but the **glue** between existing skills is substantial. The deliverable is:

1. One new skill — `write-a-spec`.
2. One new slash-only skill — `/feature` (the orchestrator) — bundling a `bin/feature.sh` shell wrapper for the actual chain execution.
3. Lane scoping on `/work-issues` via the existing `WORK_ISSUES_PROMPT` env hook (no shell-wrapper fork).
4. A small env-var addition to `/adversarial-review` for automation-friendly Phase 3.
5. A precursor fix to the `issues/*.md` glob so existing `.rubric.md` (and the new `.spec.md` / `.research.md`) sidecars stop polluting `/work-issues`'s input.
6. A dogfooding pass that uses the existing pipeline to build itself.

This plan is the result of a deep adversarial review (`docs/plans/feature-factory.md` rev. 1 → rev. 2) — every open question from rev. 1 has a concrete answer below.

## Reuse audit — what already exists

Each row was checked against the actual skill source.

| Factory agent | What it needs | Existing coverage | Verdict |
| --- | --- | --- | --- |
| **1. Researcher** (read-only map of relevant slice) | files & roles, existing patterns, risks | `/map` produces `ARCHITECTURE.md` polyglot-aware; built-in `Explore` agent type is **read-only by harness contract** (tool list: "all tools except Agent, ExitPlanMode, Edit, Write, NotebookEdit") | **No new skill.** Orchestrator step: ensure `ARCHITECTURE.md` is fresh (run `/map` if stale), then dispatch one `Explore` subagent with the feature brief; orchestrator captures the subagent's returned text and writes `issues/research/NNN-*.md`. |
| **2. Story Writer** | user story + acceptance criteria + edge cases + out-of-scope | `write-a-prd` (multi-feature) + `prd-to-issues` (which produces one issue per slice with acceptance criteria) | **No new skill, but `prd-to-issues` is not on the single-feature path.** Its interactive quiz doesn't fit `claude -p`. For single-feature, the orchestrator dispatches an inline subagent with a short "write one issue from this brief" prompt that mirrors `prd-to-issues`'s issue template. Multi-feature users run `/prd-to-issues` separately before `/feature`. |
| **3. Spec Writer** | technical brief: data model, API shape, file-by-file change list, tests required, risks | **Nothing.** `prd-to-issues` produces story-level slices, not technical briefs. `grill-with-docs` stresses but doesn't produce a brief. | **Genuine gap. Add `write-a-spec`.** |
| **4. Backend Builder** | implements backend + unit tests, cannot touch UI | `/work-issues` runs autonomous TDD; uses `tdd` skill; has per-language feedback loops; walks the rubric after commit (`work-issues/SKILL.md:45,51-57,71-73`). **Missing**: lane scoping. | **Add lane scoping via `WORK_ISSUES_PROMPT` injection** — no shell-wrapper fork. |
| **5. Frontend Builder** | implements UI + UI tests, cannot touch backend | Same as 4 | Same lane mechanism. Reads backend's commits via the existing `WORK_ISSUES_COMMIT_LOG` env hook (no new artifact). |
| **6. Test Verifier** | acceptance tests cover every criterion | `write-a-rubric` produces gradeable criteria; `/work-issues` walks rubric after commit and surfaces unmet items; `/adversarial-review`'s coverage-reviewer (lines 170-176) checks exports without test coverage and contracts without implementations. | **No new skill, but explicit gate.** Orchestrator runs `/adversarial-review` *between* the two lane commits and once at the end (see Chain), so unmet rubric items surface before frontend builds on them. |
| **7. Validator** (read-only) | report gaps grouped by severity, never patches | `/adversarial-review` runs 3 parallel reviewers, groups findings CRITICAL/IMPORTANT/MINOR, and Phase 3 offers option D ("Skip fixes — I just wanted the review") at `adversarial-review/SKILL.md:204`. | **Add `ADVERSARIAL_REVIEW_REPORT_ONLY=1` env var** — one-line edit to the Phase 3 prompt: if env is set, auto-answer D. |
| **Orchestrator** | runs the chain with 3 checkpoints; resumable across sessions; failure-handling per step | None | **Add `/feature` slash-only skill** with `bin/feature.sh` wrapper. Resumable via `.feature_runs/<id>/state.json`. |

### What this means

The earlier plan invented `research-feature` and `verify-acceptance` skills that duplicate capability already in the plugin. Both removed. The earlier plan also proposed a `--report-only` flag on `/adversarial-review`; the cleaner mechanism is the env var above, which preserves option D's existing interactive UX.

## Open questions resolved in deep review

| Question (rev. 1 ambiguity) | Decision (rev. 2) |
| --- | --- |
| Is `/feature` a skill, a shell script, or both? | **Slash-only skill** at `skills/feature/SKILL.md` with `disable-model-invocation: true`, bundling `bin/feature.sh` for actual chain execution. Skill body is the prompt; shell does the orchestration. Mirrors the `work-issues` + `bin/loop.sh`/`bin/once.sh` pattern. |
| How does state persist across the 3 checkpoints? | `.feature_runs/<run-id>/` directory mirroring `evolve`'s `.evolve_runs/` convention. Contains `brief.md`, `state.json` (`last_completed_step`, `lane_allowlist`, `run_dir`), produced sidecars, and a `LOCK` file. |
| Are the checkpoint pauses interactive `AskUserQuestion` or shell-exit + resume? | **Shell-exit + resume.** `bin/feature.sh` writes a state marker and exits; prints exact `feature.sh continue <id>` (and `accept` / `redo "<feedback>"` / `abort`) to stdout. Survives terminal close. |
| `prd-to-issues --single` — flag, preprocessor, or replace? | **None of the above.** For single-feature flow, orchestrator dispatches a thin inline subagent using `prd-to-issues`'s issue template as the prompt. `prd-to-issues` itself is not modified and not on the single-feature chain. |
| Where does the lane allowlist come from and how does it flow? | From a fenced `paths` block inside `write-a-spec`'s output. Parsed by `bin/feature.sh` (bash awk/grep). Injected into `/work-issues` via a lane-wrapped prompt file pointed to by `WORK_ISSUES_PROMPT`. |
| How does the builder discover a file outside the allowlist mid-implementation? | Writes an `## Allowlist additions requested` section to the issue file. The lane stops at the next loop iteration (existing rubric-walk mechanism); orchestrator surfaces at the next checkpoint. No silent expansion. |
| Hard-mode (settings.local.json denial)? | **Dropped for v1.** Soft-mode only (prompt instruction). Hard-mode tracked as a future iteration. |
| Where does `/adversarial-review` get its option-D auto-answer from? | New env var `ADVERSARIAL_REVIEW_REPORT_ONLY=1`. Checked at Phase 3 (`adversarial-review/SKILL.md:198`). |
| Loop-back routing when `/adversarial-review` finds Critical issues? | `bin/feature.sh` classifies each finding by file path against the lane allowlists from the spec; appends a "fix these findings" issue to the relevant lane; reruns that lane's loop. **Append commits only, never revert.** |
| Backend → frontend handoff artifact? | **None.** Frontend lane reads backend commits via `WORK_ISSUES_COMMIT_LOG` (default 5 — bump to 20 for the frontend invocation). No new artifact. |
| Rubric input scope — story only, spec only, or both? | Orchestrator concatenates story + spec into the `write-a-rubric` invocation's prompt. `write-a-rubric` itself is not modified. |
| Glob collision — sidecars get cat'd into UNTRUSTED_ISSUES? | **Precursor fix.** Tighten the glob in `bin/once.sh` and `bin/loop.sh` to exclude `*.rubric.md`, `*.spec.md`, `*.research.md`. Update `work-issues/SKILL.md:15` to match. |
| Lane validation in this repo? | Round 4 is **parser smoke test only**. This repo has no real backend/frontend; semantic test is deferred to the first downstream user with a real two-lane repo. Lessons captured in dogfooding doc. |
| Lessons-learned doc — does it flow back into skills? | New **Round 6** dogfooding step: walk every captured lesson, decide skill-edit vs. ADR vs. just-doc, commit the edits. |

## Recommended approach

### A. Architecture: `/feature` as slash-only skill + shell wrapper

```
plugins/agentic-engineering/skills/feature/
  SKILL.md                 # disable-model-invocation: true; body is the workflow doc
  bin/
    feature.sh             # main orchestrator: start | continue | abort
    feature-helpers.sh     # shared funcs (state read/write, lock, glob, severity routing)
```

`bin/feature.sh` subcommands:

- `feature.sh start <brief>` — creates `.feature_runs/<id>/`, runs steps 1–4 of the chain (research → story → checkpoint), exits at checkpoint with resume instructions.
- `feature.sh continue <id> --accept` — resume after a checkpoint with no changes.
- `feature.sh continue <id> --redo "<feedback>"` — rerun the last step with feedback prepended to the prompt.
- `feature.sh continue <id>` — alias for `--accept`.
- `feature.sh abort <id>` — move `.feature_runs/<id>/` to `.feature_runs/<id>.aborted/`, drop the lock.
- `feature.sh status <id>` — print `state.json` in human form.

`state.json` schema:

```json
{
  "id": "0042-invoice-reminders",
  "brief_path": ".feature_runs/0042-invoice-reminders/brief.md",
  "issue_path": "issues/0042-invoice-reminders.md",
  "research_path": "issues/research/0042-invoice-reminders.md",
  "spec_path": "issues/0042-invoice-reminders.spec.md",
  "rubric_path": "issues/0042-invoice-reminders.rubric.md",
  "lanes": {
    "backend": {"allowlist": ["src/api/...", "src/services/..."], "status": "complete", "last_commit": "abc1234"},
    "frontend": {"allowlist": ["web/components/...", "web/hooks/..."], "status": "pending"}
  },
  "validator_findings": ".feature_runs/0042-invoice-reminders/validator.md",
  "last_completed_step": "spec_approved",
  "started_at": "2026-05-27T10:00:00Z",
  "updated_at": "2026-05-27T11:23:00Z"
}
```

Resume semantics: on any `continue` invocation, `bin/feature.sh` reads `state.json`, dispatches the next step. Survives terminal close, machine reboot, week-long pauses.

Concurrency: `.feature_runs/<id>/LOCK` (pidfile). New `feature.sh start` aborts if any active LOCK is stale-checked (stat the pid). Two `feature.sh start` invocations on overlapping briefs are not prevented at the file level — that's a downstream concern; v1 just protects against same-run double-dispatch.

**User entry point.** When the user types `/feature "..."`, the slash command loads `skills/feature/SKILL.md` as the prompt. That SKILL.md instructs Claude to Bash-invoke `bin/feature.sh start "<brief>"` and surface its stdout (resume instructions) to the user. The interactive session is a thin babysitter; all real orchestration happens in `bin/feature.sh` via child `claude -p` invocations and `bin/loop.sh` calls. This matches the existing `work-issues` skill pattern (SKILL.md is documentation for both Claude and humans; the shell scripts do the work).

**Per-step invocation mode.** The chain (§F) mixes two modes:
- **`claude -p` (non-interactive print)** for read-only or no-pause steps: `/map`, the Explore researcher, `write-a-spec`, `write-a-rubric`, `/adversarial-review` with the env var. These print final output and exit.
- **`bin/loop.sh` (interactive `claude`, AFK loop)** for the lane build steps: it runs `claude --permission-mode acceptEdits` against the lane-wrapped prompt until the loop sentinel fires or iteration cap hits.

The orchestrator picks per step; `bin/feature.sh` does not invent a new dispatch primitive.

### B. The `--lane` protocol (no shell-wrapper fork)

The orchestrator does **not** modify `bin/once.sh` or `bin/loop.sh`. It uses the existing `WORK_ISSUES_PROMPT` env hook (`once.sh:32`, `loop.sh` equivalent):

```bash
# Inside bin/feature.sh, building the lane prompt:
lane_prompt="/tmp/feature-runs/$ID/lane-backend.prompt.md"
cat > "$lane_prompt" <<'PREAMBLE'
# Lane constraint

You are operating in **backend** lane. You may only edit files matching:

ALLOWLIST_GOES_HERE

If you need to edit a file outside this allowlist, **stop**, append an
"## Allowlist additions requested" section to the issue file with the path
and one-sentence reason, and exit. The orchestrator surfaces this at the
next checkpoint.

---

PREAMBLE
sed -i "s|ALLOWLIST_GOES_HERE|$(allowlist_for backend)|" "$lane_prompt"

# Append the real SKILL.md body (minus frontmatter)
strip_frontmatter \
  plugins/agentic-engineering/skills/work-issues/SKILL.md >> "$lane_prompt"

WORK_ISSUES_PROMPT="$lane_prompt" \
WORK_ISSUES_COMMIT_LOG=20 \
  bin/loop.sh
```

The wrapper is a textual prepend — no fork of the shell scripts, no new flags, no changes to `once.sh`/`loop.sh`. The work-issues SKILL.md gets a single-paragraph addition: "if the prompt's prepend defines a lane allowlist, honor it; never silently expand it."

**Precursor refactor (lands with Round 0 glob fix):** extract `strip_frontmatter()` from `once.sh:58-66` into a new `bin/work-issues-lib.sh` that both `once.sh` and `feature-helpers.sh` source. Avoids re-implementing the AWK and keeps frontmatter-stripping behavior in one place.

### C. Spec → allowlist format (the protocol)

`write-a-spec`'s output includes a section like:

````markdown
## File-by-file change list

### Backend

```paths
src/api/handlers/invoices.ts
src/services/invoice-reminder.ts
src/jobs/reminder-job.ts
tests/services/invoice-reminder.test.ts
```

### Frontend

```paths
web/components/billing/ReminderCard.tsx
web/hooks/useInvoiceReminders.ts
tests/components/ReminderCard.test.tsx
```
````

Rules:

- Fenced code blocks tagged `paths`. One literal path per line. No globs in v1.
- Lane labels are H3 headings (`### Backend`, `### Frontend`) — arbitrary user-defined labels resolved against `CLAUDE.md`'s `## Lane boundaries` section. For this repo (which has no real backend/frontend), `## Lane boundaries` documents the two labels with illustrative patterns and notes the lanes are project-specific.
- Parser: `bin/feature-helpers.sh::allowlist_for` extracts the fenced block under each H3.
- A path may appear in only one lane. The parser fails loud on duplicates.
- Escape valve: builder edits the issue file with an `## Allowlist additions requested` section. No silent expansion.

### D. Adversarial-review automation

One-line addition to `adversarial-review/SKILL.md:198` (the Phase 3 user-checkpoint block):

```markdown
**Automation:** If the env var `ADVERSARIAL_REVIEW_REPORT_ONLY=1` is set,
skip the prompt and behave as if the user chose D.
```

`bin/feature.sh` sets this env var when dispatching `/adversarial-review` for the validator step. Interactive use is unchanged.

### E. Severity routing (Validator → lane re-dispatch)

When `/adversarial-review` returns findings, `bin/feature-helpers.sh::route_findings` classifies each by file path against `state.json`'s `lanes.<name>.allowlist`. Findings classified into a lane get appended to a new issue at `issues/<id>-fix-findings.md` and the orchestrator re-invokes that lane's `/work-issues` loop with the issue. **Append commits only, never revert.**

Findings with paths in **no** allowlist (e.g., touched a config file, a hook, or a path outside both lanes) are accumulated under `state.validator_findings` and surfaced at Checkpoint 3 with the explicit message "validator found N findings in unmapped paths; review before opening PR." The human decides whether to amend the spec (which expands the allowlist) and `--redo`, or accept and ship. No silent auto-routing for unmapped paths — that would let the orchestrator quietly grow the spec.

**Note**: `route_findings` is also used for the builder's "Allowlist additions requested" escape valve — both inputs (validator findings, builder requests) carry file paths and need the same lane classification. One implementation, two call sites.

### F. Chain (the `/feature` orchestrator)

(All `feature.sh` invocations below are what `bin/feature.sh` does internally. User-facing entry is `/feature "<brief>"`, which Claude translates to `bin/feature.sh start "<brief>"` per §A's "User entry point" note.)

```
feature.sh start "Build invoice reminders for invoices unpaid >7 days"

  Step 0: Init run
    → mkdir .feature_runs/$ID; write brief.md; take LOCK
    → state.last_completed_step = "init"

  Step 1: Refresh map
    → if ARCHITECTURE.md missing/stale: claude -p with /map skill
    → state.last_completed_step = "map_fresh"

  Step 2: Researcher pass
    → claude -p dispatching Explore subagent with brief + ARCHITECTURE.md
    → capture returned text → issues/research/$ID.md
    → state.research_path = "..."
    → state.last_completed_step = "research_done"

  Step 3: Story
    → claude -p with inline "write-one-issue" subagent prompt
      (uses prd-to-issues' issue template structure)
    → output: issues/$ID.md
    → state.issue_path = "..."
    → state.last_completed_step = "story_drafted"

  ⏸ CHECKPOINT 1: print "Approve story at issues/$ID.md, then run:
    feature.sh continue $ID --accept
    feature.sh continue $ID --redo \"<feedback>\"
    feature.sh abort $ID"
    EXIT 0

feature.sh continue $ID --accept
  Step 4: Spec
    → claude -p with write-a-spec skill, reading $ISSUE + $RESEARCH + ARCHITECTURE.md + CLAUDE.md
    → output: issues/$ID.spec.md (must contain fenced paths blocks)
    → state.spec_path = "..."
    → state.lanes = parse_allowlists($SPEC)
    → state.last_completed_step = "spec_drafted"

  Step 5: Rubric
    → claude -p with write-a-rubric skill; prompt concatenates $ISSUE + $SPEC as input
    → output: issues/$ID.rubric.md
    → state.rubric_path = "..."
    → state.last_completed_step = "rubric_drafted"

  ⏸ CHECKPOINT 2: print "Approve spec at $SPEC and rubric at $RUBRIC, then run:
    feature.sh continue $ID --accept
    feature.sh continue $ID --redo \"<feedback>\""
    EXIT 0

feature.sh continue $ID --accept
  Step 6: Backend lane
    → write lane preamble + SKILL.md body to /tmp/.../lane-backend.prompt.md
    → WORK_ISSUES_PROMPT=$LANE_PROMPT bin/loop.sh (with timeout)
    → state.lanes.backend.status = "complete"
    → state.lanes.backend.last_commit = HEAD
    → state.last_completed_step = "backend_complete"

  Step 7: Inter-lane validator pass
    → ADVERSARIAL_REVIEW_REPORT_ONLY=1 claude -p with /adversarial-review
    → write findings to .feature_runs/$ID/validator-1.md
    → route_findings(): if any Critical hit backend allowlist → loop step 6
    → state.last_completed_step = "backend_validated"

  Step 8: Frontend lane
    → write lane-frontend.prompt.md
    → WORK_ISSUES_PROMPT=$LANE_PROMPT WORK_ISSUES_COMMIT_LOG=20 bin/loop.sh
    → state.lanes.frontend.status = "complete"
    → state.last_completed_step = "frontend_complete"

  Step 9: Final validator pass
    → ADVERSARIAL_REVIEW_REPORT_ONLY=1 claude -p with /adversarial-review --diff
    → if any Critical: route_findings and loop the appropriate lane
    → state.last_completed_step = "validated"

  ⏸ CHECKPOINT 3: print "Validator clean. Final diff at HEAD~N..HEAD. Open PR?
    feature.sh continue $ID --accept     # marks run done, releases LOCK
    feature.sh continue $ID --redo \"<feedback>\""
    EXIT 0

feature.sh continue $ID --accept
  Step 10: Finalize
    → release LOCK
    → move .feature_runs/$ID/ to .feature_runs/$ID.done/
    → print HEAD~N..HEAD diff stat
    → state.last_completed_step = "done"
```

Exactly three checkpoints. Resumable. Each step writes pass/fail to `state.json` before exiting; on dispatcher failure, `feature.sh status <id>` shows where the run stopped.

### G. Failure modes

| Failure | Behavior |
| --- | --- |
| `claude -p` fails non-zero in any step | `state.last_completed_step` unchanged; orchestrator exits non-zero; user fixes (e.g., API issue) and re-runs `feature.sh continue <id>`. |
| `write-a-spec` returns content without a parseable `paths` block | Orchestrator exits at Step 4 with `state.last_completed_step = "spec_invalid"`; prints exact format expected; user runs `--redo "your spec is missing the paths blocks under H3 lane headings"`. |
| `/work-issues` loop hits its iteration cap without completing | `bin/loop.sh` already exits non-zero with reason; orchestrator surfaces to checkpoint 3 early with the partial commits and `state.lanes.<lane>.status = "partial"`. |
| `/adversarial-review` dispatch fails (subagent crashes) | Step skipped; `state.validator_findings = "DISPATCH_FAILED"`; orchestrator surfaces to checkpoint with explicit "validator did not run; review manually." |
| Builder writes `## Allowlist additions requested` to the issue file | Lane loop exits; checkpoint 3 surfaces the requested additions to human; user re-runs `--redo` after editing the spec. |
| Two concurrent `feature.sh start` invocations | Second one detects active LOCK in `.feature_runs/*/LOCK` and refuses; user must `abort` or wait. |

### H. Precursor: fix the `issues/*.md` glob

`bin/once.sh:69-73` and `bin/loop.sh` cat **every** `.md` under `issues/`, which currently includes `.rubric.md` files (a latent bug). Adding `.spec.md` and `.research.md` makes it untenable. The fix lives in the same lib that hosts `strip_frontmatter()`:

```bash
# work-issues/bin/work-issues-lib.sh
list_issue_files() {
  [[ -d "$1" ]] || return 0
  find "$1" -maxdepth 1 -type f -name '*.md' \
    -not -name '*.rubric.md' \
    -not -name '*.spec.md' \
    -not -name '*.research.md' \
    | LC_ALL=C sort
}
```

The `LC_ALL=C sort` matters — `find`'s readdir order is unsorted on most filesystems, and reordering the prompt across runs would (a) bias `/work-issues`'s task selection nondeterministically and (b) break prompt caching by changing the cache key. The old `cat "$dir"/*.md` was implicitly sorted because shell globs are.

Call sites in `once.sh` and `loop.sh`:

```bash
mapfile -t issue_files < <(list_issue_files "$issues_dir")
if (( ${#issue_files[@]} == 0 )); then
  issues="No issues found in $issues_dir"
else
  issues=$(cat "${issue_files[@]}")
fi
```

The lib handles missing-dir → empty silent output internally (`[[ -d "$1" ]] || return 0`), so call sites don't need to swallow stderr.

Update `work-issues/SKILL.md:15` ("every `*.md` under `issues/`") to describe the exclusion. `issues/research/` is a subdir; `-maxdepth 1` ensures research files (and any future per-feature run dirs under `issues/`) are not pulled in either.

**Companion refactor in the same Round 0 commit:** extract `strip_frontmatter()` from `once.sh:58-66` (duplicated in `loop.sh` with a cosmetic difference — dead `done_fm` var) into the same `work-issues-lib.sh`. Update `once.sh` and `loop.sh` to `source` it. This lets `bin/feature-helpers.sh` (coming later) reuse both functions without duplicating AWK or `find` patterns.

**Tests:** plain shell test script at `tests/test_work_issues_lib.sh` covering: strip_frontmatter (removes YAML, passthrough on no-frontmatter), list_issue_files (excludes sidecars and subdirs, missing-dir is empty+silent, sort stability).

This is one Round 0 commit, lands before the feature-factory work.

## Net new + Modifications (final scope)

### New files

| Path | Purpose |
| --- | --- |
| `plugins/agentic-engineering/skills/write-a-spec/SKILL.md` | Technical-brief skill (Spec Writer). |
| `plugins/agentic-engineering/skills/feature/SKILL.md` | `disable-model-invocation: true`. Body is the workflow + invocation instructions. |
| `plugins/agentic-engineering/skills/feature/bin/feature.sh` | Orchestrator entry point. |
| `plugins/agentic-engineering/skills/feature/bin/feature-helpers.sh` | State I/O, locking, allowlist parsing, severity routing. Sources `work-issues/bin/work-issues-lib.sh` for `strip_frontmatter`. |
| `plugins/agentic-engineering/skills/work-issues/bin/work-issues-lib.sh` | Extracted from `once.sh:58-66`. Sourced by `once.sh`, `loop.sh`, `feature-helpers.sh`. |
| `plugins/agentic-engineering/skills/feature/evals/evals.json` | End-to-end smoke evals (see Verification). |
| `plugins/agentic-engineering/skills/write-a-spec/evals/evals.json` | Skill-creator-style evals. |
| `docs/lessons-learned/feature-factory-build.md` | Captured during dogfooding (Rounds 1–5); folded into skill edits in Round 6. Parent dir `mkdir -p`'d. |

### Modifications

| Path | Change |
| --- | --- |
| `plugins/agentic-engineering/skills/work-issues/bin/once.sh` | Tighten the `issues/*.md` glob (precursor; see §H). Source `work-issues-lib.sh` instead of inlining `strip_frontmatter`. |
| `plugins/agentic-engineering/skills/work-issues/bin/loop.sh` | Same glob tightening. |
| `plugins/agentic-engineering/skills/work-issues/SKILL.md` | Line 15 wording matches the new glob. Add one paragraph: "if a lane preamble appears before this prompt, honor its allowlist; if an edit is required outside the allowlist, write an `## Allowlist additions requested` section to the issue file and stop." |
| `plugins/agentic-engineering/skills/adversarial-review/SKILL.md` | Phase 3 block (lines ~198-206): "if `ADVERSARIAL_REVIEW_REPORT_ONLY=1`, auto-answer D." |
| `plugins/agentic-engineering/SKILLS.md` | Add `write-a-spec` to Pipeline phase table; add `/feature` to Heavyweight slash-only list. |
| `CLAUDE.md` (project) | Add `write-a-spec` and `/feature` to the routing decision tree; add `## Lane boundaries` section (illustrative for this repo, note "project-specific in downstream repos"). |
| `README.md` | One paragraph under "Recommended workflow → Build" describing the `/feature` chain. |

### Touched but not modified

- `write-a-rubric`, `write-a-prd`, `prd-to-issues`, `tdd`, `grill-with-docs`, `crap`, `/map` — invoked as-is by the orchestrator.

## Dogfooding plan — build the factory using the pipeline

Lessons doc at `docs/lessons-learned/feature-factory-build.md` gets a section per round.

**Round 0 — precursor**

- Land the glob fix + `work-issues-lib.sh` extract in one commit (§H). Run existing `/work-issues` once to confirm no regression on the current `issues/` queue (which today includes `.rubric.md` files).
- **Lessons**: did the tighter glob break anything? Did sourcing the lib change `once.sh`/`loop.sh` behavior in any subtle way?

**Round 1 — write the spec for the factory itself**

- `write-a-prd` → `issues/prd.md` for the feature factory.
- `prd-to-issues` against it. Expected issues: `write-a-spec` skill, `/feature` skill + bin, work-issues SKILL.md prompt patch, adversarial-review env-var patch.
- `write-a-rubric` per issue.
- **Lessons**: was the PRD interview the right shape for meta work? Did `prd-to-issues` give reasonable granularity for skill-creation tickets?

**Round 2 — stress-test the design**

- `grill-with-docs` against the spec for `write-a-spec` itself.
- **Lessons**: did grilling produce sharper criteria? Did `CONTEXT.md` get created lazily?

**Round 3 — build each piece via the pipeline**

- For each issue (write-a-spec, /feature, work-issues patch, adversarial-review patch), run `/work-issues` (no `--lane` yet — flag doesn't exist).
- After each commit: `/adversarial-review --diff` (manual, interactive).
- After all pieces: `crap` on `bin/feature.sh` + `bin/feature-helpers.sh`.
- **Lessons**: where did `/work-issues` get confused on meta-tasks (modifying a skill rather than building a feature)? Where did the rubric-walk fail? Did adversarial-review's coverage-reviewer flag anything useful on the new shell script?

**Round 4 — `/feature` self-test**

- Once `/feature` exists, run it on a trivial feature in this repo:
  - **Smoke 1**: `feature.sh start "Add a /version subcommand to crap that prints the script's git sha"` — one-lane parser test.
  - **Smoke 2**: `feature.sh start "Add a /loop --status flag that prints last run's exit code and duration"` — two-lane parser test (lanes resolve to the same files in this repo, so this is a **parser smoke test only**, NOT a semantic lane-enforcement test).
- **Caveat captured explicitly**: this repo has no backend/frontend separation. Round 4 validates the parser, state machine, checkpoints, and option-D injection — but **NOT** that the lane preamble actually prevents the model from editing out-of-lane files in a real two-lane repo. That validation is deferred to the first downstream user. Open an issue: `0099-validate-lane-semantics-in-polyglot-repo.md`.
- **Lessons**: which checkpoints felt right? Were resume instructions clear? Did state.json survive a terminal close?

**Round 5 — `/map` and `crap` update**

- `/map --section deps` to refresh `ARCHITECTURE.md` with the new skills (the `--section` flag exists per `map/SKILL.md`).
- `crap --full` to score the new shell scripts.
- Update `SKILLS.md`, `CLAUDE.md` decision tree, `README.md` build-workflow section.

**Round 6 — lessons → skill edits** *(new — was write-only before)*

- For each entry in `docs/lessons-learned/feature-factory-build.md`, decide:
  - **Skill edit**: open the affected SKILL.md, apply the fix, commit with a reference to the lessons line.
  - **ADR**: meaningful, hard-to-reverse decision → write `docs/adr/NNNN-*.md`.
  - **Just doc**: leave in lessons file, no skill change.
- The lessons doc is closed for this build at the end of Round 6 (further iterations open a new doc).

## Verification

Each verification step lands in `docs/lessons-learned/feature-factory-build.md`.

1. **Glob precursor**: with current `issues/` queue (which has `.rubric.md` files), run `/work-issues` once before and after the glob fix; confirm the prompt for the same task gets shorter and the task-selector behavior is unchanged.
2. **`feature.sh start` smoke**: run on `"Add a /version subcommand to crap"`; confirm steps 0–3 execute and the orchestrator exits at Checkpoint 1 with clear resume instructions.
3. **Checkpoint resume**: close terminal between Checkpoint 1 and 2; reopen, run `feature.sh continue <id> --accept`; confirm orchestrator picks up at Step 4.
4. **`--redo` flow**: reject the story (`feature.sh continue <id> --redo "make the version output JSON"`); confirm Step 3 reruns with the feedback prepended; confirm new issue reflects the feedback.
5. **Spec parser**: hand-craft a spec missing the `paths` blocks; confirm Step 4 exits with `state.last_completed_step = "spec_invalid"` and a clear error message naming the expected format.
6. **Lane preamble**: in Smoke 2, inspect the generated `/tmp/feature-runs/<id>/lane-backend.prompt.md` — confirm it contains the allowlist and the SKILL.md body.
7. **`ADVERSARIAL_REVIEW_REPORT_ONLY=1`**: invoke `/adversarial-review` directly with the env var set; confirm Phase 3 skips the prompt and proceeds as if D was chosen.
8. **Severity routing**: hand-plant a Critical finding (edit a spec file to include a known-bad path) and run validator; confirm `route_findings` puts the fix issue in the correct lane.
9. **Concurrency**: try `feature.sh start` while another run is active; confirm second invocation refuses with a clear message.
10. **Skill evals** (auto): run skill-creator-style evals on `write-a-spec` with 3–4 test prompts. Run `/feature` end-to-end smoke evals on at least 2 fixture briefs.
11. **`--lane` enforcement smoke** (in-repo, limited): given allowlist `["plugins/agentic-engineering/skills/crap/crap.py"]`, the lane prompt should result in edits only to `crap.py` even when the model could be tempted to touch `bin/loop.sh`. *Note: limited test in this repo per Round 4 caveat.*
12. **Dogfood verdict**: every round (0–6) has a section in the lessons doc. Empty findings are recorded as "no friction observed" — that's an honest result.

## Out of scope

- Wiring rubric criteria to the Anthropic Managed Agents `user.define_outcome` API. (`write-a-rubric`'s closing one-liner already points at this; the orchestrator can be extended later to submit rubrics as outcomes.)
- Hard-mode lane enforcement via `.claude/settings.local.json`. v1 is soft-only (prompt-instruction). Future iteration if soft mode proves leaky.
- A general "lane registry" beyond what each repo's `CLAUDE.md` lists.
- Modifying `prd-to-issues` for single-feature flow. (Orchestrator uses an inline subagent prompt instead.)
- Replacing or supplementing `tdd`, `crap`, `grill-with-docs`, `/map` — all reused as-is.
- Renaming to a separate `feature-factory` plugin. Workflow on top of `agentic-engineering`.
- Semantic lane-enforcement validation in this repo (no real backend/frontend split). Deferred to first downstream user with a polyglot repo; tracked as `issues/0099-validate-lane-semantics-in-polyglot-repo.md`.
- A `commands/` directory in any plugin. `/feature` lives at `skills/feature/SKILL.md` (matching the existing `/work-issues`, `/map`, `/adversarial-review`, `/zoom-out` convention of slash-only skills).
