# claude-skills

A marketplace of individually-installable commands and skills for [Claude Code](https://claude.ai/claude-code). Each plugin stands alone — install only what you need.

## Install

Add the marketplace once:

```
/plugin marketplace add belchman/claude-skills
```

Then install any subset:

```
/plugin install map@claude-skills
/plugin install adversarial-review@claude-skills
/plugin install crap@claude-skills
```

## Plugins

### `map` — slash command `/map`

Generates or updates an `ARCHITECTURE.md` at the root of your repository: a living map of structure, dependencies, conventions, and high-coupling zones.

- Works on any language or framework (polyglot-adaptive)
- Dispatches parallel agents for structure, dependencies, and conventions
- Incremental updates via `git diff` — only re-maps what changed
- Flags high-risk zones by fan-in analysis

```
/map                  # first run or incremental update
/map --full           # force full regeneration
/map --section deps   # update one section (structure | deps | conventions | impact)
```

---

### `adversarial-review` — slash command `/adversarial-review`

Runs three parallel reviewer agents against your project's docs, config, and tests — finding contradictions, gaps, and missing pieces, then fixing what you approve.

- **Spec reviewer** — contradictions, missing definitions, ambiguous behavior
- **Config reviewer** — broken hooks, permission gaps, env var issues
- **Coverage reviewer** — untested exports, unimplemented contracts, framework mismatches
- Uses `ARCHITECTURE.md` (from `/map`) for blast-radius analysis when available
- `--diff` mode scopes the review to changes since the last map

```
/adversarial-review                 # full review of all project files
/adversarial-review --diff          # review only what changed since last /map
/adversarial-review path/to/file    # review a specific file or glob
```

---

### `crap` — skill (auto-triggers on `/crap` or risky-code questions)

Ranks functions by CRAP score (cyclomatic complexity × lack of real test coverage) on the current branch, then proposes either a refactor or missing tests for the worst offender.

- CRAP = `cc² × (1 − eff_cov)³ + cc`, where `eff_cov = line_cov × mutation_kill_rate`
- Cache + baseline on disk so repeat runs are fast and regressions are gated
- Per-language detectors for coverage/mutation (Python, JS/TS, Go, Rust, Java/Kotlin, C/C++) — see [`plugins/crap/skills/crap/detectors.md`](plugins/crap/skills/crap/detectors.md)
- After ranking, offers a language-aware refactor or a test-case draft for the single worst function

```
/crap                   # changed-files scope, threshold from .crap.yml or 30
/crap 20                # threshold override
/crap --full            # whole tree
/crap --dry-run         # skip refactor/tests step
/crap --set-baseline    # write .crap-baseline.json and exit
```

**Dependencies.** `/crap` needs `python3` and `lizard` (`pip install lizard`). Coverage and mutation tools are language-specific and installed on demand — the skill prints the exact install command when something is missing. See [`plugins/crap/skills/crap/crap.yml.example`](plugins/crap/skills/crap/crap.yml.example) for project configuration.

#### How `/crap` scores code

```
1. Load config (.crap.yml or defaults; CLI flags win)
2. Determine scope — changed files vs. full tree
3. lizard → function registry (file, name, cc, lines, arg_signature)
4. Filter — drop functions where CRAP_max (cc² + cc) ≤ threshold
5. Cache-split — hash each survivor; skip any already measured
6. Measure — coverage + mutation on the cache-miss set only
7. Score — compute CRAP per function, weight by churn, diff vs. baseline
8. Report — markdown table + Savoia headline (% of methods above threshold)
9. Worst offender — propose a refactor OR anti-mutation tests; prompt to apply
```

Full details in [`plugins/crap/skills/crap/SKILL.md`](plugins/crap/skills/crap/SKILL.md). Language→tool matrix in [`detectors.md`](plugins/crap/skills/crap/detectors.md). Refactor patterns in [`refactor-playbook.md`](plugins/crap/skills/crap/refactor-playbook.md).

#### Theory

The CRAP metric is Alberto Savoia's 2007 proposal ([original post](https://www.artima.com/weblogs/viewpost.jsp?thread=215899)). Threshold of 30 and the "≤ 5% of methods above threshold or the project is crappy" rule both come straight from his paper.

**Deviation from Savoia.** He specified *basis path coverage*. This skill substitutes `line_cov × mutation_kill_rate` for `eff_cov` — which directly addresses the weakness Savoia himself flagged: *"[CRAP] cannot detect great code coverage and lousy tests."* Mutation kill rate exposes exactly that case (lousy tests fail to kill mutants, so `eff_cov` drops even when line coverage looks fine). The tests-first-before-refactor guardrail on the worst offender is Savoia's own advice made explicit in the skill's workflow.

#### Dogfood

This repo runs `/crap` against itself. After the refactor arc of driving `crap.py`'s own CRAP to zero:

| Metric | Before | After |
|---|---:|---:|
| Functions above CRAP 30 | 17 / 40 (42.5%) | **0 / 47 (0.0%)** |
| Worst offender CRAP | 2162 (`cmd_score`) | 26.4 (`_read_arg_signature`) |
| Line coverage | 0% | **89%** |
| Mutation kill rate | — | **76%** (1432 / 1889) |
| Savoia verdict | CRAPPY | **clean** |

To reproduce locally from the repo root:

```bash
pip install lizard coverage mutmut pytest

# 1. Tests + coverage
coverage run --source=plugins/crap/skills/crap -m pytest tests/ -q
coverage json -o /tmp/coverage.raw.json

# 2. Mutations (writes mutants/ — gitignored)
mutmut run

# 3. Pipeline
python3 plugins/crap/skills/crap/crap.py lizard plugins/crap/skills/crap/crap.py -o /tmp/fns.json
python3 plugins/crap/skills/crap/crap.py filter --functions /tmp/fns.json --threshold 30 > /tmp/surv.json
python3 plugins/crap/skills/crap/crap.py normalize-coverage --tool coveragepy /tmp/coverage.raw.json -o /tmp/coverage.json
python3 plugins/crap/skills/crap/crap.py score \
    --functions /tmp/fns.json --survivors /tmp/surv.json \
    --coverage /tmp/coverage.json --mutation /tmp/mutation.json \
    --no-churn --no-baseline --threshold 30
```

(The mutmut-3 → normalized JSON conversion is a small Python snippet that maps mutmut's function-keyed output to the per-line shape `crap.py score` expects. Mutmut 2.x's `mutmut results --json` output works out of the box via `normalize-mutation --tool mutmut`.)

---

---

### `claude-statusline` — bash script (not a plugin)

A two-line Claude Code statusline showing model, location, context %, **per-turn input/output tokens**, session totals, cache visibility, and cost. Color-coded context bar (green → yellow → red).

```
[Opus] claude-skills@master | effort:medium
████░░░░░░ 47% | turn ↓8.5K ↑1.2K (cache r:2.0K w:5.0K) | sess ↓45.0K ↑12.0K | $0.1234
```

Install:

```bash
curl -fsSL https://raw.githubusercontent.com/belchman/claude-skills/master/statusline/claude-statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{ "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 1 } }
```

Schema verified against the [official docs](https://code.claude.com/docs/en/statusline). All field names null-safe. See [`statusline/README.md`](statusline/README.md) for the rationale per field, customization, and the dry-run test command.

---

## Recommended workflow

1. `/map` on a new project → generates `ARCHITECTURE.md`
2. `/adversarial-review` → finds gaps in docs and config
3. `/crap` → finds risky, under-tested code to address next
4. After changes, `/map --section deps` or `/adversarial-review --diff` to stay current
5. Drop in `claude-statusline` so context %, per-turn tokens, and cost are always visible

## License

MIT — [belchman](https://github.com/belchman)
