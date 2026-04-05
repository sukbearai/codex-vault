#!/bin/bash
set -eo pipefail

# Loom session-start hook
# Injects vault context into the agent's prompt at session start.
# Works with any agent that supports SessionStart hooks (Claude Code, Codex CLI).

VAULT_DIR="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$(pwd)}}"
cd "$VAULT_DIR"

# Find vault root (look for Home.md or brain/ directory)
if [ ! -f "Home.md" ] && [ ! -d "brain/" ]; then
  # Try vault/ subdirectory (repo layout)
  if [ -d "vault/" ]; then
    VAULT_DIR="$VAULT_DIR/vault"
    cd "$VAULT_DIR"
  fi
fi

echo "## Session Context"
echo ""
echo "### Date"
echo "$(date +%Y-%m-%d) ($(date +%A))"
echo ""

# North Star — goals and focus
echo "### North Star"
if [ -f "brain/North Star.md" ]; then
  head -30 "brain/North Star.md"
else
  echo "(No North Star found — create brain/North Star.md to set goals)"
fi
echo ""

# Recent changes
echo "### Recent Changes (last 48h)"
git log --oneline --since="48 hours ago" --no-merges 2>/dev/null | head -15 || echo "(no git history)"
echo ""

# Active work
echo "### Active Work"
if [ -d "work/active" ]; then
  ls work/active/*.md 2>/dev/null | sed 's|work/active/||;s|\.md$||' | head -10 || echo "(none)"
else
  echo "(no work/active/ directory)"
fi
echo ""

# Vault file listing
echo "### Vault Files"
find . -name "*.md" -not -path "./.git/*" -not -path "./.obsidian/*" -not -path "./thinking/*" -not -path "./.claude/*" -not -path "./.codex/*" -not -path "./node_modules/*" 2>/dev/null | sort
