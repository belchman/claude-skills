# claude-statusline

A two-line Claude Code statusline showing model, location, context %, per-turn token usage, session totals, and cost. Drop-in for any Claude Code install.

## What it shows

```
[Opus] claude-skills@master | effort:medium
████░░░░░░ 47% | turn ↓8.5K ↑1.2K (cache r:2.0K w:5.0K) | sess ↓45.0K ↑12.0K | $0.1234
```

**Line 1** — `[model] dir@branch [(wt:worktree)] | effort:level [+thinking]`
**Line 2** — `<bar> ctx% | turn ↓in ↑out (cache r:read w:write) | sess ↓In ↑Out | $cost`

If you're on Claude.ai Pro/Max and rate-limit data is present, an optional third line appears:

```
⟳ 5h:78% 7d:41%
```

### Behaviour

- **Color-coded context bar** — green <70%, yellow 70–89%, red ≥90%. Catch the wall before you hit it.
- **In/out tokens for the current turn** — shows the cost of *this* exchange. Cumulative session totals shown alongside.
- **Cache visibility** — `cache r:` (read, cheap) and `cache w:` (write, one-time-but-2x-cost). High read = caching is working.
- **Effort + thinking** — only shown when the model exposes them; `+thinking` flags extended thinking is live.
- **Worktree-aware** — appends `(wt:<name>)` when you're inside a `git worktree add` directory.
- **Null-safe** — handles the empty `current_usage` that occurs before the first API call and immediately after `/compact`.

All schema field names verified against the [official statusline docs](https://code.claude.com/docs/en/statusline).

## Install

### One-shot

```bash
curl -fsSL https://raw.githubusercontent.com/belchman/claude-skills/master/statusline/claude-statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 1
  }
}
```

Settings reload automatically; the new statusline appears on your next prompt cycle.

### From a clone

```bash
git clone https://github.com/belchman/claude-skills
cp claude-skills/statusline/claude-statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
# then add the statusLine block above to ~/.claude/settings.json
```

## Requirements

- `bash` 4+
- `jq`
- `git` (only used to read the current branch name; falls back gracefully if absent or the directory isn't a repo)

The script validates none of these on startup — Claude Code re-runs the statusline frequently, so heavy validation is itself an anti-pattern. If a tool is missing, the affected field renders empty rather than erroring.

## Performance

Runs in well under 100ms (the practical UX budget). No network calls, no external API requests, no caching (Claude Code re-runs the script on every event — debounced at 300ms). All field reads come from the JSON piped to stdin or one cheap `git branch --show-current` call.

## Test it without installing

The script reads JSON from stdin, so you can dry-run any payload:

```bash
echo '{
  "model": {"display_name": "Opus"},
  "workspace": {"current_dir": "/tmp/foo"},
  "context_window": {
    "used_percentage": 47,
    "total_input_tokens": 45000, "total_output_tokens": 12000,
    "current_usage": {"input_tokens": 8500, "output_tokens": 1200, "cache_creation_input_tokens": 5000, "cache_read_input_tokens": 2000}
  },
  "cost": {"total_cost_usd": 0.1234},
  "effort": {"level": "medium"}
}' | ./claude-statusline.sh
```

## Customizing

The script is ~80 lines of bash; everything is in one file. Common tweaks:

- **Change the bar width** — edit `w=10` in the `bar()` function.
- **Change the color thresholds** — edit `color_pct()` (currently 70/90).
- **Drop a line** — comment out the `printf "%b\n" "$LINE2"` (or LINE1) at the bottom.
- **Add latency** — surface `cost.total_api_duration_ms`; `jq -r '.cost.total_api_duration_ms // 0'`.

Full schema reference: [code.claude.com/docs/en/statusline](https://code.claude.com/docs/en/statusline).

## Uninstall

```bash
# Remove the statusLine block from ~/.claude/settings.json, or:
# Use the slash command in Claude Code:
/statusline delete

# Then optionally:
rm ~/.claude/statusline.sh
```

## Why these fields?

Picked from a ranked importance list (see the parent repo's research notes):

| Tier | Field | Reason |
|---|---|---|
| 1 | Context % | Only signal that warns *before* you hit the context wall. |
| 1 | Model name | Critical with `/model` switching — different cost & limits. |
| 2 | Session cost | Direct bill-shock prevention. |
| 2 | Per-turn in/out | Tells you the cost of *this* exchange while you can still adjust. |
| 2 | Cache read/write | Tells you whether prompt caching is working. |
| 2 | Rate-limit % (optional) | Pro/Max only; non-optional if you hit weekly limits. |
| 3 | Branch + worktree | Distinguishes parallel sessions; cheap. |
| 3 | Effort + thinking | Constant reminder when reasoning is elevated. |

Fields deliberately *not* shown (better in a separate command):

- Git dirty state, ahead/behind, PR status — too wide.
- Raw cumulative token numbers (vs. %) — less legible.
- `total_api_duration_ms` — debug-only.
