---
name: grill-with-docs
description: Stress-test a plan, design, or idea against the project's domain language (CONTEXT.md) and recorded decisions (docs/adr/). One question at a time, walks the decision tree, captures crystallized terminology and decisions inline. THIS IS THE DEFAULT GRILLING SKILL — use for any interrogation in a real project, even if CONTEXT.md or docs/adr/ don't exist yet (they get created lazily on first term resolution / first ADR-worthy decision). Triggers: /grill-with-docs, "grill me", "grill this", "interrogate this plan", "stress-test this design", "walk me through the decisions", "challenge this". Use grill-me ONLY for pure green-field thinking with no codebase at all — rare.
---

# grill-with-docs

Challenge the user's plan against the project's existing language and decisions. Sharpen fuzzy terms. Capture what crystallizes — `CONTEXT.md` for shared language, `docs/adr/*` for hard-to-reverse decisions — as it happens, not at the end.

## 1. Anchor on a plan

Open with: **"What plan are we stress-testing?"**

The plan can be a PRD path, an issue, a sketch in the conversation, or a verbal description. If the user has nothing concrete, recommend running `write-a-prd` first — grilling without an artifact tends to wander.

Identify the *outcome* of the session up front: by the end, the plan should be concrete enough to feed into `prd-to-issues` (break into work) or `improve-codebase-architecture` (find deepening targets).

## 2. Pre-flight: read the project's language

Before the first question, scan for:

- `CONTEXT.md` at the repo root → single context
- `CONTEXT-MAP.md` at the root → multi-context; read it to find each `CONTEXT.md` and its `docs/adr/`
- `docs/adr/*.md` → existing decisions

Create files **lazily** — only when the first term resolves or the first ADR is needed. Don't pre-create empty scaffolding.

If `CONTEXT-MAP.md` exists, infer which context the current plan touches. Ask if unclear.

## 3. The grill

One question at a time. Wait for the answer before continuing. For each question, give your recommended answer. **If a question can be answered by reading the codebase, read the codebase — don't ask the user.**

Apply four sharpening modes as the conversation unfolds:

- **Challenge against the glossary.** Term conflicts with `CONTEXT.md`? Surface immediately: *"Your glossary defines 'cancellation' as X but you mean Y — which is it?"*
- **Sharpen fuzzy language.** Vague or overloaded? Propose a precise canonical term: *"You're saying 'account' — Customer or User? Different things."*
- **Stress-test with scenarios.** Domain relationships hand-waved? Invent edge-case scenarios that force precision about boundaries.
- **Cross-reference code.** User states how something works? Verify in code. If they disagree, surface it: *"Your code cancels whole Orders, but you said partial cancellation is possible — which is right?"*

## 4. Capture inline (don't batch)

- **Term resolved** → update `CONTEXT.md` now. Format in [CONTEXT-FORMAT.md](CONTEXT-FORMAT.md). Domain terms only — no implementation details.
- **Hard-to-reverse decision crystallizes** → draft an ADR now. Format in [ADR-FORMAT.md](ADR-FORMAT.md). Threshold below — strict.

### ADR threshold

Offer an ADR **only when all three are true**:

1. **Hard to reverse** — meaningful cost to change later.
2. **Surprising without context** — a future reader would wonder *"why on earth?"*.
3. **Real trade-off** — there were genuine alternatives and you picked one for specific reasons.

If any is missing, skip. Most decisions don't need an ADR.

## 5. Stop conditions

End the session when **any** holds:

- User signals done.
- Every open branch of the design tree has at most a one-sentence answer.
- No remaining terms in the plan conflict with `CONTEXT.md`.
- The user's stated model matches the code (no surprises remaining).
- The plan is concrete enough to feed into `prd-to-issues` or `improve-codebase-architecture` without further interrogation.

## 6. Close with a summary

Always end with this block — even if the session was short — so the user knows what to review and commit:

```
=== Session summary ===

CONTEXT.md changes:
  - <term added / refined / ambiguity resolved>
  - …

ADRs:
  - <NNNN-slug>: <one-line>
  - …

Open questions:
  - <unresolved item> (stopped because <reason>)

Next step:
  - <suggested skill: write-a-prd | prd-to-issues | improve-codebase-architecture | work-issues>
```

If nothing changed, say so — don't fabricate updates.

## Hard rules

- One question at a time. Wait for the user.
- Codebase question? Read the codebase, don't ask.
- Don't couple `CONTEXT.md` to implementation details.
- Don't batch updates — capture as decisions crystallize.
- Be opinionated when picking among synonyms; list rejected aliases under "Avoid" in `CONTEXT.md`.

<!-- Adapted from mattpocock/skills@494e4b2699ea (MIT). Improvements over upstream: explicit plan-anchor, stop conditions, closing summary, wired to this repo's PRD/issues/architecture skills. See ATTRIBUTION.md. -->
