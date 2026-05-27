---
name: prd-to-issues
description: 'Read an existing PRD (typically issues/prd.md, written by write-a-prd) and break it into vertical-slice tracer-bullet issues at issues/NNN-short-title.md, tagged HITL (needs human) or AFK (autonomous). Step 2 of the build pipeline (write-a-prd → prd-to-issues → work-issues). Use when a PRD exists and needs to become work tickets. NOT for writing the PRD itself (use write-a-prd). Triggers: /prd-to-issues, "break this PRD into issues", "turn this spec into tickets".'
---

# PRD to Issues

Break a PRD into independently-grabbable issues using vertical slices (tracer bullets), written as local markdown files.

## Process

### 1. Locate the PRD

Ask for the PRD file path (e.g. `issues/prd.md`). If not in context, read it.

### 2. Explore the codebase (optional)

If you haven't already, explore to understand current state.

### 3. Draft vertical slices

Each issue is a **tracer bullet** — a thin vertical slice cutting through ALL layers end-to-end, NOT a horizontal slice of one layer.

Slices are **HITL** (need human interaction — design review, architectural decision) or **AFK** (implementable and mergeable without it). Prefer AFK.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 4. Quiz the user (or skip if AFK)

Present a numbered list. For each slice:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which slices (if any) must complete first
- **User stories covered**: which from the PRD

Ask:

- Does the granularity feel right? (too coarse / too fine)
- Are dependencies correct?
- Should any slices be merged or split?
- Are HITL/AFK labels right?

Iterate until approved.

**AFK fallback** (no user available — `/feature` running headlessly, `claude -p` invocation, etc.): skip the quiz. Make your best granularity call from the PRD alone, then proceed straight to step 5. In each issue file's `## What to build` section, add a `### Slice rationale` sub-section noting why this slice exists as its own ticket (vs. being folded into a sibling) — a future reviewer or downstream agent reads it to challenge the slicing at the next checkpoint. If you're uncertain between two slicings, write a sibling `QUESTIONS.md` listing the choice you made and the alternative.

**Narrow-feature note:** The "vertical slice through all layers (schema, API, UI, tests)" framing assumes a multi-layer feature. For a single-file CLI flag, a one-script change, or a docs-only update, the layers may collapse to one. Don't force-split a one-issue feature into three issues just to satisfy "many thin slices"; one issue with clear acceptance criteria is the right answer when there's only one layer to cut through. The "deep module + wiring" split is the most common natural 2-issue shape for narrow features.

### 5. Create the issue files

For each approved slice, write `issues/NNN-short-title.md` (e.g. `issues/001-add-user-auth.md`). Number from the next available slot (check existing files in `issues/`).

Create files in dependency order (blockers first) so "Blocked by" can reference real filenames.

Do NOT use `gh issue create` or any GitHub CLI. Do NOT reference GitHub issue numbers. Local filenames only for cross-references.

<issue-template>
## Parent PRD

`issues/prd.md` (or whichever PRD was used)

## Type

**HITL** or **AFK** — pick one. HITL means a human needs to be in the loop (design review, credentials, architectural call). AFK means it can be picked up and merged autonomously.

## What to build

Concise description of this vertical slice. End-to-end behavior, not layer-by-layer implementation. Reference sections of the parent PRD rather than duplicating.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- Blocked by `issues/NNN-title.md` (if any)

Or "None - can start immediately".

## User stories addressed

Reference by number from the parent PRD:

- User story 3
- User story 7

</issue-template>

Do NOT close or modify the parent PRD file.

## Next

After issues are written, optionally run `write-a-rubric` per AFK issue to define grader-checkable success criteria as a sibling `issues/NNN-*.rubric.md`. Then run `work-issues` to start working the queue.
