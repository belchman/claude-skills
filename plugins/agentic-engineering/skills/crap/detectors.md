# Detectors — coverage & mutation tooling by language

Load this only when step 6 of `SKILL.md` needs to pick coverage/mutation tools.

Each section lists: **marker files** (how to detect the language/project), the default **(coverage_tool, mutation_tool)** name to pass to `crap.py normalize-*`, the exact **commands** to produce the input expected by the adapter, and **install hints** printed if a tool is missing.

---

## Python

**Markers**: `pyproject.toml`, `requirements*.txt`, `setup.py`, `setup.cfg`, `Pipfile`, `manage.py`.

**Defaults**: `coveragepy` + `mutmut`.

**Coverage**
```bash
# If the project has pytest:
coverage run --source=. -m pytest -q
# Or the existing test command:
coverage run --source=. <test-command>
coverage json -o /tmp/coverage.raw.json
python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage \
    --tool coveragepy /tmp/coverage.raw.json -o /tmp/coverage.json
```
**Install hint**: `pip install coverage`

**Mutation**
```bash
# Scope to files in to_measure.json (one path per --paths-to-mutate occurrence).
mutmut run --paths-to-mutate "<file1>,<file2>" --runner "pytest -x -q"
mutmut results --json > /tmp/mutation.raw.json
python ${CLAUDE_SKILL_DIR}/crap.py normalize-mutation \
    --tool mutmut /tmp/mutation.raw.json -o /tmp/mutation.json
```
**Install hint**: `pip install mutmut`

**Notes**
- If `manage.py` present and no test command configured, ask the user for one — Django projects typically use `python manage.py test --settings=test_settings` and won't work with bare pytest.
- `mutmut results --json` was added in mutmut 2.4; older versions need `--json-output`.

---

## JavaScript / TypeScript

**Markers**: `package.json` (check `devDependencies` for `jest`, `vitest`, `mocha`, `@stryker-mutator`).

**Defaults**: `jest` or `vitest` (istanbul format) + `stryker`.

**Coverage — Jest**
```bash
npx jest --coverage --coverageReporters=json --coverageDirectory=/tmp/cov-jest
python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage \
    --tool jest /tmp/cov-jest/coverage-final.json -o /tmp/coverage.json
```

**Coverage — Vitest**
```bash
npx vitest run --coverage --coverage.reporter=json
python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage \
    --tool vitest coverage/coverage-final.json -o /tmp/coverage.json
```
**Install hint**: `npm i -D jest` (or `vitest` + `@vitest/coverage-v8`)

**Mutation**
```bash
# stryker.conf.mjs must exist; scope via `mutate`:
npx stryker run --mutate "<file1>,<file2>" --reporters json
python ${CLAUDE_SKILL_DIR}/crap.py normalize-mutation \
    --tool stryker reports/mutation/mutation.json -o /tmp/mutation.json
```
**Install hint**: `npm i -D @stryker-mutator/core @stryker-mutator/jest-runner` (swap `jest-runner` for `vitest-runner` or `mocha-runner` as appropriate).

**Notes**
- For TypeScript, ensure the test runner's transform is configured (`ts-jest`, `@swc/jest`, or `vitest` native). Stryker picks this up automatically when the project compiles under the configured runner.
- `mutate` accepts globs; `crap.py cache-split` emits plain paths that can be comma-joined directly.

---

## Go

**Markers**: `go.mod`, `go.sum`.

**Defaults**: `gocover` + `go-mutesting` (or `gremlins`).

**Coverage**
```bash
go test -coverprofile=/tmp/coverage.out ./...
python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage \
    --tool gocover /tmp/coverage.out -o /tmp/coverage.json
```

**Mutation** — current sweet spot is `gremlins`, which emits structured output; but `go-mutesting` is more widely installed. `crap.py` does not yet ship a `gremlins` adapter. Fall back to writing a hand-rolled JSON in the normalized shape, or parse `go-mutesting` text yourself.

**Install hint**: `go install github.com/go-maintainability/gremlins/cmd/gremlins@latest`

