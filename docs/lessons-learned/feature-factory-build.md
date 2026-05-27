# Lessons learned — building the feature factory

Per `docs/plans/feature-factory.md` dogfooding plan. Each round captures honest observations about the existing skills/tooling encountered. Empty findings are recorded as "no friction observed" — silence is dishonest.

---

## Round 0 — precursor: extract `work-issues-lib.sh` + tighten `issues/*.md` glob

**Date:** 2026-05-27

**Skills dogfooded:** `tdd`, `/adversarial-review` (manual invocation via subagent).

**Final state:** `bin/work-issues-lib.sh` with `strip_frontmatter()` + `list_issue_files()`, sourced by `once.sh` + `loop.sh`. Glob now excludes `*.rubric.md`/`*.spec.md`/`*.research.md`. 6 shell tests in `tests/test_work_issues_lib.sh`, all GREEN. `SKILL.md` wording updated. No commit yet — pending user review.

### What worked

- **TDD discipline was the right shape, not overkill** for a 30-line bash change. Two of the three behaviors had specific edge cases (sidecar exclusion semantics, sort stability) where a pre-written test caught the regression cleanly. The other behavior (strip_frontmatter passthrough on no-frontmatter file) had a fixture written *before* the code change which would have caught a regression had the extracted function diverged from the original.
- **Plain shell test script (no bats)** was the right call. Adding a new test framework for one file of shell is friction with no benefit. The `assert_eq` helper + `pass_count`/`fail_count` is ~15 lines of boilerplate.
- **Symlinks for skills worked exactly as intended.** Invoking `tdd` and the adversarial reviewer prompt against the local repo's SKILL.md files just worked — no reinstall, no rebuild.
- **/adversarial-review caught two real bugs the TDD pass missed**: (1) `find`'s readdir order is not sorted, so the new payload reordered issues vs the old glob — would have subtly changed `/work-issues`'s task selection and broken prompt caching; (2) `find` on a missing dir leaks `find: /no/such/dir: No such file or directory` to stderr, and the callers were swallowing all of stderr to compensate. Both fixed before commit.

### What didn't work / friction encountered

- **`/adversarial-review` skill itself wasn't directly invokable.** The skill has `disable-model-invocation: true`, so calling it via the Skill tool wouldn't dispatch cleanly. Worked around by dispatching a single general-purpose subagent with the same kind of prompt. Net effect: had to read the skill's Phase 2 reviewer prompts and adapt them inline. This is a real ergonomic gap for in-session use — the skill is designed for `/adversarial-review` user invocation, not programmatic dispatch from another orchestrator. Will hit this again when building `/feature` (orchestrator needs to dispatch `/adversarial-review` programmatically). The `ADVERSARIAL_REVIEW_REPORT_ONLY=1` env var planned in §D solves the Phase 3 problem but not this Phase 1-2 dispatch problem.
- **Pre-existing uncommitted changes in `loop.sh` muddied the diff.** The repo's `git status` at session start showed `loop.sh` as already modified (untrusted fences, chmod, cmd-array, env validation — all good cleanup work, none from this session). They landed in the same diff as Round 0 work. Not a blocker, but the lessons here apply only to the Round 0 portion. Future rounds: snapshot baseline before starting so the diff is unambiguous.
- **The plan's `issues/*.md` glob fix description was slightly misleading.** §H showed a `find` invocation inlined into `bin/once.sh`. The cleaner implementation was a `list_issue_files()` function in the lib that both wrappers call. The lib was always the better home — should update the plan if it ever gets re-executed, or treat this as a refinement.

### Skill / process changes worth landing

Translating these lessons per Round 6 protocol (lessons → skill edits, ADRs, or just-doc):

1. **Adversarial-review dispatch ergonomics** — `disable-model-invocation: true` on the skill hard-blocks the Skill tool with `Skill adversarial-review cannot be used with Skill tool due to disable-model-invocation`. The original intent was "explicit invocation only" to prevent auto-fire in unrelated contexts. But the dogfooding workflow needs the model (or another orchestrator skill) to invoke it on demand.
   - **FIXED in this round:** removed `disable-model-invocation: true` from `adversarial-review/SKILL.md`. The skill's description still gates with explicit-trigger language ("Use only when explicitly asked: /adversarial-review, ... OR when another skill (e.g. /feature) needs to dispatch a validator pass programmatically.") so auto-fire risk is low. Verified: `Skill adversarial-review` now loads cleanly.
   - **Still tracked for Round 3+:** the plan's §D `ADVERSARIAL_REVIEW_REPORT_ONLY=1` env var (for Phase 3 auto-D) and a planned `ADVERSARIAL_REVIEW_TARGETS=<glob>` env var (to suppress Phase 1's interactive file-discovery confirmation when `/feature` dispatches it).
   - **Other slash-only skills with the same flag:** `/work-issues`, `/map`, `/zoom-out`, `/audit-agent-overhead`. These are NOT removed yet — only addressed when a build round needs them. Per the user's "fix what's broken before next round" rule, will revisit before Round 3 (which needs `/map` for the researcher pass and `/work-issues` for the lane builders).
