---
name: write-a-prd
description: Interview the user and produce issues/prd.md from a client brief, feature idea, or rough request. Step 1 of the build pipeline (write-a-prd → prd-to-issues → work-issues). Use when no PRD exists yet and one is needed. NOT for breaking an existing PRD into tasks (use prd-to-issues), and NOT for tracker-coupled output (this writes local markdown only). Triggers: /write-a-prd, "write a PRD", "draft a spec", "turn this brief into a PRD".
---

Invoked when the user wants to create a PRD. Skip steps you judge unnecessary.

1. Ask the user for a long, detailed description of the problem and any solution ideas.

2. Explore the repo to verify their assertions and understand current state.

3. Interview the user relentlessly about every aspect of the plan until you reach shared understanding. Walk each branch of the design tree, resolving dependencies one-by-one.

4. Sketch the major modules to build or modify. Look for opportunities to extract **deep modules** — modules that hide a lot of functionality behind a simple, testable interface that rarely changes. Confirm the module breakdown matches the user's expectations and which modules they want tests for.

5. Write the PRD to `issues/prd.md` using the template below. Create `issues/` if missing. Do NOT submit a GitHub issue or call any external service.

<prd-template>

## Problem Statement

The problem from the user's perspective.

## Solution

The solution from the user's perspective.

## User Stories

A LONG, numbered list. Format:

1. As an <actor>, I want <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

Cover all aspects of the feature extensively.

## Implementation Decisions

- Modules to build/modify
- Interfaces being modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets — they go stale fast.

## Testing Decisions

- What makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art (similar tests in the codebase)

## Out of Scope

What's out of scope for this PRD.

## Further Notes

Anything else.

</prd-template>
