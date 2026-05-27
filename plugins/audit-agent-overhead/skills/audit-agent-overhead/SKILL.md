---
name: audit-agent-overhead
description: 'Audit an agent setup (global ~/.claude AND project .claude AND plugin scope) for the 9 token-waste patterns that silently inflate cost and burn through usage limits. Outputs a per-pattern score against thresholds and proposes specific fixes — applied only with user approval. Heavyweight (~5KB SKILL.md + audit script); explicit invocation only. Triggers: /audit-agent-overhead, "audit my agent setup", "why am I hitting usage limits".'
disable-model-invocation: true
---

# audit-agent-overhead

Most "Claude got dumber" / "I burned through Max in 19 minutes" complaints trace to invisible per-turn overhead, not the model. This skill audits both scopes (global `~/.claude/`, project `.claude/`) against nine known waste patterns and proposes targeted fixes.

Source: [@mnilax thread, 2026](https://x.com/mnilax/status/2050261839653556522) — 90-day instrumented study of 430h / $1,340 of Claude Code usage. Productive tokens: 27%. Overhead: 73%. The patterns are his.

## When to run

- "Why am I hitting limits so fast?"
- "Claude feels slower / dumber / more expensive than last month"
- "Audit my Claude Code setup"
- "Trim my CLAUDE.md"
- After installing 3+ new plugins/skills/MCPs.
- Quarterly maintenance.

## The nine patterns

Full detail and per-pattern fix recipe in [patterns.md](patterns.md). Summary:

| # | Pattern | ~Share | Threshold (flag if over) |
|---|---|---:|---|
| 1 | CLAUDE.md bloat | 14% | combined > 1,500 tokens |
| 2 | Conversation history re-reads | 13% | sessions > 20 messages |
| 3 | Hook injection on every prompt | 11% | UserPromptSubmit hooks > 1 unjustified |
| 4 | Cache miss on session resume | 10% | default 5-min cache, frequent breaks |
| 5 | Skill auto-load on irrelevant tasks | 7% | ad-hoc skills > 5, OR total addressable > 30 (incl. plugin-provided) |
| 6 | Always-on MCP tool schemas | 6% | always-on MCPs > 3 (settings + plugin-bundled) |
| 7 | Extended thinking on simple tasks | 5% | `effortLevel: high` set globally |
| 8 | Wrong-direction generation | 4% | behavior — train Cmd+. / Esc-Esc reflex |
| 9 | SessionStart hook noise | 3% | "loaded successfully" notifications present |

Total addressable: ~73% of tokens. Realistic recovery: 27% → ~65% productive.

## Process

### 1. Run the audit

```bash
bash "${CLAUDE_SKILL_DIR}/bin/audit.sh"
```

`${CLAUDE_SKILL_DIR}` resolves to this skill's directory regardless of how it was installed (plugin cache, project `.claude/skills/`, or source repo). The script inspects three scopes and prints a per-pattern table with measured values vs. thresholds. It does not modify anything.

- **Global** — `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/skills/`
- **Project** — `./.claude/CLAUDE.md`, `./.claude/settings.json`, `./.claude/skills/`
- **Plugin scope** (the big one) — every plugin enabled in `~/.claude/settings.json:.enabledPlugins`, cross-referenced with `~/.claude/plugins/installed_plugins.json` to find install paths. SKILL.md files are deduplicated by skill name (plugins often ship the same skill under `.claude/`, `.opencode/`, and `claude-plugin/` runtime variants — only one is loaded at runtime).

### 2. Read the output, score each pattern

For each pattern flagged "OVER":

- Summarize what's bloated (the specific files / hook entries / plugin names involved).
- Quote the relevant fix recipe from [patterns.md](patterns.md).
- Estimate token savings using the share column above.

### 3. Propose fixes — one pattern at a time

**Do not batch-edit.** For each flagged pattern, present:

1. The current state (what was found).
2. The proposed change (exact edit, exact file path).
3. The risk (what behavior might change — usually "none if the rule was dead").
4. Ask: apply, skip, or modify?

Apply only what the user approves. Re-run the audit after each pattern to confirm the metric moved.

### 4. Hard rules

- **Never delete a file outright.** Move to `.claude/.audit-backup-<date>/` so it's recoverable.
- **Never edit `~/.claude/CLAUDE.md` without showing a diff first.** That file is the user's personal voice; tightening ≠ rewriting.
- **Never disable a plugin/skill/MCP without naming it and asking.** "Audit found 7 unused skills" is not consent — list them.
- **Treat the user's CLAUDE.md rules as load-bearing by default.** A "redundant" rule may be a scar from a past incident. When unsure, ask.
- **Don't recommend `/clear` aggressively.** Pattern 2 says cap at ~20 messages and use `/compact`, not nuke-and-restart.

### 5. Re-audit and report

After fixes, re-run `bin/audit.sh` and report:

- Per-pattern before/after (CLAUDE.md word count, hook count, MCP count, skill count).
- Which patterns are now within threshold.
- What's left and why (some patterns are behavioral, not config — flag those for the user to practice).

## Anti-patterns

- **Don't trust averages over baselines.** If you don't have 7+ days of logs, the script will skip the "avg input tokens / prompt" line. Don't fabricate it.
- **Don't generalize the article's percentages to this user.** They're benchmarks, not measurements. Re-run the script to get actual numbers for *this* setup.
- **Don't re-introduce overhead by writing a long fix-doc.** If your "fix recipe" is itself 500 tokens, you've made the problem worse.