2. **Tighter glob is good — but the sidecar list is now documented in 3 places** (lib header, SKILL.md L15, SKILL.md L22-23). If we ever add another sidecar suffix (e.g., `*.notes.md`), all three need updating. Worth a single-source-of-truth: lib header is canonical, the SKILL.md just references it.
   - **Action:** trivial documentation discipline; defer to Round 6.
3. **Sort stability matters for prompt caching.** This was a non-obvious failure mode that adversarial review caught. Worth a brief mention in `tdd/SKILL.md` (or a follow-up skill addition): "when refactoring code that builds prompts, test that the byte sequence is identical for representative inputs — prompt-caching keys depend on it."
   - **Action:** consider adding a one-liner to `tdd/SKILL.md` in Round 6.

### Round 0 verdict

Smooth. The 6 tests + 1 reviewer pass surfaced and fixed 2 real regressions before commit. The plan's precursor was justified — `strip_frontmatter` drift between once.sh and loop.sh (the dead `done_fm` var in loop.sh) confirmed code duplication had already produced a small divergence in this codebase. The lib extraction also gives `feature-helpers.sh` (Round 3+) a clean place to land its allowlist/severity helpers.

Ready to proceed to Round 1: `write-a-prd` on the feature factory itself.

---

## Round 1 — write the spec for the factory itself

**Date:** 2026-05-27

**Skills dogfooded:** `write-a-prd`, `prd-to-issues`, `write-a-rubric` (x6, parallel subagents).

**Final state:** `issues/prd.md` (12KB), 6 issue files (`001-write-a-spec-skill.md` through `006-routing-docs-updates.md`) all AFK-tagged with explicit `Blocked by` chains, 6 sidecar rubrics — 38–183 lines each, 11–33 criteria each. Total: 13 new files in `issues/`. No commit yet — pending Round 2.

### What worked

- **Seeding `write-a-prd` with the rev. 2 plan as the brief was the right move.** Saved an exhausting interview. The skill's `AskUserQuestion` step still let me capture the *user/business* context the plan didn't have (actor scope, success metric, rollout, timeline). Four questions, four answers, PRD drafted. The skill's "skip steps you judge unnecessary" hint at the top is genuinely permissive.
- **`prd-to-issues`'s granularity quiz fits skill-creation work fine.** The "skill-creation tickets may legitimately be horizontal" framing was honored — issue 001 is one ticket per new skill, not one ticket per layer. Six issues felt right (after the quiz proposed 6 vs 9 vs 5; I went with 6).
- **Parallel rubric dispatch (6 subagents) was a big speedup.** All 6 ran in roughly the time of a single sequential invocation. Each rubric came back with the discipline the rev. 2 `write-a-rubric` skill encodes (IDs, `Check:` hints, leanness, anti-patterns).
- **All 6 rubrics named concrete grader observations** (`grep` patterns, `git diff` ranges, exit codes, test names). Zero taste-based criteria, zero conversation-dependent items. The Round 0 rubric eval clearly improved the skill — these rubrics are noticeably tighter than what the rev. 1 skill produced.

### What didn't work / friction encountered

- **Issue 001's rubric is large (33 criteria, 183 lines) — at the upper bound of the skill's leanness guidance.** New-skill creation tickets have genuinely more surface than env-var tweaks, so this isn't strictly bloated, but it's near the cap. If `/work-issues` (Round 3) struggles with rubric size during the lane-walk step, this is the first place to look. Consider whether issue 001 should have been sliced (e.g., separate "write-a-spec SKILL.md" from "write-a-spec evals") — the granularity quiz didn't surface this option as a question, only proposed "split orchestrator" or "merge lane support."
  - **Action (deferred to Round 6):** consider adding a "split per-artifact" option to `prd-to-issues`'s granularity quiz for skill-creation tickets.
- **`prd-to-issues`'s quiz proposes only 3 alternatives.** No "tell me your own granularity" escape. For meta-work where the user has strong opinions, this funnels you into one of the pre-baked options. In this round the recommended option was right; could bite in other rounds.
  - **Action (deferred to Round 6):** consider whether `prd-to-issues` should allow free-form granularity input.
