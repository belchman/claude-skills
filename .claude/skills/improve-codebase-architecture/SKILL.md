---
name: improve-codebase-architecture
description: Explore a codebase to find opportunities for architectural improvement, focusing on making the codebase more testable by deepening shallow modules. Use when user wants to improve architecture, find refactoring opportunities, consolidate tightly-coupled modules, or make a codebase more AI-navigable.
---

# Improve Codebase Architecture

Explore a codebase like an AI would, surface architectural friction, find testability gains, and propose module-deepening refactors as GitHub-issue-style RFCs.

A **deep module** (Ousterhout, *A Philosophy of Software Design*) has a small interface hiding a large implementation. Deep modules are more testable, more AI-navigable, and let you test at the boundary instead of inside.

## Process

### 1. Explore

Use `Agent` with `subagent_type=Explore` to navigate naturally. Don't follow rigid heuristics — explore organically and note friction:

- Where does understanding one concept require bouncing between many small files?
- Where is the interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, while the real bugs hide in how they're called?
- Where do tightly-coupled modules create integration risk in the seams?
- Which parts are untested or hard to test?

The friction IS the signal.

### 2. Present candidates

Numbered list of deepening opportunities. For each:

- **Cluster**: modules/concepts involved
- **Why coupled**: shared types, call patterns, co-ownership
- **Dependency category**: see [REFERENCE.md](REFERENCE.md) for the four
- **Test impact**: which existing tests get replaced by boundary tests

Do NOT propose interfaces yet. Ask: "Which of these would you like to explore?"

### 3. User picks a candidate

### 4. Frame the problem space

Before spawning sub-agents, write a user-facing explanation for the chosen candidate:

- Constraints any new interface must satisfy
- Dependencies it would rely on
- A rough illustrative code sketch — to ground constraints, not propose

Show the user, then immediately go to Step 5 — they read while sub-agents work in parallel.

### 5. Design multiple interfaces

Spawn 3+ sub-agents in parallel via `Agent`. Each must produce a **radically different** interface. Brief each separately with file paths, coupling details, dependency category, what's hidden — independent of Step 4's user-facing framing. Give each a different constraint:

- A1: minimize the interface — 1–3 entry points max
- A2: maximize flexibility — many use cases, extension points
- A3: optimize for the most common caller — trivial default case
- A4 (if applicable): ports & adapters for cross-boundary deps

Each outputs:

1. Interface signature (types, methods, params)
2. Usage example
3. What complexity it hides
4. Dependency strategy (see [REFERENCE.md](REFERENCE.md))
5. Trade-offs

Present sequentially, then compare in prose. Give your own recommendation — strongest design and why; propose a hybrid if elements combine well. Be opinionated.

### 6. User picks an interface (or accepts your recommendation)

### 7. Write the issue file

Write the RFC as a local markdown file in `issues/` using the template in [REFERENCE.md](REFERENCE.md). Don't ask the user to review before writing — write it and share the path.
