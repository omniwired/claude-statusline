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
LIGHT_RED=$'\033[91m'

# Parse input from Claude Code
MODEL=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
API_DURATION_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "unknown"')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')

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

# Context usage from transcript (parses last few lines for token info)
CONTEXT_PCT=""
CONTEXT_COLOR="$GREEN"
CONTEXT_ICON="🟢"
CONTEXT_BAR=""

if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  # Read last 20 lines of transcript and look for usage data
  USAGE_DATA=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null | grep -o '"usage":{[^}]*}' | tail -1)

  if [[ -n "$USAGE_DATA" ]]; then
    # Extract token counts
    INPUT_TOKENS=$(echo "$USAGE_DATA" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*' | head -1)
    CACHE_READ=$(echo "$USAGE_DATA" | grep -o '"cache_read_input_tokens":[0-9]*' | grep -o '[0-9]*' | head -1)
    CACHE_CREATE=$(echo "$USAGE_DATA" | grep -o '"cache_creation_input_tokens":[0-9]*' | grep -o '[0-9]*' | head -1)

    INPUT_TOKENS=${INPUT_TOKENS:-0}
    CACHE_READ=${CACHE_READ:-0}
    CACHE_CREATE=${CACHE_CREATE:-0}

    TOTAL_TOKENS=$((INPUT_TOKENS + CACHE_READ + CACHE_CREATE))

    if [[ $TOTAL_TOKENS -gt 0 ]]; then
      # Calculate percentage (assume 200k context for Claude)
      CONTEXT_PCT=$((TOTAL_TOKENS * 100 / 200000))
      [[ $CONTEXT_PCT -gt 100 ]] && CONTEXT_PCT=100

      # Color based on usage level
      if [[ $CONTEXT_PCT -ge 95 ]]; then
        CONTEXT_COLOR="${BOLD}${RED}"
        CONTEXT_ICON="🚨"
      elif [[ $CONTEXT_PCT -ge 90 ]]; then
        CONTEXT_COLOR="$RED"
        CONTEXT_ICON="🔴"
      elif [[ $CONTEXT_PCT -ge 75 ]]; then
        CONTEXT_COLOR="$LIGHT_RED"
        CONTEXT_ICON="🟠"
      elif [[ $CONTEXT_PCT -ge 50 ]]; then
        CONTEXT_COLOR="$YELLOW"
        CONTEXT_ICON="🟡"
      fi

      # Build progress bar (8 segments)
      FILLED=$((CONTEXT_PCT * 8 / 100))
      EMPTY=$((8 - FILLED))
      CONTEXT_BAR=""
      for ((i=0; i<FILLED; i++)); do CONTEXT_BAR+="█"; done
      for ((i=0; i<EMPTY; i++)); do CONTEXT_BAR+="▁"; done
    fi
  fi
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

# Context meter (if available)
if [[ -n "$CONTEXT_PCT" ]]; then
  OUTPUT+=" ${DIM}│${RESET} "
  OUTPUT+="${CONTEXT_ICON}${CONTEXT_COLOR}${CONTEXT_BAR}${RESET} ${CONTEXT_PCT}%"
fi

echo "$OUTPUT"
