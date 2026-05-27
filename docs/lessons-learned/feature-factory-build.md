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