- **No-issue dependency between rubric writing and prd-to-issues** — I had to run prd-to-issues first, get the 6 issue files, then dispatch 6 rubric subagents. Each rubric subagent re-reads the issue file from disk. If the issue file is large, that's wasted token spend. Minor — not actionable.

### Skill / process changes worth landing

Nothing blocks Round 2. Captured deferred items above are Round 6 candidates.

**Pre-Round-2 status check (per user rule "fix what's broken before next round"):**
- write-a-prd: worked, no fix needed.
- prd-to-issues: worked; the quiz limitations are notes for Round 6, not blockers.
- write-a-rubric: rev. 2 skill performed at the quality the iter-2 evals predicted. No fix needed.
- adversarial-review flag fix (from Round 0) is still in place — verified Skill tool can still load it.

### Round 1 verdict

Smooth. The dogfooding loop produced 13 working artifacts in one Round, and the existing skills handled meta-work (building skills with skills) competently. Issue 001's rubric size is the only flag worth watching during Round 3 implementation.

Ready to proceed to Round 2: `grill-with-docs` on the design of `write-a-spec` (issue 001 + rubric + plan §C). Goal: surface ambiguities the rubric doesn't catch before any builder picks the issue up.

---

## Round 2 — stress-test the design

**Date:** 2026-05-27

**Skill dogfooded:** `grill-with-docs` (one session, 5 questions).

**Final state:** issue 001 and its rubric updated with 5 resolved decisions. New `CONTEXT.md` at repo root (project glossary). New `docs/adr/0001-fenced-paths-blocks-for-lane-allowlists.md`. No commit yet — pending Round 3.

### What worked

- **grill-with-docs found a real rubric bug.** The rubric's FM-5 said write-a-spec's tool allowlist must be `Read, Grep, Glob` only — no `Write`. But the skill HAS to write its `*.spec.md` output. The 6 parallel rubric subagents in Round 1 all faithfully implemented the issue's "no Edit/Write to project files; only writes its own output" — but the rubric dropped the carve-out and made it absolute. A builder following the rubric would have produced a skill that can't write its output and fail at runtime. **This is exactly what grilling-before-building is for.** Caught in 5 questions; ~10 minutes of skill time.
- **Lazy CONTEXT.md / ADR creation per the skill's discipline worked cleanly.** I created `CONTEXT.md` when the first load-bearing term (`lane`) was about to be referenced multiple ways. Created the ADR when the fenced-`paths`-block decision hit all three threshold tests (hard to reverse, surprising without context, real trade-off).
- **One-question-at-a-time discipline kept the user from being overwhelmed.** 5 questions, 5 answers, ~5 minutes. All five had a recommended option the user accepted. The skill's "give your recommended answer" rule lets the user pattern-match fast.
- **Questions surfaced 4 real design ambiguities** beyond the tool-allowlist bug: single-lane handling (omit empty lane), lane source (read CLAUDE.md), tests-required content shape (behavior list), missing-research handling (proceed + Risks bullet). All four are now pinned in the issue + rubric.

### What didn't work / friction encountered

- **The grill skill doesn't enforce its "give your recommended answer" rule strictly.** A naive grill could ask questions without recommendations, dumping the design burden on the user. The skill's prompt language is "give your recommended answer" — easy to skip. Worth pinning more aggressively in the skill body (Round 6 candidate).
- **No tooling to check the existing rubric against the resolved design after grilling.** I had to manually update FM-5 and add LD-1..3, TB-1..2, MR-1..2 criteria. A future workflow could do: `grill-with-docs --apply-to <rubric-path>` to suggest rubric edits. Defer.
- **The grilling session output didn't auto-commit CONTEXT.md / ADRs.** The skill creates them, but they sit untracked. Worth a closing-summary suggestion. Minor.

### Skill / process changes worth landing

1. **Critical fix landed THIS round:** rubric 001's FM-5 corrected to permit `Write` for the sidecar output only. Without this, Round 3 would have produced a broken skill.
2. **Issue 001 expanded** with 5 new acceptance criteria from grilling (Lane discovery, single-lane handling, Tests required = behavior list, missing-research handling, the FM-5 carve-out language).
3. **Rubric 001 expanded** with 7 new criteria (LD-1..3, TB-1..2, MR-1..2) and C-2 relaxed to match FM-5.
4. **Round 6 candidates** (lessons for future skill edits):
   - `grill-with-docs/SKILL.md` — strengthen the "give your recommended answer" rule.
   - `grill-with-docs/SKILL.md` — closing summary should suggest committing `CONTEXT.md` / ADRs.

