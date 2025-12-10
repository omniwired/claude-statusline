#!/bin/bash
# claude-statusline - A lightweight status line for Claude Code
# https://github.com/omniwired/claude-statusline
# MIT License

input=$(cat)

# ANSI colors using $'...' syntax for proper escape handling
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'

CYAN=$'\033[36m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
MAGENTA=$'\033[35m'
BLUE=$'\033[34m'
RED=$'\033[31m'

# Parse input from Claude Code
MODEL=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
API_DURATION_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "unknown"')

# Format cost to 4 decimal places
COST_FMT=$(printf "%.4f" "$COST")

# Convert milliseconds to human readable duration
format_duration() {
  local ms=$1
  local sec=$((ms / 1000))
  if [ "$sec" -ge 3600 ]; then
    echo "$((sec / 3600))h$((sec % 3600 / 60))m"
  elif [ "$sec" -ge 60 ]; then
    echo "$((sec / 60))m$((sec % 60))s"
  else
    echo "${sec}s"
  fi
}

DURATION_FMT=$(format_duration "$DURATION_MS")
API_DURATION_FMT=$(format_duration "$API_DURATION_MS")

# Shorten CWD to just the directory name
SHORT_CWD=$(basename "$CWD")

# Git branch (if in a repo)
GIT_BRANCH=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
  [ -n "$BRANCH" ] && GIT_BRANCH="${DIM}@${RESET}${MAGENTA}${BRANCH}${RESET}"
fi

# Daily total from ccusage cache (optional - requires ccusage setup)
# See README for instructions on setting up daily cost tracking
DAILY_TOTAL=""
if [[ -f ~/.cache/ccusage_status ]]; then
  DAILY_TOTAL=$(cat ~/.cache/ccusage_status)
fi

# Build output
OUTPUT="${BOLD}${CYAN}${MODEL}${RESET}"
OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${BLUE}${SHORT_CWD}${RESET}${GIT_BRANCH}"
OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${GREEN}\$${COST_FMT}${RESET}"

if [[ -n "$DAILY_TOTAL" ]]; then
  OUTPUT+="${DIM}/${RESET}${GREEN}${DAILY_TOTAL}${RESET}"
fi

OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${YELLOW}${DURATION_FMT}${RESET} ${DIM}(${API_DURATION_FMT} api)${RESET}"
OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${GREEN}+${LINES_ADDED}${RESET}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"

echo "$OUTPUT"
