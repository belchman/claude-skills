---
name: crap
description: Rank functions by CRAP score (complexity × lack of real test coverage) on the current branch, then propose either a refactor or missing tests for the worst offender. Use when the user runs /crap or asks to find risky, complex, poorly-tested code.
allowed-tools: Glob Grep Read Bash Write Edit AskUserQuestion
---

# /crap — CRAP-score reduction workflow

## What CRAP means

**CRAP = Change Risk Anti-Patterns** (Alberto Savoia, 2007).

```
CRAP(fn) = cc(fn)² × (1 − eff_cov(fn)/100)³ + cc(fn)
eff_cov  = line_cov × mutation_kill_rate
```

`cc` is cyclomatic complexity. `eff_cov` is line coverage multiplied by mutation-kill rate so that code "executed by tests but not actually verified" doesn't count as covered. A function gets its CRAP down by (a) being simpler or (b) being thoroughly tested.

**Deviation from Savoia's original.** Savoia specified *basis path coverage*. This skill substitutes `line_cov × mutation_kill_rate`, which directly addresses the weakness Savoia himself flagged: *"[CRAP] cannot detect great code coverage and lousy tests."* Mutation kill rate exposes that case — lousy tests fail to kill mutants, so `eff_cov` drops even when line coverage looks fine. The 30 threshold and the 5%-of-methods project rule are unchanged from Savoia's Artima post.

Load-on-demand references (read only when needed):
- `detectors.md` — language → coverage/mutation tool matrix
- `refactor-playbook.md` — per-language refactor patterns

## Invocation

```
/crap                  # changed-files scope, threshold from .crap.yml or 30
/crap 20               # threshold override
/crap --full           # whole tree
/crap --dry-run        # skip refactor/tests step
/crap --set-baseline   # run in full mode, write .crap-baseline.json, exit
```

## Workflow

Follow these steps exactly. The skill directory is `${CLAUDE_SKILL_DIR}`; `crap.py` lives there. Claude Code expands `${CLAUDE_SKILL_DIR}` at skill-load time so the commands below work whether the skill is installed globally or bundled in a plugin.

### 1. Load config

Read `.crap.yml` from the repo root if present; fall back to defaults below. CLI flags win.

```yaml
threshold: 30
top_n: 20
scope: changed          # changed | full
base: origin/main
churn_weight: true
churn_window_days: 90
baseline: .crap-baseline.json
cache: .crap-cache
exclude:
  - "**/migrations/**"
  - "**/tests/**"
  - "**/vendor/**"
  - "**/node_modules/**"
mutation_timeout: 1800
parallelism: auto
test_command: null
coverage_tool: auto
mutation_tool: auto
```

### 2. Determine scope

- `scope=changed`: `git diff --name-only --merge-base <base> HEAD` plus `git diff --name-only` (unstaged) plus `git diff --name-only --cached` (staged). Union, de-dup.
- `scope=full`: enumerate source files under the repo root.
- Apply `exclude` globs in both cases.

If the file list is empty, report "no in-scope source files" and exit 0.

### 3. Build the function registry with lizard

One command does lizard + CSV parsing + JSON emit:
```bash
python3 ${CLAUDE_SKILL_DIR}/crap.py lizard <scoped_files> -o functions.json
```

If lizard isn't installed, this prints `pip install lizard` and exits 3 — do that and stop. The subcommand invokes `python -m lizard` so it works whether or not the `lizard` console script is on PATH.

Each entry in `functions.json`:
```json
{"file": "path/to/x.py", "name": "fn_name", "start_line": 10, "end_line": 42,
 "cc": 7, "arg_signature": "a,b,c"}
```

If you already have a `lizard --csv` dump on disk, use `parse-lizard <path>` instead.

### 4. Pass-1 CRAP_max filter

```bash
python ${CLAUDE_SKILL_DIR}/crap.py filter \
  --functions functions.json \
  --threshold <T> > survivors.json
```

This computes `CRAP_max = cc² + cc` per fn and drops any `≤ threshold`. If `survivors.json` is empty, skip to step 8 and report "no risky functions in scope."

### 5. Cache lookup

```bash
python ${CLAUDE_SKILL_DIR}/crap.py cache-split \
  --survivors survivors.json \
  --cache .crap-cache \
  --to-measure to_measure.json \
  --cached-results cached.json
```