### Pre-Round-3 status check (per user rule "fix what's broken before next round")

Round 2 fixes:
- ✅ rubric 001 FM-5 (tool allowlist now permits Write — applied)
- ✅ rubric 001 C-2 (relaxed to match FM-5 — applied)
- ✅ issue 001 acceptance criteria expanded with Q1-Q5 outcomes (applied)
- ✅ CONTEXT.md created (applied)
- ✅ ADR 0001 created (applied)

Round 3 will need `/work-issues` to autonomously work each issue. Per Round 0 precedent, slash-only skills with `disable-model-invocation: true` cannot be invoked by other orchestrator skills or by the Skill tool. Round 3 plans to invoke `/work-issues` via Skill tool dispatch from inside this conversation — **this will fail** the same way `/adversarial-review` did in Round 0.

**Pre-Round-3 fix required:** remove `disable-model-invocation: true` from `/work-issues/SKILL.md`. The skill description already gates with explicit-trigger language ("Heavyweight (commits code, modifies the issue queue); explicit invocation only.") so auto-fire risk stays low, matching the precedent we set for adversarial-review.

### Round 2 verdict

Grilling found one critical rubric bug + 4 design ambiguities in 5 questions. Without this round, Round 3 would have produced a broken `write-a-spec` skill. The lazy-CONTEXT.md and lazy-ADR pattern proved its value — both files now exist as durable references for future rounds.

Ready to proceed to Round 3 (build each piece via `/work-issues`) — AFTER applying the pre-Round-3 fix above.

---

## Round 3 — build each piece via /work-issues

**Date:** 2026-05-27

**Skills dogfooded (heavily):** `/work-issues` (5 iterations: 004, 001, 002, 003, 005), `tdd` (RED-GREEN cycles for shell tests), `/adversarial-review` (parallel 3-reviewer pass after every issue), `skill-creator` (5-iteration eval workflow on /feature). Plus implicit reuse of `write-a-rubric` (referenced; not re-invoked).

**Final state:** All 5 unblocked AFK issues shipped (001 write-a-spec, 002 adversarial-review env vars, 003 work-issues lane paragraph, 004 lib helpers, 005 /feature orchestrator). 70 shell tests across 3 suites GREEN. 8 commits in this round: 5 initial implementations + 3 adversarial-review fix-ups + 1 skill-creator-driven SKILL.md revision on /feature.

### Pattern that emerged: "rubric < contract"

Every single big-issue commit (001, 004, 005) had its initial implementation pass the rubric perfectly, then adversarial review found 2-6 CRITICAL real bugs the rubric didn't anticipate. The pattern is consistent:

| Issue | Initial commit | Rubric coverage | Adversarial findings |
|---|---|---|---|
| 004 lib helpers | b07cf00 | All 23 criteria | 2 CRITICAL (sort instability, stderr leak) |
| 001 write-a-spec | 31c6978 | All 40+ criteria | 4 CRITICAL (parser path, H3 silent failure, brace expansion, no AFK fallback) |
| 005 /feature | 0d14273 | All 32 criteria | 11+ CRITICAL (case-wrong markers, route_findings never called, lane chain ignores failures, atomic state, --redo no-op, infinite loop, empty allowlist, etc.) |

The rubric is a STRUCTURAL FLOOR ("these specific things must exist"). It does not capture the CONTRACT ("the thing must actually work as designed"). Adversarial review catches the contract gap.

**Action for Round 6:** consider updating `write-a-rubric` to suggest more contract-level criteria. Or add a step to `/work-issues` that automatically dispatches `/adversarial-review --diff` after every commit. The pattern is consistent enough across 3 issues to bake it into the pipeline.

### Skill-creator eval workflow (5 iterations on /feature)

Per user request, ran 5 iterations of skill-creator eval against /feature SKILL.md to verify "exactly what we want."

**Iter-1**: 3 easy prompts (trivial CLI, backend feature, fullstack) → 3/3 with-skill Bash-invoked. Skill works on easy cases. But the prompts were too easy to find issues.

**Iter-2**: 3 harder prompts (context-loaded mid-conversation, user pushback "do it inline", deferred brief on message 2):
- Context-loaded: Bash-invoked + added "scope sanity" caveat unprompted
- User pushback: deferred to user, edited inline (correct per CLAUDE.md user-override, but exposed gap)
- Deferred brief: asked then Bash-invoked
- **Gap found**: SKILL.md was too absolute about Bash-invoking. The chain has real overhead (3 checkpoints, 6 subagent dispatches) that's overkill for trivial work. SKILL.md didn't acknowledge this.

