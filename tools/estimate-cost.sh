#!/usr/bin/env bash
#
# estimate-cost.sh — Claude Code cost estimator
# Estimates token usage and cost for common tasks based on codebase size.

set -euo pipefail

if [ -t 1 ]; then
  BOLD="\033[1m"; DIM="\033[2m"; CYAN="\033[36m"; YELLOW="\033[33m"; RESET="\033[0m"
else
  BOLD=""; DIM=""; CYAN=""; YELLOW=""; RESET=""
fi

PROJECT_DIR="${1:-.}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: Directory not found: $PROJECT_DIR"
  exit 1
fi

echo -e "${BOLD}${CYAN}Claude Code Cost Estimator${RESET}"
echo -e "${DIM}Analyzing: $(cd "$PROJECT_DIR" && pwd)${RESET}"
echo ""

FILE_COUNT=$(find "$PROJECT_DIR" \
  -type f \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
     -o -name "*.rb" -o -name "*.dart" -o -name "*.swift" -o -name "*.kt" \
     -o -name "*.css" -o -name "*.scss" -o -name "*.html" -o -name "*.vue" \
     -o -name "*.svelte" -o -name "*.c" -o -name "*.cpp" -o -name "*.h" \) \
  ! -path "*/node_modules/*" \
  ! -path "*/.git/*" \
  ! -path "*/vendor/*" \
  ! -path "*/dist/*" \
  ! -path "*/build/*" \
  ! -path "*/.next/*" \
  ! -path "*/target/*" \
  ! -path "*/__pycache__/*" \
  2>/dev/null | wc -l | tr -d ' ')

TOTAL_LINES=$(find "$PROJECT_DIR" \
  -type f \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
     -o -name "*.rb" -o -name "*.dart" \) \
  ! -path "*/node_modules/*" \
  ! -path "*/.git/*" \
  ! -path "*/vendor/*" \
  ! -path "*/dist/*" \
  ! -path "*/build/*" \
  ! -path "*/.next/*" \
  ! -path "*/target/*" \
  ! -path "*/__pycache__/*" \
  -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')

TOKENS_PER_LINE=10
TOTAL_TOKENS=$((TOTAL_LINES * TOKENS_PER_LINE))

HAS_CLAUDE_MD="No"
CLAUDE_MD_LINES=0
if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  HAS_CLAUDE_MD="Yes"
  CLAUDE_MD_LINES=$(wc -l < "$PROJECT_DIR/CLAUDE.md" | tr -d ' ')
fi

echo -e "${BOLD}Project Metrics${RESET}"
echo -e "  Source files:        $FILE_COUNT"
echo -e "  Lines of code:       $TOTAL_LINES"
echo -e "  Est. total tokens:   $TOTAL_TOKENS"
echo -e "  CLAUDE.md:           $HAS_CLAUDE_MD ($CLAUDE_MD_LINES lines)"
echo ""

HAIKU_INPUT=1.00;  HAIKU_OUTPUT=5.00
SONNET_INPUT=3.00; SONNET_OUTPUT=15.00
OPUS_INPUT=15.00;  OPUS_OUTPUT=75.00

calc_cost() {
  local input_k=$1 output_k=$2 price_in=$3 price_out=$4
  echo "scale=3; ($input_k * $price_in / 1000) + ($output_k * $price_out / 1000)" | bc 2>/dev/null || echo "N/A"
}

echo -e "${BOLD}Estimated Cost Per Task${RESET}"
echo -e "${DIM}(Rough estimates — actual costs vary with task complexity and conversation length)${RESET}"
echo ""

printf "  %-30s %-10s %-10s %-10s\n" "Task" "Haiku" "Sonnet" "Opus"
echo -e "  ${DIM}──────────────────────────────────────────────────────────────${RESET}"

for spec in "5 1 Quick question" "20 3 Single bug fix" "50 10 Small feature" "30 5 Code review (PR)" "150 30 Large feature / refactor" "200 20 Full codebase audit" "500 100 Multi-agent team session"; do
  read -r in out label <<< "$spec"
  H=$(calc_cost "$in" "$out" $HAIKU_INPUT $HAIKU_OUTPUT)
  S=$(calc_cost "$in" "$out" $SONNET_INPUT $SONNET_OUTPUT)
  O=$(calc_cost "$in" "$out" $OPUS_INPUT $OPUS_OUTPUT)
  printf "  %-30s %-10s %-10s %-10s\n" "$label" "\$$H" "\$$S" "\$$O"
done

echo ""
echo -e "${BOLD}Cost-Saving Tips${RESET}"
echo ""
echo "  - Use Haiku for simple tasks (explain, review, summarize)"
echo "  - Use Sonnet for most development work (default)"
echo "  - Use Opus only for complex architecture, hard bugs, or large refactors"
echo "  - Run /compact regularly to reduce context size and cost"
echo "  - Use --max-turns to limit runaway agentic loops"
echo "  - Scope prompts narrowly (one file > whole directory)"

if [ "$HAS_CLAUDE_MD" = "No" ]; then
  echo ""
  echo -e "  ${YELLOW}TIP:${RESET} Add a CLAUDE.md to reduce exploration tokens — Claude"
  echo "  will know your project structure without reading every file."
fi

echo ""
echo -e "${DIM}Prices based on Anthropic API pricing as of 2026. Actual costs depend on caching and context reuse.${RESET}"
