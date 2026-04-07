#!/bin/bash
set -eo pipefail

# Codex-Vault session-start hook
# Injects vault context into the agent's prompt at session start.
# Works with any agent that supports SessionStart hooks (Claude Code, Codex CLI).
#
# Output contract (matches claude-mem pattern):
#   stdout → JSON with hookSpecificOutput.additionalContext (agent context)
#   stderr → visible banner (user terminal)
#
# Dynamic context: adapts git log window, reads full North Star,
# shows all active work, and includes uncommitted changes.

VAULT_DIR="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}"
cd "$VAULT_DIR"

# Find vault root (look for Home.md or brain/ directory)
if [ ! -f "Home.md" ] && [ ! -d "brain/" ]; then
  # Try vault/ subdirectory (integrated layout)
  if [ -d "vault/" ]; then
    VAULT_DIR="$VAULT_DIR/vault"
    cd "$VAULT_DIR"
  fi
fi

# --- Visible banner (stderr → user terminal) ---
{
  echo ""
  echo "  📚 Codex-Vault · Session Loaded"

  # North Star preview
  if [ -f "brain/North Star.md" ]; then
    GOAL=$(sed -n '/^## Current Focus/,/^## /{/^- ./{s/^- //;p;q;};}' "brain/North Star.md" | cut -c1-40)
    [ -n "$GOAL" ] && echo "  🎯 $GOAL" || echo "  🎯 (set goals in North Star.md)"
  else
    echo "  🎯 (create brain/North Star.md)"
  fi

  # Active work count
  WORK_COUNT=$(find work/active -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  echo "  📋 $WORK_COUNT active project(s)"

  # Uncommitted changes count
  CHANGE_COUNT=$(git status --short -- . 2>/dev/null | wc -l | tr -d ' ')
  if [ "$CHANGE_COUNT" -gt 0 ]; then
    echo "  ✏️  $CHANGE_COUNT uncommitted change(s)"
  else
    echo "  ✅ working tree clean"
  fi
  echo ""
} >&2

# --- Collect context into variable ---
CONTEXT=$(
cat <<'CONTEXT_HEADER'
## Session Context

CONTEXT_HEADER

echo "### Date"
echo "$(date +%Y-%m-%d) ($(date +%A))"
echo ""

# North Star — full file (should be concise by design)
echo "### North Star"
if [ -f "brain/North Star.md" ]; then
  cat "brain/North Star.md"
else
  echo "(No North Star found — create brain/North Star.md to set goals)"
fi
echo ""

# Recent changes — adaptive window
echo "### Recent Changes"
COMMITS_48H=$(git log --oneline --since="48 hours ago" --no-merges 2>/dev/null | wc -l | tr -d ' ')
if [ "$COMMITS_48H" -gt 0 ]; then
  echo "(last 48 hours)"
  git log --oneline --since="48 hours ago" --no-merges 2>/dev/null | head -15 || true
else
  COMMITS_7D=$(git log --oneline --since="7 days ago" --no-merges 2>/dev/null | wc -l | tr -d ' ')
  if [ "$COMMITS_7D" -gt 0 ]; then
    echo "(nothing in 48h — showing last 7 days)"
    git log --oneline --since="7 days ago" --no-merges 2>/dev/null | head -15 || true
  else
    echo "(nothing recent — showing last 5 commits)"
    git log --oneline -5 --no-merges 2>/dev/null || echo "(no git history)"
  fi
fi
echo ""

# Recent operations from log — adaptive
echo "### Recent Operations"
if [ -f "log.md" ]; then
  ENTRY_COUNT=$(grep -c "^## \[" "log.md" 2>/dev/null || echo "0")
  if [ "$ENTRY_COUNT" -gt 0 ]; then
    # Show last 5 entries with full header line (includes date + type)
    grep "^## \[" "log.md" | tail -5
  else
    echo "(no entries in log.md)"
  fi
else
  echo "(no log.md)"
fi
echo ""

# Active work — show all (this is the current focus, no truncation)
echo "### Active Work"
if [ -d "work/active" ]; then
  WORK_FILES=$(ls work/active/*.md 2>/dev/null || true)
  if [ -n "$WORK_FILES" ]; then
    echo "$WORK_FILES" | sed 's|work/active/||;s|\.md$||'
  else
    echo "(none)"
  fi
else
  echo "(no work/active/ directory)"
fi
echo ""

# Uncommitted changes — shows agent what's in-flight
echo "### Uncommitted Changes"
CHANGES=$(git status --short -- . 2>/dev/null | head -20 || true)
if [ -n "$CHANGES" ]; then
  echo "$CHANGES"
else
  echo "(working tree clean)"
fi
echo ""

# Recently modified brain files — highlights memory that may need review
echo "### Recently Modified Brain Files"
if [ -d "brain" ]; then
  GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
  if [ -n "$GIT_DIR" ] && [ -f "$GIT_DIR/index" ]; then
    RECENT_BRAIN=$(find brain/ -name "*.md" -newer "$GIT_DIR/index" 2>/dev/null || true)
  else
    RECENT_BRAIN=""
  fi
  if [ -n "$RECENT_BRAIN" ]; then
    echo "$RECENT_BRAIN" | sed 's|brain/||;s|\.md$||'
  else
    # Fallback: show brain files modified in last 7 days
    RECENT_BRAIN=$(find brain/ -name "*.md" -mtime -7 2>/dev/null || true)
    if [ -n "$RECENT_BRAIN" ]; then
      echo "(modified in last 7 days)"
      echo "$RECENT_BRAIN" | sed 's|brain/||;s|\.md$||'
    else
      echo "(no recent changes)"
    fi
  fi
fi
echo ""

# Vault file listing — tiered to avoid flooding context in large vaults
echo "### Vault Files"
ALL_FILES=$(find . -name "*.md" -not -path "./.git/*" -not -path "./.obsidian/*" -not -path "./thinking/*" -not -path "./.claude/*" -not -path "./.codex/*" -not -path "./.codex-vault/*" -not -path "./node_modules/*" 2>/dev/null | sort)
FILE_COUNT=$(echo "$ALL_FILES" | grep -c . 2>/dev/null || echo "0")

_folder_summary() {
  echo "$ALL_FILES" | sed 's|^\./||' | cut -d/ -f1 | sort | uniq -c | sort -rn | while read count dir; do
    echo "  $dir/ ($count files)"
  done
}

_key_files() {
  echo "$ALL_FILES" | grep -E "(Home|Index|North Star|Memories|Key Decisions|Patterns|log)\\.md$" || true
}

if [ "$FILE_COUNT" -le 20 ]; then
  echo "$ALL_FILES"

elif [ "$FILE_COUNT" -le 50 ]; then
  HOT_FILES=$(echo "$ALL_FILES" | grep -v -E "^\./sources/|^\./work/archive/" || true)
  COLD_COUNT=$(echo "$ALL_FILES" | grep -E "^\./sources/|^\./work/archive/" | grep -c . 2>/dev/null || echo "0")

  if [ -n "$HOT_FILES" ]; then
    echo "$HOT_FILES"
  fi
  if [ "$COLD_COUNT" -gt 0 ]; then
    echo ""
    echo "(+ $COLD_COUNT files in sources/ and work/archive/ — use /recall to search)"
  fi

elif [ "$FILE_COUNT" -le 150 ]; then
  echo "($FILE_COUNT files — showing summary)"
  echo ""
  _folder_summary
  echo ""
  echo "Recently modified (7 days):"
  find . -name "*.md" -mtime -7 -not -path "./.git/*" -not -path "./.obsidian/*" -not -path "./thinking/*" -not -path "./.claude/*" -not -path "./.codex/*" -not -path "./.codex-vault/*" -not -path "./node_modules/*" 2>/dev/null | sort || echo "  (none)"
  echo ""
  echo "Key files:"
  _key_files

else
  echo "($FILE_COUNT files — showing summary)"
  echo ""
  _folder_summary
  echo ""
  echo "Recently modified (3 days):"
  find . -name "*.md" -mtime -3 -not -path "./.git/*" -not -path "./.obsidian/*" -not -path "./thinking/*" -not -path "./.claude/*" -not -path "./.codex/*" -not -path "./.codex-vault/*" -not -path "./node_modules/*" 2>/dev/null | sort || echo "  (none)"
  echo ""
  echo "Key files:"
  _key_files
  echo ""
  echo "Use /recall <topic> to search the vault."
fi
)

# --- Output structured JSON (stdout → agent via hookSpecificOutput) ---
python3 -c "
import json, sys
context = sys.stdin.read()
json.dump({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': context
    }
}, sys.stdout)
" <<< "$CONTEXT"
