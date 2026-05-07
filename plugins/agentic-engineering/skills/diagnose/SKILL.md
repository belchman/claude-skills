---
name: diagnose
description: Disciplined diagnosis loop for hard bugs and performance regressions. Reproduce → minimise → hypothesise → instrument → fix → regression-test. Use when the user says "diagnose this" / "debug this", reports a bug, says something is broken/throwing/failing, or describes a performance regression.
---

# diagnose

A discipline for hard bugs. Skip phases only when explicitly justified.

When exploring the codebase, use `CONTEXT.md` to ground your mental model of the relevant modules and check `docs/adr/` for decisions in the area you're touching.

## Phase 0 — Capture the symptom

Before anything else, write down what the user actually reported. The wrong-bug failure mode (debugging a nearby symptom rather than the reported one) starts here.

Capture, even if only in conversation:

- [ ] **Actual behavior** — exactly what the user saw (error message verbatim, wrong output, slow timing).
- [ ] **Expected behavior** — what they expected to see.
- [ ] **First known good / first known bad** — last release, last commit, last input that worked. "Always broken" and "broke yesterday" are different bugs.
- [ ] **Repro the user has, if any** — even an unreliable one tells you a lot.
- [ ] **Severity / blast radius** — one user vs. all users, prod vs. dev, recoverable vs. data-loss.

If any of these are missing and the user is reachable, ask. If AFK, note the gap explicitly and proceed with the strongest assumption stated.

Only after the symptom is captured does Phase 1 begin.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. With a fast, deterministic, agent-runnable pass/fail signal you will find the cause — bisection, hypothesis-testing, and instrumentation all just consume that signal. Without one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Ways to construct one — try roughly in order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) — drives the UI, asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real network request / payload / event log; replay through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** "Sometimes wrong output" — run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** Bug appeared between two known states (commit, dataset, version)? Automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Same input through old vs. new (or two configs) and diff outputs.
10. **HITL bash script.** Last resort. If a human must click, drive them with a structured loop ([scripts/hitl-loop.template.sh](scripts/hitl-loop.template.sh)) so output still feeds back to you.

Right loop, bug 90% fixed.

### Iterate on the loop itself

Treat the loop as a product. Once you have *a* loop, ask:

- Faster? (Cache setup, skip unrelated init, narrow scope.)
- Sharper signal? (Assert on the specific symptom, not "didn't crash".)
- More deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop. A 2-second deterministic loop is a debugging superpower.

### Non-deterministic bugs

Goal isn't a clean repro — it's a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. 50%-flake = debuggable. 1% = not — keep raising the rate.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask for: (a) access to the environment that reproduces, (b) a captured artifact (HAR, log dump, core dump, screen recording with timestamps), or (c) permission for temporary production instrumentation. Do **not** hypothesise without a loop.

Don't proceed to Phase 2 until you have a loop you believe in.

## Phase 2 — Reproduce

Run the loop. Watch the bug appear. Confirm:

- [ ] The loop produces the failure mode the **user** described — not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] Reproducible across multiple runs (or, for non-deterministic bugs, at a high enough rate to debug against).
- [ ] You captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix actually addresses it.

Don't proceed until you reproduce.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any. Single-hypothesis generation anchors on the first plausible idea.

Each hypothesis must be **falsifiable**:

> Format: *"If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."*

Can't state the prediction → it's a vibe. Discard or sharpen.

**Show the ranked list to the user before testing.** They often re-rank instantly with domain knowledge ("we just shipped a change to #3"), or know what's already been ruled out. Cheap checkpoint, big time saver. Don't block — proceed with your ranking if AFK.

## Phase 4 — Instrument

Each probe must map to a specific prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end is a single grep. Untagged logs survive; tagged logs die.

**Perf branch.** For performance regressions, logs are usually wrong. Instead: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5 — Fix + regression test

Write the regression test **before the fix** — but only if there's a **correct seam** for it.

A correct seam exercises the **real bug pattern** as it occurs at the call site. Too-shallow seam (single-caller test for a multi-caller bug, unit test that can't replicate the chain) gives false confidence.

**No correct seam exists?** That's itself the finding. Note it. The architecture is preventing the bug from being locked down. Flag for Phase 6.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 loop against the original (un-minimised) scenario.

## Phase 6 — Cleanup + post-mortem

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run Phase 1)
- [ ] Regression test passes (or absence of seam is documented)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway prototypes deleted (or moved to a clearly-marked debug location)
- [ ] The hypothesis that turned out correct is stated in the commit / PR — so the next debugger learns

**Then ask: what would have prevented this bug?** If the answer is architectural (no good test seam, tangled callers, hidden coupling) hand off to `improve-codebase-architecture` with specifics. Make the recommendation **after** the fix is in — you have more information now than when you started.

<!-- Vendored from mattpocock/skills@494e4b2699ea (MIT), lightly compressed. See ATTRIBUTION.md. -->
