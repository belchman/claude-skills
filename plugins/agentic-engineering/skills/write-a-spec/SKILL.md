---
name: write-a-spec
description: 'Turn an approved story (issues/NNN-*.md) plus an optional research dump into a technical spec sidecar at issues/NNN-*.spec.md — data model, API, file-by-file change list per lane (as fenced ```paths blocks), behavior-list of tests required, and risks. The spec drives /feature''s lane allowlist; lane H3 headings must match labels from CLAUDE.md ## Lane boundaries. Sidecar only — does not modify source files. Use when the user wants to write a technical brief from a story or issue, or whenever /feature dispatches the Spec Writer phase. Triggers: /write-a-spec, "write a spec", "technical spec", "spec from this issue", "draft a technical brief".'
---

# write-a-spec

A **spec** is the technical-brief sidecar to an issue. It sits between the approved story (what the user wants) and the lane builders (`/work-issues --lane …` via `/feature`), and it must answer two questions:

1. **What changes** — data model, API shape, files touched per lane, tests required, risks.
2. **Where the lane allowlists come from** — the spec's `File-by-file change list` is the *source* `work-issues-lib.sh::allowlist_for` parses (via `/feature`'s orchestrator) to scope each lane's `/work-issues` invocation.

A vague spec produces a confused builder and a broken lane scope. This skill exists to keep specs sharp enough that the parser can deterministically extract per-lane allowlists and a builder can implement without re-asking.

Source-of-truth for the protocol: [`docs/plans/feature-factory.md`](../../../../docs/plans/feature-factory.md) §C ("Spec → allowlist format") + ADR [`0001-fenced-paths-blocks-for-lane-allowlists`](../../../../docs/adr/0001-fenced-paths-blocks-for-lane-allowlists.md). Project glossary: [`CONTEXT.md`](../../../../CONTEXT.md).

## When to run

- Step 4 of the `/feature` chain — orchestrator hands the approved story + research dump in.
- Direct user invocation — `/write-a-spec issues/NNN-foo.md` works the same way; missing research dump is handled (see below).
- After a story is approved at `/feature`'s Checkpoint 1 but before the user reviews the spec at Checkpoint 2.

## Inputs (priority order)