---

## Rust

**Markers**: `Cargo.toml`.

**Defaults**: `tarpaulin` (cobertura XML) + `cargo-mutants` (outcomes.json).

**Coverage**
```bash
cargo tarpaulin --out Xml --output-dir /tmp/tarpaulin
python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage \
    --tool tarpaulin /tmp/tarpaulin/cobertura.xml -o /tmp/coverage.json
```
**Install hint**: `cargo install cargo-tarpaulin`

**Mutation**
```bash
cargo mutants --json > /tmp/mutants.json --in-diff origin/main   # or --file <f>
python ${CLAUDE_SKILL_DIR}/crap.py normalize-mutation \
    --tool cargo-mutants /tmp/mutants.json -o /tmp/mutation.json
```
**Install hint**: `cargo install cargo-mutants`

---

## Java / Kotlin

**Markers**: `pom.xml`, `build.gradle`, `build.gradle.kts`.

**Defaults**: `cobertura` or `jacoco` (emit cobertura) + `pitest`.

**Coverage**
```bash
# Jacoco → cobertura XML via jacoco-report plugin, or use the `cobertura` plugin directly.
mvn verify                                # run your suite
# Then point at target/site/cobertura/coverage.xml or equivalent jacoco output
python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage \
    --tool cobertura target/site/cobertura/coverage.xml -o /tmp/coverage.json
```

**Mutation**
```bash
mvn -DtargetClasses="com.example.*" -DoutputFormats=XML org.pitest:pitest-maven:mutationCoverage
python ${CLAUDE_SKILL_DIR}/crap.py normalize-mutation \
    --tool pitest target/pit-reports/*/mutations.xml -o /tmp/mutation.json
```
**Install hint (pitest)**: add `org.pitest:pitest-maven` to `pom.xml` (or the Gradle plugin).

---

## C / C++

**Markers**: `CMakeLists.txt`, `Makefile`, `meson.build`.

**Defaults**: `lcov` + (no first-class mutation adapter; `mull` emits SARIF — route via `normalized`).

**Coverage**
```bash
# Build with coverage flags, run tests, capture lcov
cmake -DCMAKE_C_FLAGS="--coverage" -DCMAKE_CXX_FLAGS="--coverage" -S . -B build
cmake --build build && ctest --test-dir build
lcov --capture --directory build --output-file /tmp/coverage.info
python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage \
    --tool lcov /tmp/coverage.info -o /tmp/coverage.json
```
**Install hint**: install `lcov` from your package manager.

**Mutation**: `mull-runner`, `dextool-mutate`, or hand-rolled via `clang`'s AST. No `crap.py` adapter — skip mutation for C/C++ and fall back to line-only coverage. `eff_cov` will equal `line_cov`, which still gates poorly-tested complex code.

---

## Generic fallback

If the language isn't recognized or no adapter exists:

1. Ask the user to produce a **normalized** JSON in the shapes below, then run:
   ```bash
   python ${CLAUDE_SKILL_DIR}/crap.py normalize-coverage --tool normalized <path> -o /tmp/coverage.json
   python ${CLAUDE_SKILL_DIR}/crap.py normalize-mutation --tool normalized <path> -o /tmp/mutation.json
   ```
2. Or skip mutation entirely — `eff_cov` collapses to `line_cov`, which still ranks functions usefully.

### Normalized coverage shape
```json
{
  "src/foo.py": {
    "10": 3,
    "11": 0,
    "12": 1
  }
}
```
Keys: repo-relative file path, then line number (string), then hit count.

### Normalized mutation shape
```json
{
  "src/foo.py": {
    "15": {"killed": 2, "survived": 1, "survived_mutants": ["ROR>="]},
    "18": {"killed": 1, "survived": 0, "survived_mutants": []}
  }
}
```

---

## Detection priority

When multiple languages are present, detect per file (lizard already knows the language per function). Run each toolchain against the files that match it. `crap.py score` merges all results through the same normalized JSON files — multiple coverage reports can be merged by concatenating their normalized JSON before passing to `score`.