Hash each survivor by `sha256(function_source_bytes)` to decide hit/miss. Ensure `.crap-cache/` is in `.gitignore` (add it if not).

### 6. Run coverage and mutation on the cache-miss set

Detect language(s) of the files in `to_measure.json` and consult `detectors.md` for the exact commands. General shape:

- **Coverage** must produce `{file: {line: hit_count}}` JSON (tool adapters live in `crap.py`).
- **Mutation** must produce per-line `{killed, survived, survived_mutants}` JSON.

Scope both to the cache-miss file list. Respect `mutation_timeout`. If a required tool isn't installed, print the exact install command from `detectors.md` and stop.

Save outputs to `/tmp/coverage.json` and `/tmp/mutation.json` (normalized via `crap.py` adapters — see `crap.py measure --help`).

### 7. Compute CRAP and produce the report

```bash
python ${CLAUDE_SKILL_DIR}/crap.py score \
    --functions functions.json \
    --survivors survivors.json \
    --coverage /tmp/coverage.json \
    --mutation /tmp/mutation.json \
    --cached cached.json \
    --cache .crap-cache \
    --churn-window 90 \
    --baseline .crap-baseline.json \
    --threshold <T> --top <N>
```

Omit `--churn-window` and pass `--no-churn` if `churn_weight: false`. Omit `--baseline` if disabled.

`crap.py` emits a markdown table to stdout with columns: `file:line | function | cc | cov% | mut% | eff_cov% | churn | CRAP | Δ`. Rows are tagged `new`, `regressed`, `same`, `improved` relative to the baseline.

**Exit codes** (propagate to the shell):
- `0` clean
- `1` threshold hits but no regressions
- `2` regressions (new/worse vs baseline)

### 8. Brief the user

Echo the table. Add two short summary lines from `crap.py score`'s stderr:
- N functions above threshold, K regressions, M new above threshold, worst offender.
- Savoia's project rule: X% of methods above CRAP threshold — project is **CRAPPY** (>5%) or **clean** (≤5%).

If `--set-baseline` was passed, `crap.py` will have written `.crap-baseline.json`; stop here.

If `--dry-run` or exit 0, stop here.

### 9. Refactor-or-tests for the worst offender

`crap.py score` annotates the top row with `"dominant_axis": "cc"` or `"tests"` using:

```
cc_axis    = cc² × (1 − line_cov)³
test_axis  = cc² × (1 − eff_cov)³ − cc² × (1 − line_cov)³
```

If `cc_axis > test_axis` → refactor. Else → tests.

- **Refactor path**: Read the function. Load the matching section of `refactor-playbook.md` for the file's language. Draft a unified diff plus a one-sentence rationale.

  **Tests-first guardrail (Savoia's own advice).** If the scored row shows `eff_cov < 80%`, do not propose the refactor on its own. First draft *characterization tests* that pin down the function's current behavior — one test per distinct branch, plus the mutants in `survived_mutants` as targeted cases. The characterization suite is the safety net the refactor leans on. Present both the characterization tests and the refactor diff together, make clear which runs first, and recommend applying the tests alone first if the user is unsure.

  If `eff_cov >= 80%`, propose the refactor directly — the existing tests are a sufficient safety net.

- **Tests path**: Read the function and the `survived_mutants` list from `/tmp/mutation.json`. Draft new test cases that would kill each surviving mutant (hypothesis/fast-check/proptest when available, else plain cases).

Then use `AskUserQuestion`:
- Question: "Apply the proposed change to <file>:<fn>?"
- Options (refactor path, `eff_cov < 80%`): `apply characterization tests first` / `apply tests + refactor together` / `refine` / `skip`
- Options (refactor path, `eff_cov >= 80%`): `apply refactor` / `refine` / `skip`
- Options (tests path): `apply tests` / `refine` / `skip`

On `apply`, write the change with Edit/Write and remind the user to re-run their test suite. On the `apply characterization tests first` branch, stop after writing the tests and instruct the user to re-run `/crap` once they've re-run their suite — the refactor diff will be re-proposed on top of the now-safer baseline.

## Notes

- Never call mutation tools on files that weren't in the cache-miss set.
- Never delete `.crap-cache/` — it's the speed lever.
- If `--set-baseline`, force `scope=full` regardless of CLI/config.
- `crap.py` is stdlib-only; do not add dependencies to it.
