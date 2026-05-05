---
name: tdd
description: Test-driven development with red-green-refactor loop. Use when user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, or asks for test-first development.
---

# Test-Driven Development

## Philosophy

**Core principle:** tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

- **Good tests** are integration-style: real code paths through public APIs. They read like specs ("user can checkout with valid cart") and survive refactors.
- **Bad tests** couple to implementation: mock internal collaborators, hit private methods, or verify via side channels (e.g. raw DB queries). Warning sign: the test breaks on a refactor with no behavior change.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking rules.

## Anti-pattern: horizontal slices

**Do not write all tests first, then all implementation.** Bulk-written tests verify *imagined* behavior — they test the *shape* of things (signatures, data) rather than user-facing behavior, and become insensitive to real changes.

**Correct:** vertical slices. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle.

```
WRONG (horizontal):  RED: t1,t2,t3,t4,t5  → GREEN: i1,i2,i3,i4,i5
RIGHT (vertical):    RED→GREEN: t1→i1, t2→i2, t3→i3, ...
```

## Workflow

### 1. Planning

Before writing code:

- [ ] Confirm interface changes with the user
- [ ] Confirm which behaviors to test, prioritized — you can't test everything
- [ ] Identify [deep modules](deep-modules.md) (small interface, deep implementation)
- [ ] Design interfaces for [testability](interface-design.md)
- [ ] List behaviors (not implementation steps)
- [ ] Get user approval

Ask: "What should the public interface look like? Which behaviors matter most?"

### 2. Tracer bullet

Write ONE test for ONE behavior. RED → minimal code → GREEN. Proves the path works end-to-end.

### 3. Incremental loop

For each remaining behavior: RED (next test fails) → GREEN (minimal code passes).

Rules: one test at a time; only enough code to pass it; no anticipating future tests; tests stay on observable behavior.

### 4. Refactor

After GREEN, look for [refactor candidates](refactoring.md):

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID where natural
- [ ] Reconsider existing code in light of the new code
- [ ] Re-run tests after each step

**Never refactor while RED.** Get to GREEN first.

## Per-cycle checklist

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive an internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