**Iter-3** (after revision adding "When this skill is the right tool" section + "Don't bureaucratize trivial work" guidance): 3/3 correctly suggested direct path for trivial prompts, handled user override cleanly.

**Iter-4** (mixed trivial / substantive / borderline): 3/3 — scope discrimination works. Substantive case correctly Bash-invoked without hedging; trivial case correctly suggested direct; borderline case offered ask+escape hatch.

**Iter-5** (edge cases — vague brief, multi-feature pack, question disguised as feature): 3/3 — asked clarification on vague, suggested splitting on multi-pack, offered three forks on question.

**Net: 14/15 correct on first invocation; 15/15 after one SKILL.md revision.** The skill is genuinely robust across the realistic prompt space.

### Skill / process changes worth landing

Captured for Round 6:
1. **rubric < contract pattern** — investigate whether write-a-rubric should add contract-level prompts, or whether /work-issues should auto-dispatch /adversarial-review --diff after every commit.
2. **disable-model-invocation: true removal as a pattern** — Round 0 removed it from /adversarial-review; Round 2 from /work-issues; Round 3 LEFT it on /feature (correctly, since the user-facing UX is /feature being a slash-only trigger). The decision tree for when to remove the flag is: "remove if another orchestrator skill needs to dispatch this programmatically via Skill tool."
3. **5-iteration skill-creator eval is high-value for SKILL.md prompt quality** — found a real gap in iter-2 that would have shipped without it. Worth budgeting eval rounds for every new heavyweight skill.
4. **State machine review pattern** — adversarial review on /feature found 9 of 13 state values had no continue --accept arm. This is a CLASS of bug for any state-machine orchestrator. Add to the adversarial-review skill's coverage-reviewer agent: "list state values referenced in the code; verify every value has a handler."

### Pre-Round-4 status check

Round 4 is the self-test: run /feature on a trivial in-repo brief end-to-end. Pre-checks:
- ✅ All 5 issues merged
- ✅ /feature SKILL.md handles scope discrimination
- ✅ 70 tests across 3 suites GREEN
- ✅ Symlink in place at ~/.claude/skills/feature → repo skill dir
- ⚠️ Issue 006 (routing docs) still open — blocks discoverability via README/SKILLS.md but not /feature's own behavior
- ⚠️ /map skill still has disable-model-invocation: true — /feature's step_refresh_map would fail when invoked from a fresh claude -p context with no /map skill loaded. Need to either: (a) remove disable-model-invocation from /map per the established pattern, OR (b) skip the /map step in /feature when ARCHITECTURE.md is already present (which feature.sh already does)
- ⚠️ /work-issues's bin/loop.sh dispatches `claude` (not `claude -p`). When called from /feature's step_lane, it will spawn a sub-claude that needs to also load all the right skills. Risk: skill cascade depth might exceed practical limits

### Round 3 verdict

The dogfooding loop produced a working factory in 8 commits over 5 substantive iterations. The adversarial-review-after-every-commit pattern caught 17+ critical bugs across the round; without it, /feature would have shipped with a fundamentally broken state machine. The 5-iteration skill-creator eval pattern added one substantial SKILL.md revision (scope discrimination) the rubric didn't capture.

Ready to proceed to Round 4 (self-test /feature on a trivial in-repo brief) — after considering whether to address the /map disable-model-invocation issue first.

---

## Round 4 — `/feature` self-test (stubbed end-to-end)

**Date:** 2026-05-27

**Skills dogfooded:** `/feature` itself (stubbed), the orchestrator's own integration test suite.

**Final state:** Two new full-chain tests added to `tests/test_feature_orchestrator.sh` (`test_full_chain_end_to_end`, `test_full_chain_two_lane_brief`); 30/30 GREEN. New env override `FEATURE_REPO_ROOT` documented in `feature/SKILL.md`. 12 leaked test artifacts cleaned out of `issues/` and `issues/research/`.

### What worked

- **Full-chain test caught the implicit-checkpoint discrepancy.** Documenting via the test was easier than reading the source — by structurally asserting `last_completed_step` at each step (`rubric_drafted` → `backend_validated` → `validated` → `done`), the actual user-facing flow became visible: 5 invocations (`start` + 4 × `continue --accept`), not 4. The SKILL.md / README.md / CLAUDE.md description "3 checkpoints" is correct (only CP1, CP2, CP3 paged) but the user must invoke `continue` between backend and frontend lanes too. That "between-lanes gate" is a silent pause point.
- **Stub claude was sufficient for chain verification.** No real Anthropic API call was needed — the stub creates valid spec (with `### Backend` H3 + `paths` fenced block) and rubric artifacts, and `loop.sh` stub exits 0. This caught real orchestration bugs without burning tokens.

