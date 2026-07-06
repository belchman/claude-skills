#!/bin/sh
# format-on-write.sh — agent-loop PostToolUse hook (matcher: Edit|Write).
# Formats JUST the touched file, using only a formatter the repo shows
# evidence of (config file present). Always exits 0 — formatting is never
# blocking. Probe result cached per session under /tmp.
# Self-gates like guard-destructive.sh (repo copy wins).
set -u

REPO="${CLAUDE_PROJECT_DIR:-.}"
[ -d "$REPO/.claude/agent-loop" ] || exit 0
REPO_COPY="$REPO/.claude/hooks/format-on-write.sh"
case "$0" in
  "$REPO_COPY") : ;;
  *) [ -f "$REPO_COPY" ] && exit 0 ;;
esac

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | grep -o '"file_path" *: *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
SESSION=$(printf '%s' "$INPUT" | grep -o '"session_id" *: *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
CACHE="/tmp/agent-loop-fmt-${SESSION:-nosession}"

if [ ! -f "$CACHE" ]; then
  {
    { [ -f "$REPO/.prettierrc" ] || [ -f "$REPO/.prettierrc.json" ] || [ -f "$REPO/prettier.config.js" ]; } && command -v npx >/dev/null 2>&1 && echo "prettier"
    [ -f "$REPO/pyproject.toml" ] && grep -q '\[tool\.ruff' "$REPO/pyproject.toml" 2>/dev/null && command -v ruff >/dev/null 2>&1 && echo "ruff"
    [ -f "$REPO/Cargo.toml" ] && command -v rustfmt >/dev/null 2>&1 && echo "rustfmt"
    [ -f "$REPO/go.mod" ] && command -v gofmt >/dev/null 2>&1 && echo "gofmt"
  } > "$CACHE" 2>/dev/null || true
fi

EXT="${FILE##*.}"
case "$EXT" in
  js|jsx|ts|tsx|json|css|md|yml|yaml)
    grep -qx prettier "$CACHE" && ( cd "$REPO" && npx --no-install prettier --write "$FILE" >/dev/null 2>&1 ) ;;
  py)
    grep -qx ruff "$CACHE" && ( cd "$REPO" && ruff format "$FILE" >/dev/null 2>&1 ) ;;
  rs)
    grep -qx rustfmt "$CACHE" && rustfmt "$FILE" >/dev/null 2>&1 ;;
  go)
    grep -qx gofmt "$CACHE" && gofmt -w "$FILE" >/dev/null 2>&1 ;;
esac

exit 0
