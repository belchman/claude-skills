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