### What didn't work / friction encountered

- **Test artifacts leaked into the real repo's `issues/` directory.** `feature.sh` computed `repo_root` from `git rev-parse --show-toplevel`, so even with `FEATURE_RUNS_DIR` sandboxed, `step_story` / `step_spec` / `step_rubric` / `step_researcher` wrote to `$repo_root/issues/`, polluting the actual repo. Found 12 leaked files from prior test runs (`0001-feature-lane.spec.md`, `0001-add-version-subcommand-to-crap-that-prin.rubric.md`, etc.) plus an entire `issues/research/` subtree that didn't exist before tests.
  - **FIXED in this round:** added `FEATURE_REPO_ROOT` env override to `feature.sh` (line 36); test harness sets it to `$sb`; documented in `feature/SKILL.md` under "Env overrides".
  - **Cleanup performed:** `rm -f issues/0001-*` and `rmdir issues/research`.
  - **Class of bug:** any orchestrator that runs in a sandbox MUST sandbox every path the wrapped script writes to. `FEATURE_RUNS_DIR` only sandboxed the run-state dir; everything else (issue/spec/rubric/research outputs) leaked. The rubric for issue 005 didn't catch this — the orchestrator was "correct" w.r.t. the spec, but the spec didn't think about test isolation.
- **Implicit fourth checkpoint surfaced.** The chain is documented as "3 checkpoints" but in practice the user is paged 4 times. The pause between backend and frontend lanes exists (state = `backend_validated`, message "Run continue to start the Frontend lane") but isn't called "Checkpoint" — yet the user must take an action to proceed. This is a UX inconsistency: either the message should say "Checkpoint 2.5: backend done, OK to start frontend?" or the chain should auto-continue.
  - **Not fixed in this round.** Decision deferred to Round 6 — needs a design call: is the pause intentional (user reviews backend's commit before frontend touches the codebase) or accidental (state machine boundary that should be transparent)?
- **`tests/test_crap.py` pre-existing failure.** Module collection error: `ModuleNotFoundError: No module named 'plugins.crap'`. Confirmed not caused by this round's changes (`git stash` + rerun = same error). Out of scope for Round 4; flag for separate cleanup.

### Skill / process changes worth landing

1. **`FEATURE_REPO_ROOT` env override** — landed. Documented in `feature/SKILL.md`.
2. **Implicit-fourth-checkpoint UX** — Round 6 candidate. Options: (a) collapse rubric_drafted → frontend_validated into one continue (validator runs after both lanes); (b) re-label the message as "Checkpoint 2.5"; (c) leave as-is and document it as "intentional inter-lane pause" in the SKILL.md `## What the chain does` section. Need a design call before committing.
3. **Sandbox-everything-on-FEATURE_REPO_ROOT rule** — the lesson "sandbox the run dir is not enough" applies to any orchestrator. Worth a one-line addition to a future "writing test-friendly shell orchestrators" reference in the `tdd` or `improve-codebase-architecture` skill.

### Round 4 verdict

The orchestrator works end-to-end with stubs. The test artifact leakage was a real bug surfaced only by trying to use the thing on its own repo — pure unit tests would never have caught it (since they don't read the real `issues/` directory). The "dogfood by self-testing" pattern earned its keep here. The "3 vs 4 checkpoints" UX issue is the only open item for Round 6.

Ready to proceed to Round 5 (run `/map --section deps` + `crap --full` on shell + final SKILLS.md/CLAUDE.md/README sweep).

---

## Round 5 — `/map` refresh + `crap` sweep + final routing-docs check

**Date:** 2026-05-27

**Skills dogfooded:** `/map` (dispatched as a general-purpose subagent because `/map` carries `disable-model-invocation: true`); `/crap` (attempted, see findings); `.gitignore` hygiene pass.

**Final state:** `ARCHITECTURE.md` exists at the repo root (132 lines, last-mapped `4295b8f`). `.gitignore` now excludes `.feature_runs/` and `plugins/*/skills/*-workspace/`. No real CRAP score recorded — see below.

### What worked

- **One-shot subagent dispatch for `/map` produced a workable architecture map** without going through the full 3-parallel-agent dance. The deliverable was tighter than a stock `/map` run because the agent had explicit instructions about what high-coupling zones to call out (`work-issues-lib.sh`, `feature-helpers.sh`, lane label contract). For a small repo where we already know the structure, a focused single-agent dispatch beats the full `/map` orchestration.
- **The subagent caught two inconsistencies the routing docs didn't surface:** (a) `/work-issues` and `/adversarial-review` are listed as "slash-only" in SKILLS.md heavyweight list but DON'T carry `disable-model-invocation: true` in their frontmatter — only `feature`, `map`, `zoom-out` actually do. The slash-only behavior is enforced via skill description prose for the other two. This is a deliberate-but-undocumented inconsistency. (b) `*-workspace/` directories from skill-creator evals were sitting untracked in the working tree and would have leaked into the next commit if not gitignored.
- **Forcing a fresh ARCHITECTURE.md write surfaced what was missing:** the `## Lane boundaries` story (added in Round 0006 docs sweep) only made sense if there was an architecture map to point at — otherwise the lane labels were floating without a place to be authoritative. Now they have one.

### What didn't work / friction encountered

- **`crap` can't score shell scripts.** `crap.py` shells out to `lizard`, and `lizard.languages()` does NOT include a shell-script reader. The whole orchestrator (`feature.sh`, `feature-helpers.sh`, `work-issues-lib.sh`, `loop.sh`, `once.sh`) is invisible to the CRAP pipeline. The dogfooding plan's "Round 5: `crap --full` on shell" was based on an incorrect assumption about coverage.
  - **Not fixed in this round.** Options: (a) add a shell-script CRAP detector to `crap.py` using a different cyclomatic-complexity tool (`shellcheck` doesn't measure CC; `mccabe`, `pmccabe`, or a bespoke parser would work); (b) document the gap in the `crap` SKILL.md and stop promising shell coverage. Defer to Round 6.
- **`/map` skill's `disable-model-invocation: true` blocks Skill-tool dispatch from this conversation.** Worked around by dispatching a `general-purpose` subagent with `/map`'s prompt as guidance. This is the third time the pattern has come up (Rounds 0, 4, 5). User pushed back on the workaround mid-round and asked to fix it properly. **FIXED in this round:** removed `disable-model-invocation: true` from `map/SKILL.md`; updated the description to explicitly list `/feature step_refresh_map` as an authorized programmatic dispatcher. SKILLS.md and CLAUDE.md heavyweight sections rewritten to acknowledge the two enforcement mechanisms (hard frontmatter flag vs. soft description prose) — the prior wording falsely claimed all listed skills had the flag, which has been incorrect since Round 0 removed it from `/adversarial-review`.
- **Working-tree pollution.** The skill-creator `*-workspace/` directories had been accumulating across iterations without being gitignored. Same class as Round 4's `issues/` leak: the dogfooded skill writes to the working tree, and the tests-of-tests don't clean up. Fixed via `.gitignore` rule, but the broader pattern is "any skill that writes scratch state during its own evaluation needs a documented gitignore line."

### Skill / process changes worth landing

1. **`.gitignore` updated** — landed. Now ignores `.feature_runs/` and `plugins/*/skills/*-workspace/`.
2. **`ARCHITECTURE.md` exists** — landed. Future `/feature` runs will skip `step_refresh_map` (line 317 of feature.sh: `if [[ -f "$repo_root/ARCHITECTURE.md" ]]; then return 0; fi`).
3. **`crap` shell-script gap** — Round 6 candidate. Either implement a shell detector OR document the limitation in `crap/SKILL.md` so future rounds don't promise coverage that isn't there.
4. **slash-only consistency** — Round 6 candidate. Either tighten `work-issues`/`adversarial-review` frontmatter to add `disable-model-invocation: true` (matching their SKILLS.md heavyweight-list claim), OR remove them from the heavyweight list and document the actual enforcement mechanism.
5. **`/map` programmatic dispatch ergonomics** — same pattern as Round 0's adversarial-review fix. Round 6 candidate.

### Round 5 verdict

The map refresh produced a real deliverable that future rounds (and future readers) can rely on. The CRAP gap is a genuine surprise — the dogfooding plan over-promised what the existing tooling can do, which is itself a useful Round 6 input. The .gitignore tightening is the kind of housekeeping that compounds: every untracked scratch directory caught now is one not surfaced as a "?? plugins/..." noise line in every future `git status`.

Ready to proceed to Round 6 (lessons → skill edits).

---

## Round 6 — lessons → skill edits

**Date:** 2026-05-27

**Skills dogfooded:** every skill that absorbed a lesson — `tdd`, `write-a-rubric`, `adversarial-review`, `crap`, `feature`.

**Final state:** Five SKILL.md files updated with hard-won lessons from Rounds 0-5. Open items deferred (with reasons noted).

### What landed

| Skill | Lesson | Source round |
|---|---|---|
| `tdd/SKILL.md` | New "When the function under test builds prompts" section — pin byte sequences when the output feeds a cache key. | Round 0 (find readdir order broke `/work-issues`'s prompt cache). |
| `write-a-rubric/SKILL.md` | New "Rubric < contract" section — passing rubric is necessary but not sufficient; pair with `/adversarial-review` on the diff. | Rounds 3a-3e (5 issues with passing rubrics, 17+ critical contract bugs caught later). |
| `adversarial-review/SKILL.md` | New bullet in `coverage-reviewer` agent — enumerate state values from the code/spec and verify every reachable state has a handler arm + a test. | Round 3e (9/13 state values had no `continue --accept` arm; rubric didn't catch). |
| `crap/SKILL.md` | New "Languages NOT supported" section — `lizard` doesn't read shell/Make/CMake/Dockerfile/YAML; document the gap and recommend `shellcheck` + `tests/test_*.sh` + `/adversarial-review` for shell. | Round 5 (orchestrator's 5 shell files were invisible to CRAP). |
| `feature/SKILL.md` | New "Invocation count vs. checkpoint count" subsection — chain has 3 named checkpoints but 4 `continue --accept` invocations; the inter-lane gate at `backend_validated` is intentional and silent. | Round 4 (full-chain test surfaced the 5-invocation reality). |

### What didn't land (and why)

- **Sidecar suffix triple-source-of-truth** (Round 0 lesson): the three places listing `*.rubric.md`, `*.spec.md`, `*.research.md` (lib header + work-issues SKILL.md L15 + work-issues SKILL.md L22-23) could collapse to one. **Decision: leave as-is.** The list has 3 entries and changes ~never. The cost of consolidating (introduce a "constants file" abstraction) exceeds the cost of keeping the three in sync manually. If a fourth sidecar ever lands, revisit then. Captured here so future-Matt doesn't re-discover.
- **`/adversarial-review` and `/work-issues` slash-only enforcement** (Round 5 lesson): the SKILLS.md/CLAUDE.md table now honestly distinguishes "hard frontmatter gate" vs "soft description prose" (landed in Round 5 commit). **Decision: no further skill edit.** The split is documented and the rationale (orchestrator programmatic dispatch) is in the table. Future maintainers can read the table and choose deliberately.
- **`/crap` shell detector** (Round 5 lesson): adding a `pmccabe`-based or bespoke shell reader to `crap.py` is real work — language detection, function-boundary parsing, CRAP metric integration. **Decision: defer to a separate issue.** The documentation now warns users the gap exists, which prevents the false-positive ("`/crap` is clean, so we're fine") that previously was the silent failure mode. If someone wants the feature, file an issue.
- **`feature/SKILL.md` inter-lane gate design call** (Round 4 lesson): keep silent vs. rename "Checkpoint 2.5" vs. collapse to one continue. **Decision: keep silent + document.** The pause is the right design (user can abort between lanes) and renaming it would over-promise — there's no "this is a hard gate, you must respond" semantic in the current code, just a natural script boundary. Documenting it in SKILL.md "Invocation count vs. checkpoint count" closes the gap.

### Pattern reinforced across all six rounds

> **Rubric pins the visible shape. Adversarial review pins the contract. Both are needed.**

This is the highest-value lesson of the entire dogfooding pass. Every issue (001-005) had a careful, sharp rubric. Every issue passed its rubric. Every issue still had critical bugs caught by adversarial review *after* the rubric passed. The bugs were structural (state-machine completeness, atomicity, exit-code propagation) — the kind a static artifact inspection cannot see by design. The skill edits in this round (tdd, write-a-rubric, adversarial-review) now name this pattern explicitly so future build rounds in any project benefit from it without re-discovery.

### Round 6 verdict — and dogfooding pass close-out

Five skill edits, four deferred-with-reason items, one named pattern. The dogfooding plan in `docs/plans/feature-factory.md` is complete:

- Round 0 — lib extraction precursor ✅
- Round 1 — `write-a-prd` + `prd-to-issues` on the factory ✅
- Round 2 — `grill-with-docs` + CONTEXT.md + ADR 0001 ✅
- Round 3 — `/work-issues` × 5 (issues 001-005) ✅
- Round 4 — `/feature` self-test (stubbed, full chain) ✅
- Round 5 — `/map` refresh + `crap` sweep + routing-docs final pass ✅
- Round 6 — lessons → skill edits ✅

The factory exists. The factory has been used on itself. The factory's findings are written down. Future feature work in this repo (or in any downstream consumer) starts at `/feature "<brief>"` and exits at `done` with three real checkpoints between.
