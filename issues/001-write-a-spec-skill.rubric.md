# write-a-spec skill — Rubric

Graders judge the produced artifacts only — the new skill files at
`plugins/agentic-engineering/skills/write-a-spec/`. They do not see the issue,
the PRD, or the feature-factory plan. Source of truth for the spec→allowlist
protocol is `docs/plans/feature-factory.md` §C — but the grader confirms the
protocol survived into the skill file, not into the plan.

## Deliverable

- Two files exist under `plugins/agentic-engineering/skills/write-a-spec/`:
  1. `SKILL.md`
  2. `evals/evals.json`
- No other source files in the repo are modified by the skill author beyond
  these two new files (plus the rubric/issue housekeeping outside this scope).
  _Check: `git status --porcelain` shows only additions under
  `plugins/agentic-engineering/skills/write-a-spec/` (plus issue/rubric
  metadata)._

## Frontmatter & Tool Allowlist (FM)

- **FM-1**: `SKILL.md` opens with YAML frontmatter delimited by `---` on the
  first line and a matching `---` closer before the body. _Check:
  `head -1 SKILL.md` equals `---`; the second `---` line appears within the
  first 20 lines._
- **FM-2**: Frontmatter contains a `name:` key whose value is exactly
  `write-a-spec`. _Check: `grep -E '^name: *write-a-spec$' SKILL.md`
  returns one line._
- **FM-3**: Frontmatter contains a `description:` key. Value is a single
  quoted string (single or double quotes — escapes any colon-space). _Check:
  `grep -E "^description: *['\"]" SKILL.md` returns one line._
- **FM-4**: The `description` value mentions the skill's role as the bridge
  from an approved story + research dump to a technical spec, and names at
  least one trigger phrase (e.g. `write a spec`, `/write-a-spec`, or
  `technical spec`). _Check: the description string contains the substring
  `spec` AND one of `story`, `issue`, `brief`, or `research`._
- **FM-5**: Frontmatter declares a tool allowlist restricted to read-only
  tools. The `allowed-tools` (or equivalent) value lists **only** `Read`,
  `Grep`, `Glob` — no `Edit`, `Write`, `Bash`, or `MultiEdit`. _Check: parse
  the frontmatter and assert the tools field is a subset of
  `{Read, Grep, Glob}`._

## Spec Template Sections (TS)

The skill body specifies the template the spec file (`issues/NNN-*.spec.md`)
must follow. Each of the named sections below must appear in the template
documented inside `SKILL.md`, identified by heading text.

- **TS-1**: A `Deliverable` section is documented. _Check: `grep -E
  '^##+ +Deliverable' SKILL.md` returns at least one line._
- **TS-2**: A `Data model` section is documented. _Check: `grep -E
  '^##+ +Data model' SKILL.md` returns at least one line._
- **TS-3**: An `API` section is documented. _Check: `grep -E
  '^##+ +API' SKILL.md` returns at least one line._
- **TS-4**: A `File-by-file change list` section is documented. _Check:
  `grep -E '^##+ +File-by-file change list' SKILL.md` returns at least one
  line._
- **TS-5**: A `Tests required` section is documented. _Check: `grep -E
  '^##+ +Tests required' SKILL.md` returns at least one line._
- **TS-6**: A `Risks & open questions` section is documented. _Check:
  `grep -E '^##+ +Risks (&|and) open questions' SKILL.md` returns at least
  one line._
- **TS-7**: A `Tenant/timezone concerns` section is documented. _Check:
  `grep -E '^##+ +Tenant/timezone concerns' SKILL.md` returns at least one
  line._

## Paths Block Convention (PB)

These criteria verify the `paths` fenced-block protocol is documented inside
`SKILL.md` strictly enough that `bin/feature.sh`'s parser can rely on it.

- **PB-1**: The skill body shows a fenced code block whose info string is
  literally `paths` (lowercase). _Check: `SKILL.md` contains a line matching
  `^```paths$`._
- **PB-2**: Lane sub-sections appear as H3 headings (three `#`) directly
  above their `paths` block in the worked example. _Check: in the
  documented example, immediately before a `^```paths$` line there is at
  least one `^### ` H3 heading within the preceding 10 lines._
- **PB-3**: The skill body explicitly states the rule that each line inside
  a `paths` block is one literal file path. _Check: `SKILL.md` contains a
  sentence like "one literal path per line" or "one path per line"._
- **PB-4**: The skill body explicitly forbids globs (`*`, `**`, `?`) inside
  `paths` blocks for v1. _Check: `SKILL.md` contains both the word `glob`
  and a negation token (`no`, `not`, `forbidden`, `disallowed`) within the
  same paragraph or list item._
- **PB-5**: The skill body states a path may appear in only one lane (no
  cross-lane duplicates). _Check: `SKILL.md` contains a statement to the
  effect of "a path may appear in only one lane" or equivalent (e.g.
  "duplicates across lanes are rejected")._
