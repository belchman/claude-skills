---
name: prd-to-issues
description: Read an existing PRD (typically issues/prd.md, written by write-a-prd) and break it into vertical-slice tracer-bullet issues at issues/NNN-short-title.md, tagged HITL (needs human) or AFK (autonomous). Step 2 of the build pipeline (write-a-prd → prd-to-issues → work-issues). Use when a PRD exists and needs to become work tickets. NOT for writing the PRD itself (use write-a-prd). Triggers: /prd-to-issues, "break this PRD into issues", "turn this spec into tickets".
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

### 4. Quiz the user

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

### 5. Create the issue files

For each approved slice, write `issues/NNN-short-title.md` (e.g. `issues/001-add-user-auth.md`). Number from the next available slot (check existing files in `issues/`).

Create files in dependency order (blockers first) so "Blocked by" can reference real filenames.

Do NOT use `gh issue create` or any GitHub CLI. Do NOT reference GitHub issue numbers. Local filenames only for cross-references.

<issue-template>
## Parent PRD

`issues/prd.md` (or whichever PRD was used)

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
