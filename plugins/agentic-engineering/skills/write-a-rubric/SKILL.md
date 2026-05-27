---
name: write-a-rubric
description: 'Produce a gradeable rubric file from an issue, PRD, or free-form goal — sharpened to the standard required by Anthropic''s Managed Agents user.define_outcome event. Sidecar artifact (issues/NNN-*.rubric.md or rubrics/SLUG.md); does not modify source files. Use when the user wants to define "what done looks like" for grader-checkable success criteria. Triggers: /write-a-rubric, "write a rubric", "outcome rubric", "define-outcome", "managed-agent outcome", "make this gradeable".'
---

# write-a-rubric

A rubric is a markdown document of **independently gradeable criteria**: assertions a separate context — given only the produced artifact, no conversation, no source code — can verify pass/fail. Vague criteria produce noisy evaluations; this skill exists to keep them sharp.

Source discipline: [Anthropic Managed Agents — Define outcomes](https://platform.claude.com/docs/en/managed-agents/define-outcomes).

## When to run

- Triggered by an issue, PRD, or free-form goal that needs a grader-checkable spec.
- Optional sidecar to `prd-to-issues` — produce a rubric per AFK issue worth grading.
- Required input for a future `/dispatch-outcome` skill that calls the Managed Agents API.

## Inputs (priority order)

1. Path to an `issues/NNN-*.md` file (most common).
2. Path to `issues/prd.md` (rare — produces a project-level rubric at `rubrics/prd.md`).
3. Free-form goal in the user's message.

If invoked from an issue, also read `issues/prd.md` for parent context if it exists.

## Output

| Source | Path |
|---|---|
| `issues/NNN-<slug>.md` | `issues/NNN-<slug>.rubric.md` (mirrors filename) |
| `issues/prd.md` | `rubrics/prd.md` |
| Free-form goal | `rubrics/<slug>.md` |

Create `rubrics/` lazily if needed.

## What makes a criterion "gradeable"

Picture a separate context that sees **only the produced artifact** — no conversation, no source code, no context about what was asked. Could that context decide pass/fail? If yes, the criterion is gradeable. If not, sharpen or split.

The single most powerful sharpening move is naming the **observation** the grader makes — the command they run, the file they open, the byte they compare, the count they read. Not every criterion needs an explicit command, but every criterion needs an observable. When the observable isn't obvious, write it down.

**Vague → sharp:**

| Vague | Sharp |
|---|---|
| Output is correct | `sha256(gunzip(output))` equals `sha256(gunzip(legacy_fixture))` for each fixture in `tests/fixtures/small/` |
| Handles edge cases | A test exists for each of: empty table, single row, embedded commas, embedded newlines, NULLs, unicode |
| Performant | p95 latency on the eval query set regresses ≤ 10% vs. the pre-change baseline, both numbers recorded in `results.md` |
| Has tests | Unit tests for these five named cases exist as distinct test functions: under-limit, at-limit, over-limit-minute, over-limit-day, enterprise-bypass |
| Well-documented | A file at `docs/exporter.md` exists and contains sections titled "Resume state", "S3 key contract", and "How to abort a run" |

Each sharpened version names what the grader can see in the artifact alone.

## Process

1. **Read input.** Issue, PRD, or capture the free-form goal.
2. **Identify the deliverable.** What artifact is produced, where it lives, in what format. If unclear, ask once.
3. **Seed from acceptance criteria** if the source is an issue with `## Acceptance criteria`. Treat them as starting points to *sharpen*, not as the rubric itself.
4. **Draft criteria.** Group by category. Common categories: Deliverable, Inputs/Data, Behavior, Output Quality, Constraints. Each criterion is one independent observable assertion. For non-obvious criteria, attach a short verification hint — the command, file, or comparison the grader uses.
5. **Self-critique pass.** For each criterion ask: *"Could a grader with ONLY the produced artifact — no conversation, no source code, no extra context — verify this?"* If no, sharpen or split using the table above.
6. **Stop check.** Continue until **≥4 gradeable criteria across ≥2 categories** AND the deliverable is unambiguous, OR the user explicitly says "ship it." Then stop. Leanness matters: every criterion must earn its place. A focused 10-criterion rubric grades more reliably than a 25-criterion one — duplicates and unscorable items become noise the grader has to filter through. If you find yourself past ~20 criteria for a single issue, look for items to cut or merge before items to add.
7. **Write the file** at the path above.
8. **Print the closing one-liner**:
   `Next: pass as {type:'text', content:...} to user.define_outcome, or upload via Files API.`

## Rubric template

```markdown
# <Outcome title> — Rubric

## Deliverable
- <what artifact, where, in what format — name a concrete path / object / command-output>

## <Category 1, e.g. Inputs / Data>
- **<ID-1>**: <gradeable criterion>. _Check: <command, file path, or observation>._
- **<ID-2>**: <gradeable criterion>. _Check: <how the grader verifies>._

## <Category 2, e.g. Behavior>
- **<ID-3>**: <gradeable criterion>. _Check: <how>._

## Output Quality
- <file format, naming, location — name the exact path/extension expected>
- <"must include" sections, named by title>

## Constraints
- <hard limits, must-not-do items — stated as observable absences where possible>
```

Notes on the template:

- **IDs** (e.g. `MEM-1`, `S2`, `R3`) help the grader cite which check failed and let downstream tools key off stable identifiers. Use short prefixes per category.
- **The `Check:` italicised tail is optional but encouraged.** Use it when the observable isn't obvious from the assertion itself. Skip it when the assertion already names its own check (e.g., "A file at path X exists" — the check is `test -f X`).

## Worked one-criterion example

```markdown
- **RES-1**: After SIGKILL of the worker mid-export, a subsequent run with the
  same `(tenant, date)` resumes from the last committed offset rather than
  restarting from row 0. _Check: `tests/resume/test_kill_resume.py` passes;
  decompressed final object has exactly `expected_rows + 1` lines._
```

What this criterion does right:
- One observable assertion (resumes from offset, doesn't restart).
- Names the artifact the grader inspects (the test file + the final object).
- Verification is mechanical — exit code + line count, no judgement.
- No conversation reference ("as we discussed", "the case Sarah mentioned").

## Anti-patterns

- **Vague verbs.** "looks good", "is reasonable", "handles edge cases", "is clean", "is well-structured" — all unscorable. Replace with the specific observable.
- **Multi-check bullets.** "validates input AND returns a token AND logs the event" — split into three.
- **Taste-based criteria.** "is elegant", "is well-written" — push into examples instead, or drop.
- **Restating the description.** "does what was asked" — adds nothing the grader can check.
- **Conversation-dependent criteria.** "matches what we discussed", "covers the edge case Sarah mentioned" — the grader can't read the conversation. Make it explicit in the rubric.
- **Bloated rubrics.** A rubric with 30 criteria is not 3× better than one with 10 — it's noisier. Each criterion must earn its place. Prefer to merge or cut over to add.
- **Post-launch criteria mixed with artifact criteria.** "Zero Sev-2s in the quarter after rollout" can't be graded from the artifact itself. If you must include such items, isolate them in a separate section the grader knows to defer.

## Hard rules

- One file per outcome.
- Do not modify the source issue or PRD.
- Do not call the Managed Agents API. Do not call the Files API. This skill produces text only.
- If the source is too thin to produce ≥4 sharp criteria, ask the user — don't fabricate. If no user is available (e.g., AFK / autonomous run), write a sibling `QUESTIONS.md` listing what you'd have asked, then produce a best-guess rubric with assumptions clearly marked at the top.

## Rubric &lt; contract

A rubric grades the **artifact's observable shape** — file paths, headings, byte equality, exit codes. It does NOT grade the **contract** the artifact participates in: race conditions, exit-code propagation through pipelines, behavior on empty/whitespace input, behavior on missing trailing newline, behavior under SIGKILL, atomicity of state writes, byte-stability for prompt caching. Most production bugs live in the contract, not the artifact.

This means **a passing rubric is necessary but not sufficient**. The natural follow-up after `write-a-rubric` is a contract-level review — `/adversarial-review` against the diff catches what the rubric can't see by design. Pattern observed across the feature-factory dogfooding: 5 issues each had passing rubrics yet adversarial review caught **17+ critical bugs** the rubric was structurally unable to anticipate. Examples that recurred: missing trailing newline dropped last line of input; non-atomic state write torn on crash; exit codes silently swallowed by `|| true`; whitespace in user input matched the wrong path; glob characters silently passed through.

When sharpening criteria, prefer ones that observe the *artifact*. Resist the urge to write criteria like "handles SIGKILL gracefully" or "is robust to concurrent invocations" — those need active testing the grader can't do from a static file. Leave them to the post-rubric contract review. Document the boundary in the rubric itself if it's load-bearing (e.g., a final `## Out of rubric scope` section listing the contract concerns deferred to `/adversarial-review`).