- **PB-6**: The skill body shows a complete worked example with at least
  two distinct H3 lanes (e.g. `### Backend` and `### Frontend`), each with
  its own `paths` block containing at least one path. _Check: count of
  `^```paths$` lines inside the worked example is ≥ 2, and the preceding
  H3 headings differ._

## Output Path Convention (OP)

- **OP-1**: The skill body states that for input `issues/NNN-*.md` the
  output path is `issues/NNN-*.spec.md` (same NNN, same slug, `.spec.md`
  extension — sidecar pattern). _Check: `SKILL.md` contains the literal
  substring `.spec.md` AND the substring `issues/`._
- **OP-2**: The skill body states the output is a new file (does not
  modify the source issue file). _Check: `SKILL.md` contains a sentence
  asserting the skill does not edit the issue, OR documents the allowed
  tools as read-only (covered by FM-5)._

## Anti-patterns Section (AP)

- **AP-1**: `SKILL.md` contains a section titled `Anti-patterns` (any
  heading depth). _Check: `grep -E '^##+ +Anti-patterns' SKILL.md`
  returns ≥ 1 line._
- **AP-2**: The Anti-patterns section explicitly forbids globs in
  `paths` blocks. _Check: within the Anti-patterns section the words
  `glob` and one of `paths`/`paths block` appear together._
- **AP-3**: The Anti-patterns section explicitly forbids the same path
  appearing in multiple lanes. _Check: within the Anti-patterns section
  a sentence forbids multi-lane / cross-lane / duplicate paths._
- **AP-4**: The Anti-patterns section explicitly forbids taste-based
  criteria (e.g. "looks good", "is clean", "well-structured"). _Check:
  within the Anti-patterns section the word `taste` appears, or at least
  two of the strings `looks good`, `clean`, `elegant`, `well-structured`,
  `nice`, `reasonable` appear as forbidden phrasings._
- **AP-5**: The Anti-patterns section explicitly forbids
  conversation-dependent items (e.g. "as we discussed", "what Sarah
  mentioned"). _Check: within the Anti-patterns section either the word
  `conversation` appears or a phrase like `as we discussed` / `what we
  talked about` is cited as forbidden._

## Closing One-liner (CL)

- **CL-1**: The skill body documents a closing one-liner the skill prints
  on completion, mirroring `write-a-rubric`'s pattern. _Check: `SKILL.md`
  contains a code block or quoted line introduced by a phrase like
  `closing one-liner`, `prints`, or `output line`._
- **CL-2**: The documented closing one-liner references at least one of
  the next-step entry points: `prd-to-issues`, `/feature`, or
  `write-a-rubric`. _Check: the documented closing line contains at
  least one of those literal substrings._

## Evals File (EV)

- **EV-1**: A file exists at
  `plugins/agentic-engineering/skills/write-a-spec/evals/evals.json`.
  _Check: `test -f plugins/agentic-engineering/skills/write-a-spec/evals/evals.json`._
- **EV-2**: The file parses as valid JSON. _Check: `jq empty
  plugins/agentic-engineering/skills/write-a-spec/evals/evals.json`
  exits 0._
- **EV-3**: The top-level object has a `skill_name` key equal to
  `write-a-spec` and an `evals` array. _Check: `jq -r '.skill_name'`
  prints `write-a-spec`; `jq '.evals | type'` prints `"array"`._
- **EV-4**: The `evals` array contains 3 or 4 entries (inclusive). _Check:
  `jq '.evals | length'` returns a number in `{3, 4}`._
- **EV-5**: Each eval entry has the keys `id`, `name`, `prompt`, `files`.
  _Check: `jq '[.evals[] | keys] | add | unique'` is a superset of
  `["id", "name", "prompt", "files"]`._
- **EV-6**: The set of `name` values covers all four scenarios named in
  the acceptance criteria: a typical issue, a thin issue (assumptions /
  open questions), a multi-lane feature, and a single-lane feature. The
  three-eval variant must still represent all four scenarios — e.g. by
  combining "thin" and "multi-lane" into one fixture; the four-eval
  variant uses one fixture per scenario. _Check: read the `name` and
  `prompt` of each eval; confirm each of the four scenarios maps to at
  least one eval (substring match on `typical`, `thin` /
  `assumption(s)`, `multi-lane` / `multi`, `single-lane` / `single` is
  sufficient — exact wording isn't required as long as the intent is
  unambiguous from name + prompt)._

## Constraints

- **C-1**: The skill MUST NOT include `disable-model-invocation: true`
  (it is invoked by `/feature` and by direct user request). _Check:
  `grep 'disable-model-invocation' SKILL.md` returns zero lines._
- **C-2**: The skill MUST NOT declare write-capable tools (`Edit`,
  `Write`, `MultiEdit`, `Bash`) in its allowlist. _Check: covered by
  FM-5; restated here as a hard constraint._
- **C-3**: The skill MUST NOT contain instructions to call the Anthropic
  Managed Agents API or the Files API (out of scope per PRD). _Check:
  `grep -Ei 'managed.agents|files api|user\.define_outcome' SKILL.md`
  returns zero lines._
- **C-4**: The skill MUST NOT instruct the writer to modify the source
  issue file or `issues/prd.md`. _Check: `SKILL.md` does not contain a
  sentence instructing edits to those files; the read-only tool
  allowlist (FM-5) makes this enforceable._
