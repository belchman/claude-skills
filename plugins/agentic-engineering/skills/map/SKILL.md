---
name: map
description: 'Generate or update ARCHITECTURE.md — a living map of a project''s structure, dependencies, and high-coupling zones. Polyglot-adaptive. Heavyweight (writes ARCHITECTURE.md, dispatches parallel agents); explicit invocation only. Triggers: /map, "generate ARCHITECTURE.md", "map this codebase".'
disable-model-invocation: true
allowed-tools: Glob Grep Read Bash Write Edit Agent
---

# /map — Generate or update ARCHITECTURE.md

You are the `/map` orchestrator. Your job is to generate or update an `ARCHITECTURE.md` file at the root of this repository.

## Step 1: Parse arguments

Split `$ARGUMENTS` on whitespace.

- `--full` -> Mode 3 (full regeneration)
- `--section <name>` -> Mode 4 (section update). Valid names: `structure`, `deps`, `conventions`, `impact`. If the name is unrecognized, print the valid options and stop.
- `--full` and `--section` both present -> `--full` takes precedence.
- Unknown flags -> ignore with a warning.
- No arguments -> continue to mode selection below.

## Step 2: Select mode

- If `--full` was passed: **Mode 3** (full regeneration).
- If `--section` was passed: **Mode 4** (section update). If `ARCHITECTURE.md` does not exist, fall back to Mode 1 and inform the user.
- If `ARCHITECTURE.md` does not exist: **Mode 1** (first run).
- If `ARCHITECTURE.md` exists with valid metadata: **Mode 2** (incremental update).
- If `ARCHITECTURE.md` exists without metadata: parse for known headings, wrap unrecognized content as `<!-- manual -->`, warn the user about what was wrapped, then run **Mode 3** (full regeneration) so manual-wrapped content is preserved via re-injection.

## Step 3: Execute

### Mode 1 / Mode 3: Full generation

1. Read project files to discover language, framework, and structure.
2. Dispatch three agents in parallel using the Agent tool (subagent_type: "general-purpose"):
   - **structure-mapper**: Produces `## Structure` markdown. Agent prompt:
     > You are a project structure analyst. Your job is to understand and document this project's layout.
     > 1. Check for manifest files (examples, not exhaustive): package.json, Cargo.toml, pyproject.toml, go.mod, mix.exs, build.sbt. Also check the project root for any other build, package, or dependency files specific to the detected language.
     > 2. First run `ls` on the project root to discover the actual directory layout. Do NOT limit yourself to common patterns — explore ALL directories that contain source code. Common examples include `src/`, `lib/`, `app/`, `pkg/`, `cmd/`, `internal/`, `Sources/`, `crates/`, `packages/`, but always adapt to what actually exists. Do not assume `src/` is the only source directory. If no language can be determined from manifests or file extensions, treat all non-binary files as potential source code. Note the uncertainty in the output.
     > 3. Glob for test files in common directories: tests/**/*, test/**/*, spec/**/*, __tests__/**/* Also check for language-specific conventions (examples, not exhaustive): *_test.go (Go), test_*.py (Python), *_spec.rb (Ruby), t/*.t (Perl), src/test/**/* (Java/Maven). In Rust, look for inline #[cfg(test)] modules. For any other language detected, check for its test file naming conventions.
     > 4. Glob for config files (examples, not exhaustive): .eslintrc.* (JS), rustfmt.toml (Rust), .rubocop.yml (Ruby), mypy.ini (Python), .golangci.yml (Go), .formatter.exs (Elixir). Also search the root for any other dotfiles and YAML/TOML/JSON files that appear to be linter, formatter, or build tool configuration for the detected language.
     > 5. Read the manifest to identify language, framework, and project purpose
     > 6. Read 2-3 representative source files to understand the code style
     > Produce a Structure section with: brief project description (1-2 sentences), annotated directory tree (only directories and key files, not every file; limit to 3 levels deep, ~30 entries max; for monorepos, show package/workspace boundaries and note the count of sub-packages), key entry points (application start, CLI, test runner).
     > Output ONLY the markdown for the Structure section. No preamble.
   - **dependency-mapper**: Produces `## Dependencies` markdown + structured JSON. Agent prompt:
     > You are a dependency analyst. Your job is to map how modules connect in this project.
     > 1. First identify the project's language(s) from manifests and file extensions. Then grep for language-appropriate import patterns (examples, not exhaustive): `import`/`from` (Python/JS/TS/Java/Go/Swift/Dart), `require`/`require_relative` (Ruby/Node), `use`/`mod` (Rust), `using` (C#), `#include` (C/C++), `open` (OCaml). For any language not listed, research its module/import system and grep for the appropriate keywords. Only search source files, not comments or documentation. If no language can be determined, search broadly for import-like statements.
     > 2. Build a list of: [source_file, imported_module] pairs
     > 3. Count fan-in for each module (how many files import it)
     > 4. Identify the top 10 most-imported modules (these are key interfaces)
     > 5. Read the manifest for external dependencies
     > 6. Grep to find where each external dep is actually used
     > Produce a Dependencies section with: Mermaid dependency graph (show only modules with fan-in >= 2, group by directory; if more than 30, show top 20 and note omitted count), external dependencies table (package, purpose, used by), key interfaces list (high fan-in modules with 1-line descriptions).
     > In addition to the markdown, output a structured JSON data block at the end: `{"edges": [{"source": "...", "target": "..."}], "fan_in": {"file": count}}`.
     > Output the markdown for the Dependencies section first, then the JSON block. No other preamble.
     Extract the last ```json block from the dependency-mapper's response as the structured data. Everything before it is the Dependencies section markdown.
   - **convention-scanner**: Produces `## Conventions` markdown. Agent prompt:
     > You are a codebase convention analyst. Your job is to identify patterns and practices in this project.
     > 1. Read 3-5 source files from different areas of the codebase
     > 2. Read any linter/formatter configs (examples, not exhaustive): .eslintrc, .prettierrc (JS), rustfmt.toml (Rust), .rubocop.yml (Ruby), .pylintrc, .flake8 (Python), .golangci.yml (Go), .clang-format (C/C++), .editorconfig. Also search root for any other linter/formatter config files specific to the detected language.
     > 3. Read the language-specific config if present (examples, not exhaustive): tsconfig.json (JS/TS), pyproject.toml (Python), Cargo.toml (Rust), go.mod (Go), Gemfile (Ruby), pom.xml/build.gradle (Java), mix.exs (Elixir), build.sbt (Scala). Check for any other language-specific project configuration files.
     > 4. Check for infrastructure/build configs: Makefile, Dockerfile*, docker-compose*, .env*
     > 5. Read CI config if present: .github/workflows/**/*, .gitlab-ci.yml, .circleci/**/*, Jenkinsfile*, .buildkite/**/*, .travis.yml, azure-pipelines.yml, bitbucket-pipelines.yml. Check for any other CI/automation configuration present.
     > 6. Check for CLAUDE.md, AGENTS.md, GEMINI.md, COPILOT.md, CURSOR.md, AIDER.md, .cursorrules, .windsurfrules, .clinerules, .github/copilot-instructions.md, CONTRIBUTING.md, or any root-level markdown or dotfile that appears to contain AI assistant instructions or contribution guidelines.
     > 7. Look for patterns: error handling, naming, file organization, testing approach
     > Produce a Conventions section with: Patterns subsection (3-7 bullet points), Configuration subsection (key config choices), Established Practices subsection (implicit rules observed across multiple files).
     > Output ONLY the markdown for the Conventions section. No preamble.
   If an agent fails, retry once. If it fails again, skip that section and warn the user.