1. **Path to an `issues/NNN-*.md` file** (the approved story). Required.
2. **Path to `issues/research/NNN-*.md`** (the research dump from `/feature`'s Explore subagent pass). **Optional.** If missing, proceed and add a Risks bullet — see "Missing-research handling" below.
3. **`CLAUDE.md`** at the repo root — required to look up lane vocabulary. Read its `## Lane boundaries` section if present (see "Lane discovery").
4. **`ARCHITECTURE.md`** at the repo root — optional, read if present to ground module / dependency claims.

If invoked from an issue, also read `issues/prd.md` for parent context if it exists.

## Output

| Source | Output |
|---|---|
| `issues/NNN-<slug>.md` | `issues/NNN-<slug>.spec.md` (sidecar; mirrors filename) |

The output is a **new file**. The skill does **not** modify the source issue, the PRD, or any other existing file. The only `Write`-tool use is to create the spec at the output path above.

## Lane discovery

Before drafting the `File-by-file change list`, read `CLAUDE.md` and look for a `## Lane boundaries` section. That section is the canonical lane vocabulary for the project (e.g. `Backend`, `Frontend`, `CLI`, `Worker`). Lane H3 headings in the spec **MUST** match labels defined there — the orchestrator's parser compares H3 text to allowlist names character-for-character.

If `CLAUDE.md` has no `## Lane boundaries` section, ask the user once for the project's lane vocabulary, then proceed. Don't invent lanes silently.

**AFK fallback** (no user available — `/feature` running headlessly, `claude -p` invocation, etc.): instead of stalling on "ask the user," write a sibling `issues/NNN-<slug>.QUESTIONS.md` file listing the lane-vocabulary question explicitly. Use a best-guess lane vocabulary derived from top-level directory names in the repo (e.g. `src/api` → `Backend`, `web/` → `Frontend`, `cmd/` → `CLI`) AND clearly mark this guess in the spec's Risks section: "Lane vocabulary inferred from top-level dirs; CLAUDE.md `## Lane boundaries` is missing. Confirm before any lane build runs."

If `CLAUDE.md` is missing entirely, treat it the same as "has no Lane boundaries section" — write `QUESTIONS.md`, infer from top-level dirs, mark in Risks.

## Single-lane handling

If the feature only touches one lane (e.g. a backend cron job, a frontend-only UI tweak, a CLI subcommand), the spec **omits the unused lane's H3 entirely** — do **not** emit an empty `paths` block. The orchestrator's parser treats a missing lane as "skip this lane's invocation," which is the correct behavior for single-lane features. Empty paths blocks would be parsed as "this lane exists but has no edits," which is a different (and confusing) signal.

## Missing-research handling

If the expected `issues/research/NNN-*.md` file is missing (e.g. the user invoked the skill directly without running `/feature`'s Explore pass), proceed anyway. Add an explicit Risks bullet:

> No research pass performed; consider running `/feature` for fuller context. The file/module assumptions in this spec are based on the issue text and CLAUDE.md only.

Direct user invocation must work — this skill is not exclusively coupled to `/feature`. Do **not** refuse to draft a spec because the research dump is absent.

## Process

1. **Read input.** Issue, research dump (if present), `CLAUDE.md`, `ARCHITECTURE.md`.
2. **Resolve lane vocabulary** from `CLAUDE.md` `## Lane boundaries`.
3. **Identify the deliverable.** What artifact is produced, where it lives, in what shape.
4. **Draft each template section.** Use the template below verbatim — sections that are genuinely N/A still appear with body `_N/A — <one-sentence reason>_` (forces conscious consideration; doesn't silently skip a category the builder might have missed).
5. **Self-critique pass.** For each `paths` line: is this an actual literal path the builder will touch, or a placeholder? For each `Tests required` bullet: is this a testable behavior with an observable outcome, or a wish?
6. **Stop check.** All seven template sections present; every lane that has changes has an H3 + fenced `paths` block; every path is literal (no globs); every test bullet names an observable behavior.
7. **Write the file** at `issues/NNN-<slug>.spec.md`.
8. **Print the closing one-liner**:
   `Next: review the spec at issues/NNN-<slug>.spec.md, then run write-a-rubric and feature.sh continue <id> --accept (or feed to /feature's Checkpoint 2 if orchestrated).`

## Spec template

Use this template verbatim. All seven H2 sections must appear in the produced spec, in this order.

````markdown
# <Feature title> — Spec

Source story: `issues/NNN-<slug>.md`
Source research: `issues/research/NNN-<slug>.md` (or `_N/A — not run_`)

## Deliverable

- <What artifact is produced, where it lives, in what format. Name a concrete path / object / command output.>

## Data model

- <Schema changes: new columns, new tables, new indexes, migrations. One bullet per change.>

_If genuinely no data model change: `_N/A — <one-sentence reason>_`._

## API

- <New / changed endpoints. For each: method + path + request shape + response shape + status codes.>

_If genuinely no API change: `_N/A — <one-sentence reason>_`._

## File-by-file change list

### <Lane 1, e.g. Backend>

```paths
src/api/handlers/<name>.ts
src/services/<name>.ts
tests/services/<name>.test.ts
```

### <Lane 2, e.g. Frontend>

```paths
web/components/<name>.tsx
web/hooks/<name>.ts
tests/components/<name>.test.tsx
```

_If the feature is single-lane, omit the unused lane's H3 entirely — do not emit an empty `paths` block._

## Tests required

- <one bullet per testable behavior — verb + observable outcome>
- <e.g. `over-limit-minute returns 429 + Retry-After header`>
- <e.g. `enterprise-plan key bypasses rate limiter — verified by 100 reqs without 429`>

_Each bullet becomes one criterion in the downstream rubric (`write-a-rubric`). NOT test file paths and NOT coverage percentages — behavior-level only._

## Risks & open questions

- <Known unknowns, things that need a human call, anything that could change scope mid-build.>

## Tenant/timezone concerns

- <Multi-tenant isolation: does this leak data across tenants? Timezone: does this break in non-UTC?>

_If genuinely no concerns: `_N/A — <one-sentence reason>_`._ Most features have at least one concern worth pinning here, even if "no — single-tenant only" or "no — internal admin tool, no user-facing TZ."
````

## Paths block convention

The `File-by-file change list` section's lane subsections must follow this format strictly — `work-issues-lib.sh::allowlist_for` parses it character-by-character. The parser fails silently (empty output + exit 0) on most mismatches, treating them as "lane not found / skip" — so a typo or formatting deviation produces a silently-skipped lane, not an error:

- **Lane labels** are H3 headings of the form `### <Bareword>` — a single bareword from `CLAUDE.md`'s `## Lane boundaries`, with no markdown styling. Specifically:
  - **No bold**: `### **Backend**` is wrong; parser sees lane name `**Backend**`, never matches lookup for `Backend`.
  - **No links**: `### [Backend](https://...)` is wrong for the same reason.
  - **No trailing `###`** (CommonMark ATX-close): `### Backend ###` puts ` ###` inside the lane name. Use `### Backend` only.
  - **No leading indentation**: `   ### Backend` is not recognised as an H3 by the parser.
  - **No parenthetical annotations**: `### Backend (cron)` becomes lane name `Backend (cron)` — fails the lookup.
  - Trailing whitespace IS tolerated (parser trims) — but leading whitespace anywhere in the heading is not.
- **Paths blocks** are fenced code blocks whose info string is literally `paths` (lowercase, no attributes). Variants the parser silently rejects: `\`\`\`paths bash`, `\`\`\`Paths`, `\`\`\`paths-list`, `~~~paths` (tilde fence), indented fences.
- **Each line inside a `paths` block is one literal file path** — no globs (`*`, `**`, `?`, `[`), no brace expansion (`{a,b}`), no shell metacharacters. The parser rejects all of these with exit 1 and stderr names the offender.
- **A path may appear in only one lane** within a single spec. `route_findings` fails loud on cross-lane duplicates (per plan §C and ADR 0001).
- **Lane sub-sections appear directly under the `File-by-file change list` H2** with their `paths` block following (blank lines OK, prose OK between H3 and fence).
- **Self-check before writing**: after drafting, run `grep -c '^```paths$' <spec>` — the count MUST equal the number of lanes you intended. If you intended 2 lanes but the count is 1, you have a fence typo. Run `grep '^### ' <spec>` — every line must be exactly `### <BarewordLabel>` with no styling.

### Worked example

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

What this does right:

- Two distinct H3 lanes, each with its own `paths` block.
- Every line is a literal path (no `src/api/**/*.ts`).
- Test paths live in the lane that owns them — backend tests under Backend, frontend tests under Frontend.
- No path appears in both lanes.

## Anti-patterns

- **Globs in `paths` blocks.** `src/api/**/*.ts` is not a literal path. The parser will reject the spec. List every file explicitly.
- **Same path in multiple lanes.** `src/shared.ts` cannot appear under both `### Backend` and `### Frontend`. If you need a shared file, that's a design problem — the file probably wants splitting, or one lane owns the file and the other reads from it.
- **Taste-based criteria in `Tests required`.** "looks good", "is clean", "well-structured", "is elegant" — unscorable. Replace with an observable: "function X returns Y given Z."
- **Conversation-dependent items.** "as we discussed", "the case Sarah mentioned", "what we talked about Monday" — the rubric writer and the builder can't read the conversation. Make it explicit in the spec.
- **File paths in `Tests required`.** That's the builder's call. The spec says *what behavior must be tested*; the builder picks the file layout.
- **Coverage percentages in `Tests required`.** "80% coverage" doesn't tell the builder what to test. Behavior list does.
- **Inventing lane labels not in CLAUDE.md.** The orchestrator's parser will get `lane-not-found` and skip the lane silently. Match the vocabulary.
- **Refusing on missing research.** Direct-user invocation is supported. Add a Risks bullet and proceed.

## Hard rules

- One spec file per issue. Output path: `issues/NNN-<slug>.spec.md` (sidecar to `issues/NNN-<slug>.md`).
- Do **not** modify the source issue or PRD or any existing file.
- This skill produces text only. It does not call any external API or service.
- All seven template H2 sections (`Deliverable`, `Data model`, `API`, `File-by-file change list`, `Tests required`, `Risks & open questions`, `Tenant/timezone concerns`) must appear in the output. Sections that are genuinely N/A use `_N/A — <one-sentence reason>_` as the body.
- Lane H3 headings must match labels from `CLAUDE.md`'s `## Lane boundaries`. If no such section exists, ask the user once for the project's lane vocabulary; don't invent.
- If the source story is too thin to produce a meaningful spec (e.g. acceptance criteria are vague placeholders), ask the user — don't fabricate behavior. If no user is available (AFK / autonomous run), write a sibling `QUESTIONS.md` listing what you'd have asked, then produce a best-guess spec with assumptions clearly marked.
