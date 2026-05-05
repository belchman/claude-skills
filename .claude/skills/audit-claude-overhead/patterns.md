# The Nine Patterns — full reference

Source: [@mnilax thread, 2026](https://x.com/mnilax/status/2050261839653556522). Percentages are his measurements (90 days, 430h, $1,340 spend, 27% productive baseline). Treat as benchmarks; measure your own.

---

## 1. CLAUDE.md bloat — ~14% of tokens

**Pattern:** CLAUDE.md grows over months. Every turn, every session re-loads all of it. Most rules don't apply to the current task.

**Threshold:** combined `~/.claude/CLAUDE.md` + `./.claude/CLAUDE.md` over **1,200–1,500 words** (~1,500–1,900 tokens).

**Fix:**
- Move framework-specific rules to **project-level** CLAUDE.md (only loads in that project).
- Extract repeated patterns into **skills** (load only when invoked).
- Delete anything you can't remember writing or justify.
- Convert verbose "here's why we do X" rules into 3–5-word imperatives.

**Caution:** old rules can be scars from past incidents. Ask before deleting if you're unsure.

---

## 2. Conversation history re-reads — ~13%

**Pattern:** every follow-up re-tokenizes the entire prior conversation. Message 30 in a thread costs ~30× message 1 in re-read tokens.

**Threshold:** chats over **20 messages**.

**Fix:**
- **Edit prior messages** instead of stacking follow-ups. Up-arrow → edit → resend replaces, doesn't append.
- Hard cap at 20 messages. When you cross it, ask Claude to summarize, then start a new chat with the summary as message 1.
- Use `/compact` (summarize-and-restart) over `/clear` (nuke) when continuity matters.

---

## 3. Hook injection waste — ~11%

**Pattern:** plugins register `UserPromptSubmit` hooks that prepend context (branch, file changes, memory snippets, instinct summaries) to every prompt. Each is small. Combined: thousands of tokens per turn.

**Threshold:** more than **1** active `UserPromptSubmit` hook you can't justify.

**Diagnostic:**
```bash
jq '.hooks.UserPromptSubmit' ~/.claude/settings.json 2>/dev/null
jq '.hooks.UserPromptSubmit' ./.claude/settings.json 2>/dev/null
```

**Fix:** for each hook, ask "do I rely on this every prompt?" If no, disable the plugin or remove the hook entry.

---

## 4. Cache miss on session resume — ~10%

**Pattern:** Anthropic's prompt cache defaults to **5-minute** TTL. Step away for 6 minutes — the cached system prompt + CLAUDE.md + tool schemas re-tokenize at full price (vs. 0.1× for cache reads).

**Threshold:** frequent multi-minute breaks during work, default 5-min cache.

**Fix:**
- **Workaround:** ping Claude with any cheap prompt before stepping away if the break will be ≥ 4 min.
- **Real fix:** upgrade to **1-hour cache** (paid plans). Write tokens are 2× base (one-time per write); reads are 0.1×. Pays for itself with 10+ resumes per session.
- Check current TTL via API request settings or plan dashboard.

---

## 5. Skill auto-load on irrelevant tasks — ~7%

**Pattern:** skills auto-invoke on description match. Detection is conservative — when in doubt, load. Backend task pulls in your UI skill; text task pulls in video-gen. Each `SKILL.md` is 800–2,500 tokens.

**Thresholds:**
- ad-hoc skills (`~/.claude/skills/`, `./.claude/skills/`) > **5**
- total addressable skills (ad-hoc + plugin-provided) > **30**

The bigger lever in 2026 is *plugin-provided* skills. A single plugin like `impeccable` or `superpowers` ships 14–21 skills — every enabled plugin's full skill catalog is addressable to the orchestrator's matching pool, and each adds description tokens to skill routing.

**Diagnostic:**
```bash
# ad-hoc (yours)
ls ~/.claude/skills/ ./.claude/skills/ 2>/dev/null

# plugin-provided (the heavy hitters)
jq -r '.enabledPlugins | to_entries[] | select(.value==true) | .key' ~/.claude/settings.json
# then cross-ref with ~/.claude/plugins/installed_plugins.json for install paths
```

**Fix:** disable any ad-hoc skill not invoked in the last 7 days. For plugins: keep daily-driver plugins enabled; disable plugins where you reach for the slash-command form once a week or less. The audit script does the dedupe + counting automatically.

---

## 6. "Just in case" MCP tool definitions — ~6%

**Pattern:** every connected MCP ships its tool schema with every request. Postgres MCP alone is ~1,200 tokens. Twelve always-on MCPs ≈ 7K tokens of schemas you mostly don't use.

**Threshold:** more than **3** always-on MCPs total (settings.json **plus** plugin-bundled).

**Diagnostic:**
```bash
# direct registrations
jq '.mcpServers // {} | keys' ~/.claude/settings.json
jq '.mcpServers // {} | keys' ./.claude/settings.json

# plugin-bundled (the audit script walks installed plugins for .mcp.json / plugin.json)
find ~/.claude/plugins/cache -name '.mcp.json' -o -name 'plugin.json' \
  | xargs -I{} jq -r '(.mcpServers // {}) | keys[]?' {} 2>/dev/null | sort -u
```

**Fix:** keep the 3 you use daily on auto-load. Move the rest to per-session enable (`/mcp enable <server>`). For MCPs bundled inside plugins you don't use weekly, disable the parent plugin.

---

## 7. Extended thinking on simple questions — ~5%

**Pattern:** "Advanced Thinking" / extended thinking left ON globally. Burns 3K+ thinking tokens on trivial tasks ("rename this var to camelCase").

**Threshold:** `effortLevel: "high"` set globally in `~/.claude/settings.json` (or its older equivalent `extendedThinking: true`). `medium` is reasonable; `low` is appropriate if most of your work is straightforward edits.

**Diagnostic:**
```bash
jq '{effortLevel, autoDreamEnabled}' ~/.claude/settings.json
```

**Fix:**
- Set `effortLevel` to `medium` (or `low`) globally. Toggle higher per-task when reasoning is genuinely needed (architecture, gnarly bug, multi-step planning).
- If your first attempt at a hard task is wrong, retry with higher effort.
- `autoDreamEnabled: true` triggers extra background thinking — verify it matches how you actually work.

Rule of thumb: ~80% of tasks don't need elevated thinking. The 20% that do, you'll know.

---

## 8. Wrong-direction generation — ~4%

**Pattern:** Claude starts a 400-line response. By line 50 it's clearly wrong. Most users let it finish, then re-prompt. The remaining 350 lines are billed output tokens.

**Threshold:** behavioral — no automatic detection.

**Fix:**
- **Cmd+. (Mac) / Ctrl+.** stops generation immediately. Claude keeps what it wrote; you redirect from there.
- **Esc-Esc** in Claude Code terminal opens the checkpoint scroller — rewind to any prior state and try a different fork without re-running.
- Practice the reflex: kill within ~5 seconds of seeing drift.

---

## 9. SessionStart hook noise — ~3%

**Pattern:** plugins add SessionStart hooks that print "loaded successfully" notices, version banners, env var summaries. ~50 tokens each × N plugins = ~1,400 tokens at every session start, for nothing.

**Threshold:** SessionStart hooks that print notifications without injecting load-bearing context.

**Diagnostic:**
```bash
jq '.hooks.SessionStart' ~/.claude/settings.json 2>/dev/null
jq '.hooks.SessionStart' ./.claude/settings.json 2>/dev/null
```

**Fix:** keep only hooks that inject context Claude needs (branch, env, project state). Kill announcement-only ones.

---

## What didn't work (per source)

- Switching to Haiku for "simple" tasks — ~3% reduction. Cheap model on bloated context still beats expensive model on lean. **Fix the context.**
- Aggressive `/clear` between every task — counter-productive. Loses needed context. Prefer long sessions + lean overhead.
- Disabling all skills — net negative; users start re-typing the same instructions in every prompt. Keep 3–5.
- Off-peak scheduling — partial. Real win is the patterns above, not the clock.
- Subscription downgrade — cost-per-work-hour stays the same; pain just hits sooner.
- Hunting the March 2026 cache bug — Anthropic patched it. Not worth individual investigation.

## Mental model

> Every Claude Code session is a long invoice that pre-charges you for: CLAUDE.md (always) + every active plugin's hooks (always) + every active skill (when relevance detected) + every connected MCP (always) + conversation history up to that turn (always) + cache-miss recompilation (after every 5-min break).
>
> Productive tokens are the residual.

Better prompts help when overhead is small. When overhead is 73%, prompts barely matter. **Cut the tax.**
