#!/bin/bash
# ccusage-cached - Cached daily cost fetcher for claude-statusline
# https://github.com/omniwired/claude-statusline
# MIT License
#
# This script fetches daily Claude Code costs via ccusage and caches
# the result to avoid heavy npx/bun calls on every status update.
#
# Install: Copy to ~/.local/bin/ccusage-cached and chmod +x
# Usage: Run periodically (e.g., from shell prompt) or on-demand

CACHE=~/.cache/ccusage_status
MAX_AGE=3600  # 1 hour in seconds

mkdir -p ~/.cache

# Check if cache exists and is fresh
if [[ -f "$CACHE" ]]; then
    age=$(($(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null)))
    if [[ $age -lt $MAX_AGE ]]; then
        cat "$CACHE"
        exit 0
    fi
fi

# Cache is stale/missing - show old value if exists, refresh in background
[[ -f "$CACHE" ]] && cat "$CACHE"

# Refresh cache in background (uses bun if available, falls back to npx)
(
  if command -v bun &>/dev/null; then
    bun x ccusage daily --since "$(date +%Y%m%d)" --json 2>/dev/null
  else
    npx -y ccusage@latest daily --since "$(date +%Y%m%d)" --json 2>/dev/null
  fi | jq -r '"$" + (.totals.totalCost | . * 100 | floor / 100 | tostring)' > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
) &
