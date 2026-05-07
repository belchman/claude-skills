---
name: grill-me
description: Pure socratic interrogation with NO project artifacts at all — no codebase, no CONTEXT.md, no ADRs to reference. One question at a time, walk the decision tree, recommend an answer for each branch. Rare edge case — most grilling happens inside a project, so use grill-with-docs by default (it handles the no-CONTEXT.md case by creating one lazily). Use grill-me ONLY when the user is brainstorming entirely outside a codebase (a fresh idea before any code exists, a hypothetical, a non-software design problem).
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Stop conditions

End the session when **any** holds:

- The user signals done.
- Every open branch of the design tree has at most a one-sentence answer.
- The plan is concrete enough to feed into the user's next step (e.g. `write-a-prd`, sketching an implementation, or a separate decision).

Without a stop condition, pure socratic loops wander. When you hit one, summarize what crystallized and what's still open in one closing block.