3. After dependency-mapper completes, compute the Impact Analysis from its JSON data:
   - Sort modules by fan-in. Files with fan-in >= 3 go in High-Coupling Zones.
   - Trace 2-3 critical paths. Identify leaf nodes for Safe Zones.
4. Assemble all sections into `ARCHITECTURE.md` with the metadata block.
5. For Mode 3 only: re-inject extracted `<!-- manual -->` blocks per the re-injection rules.
6. Print a summary of what was generated.

### Mode 2: Incremental update

1. Parse `ARCHITECTURE.md` and extract the metadata block. If `last-mapped` is `0000000`, run Mode 1 instead.
2. Run `git diff <last-mapped-sha>..HEAD --name-status` and `git diff HEAD --name-status`. Also run `git ls-files --others --exclude-standard` to capture untracked files (treat as status `A`). Merge all results. If a file appears in both diffs, use the uncommitted status. Exclude `ARCHITECTURE.md`.
3. Determine affected sections using the scoping logic (see Diff-Aware Scoping Logic in spec).
4. If no sections affected, print "No structural changes since last map" and stop.
5. Launch agents for affected sections (parallel if multiple, direct if one). Impact analysis always runs after dependency-mapper.
6. Replace only affected sections. Preserve unchanged sections and `<!-- manual -->` blocks.
7. Update metadata with current HEAD SHA.
8. Print a summary of what was updated.

### Mode 4: Section update

1. Parse `ARCHITECTURE.md`.
2. For `--section impact`: check if Dependencies section has a Mermaid graph. If not, run dependency-mapper first.
3. Run the corresponding agent for the requested section.
4. Replace that section. Preserve everything else.
5. Update metadata.
6. Print a summary.

## Error handling

- Not a git repo or git unavailable: run in full mode without diff-awareness, warn the user.
- Write permission denied or read-only file: print error and stop.
- Agent failure: retry once, then skip with warning.
- Corrupt metadata: treat as no metadata, run full generation.

## Notes

- `/map` intentionally analyzes the full project regardless of `.claude/review-config.md` ignore patterns. The review-config is consumed only by `/adversarial-review`.
