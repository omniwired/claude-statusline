#!/bin/bash
# claude-statusline - A lightweight status line for Claude Code
# https://github.com/omniwired/claude-statusline
# MIT License - Optimized version (single jq call)

input=$(cat)

# ANSI colors
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

# Single jq call to extract all values
eval "$(echo "$input" | jq -r '
  "MODEL=\(.model.display_name // .model.id // "unknown")",
  "COST=\(.cost.total_cost_usd // 0)",
  "DURATION_MS=\(.cost.total_duration_ms // 0)",
  "API_DURATION_MS=\(.cost.total_api_duration_ms // 0)",
  "LINES_ADDED=\(.cost.total_lines_added // 0)",
  "LINES_REMOVED=\(.cost.total_lines_removed // 0)",
  "CWD=\(.workspace.current_dir // .cwd // "unknown")",
  "TRANSCRIPT_PATH=\(.transcript_path // "")"
' | sed "s/'/'\\\\''/g; s/=\\(.*\\)/='\\1'/")"

# Format cost
COST_FMT=$(printf "%.4f" "$COST")

# Duration formatting (inline)
sec=$((DURATION_MS / 1000))
if [ "$sec" -ge 3600 ]; then
  DURATION_FMT="$((sec / 3600))h$((sec % 3600 / 60))m"
elif [ "$sec" -ge 60 ]; then
  DURATION_FMT="$((sec / 60))m$((sec % 60))s"
else
  DURATION_FMT="${sec}s"
fi

api_sec=$((API_DURATION_MS / 1000))
if [ "$api_sec" -ge 3600 ]; then
  API_DURATION_FMT="$((api_sec / 3600))h$((api_sec % 3600 / 60))m"
elif [ "$api_sec" -ge 60 ]; then
  API_DURATION_FMT="$((api_sec / 60))m$((api_sec % 60))s"
else
  API_DURATION_FMT="${api_sec}s"
fi

SHORT_CWD="${CWD##*/}"

# Git branch (cached - refreshes every 5 seconds)
GIT_BRANCH=""
GIT_CACHE=~/.cache/statusline_git
NOW=${EPOCHSECONDS:-$(printf '%(%s)T' -1)}
if [[ -f "$GIT_CACHE" ]]; then
  IFS='|' read -r CACHE_TIME CACHE_DIR CACHE_BRANCH < "$GIT_CACHE"
  if [[ "$CACHE_DIR" == "$CWD" && $((NOW - CACHE_TIME)) -lt 5 ]]; then
    [[ -n "$CACHE_BRANCH" ]] && GIT_BRANCH="${DIM}@${RESET}${MAGENTA}${CACHE_BRANCH}${RESET}"
  else
    BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null)
    echo "$NOW|$CWD|$BRANCH" > "$GIT_CACHE"
    [[ -n "$BRANCH" ]] && GIT_BRANCH="${DIM}@${RESET}${MAGENTA}${BRANCH}${RESET}"
  fi
else
  BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null)
  echo "$NOW|$CWD|$BRANCH" > "$GIT_CACHE"
  [[ -n "$BRANCH" ]] && GIT_BRANCH="${DIM}@${RESET}${MAGENTA}${BRANCH}${RESET}"
fi

# Daily total cache
DAILY_TOTAL=""
[[ -f ~/.cache/ccusage_status ]] && DAILY_TOTAL=$(<~/.cache/ccusage_status)

# Context usage - optimized with single read + bash parsing
CONTEXT_PCT=""
CONTEXT_COLOR="$GREEN"
CONTEXT_ICON="🟢"
CONTEXT_BAR=""

if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  USAGE_LINE=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null | grep -o '"usage":{[^}]*}' | tail -1)

  if [[ -n "$USAGE_LINE" ]]; then
    # Bash pattern extraction (no subshells)
    INPUT_TOKENS=0 CACHE_READ=0 CACHE_CREATE=0
    [[ $USAGE_LINE =~ \"input_tokens\":([0-9]+) ]] && INPUT_TOKENS=${BASH_REMATCH[1]}
    [[ $USAGE_LINE =~ \"cache_read_input_tokens\":([0-9]+) ]] && CACHE_READ=${BASH_REMATCH[1]}
    [[ $USAGE_LINE =~ \"cache_creation_input_tokens\":([0-9]+) ]] && CACHE_CREATE=${BASH_REMATCH[1]}

    TOTAL_TOKENS=$((INPUT_TOKENS + CACHE_READ + CACHE_CREATE))

    if [[ $TOTAL_TOKENS -gt 0 ]]; then
      CONTEXT_PCT=$((TOTAL_TOKENS * 100 / 200000))
      [[ $CONTEXT_PCT -gt 100 ]] && CONTEXT_PCT=100

      if [[ $CONTEXT_PCT -ge 95 ]]; then
        CONTEXT_COLOR="${BOLD}${RED}" CONTEXT_ICON="🚨"
      elif [[ $CONTEXT_PCT -ge 90 ]]; then
        CONTEXT_COLOR="$RED" CONTEXT_ICON="🔴"
      elif [[ $CONTEXT_PCT -ge 75 ]]; then
        CONTEXT_COLOR="$LIGHT_RED" CONTEXT_ICON="🟠"
      elif [[ $CONTEXT_PCT -ge 50 ]]; then
        CONTEXT_COLOR="$YELLOW" CONTEXT_ICON="🟡"
      fi

      # Progress bar with printf (no loop)
      FILLED=$((CONTEXT_PCT * 8 / 100))
      CONTEXT_BAR=$(printf '█%.0s' $(seq 1 $FILLED 2>/dev/null))$(printf '▁%.0s' $(seq 1 $((8-FILLED)) 2>/dev/null))
    fi
  fi
fi

# Build output
OUTPUT="${BOLD}${CYAN}${MODEL}${RESET}"
OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${BLUE}${SHORT_CWD}${RESET}${GIT_BRANCH}"
OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${GREEN}\$${COST_FMT}${RESET}"
[[ -n "$DAILY_TOTAL" ]] && OUTPUT+="${DIM}/${RESET}${GREEN}${DAILY_TOTAL}${RESET}"
OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${YELLOW}${DURATION_FMT}${RESET} ${DIM}(${API_DURATION_FMT} api)${RESET}"
OUTPUT+=" ${DIM}│${RESET} "
OUTPUT+="${GREEN}+${LINES_ADDED}${RESET}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"

if [[ -n "$CONTEXT_PCT" ]]; then
  OUTPUT+=" ${DIM}│${RESET} "
  OUTPUT+="${CONTEXT_ICON}${CONTEXT_COLOR}${CONTEXT_BAR}${RESET} ${CONTEXT_PCT}%"
fi

echo "$OUTPUT"
