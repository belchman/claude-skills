# Lane allowlists are fenced `paths` blocks inside spec markdown

**Status:** accepted (2026-05-27, plan rev. 2 §C)

The `/feature` orchestrator needs a deterministic way to extract per-lane file allowlists from the spec a human just approved. We picked **fenced markdown code blocks tagged `paths`, one literal path per line, under H3 lane headings** as the format. Alternatives considered: YAML frontmatter (e.g. `lanes: {backend: [...], frontend: [...]}`), a JSON sidecar (`issues/NNN-*.lanes.json`), or natural-language path lists the parser scans heuristically.

We picked fenced `paths` blocks because the spec is the artifact a human reviews at Checkpoint 2 — readability and reviewability of the spec dominates parser convenience. Markdown with fenced blocks looks right in a PR; a JSON sidecar would be a second file the reviewer has to cross-check; YAML frontmatter would push the allowlist above the prose context that explains it. Globs are explicitly forbidden in v1 — the literal-paths constraint keeps `bin/feature-helpers.sh::allowlist_for` parse-deterministic, and the human-reviewer can eyeball every path that's about to be edited.

## Considered options

- **YAML frontmatter** — strict, easy to parse, but separates allowlist from explanatory prose. Pushes the human reviewer to read top-to-bottom in an unusual order. Rejected.
- **JSON sidecar (`issues/NNN-*.lanes.json`)** — most parser-friendly, but introduces another sidecar to keep in sync with the spec narrative. Rejected.
- **Globs in `paths` blocks (e.g. `src/api/**/*.ts`)** — flexible, but allows the spec writer to grant edit access to files they haven't enumerated. Reviewer sees `src/api/**` and can't verify which files actually match. v1 forbids; v2 may revisit.

## Consequences

- The parser (`allowlist_for`) is a 5-line awk script (match `^### <lane>$`, then capture lines between `^```paths$` and `^```$`).
- Changing the format later is **hard**: every existing spec needs migration, and `write-a-spec`'s template (plus its evals) needs updating. Mitigate by keeping v1 strict — globs and complex syntax stay out so a future loosening is additive.
- A path may appear in only one lane (parser fails loud on duplicates). Specs that need a file in both lanes have a design problem — the file probably needs splitting.
