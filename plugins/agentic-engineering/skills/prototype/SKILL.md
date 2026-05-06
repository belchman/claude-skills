---
name: prototype
description: Build a throwaway prototype to flush out a design before committing. Routes between two branches — a runnable terminal app for state/business-logic questions, or several radically different UI variations toggleable from one route. Use when the user wants to prototype, sanity-check a data model or state machine, mock up a UI, explore design options, or says "prototype this", "let me play with it", "try a few designs".
---

# prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick a branch

Identify the question — from the user's prompt, surrounding code, or by asking:

- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md). Tiny interactive terminal app that pushes the state machine through cases hard to reason about on paper.
- **"What should this look like?"** → [UI.md](UI.md). Several radically different UI variations on a single route, switchable via URL search param + a floating bottom bar.

The two branches produce very different artifacts — getting this wrong wastes the whole prototype. If genuinely ambiguous and the user isn't reachable, default to whichever matches the surrounding code (backend module → logic; page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype next to the module/page it's for so context is obvious — but name it so a casual reader sees it's a prototype, not production. For throwaway UI routes, follow the project's existing routing convention; don't invent a new top-level structure.
2. **One command to run.** Whatever the project's task runner supports — `pnpm <name>`, `python <path>`, `bun <path>`. The user must start it without thinking.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is *checking*, not something it depends on. If the question explicitly involves a DB, use a scratch DB or local file with a clear "PROTOTYPE — wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype runnable, no abstractions. Learn fast, then delete.
5. **Surface the state.** After every action (logic) or variant switch (UI), print or render the full relevant state so the user sees what changed.
6. **Delete or absorb when done.** Once the prototype has answered its question, delete it or fold the validated decision into real code. Don't leave it rotting.

## When done

The *answer* is the only thing worth keeping. Capture it somewhere durable (commit message, ADR, issue, or a `NOTES.md` next to the prototype) along with the question it answered. If the user is around, that capture is a quick conversation; if not, leave the placeholder so they (or you, on the next pass) can fill in the verdict before deleting the prototype.

<!-- Vendored verbatim from mattpocock/skills@494e4b2699ea (MIT). See ATTRIBUTION.md. -->
