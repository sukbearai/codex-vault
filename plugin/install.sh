#!/bin/bash
set -eo pipefail

# Loom installer
# Detects installed LLM agents and generates the appropriate configuration.
# Supports: Claude Code, Codex CLI.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_DIR="$REPO_DIR/vault"

echo "=== Loom Installer ==="
echo ""

# --- Detect agents ---

AGENTS=()

if command -v claude &>/dev/null; then
  AGENTS+=("claude")
  echo "[+] Claude Code detected"
fi

if command -v codex &>/dev/null; then
  AGENTS+=("codex")
  echo "[+] Codex CLI detected"
fi

if [ ${#AGENTS[@]} -eq 0 ]; then
  echo "[!] No supported agents found."
  echo "    Install Claude Code: https://docs.anthropic.com/en/docs/claude-code"
  echo "    Install Codex CLI:   https://github.com/openai/codex"
  echo ""
  echo "    You can still use the vault manually — just open it in Obsidian."
  exit 0
fi

echo ""

# --- Setup functions ---

setup_claude() {
  echo "--- Setting up Claude Code ---"

  # Create .claude directory in vault
  mkdir -p "$VAULT_DIR/.claude/commands"

  # Generate settings.json with hooks pointing to plugin/hooks/
  cat > "$VAULT_DIR/.claude/settings.json" << 'SETTINGS'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash plugin/hooks/session-start.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 plugin/hooks/classify-message.py",
            "timeout": 15
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 plugin/hooks/validate-write.py",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
SETTINGS

  # Copy commands from adapters
  if [ -d "$REPO_DIR/adapters/claude-code/commands" ]; then
    cp "$REPO_DIR/adapters/claude-code/commands/"*.md "$VAULT_DIR/.claude/commands/" 2>/dev/null || true
  fi

  # Generate CLAUDE.md from shared instructions
  {
    echo "# Loom"
    echo ""
    cat "$REPO_DIR/plugin/instructions.md" | tail -n +3
  } > "$VAULT_DIR/CLAUDE.md"

  echo "  [+] .claude/settings.json (3 hooks)"
  echo "  [+] .claude/commands/ ($(ls "$VAULT_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ') commands)"
  echo "  [+] CLAUDE.md"
  echo ""
}

setup_codex() {
  echo "--- Setting up Codex CLI ---"

  mkdir -p "$VAULT_DIR/.codex"

  # Generate hooks.json
  cat > "$VAULT_DIR/.codex/hooks.json" << 'HOOKS'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "bash plugin/hooks/session-start.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 plugin/hooks/classify-message.py",
            "timeout": 15
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 plugin/hooks/validate-write.py",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
HOOKS

  # Generate AGENTS.md from shared instructions
  {
    echo "# Loom"
    echo ""
    cat "$REPO_DIR/plugin/instructions.md" | tail -n +3
  } > "$VAULT_DIR/AGENTS.md"

  echo "  [+] .codex/hooks.json (3 hooks)"
  echo "  [+] AGENTS.md"
  echo ""
}

# --- Run setup for each detected agent ---

for agent in "${AGENTS[@]}"; do
  "setup_$agent"
done

# --- Done ---

echo "=== Done ==="
echo ""
echo "Your vault is ready at: $VAULT_DIR"
echo ""
echo "Next steps:"
echo "  cd $VAULT_DIR"

for agent in "${AGENTS[@]}"; do
  case $agent in
    claude) echo "  claude                  # start with Claude Code" ;;
    codex)  echo "  codex                   # start with Codex CLI" ;;
  esac
done

echo ""
echo "  Fill in brain/North Star.md with your goals, then start talking."
