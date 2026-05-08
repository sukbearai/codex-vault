#!/bin/bash
set -eo pipefail

# Codex-Vault installer
# Detects installed LLM agents and generates the appropriate configuration.
# Supports: Claude Code, Codex CLI.
#
# Two modes:
#   Standalone — run from within the codex-vault repo (vault/ is the working directory)
#   Integrated — run from a user's project root (.vault/ becomes a subdirectory)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(pwd)"

echo "=== Codex-Vault Installer ==="
echo ""

# --- Detect mode ---
# If CWD is the codex-vault repo (or vault/), use standalone mode.
# Otherwise, use integrated mode (install into user's project).

MODE="integrated"
if [ "$PROJECT_DIR" = "$REPO_DIR" ] || [ "$PROJECT_DIR" = "$REPO_DIR/vault" ]; then
  MODE="standalone"
fi
# Also detect if inside repo subdirectories
case "$PROJECT_DIR" in
  "$REPO_DIR"/*) MODE="standalone" ;;
esac

if [ "$MODE" = "standalone" ]; then
  VAULT_DIR="$REPO_DIR/vault"
  CONFIG_DIR="$VAULT_DIR"            # configs go inside vault/
  HOOKS_REL=".codex-vault/hooks"       # relative to vault/
  echo "[*] Standalone mode — vault is the working directory"
else
  VAULT_DIR="$PROJECT_DIR/.vault"
  CONFIG_DIR="$PROJECT_DIR"          # configs go at project root
  HOOKS_REL=".vault/.codex-vault/hooks" # relative to project root
  echo "[*] Integrated mode — installing into $(basename "$PROJECT_DIR")/"
fi

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

# --- Copy vault template (integrated mode only) ---

if [ "$MODE" = "integrated" ]; then
  if [ -d "$VAULT_DIR" ] && [ -f "$VAULT_DIR/Home.md" ]; then
    echo "[*] Vault already exists at .vault/ — skipping template copy"
  else
    echo "[+] Creating vault from template..."
    mkdir -p "$VAULT_DIR"
    # Copy vault contents, excluding agent-specific configs (we generate those)
    # Use cp -r (universally available) instead of rsync
    cp -r "$REPO_DIR/vault/"* "$VAULT_DIR/" 2>/dev/null || true
    cp -r "$REPO_DIR/vault/".* "$VAULT_DIR/" 2>/dev/null || true
    # Remove agent configs — we generate fresh ones for the target layout
    rm -rf "$VAULT_DIR/.claude" "$VAULT_DIR/.codex" "$VAULT_DIR/CLAUDE.md" "$VAULT_DIR/AGENTS.md" 2>/dev/null || true
    echo "    Copied template to .vault/"
  fi
  echo ""

  # Add .vault, .claude, .codex to .gitignore if not already present
  # These are per-user configs — committing them causes merge conflicts in teams.
  GITIGNORE="$PROJECT_DIR/.gitignore"
  GITIGNORE_ENTRIES=(".vault/" ".claude/" ".codex/")
  GITIGNORE_ADDED=()

  if [ ! -f "$GITIGNORE" ]; then
    printf '# Per-user agent configs (avoid conflicts in multi-user repos)\n' > "$GITIGNORE"
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
      printf '%s\n' "$entry" >> "$GITIGNORE"
      GITIGNORE_ADDED+=("$entry")
    done
  else
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
      pattern="^$(printf '%s' "$entry" | sed 's/\./\\./g')"
      bare="${entry%/}"
      if ! grep -q "$pattern" "$GITIGNORE" && ! grep -q "^${bare}$" "$GITIGNORE"; then
        GITIGNORE_ADDED+=("$entry")
      fi
    done
    if [ ${#GITIGNORE_ADDED[@]} -gt 0 ]; then
      printf '\n# Per-user agent configs (avoid conflicts in multi-user repos)\n' >> "$GITIGNORE"
      for entry in "${GITIGNORE_ADDED[@]}"; do
        printf '%s\n' "$entry" >> "$GITIGNORE"
      done
    fi
  fi

  if [ ${#GITIGNORE_ADDED[@]} -gt 0 ]; then
    echo "[+] Added ${GITIGNORE_ADDED[*]} to .gitignore"
  fi
  echo ""
fi

# --- Copy hooks into vault (makes vault self-contained) ---

HOOKS_DIR="$VAULT_DIR/.codex-vault/hooks"
mkdir -p "$HOOKS_DIR/claude" "$HOOKS_DIR/codex"
find "$REPO_DIR/plugin/hooks/claude" -maxdepth 1 -type f -exec cp {} "$HOOKS_DIR/claude/" \;
find "$REPO_DIR/plugin/hooks/codex" -maxdepth 1 -type f -exec cp {} "$HOOKS_DIR/codex/" \;
chmod +x "$HOOKS_DIR/claude/"*.py "$HOOKS_DIR/codex/"*.py 2>/dev/null || true
if [ "$MODE" = "standalone" ]; then
  echo "[+] Hook scripts copied to vault/.codex-vault/hooks/{claude,codex}/"
else
  echo "[+] Hook scripts copied to .vault/.codex-vault/hooks/{claude,codex}/"
fi
echo ""

# --- Helper: merge hooks into existing settings.json (Claude Code) ---
# Uses python3 for reliable JSON manipulation.

merge_hooks_json() {
  local target_file="$1"
  local hooks_rel="$2"

  # Pass data via env vars to python3 — no shell interpolation in python code.
  CVAULT_TARGET_FILE="$target_file" CVAULT_HOOKS_REL="$hooks_rel" python3 <<'PYEOF'
import json, os

target_file = os.environ["CVAULT_TARGET_FILE"]
hooks_rel = os.environ["CVAULT_HOOKS_REL"]

new_hooks = {
    "SessionStart": [{
        "matcher": "startup|resume|compact",
        "hooks": [{"type": "command", "command": f"python3 \"$CLAUDE_PROJECT_DIR/{hooks_rel}/session-start.py\"", "timeout": 30}]
    }],
    "UserPromptSubmit": [{
        "hooks": [{"type": "command", "command": f"python3 \"$CLAUDE_PROJECT_DIR/{hooks_rel}/classify-message.py\"", "timeout": 15}]
    }],
    "PostToolUse": [{
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": f"python3 \"$CLAUDE_PROJECT_DIR/{hooks_rel}/validate-write.py\"", "timeout": 15}]
    }],
}

if os.path.isfile(target_file):
    with open(target_file) as f:
        existing = json.load(f)
else:
    existing = {}

if "hooks" not in existing:
    existing["hooks"] = {}

# For each hook event, append entries (avoid duplicates by checking command)
for event, entries in new_hooks.items():
    if event not in existing["hooks"]:
        existing["hooks"][event] = entries
    else:
        existing_cmds = set()
        for rule in existing["hooks"][event]:
            for h in rule.get("hooks", []):
                existing_cmds.add(h.get("command", ""))
        for entry in entries:
            cmds = [h.get("command", "") for h in entry.get("hooks", [])]
            if not any(c in existing_cmds for c in cmds):
                existing["hooks"][event].append(entry)

with open(target_file, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
PYEOF
}

# --- Helper: merge hooks into existing hooks.json (Codex CLI) ---
# Codex CLI differences:
#   - SessionStart matcher: "startup|resume" (no compact)
#   - PostToolUse matcher: "Bash" (Codex only supports Bash, not Write|Edit)

merge_codex_hooks_json() {
  local target_file="$1"
  local hooks_rel="$2"

  CVAULT_TARGET_FILE="$target_file" CVAULT_HOOKS_REL="$hooks_rel" python3 <<'PYEOF'
import json, os

target_file = os.environ["CVAULT_TARGET_FILE"]
hooks_rel = os.environ["CVAULT_HOOKS_REL"]

new_hooks = {
    "SessionStart": [{
        "matcher": "startup|resume",
        "hooks": [{"type": "command", "command": f"python3 {hooks_rel}/session-start.py", "timeout": 30,
                    "statusMessage": "\U0001f4da Codex-Vault loading..."}]
    }],
    "UserPromptSubmit": [{
        "hooks": [{"type": "command", "command": f"python3 {hooks_rel}/classify-message.py", "timeout": 15}]
    }],
    "PostToolUse": [{
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": f"python3 {hooks_rel}/validate-write.py", "timeout": 15}]
    }],
}

if os.path.isfile(target_file):
    with open(target_file) as f:
        existing = json.load(f)
else:
    existing = {}

if "hooks" not in existing:
    existing["hooks"] = {}

# Remove old Codex-Vault Codex hook entries before inserting the canonical
# mapping. Older installs may have left these under PreToolUse, where Codex
# rejects additionalContext from context-producing scripts.
def is_managed_codex_hook(command):
    return ".codex-vault/hooks/codex/" in command or "codex-mem/hooks/codex/" in command

for event in list(existing["hooks"].keys()):
    entries = existing["hooks"].get(event)
    if not isinstance(entries, list):
        continue
    kept_entries = []
    for rule in entries:
        if not isinstance(rule, dict):
            kept_entries.append(rule)
            continue
        hooks = rule.get("hooks", [])
        if not isinstance(hooks, list):
            kept_entries.append(rule)
            continue
        kept_hooks = [
            h for h in hooks
            if not (isinstance(h, dict) and is_managed_codex_hook(h.get("command", "")))
        ]
        if kept_hooks:
            new_rule = dict(rule)
            new_rule["hooks"] = kept_hooks
            kept_entries.append(new_rule)
    if kept_entries:
        existing["hooks"][event] = kept_entries
    else:
        del existing["hooks"][event]

for event, entries in new_hooks.items():
    if event not in existing["hooks"]:
        existing["hooks"][event] = entries
    else:
        existing_cmds = set()
        for rule in existing["hooks"][event]:
            for h in rule.get("hooks", []):
                existing_cmds.add(h.get("command", ""))
        for entry in entries:
            cmds = [h.get("command", "") for h in entry.get("hooks", [])]
            if not any(c in existing_cmds for c in cmds):
                existing["hooks"][event].append(entry)

with open(target_file, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
PYEOF
}

# --- Helper: append codex-vault section to instruction file ---

append_instructions() {
  local target_file="$1"

  # Generate instructions: heading + blank line + body (skip first 2 lines of instructions.md)
  local section_content
  section_content="$(printf '# Codex-Vault\n\n'; tail -n +3 "$REPO_DIR/plugin/instructions.md")"

  if [ -f "$target_file" ]; then
    # Check if section already exists
    if grep -q "^# Codex-Vault" "$target_file"; then
      echo "    (codex-vault section already present — skipping)"
      return
    fi
    # Append with separator
    printf '\n---\n%s\n' "$section_content" >> "$target_file"
  else
    echo "$section_content" > "$target_file"
  fi
}

# --- Setup functions ---

# --- Helper: install skills into .<agent>/skills/<name>/SKILL.md ---

install_skills() {
  local target_dir="$1"
  local agent_dir="$2"   # .claude or .codex
  local src_dir="$REPO_DIR/plugin/skills"
  local count=0

  if [ ! -d "$src_dir" ]; then
    return
  fi

  for src_file in "$src_dir"/*.md; do
    [ -f "$src_file" ] || continue
    local skill_name
    skill_name=$(basename "$src_file" .md)
    local skill_dir="$target_dir/$agent_dir/skills/$skill_name"
    mkdir -p "$skill_dir"
    cp "$src_file" "$skill_dir/SKILL.md"
    count=$((count + 1))
  done

  echo "  [+] $agent_dir/skills/ ($count skills)"
}

setup_claude() {
  echo "--- Setting up Claude Code ---"

  if [ "$MODE" = "integrated" ]; then
    # Integrated: merge hooks into project root .claude/settings.json
    mkdir -p "$CONFIG_DIR/.claude"
    merge_hooks_json "$CONFIG_DIR/.claude/settings.json" "$HOOKS_REL/claude"
    echo "  [+] .claude/settings.json (hooks merged at project root)"

    # Append instructions to project root CLAUDE.md
    append_instructions "$CONFIG_DIR/CLAUDE.md"
    echo "  [+] CLAUDE.md (codex-vault section appended at project root)"

    # Install skills into project root .claude/skills/
    install_skills "$CONFIG_DIR" ".claude"
  else
    # Standalone: write directly into vault/ (original behavior)
    mkdir -p "$VAULT_DIR/.claude"
    merge_hooks_json "$VAULT_DIR/.claude/settings.json" "$HOOKS_REL/claude"
    echo "  [+] .claude/settings.json (3 hooks)"

    # Install skills into vault/.claude/skills/
    install_skills "$VAULT_DIR" ".claude"

    append_instructions "$VAULT_DIR/CLAUDE.md"
    echo "  [+] CLAUDE.md"
  fi
  echo ""
}

# --- Helper: enable Codex hooks feature flag in config.toml ---

enable_codex_hooks() {
  local config_file="$1/.codex/config.toml"
  mkdir -p "$(dirname "$config_file")"

  CONFIG_FILE="$config_file" python3 <<'PYEOF'
import os
import re
from pathlib import Path

path = Path(os.environ["CONFIG_FILE"])
content = path.read_text() if path.exists() else ""
lines = content.splitlines()

section_re = re.compile(r"^\s*\[[^]]+\]\s*$")
features_re = re.compile(r"^\s*\[features\]\s*$")
hooks_re = re.compile(r"^\s*hooks\s*=")
deprecated_hooks_re = re.compile(r"^\s*codex_hooks\s*=")

features_idx = None
features_end = len(lines)
for idx, line in enumerate(lines):
    if features_re.match(line):
        features_idx = idx
        for end_idx in range(idx + 1, len(lines)):
            if section_re.match(lines[end_idx]):
                features_end = end_idx
                break
        break

if features_idx is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines.extend(["[features]", "hooks = true"])
else:
    has_hooks = False
    next_lines = []
    for idx, line in enumerate(lines):
        in_features = features_idx < idx < features_end
        if in_features and deprecated_hooks_re.match(line):
            continue
        if in_features and hooks_re.match(line):
            if not has_hooks:
                next_lines.append("hooks = true")
                has_hooks = True
            continue
        next_lines.append(line)
    lines = next_lines
    if not has_hooks:
        lines.insert(features_idx + 1, "hooks = true")

path.write_text("\n".join(lines).rstrip() + "\n")
PYEOF

  echo "  [+] .codex/config.toml (hooks enabled)"
}

setup_codex() {
  echo "--- Setting up Codex CLI ---"

  # Check if Claude Code is also installed — if so, AGENTS.md just references CLAUDE.md
  local has_claude=false
  for a in "${AGENTS[@]}"; do
    [ "$a" = "claude" ] && has_claude=true
  done

  if [ "$MODE" = "integrated" ]; then
    # Integrated: merge hooks into project root .codex/hooks.json
    mkdir -p "$CONFIG_DIR/.codex"
    merge_codex_hooks_json "$CONFIG_DIR/.codex/hooks.json" "$HOOKS_REL/codex"
    echo "  [+] .codex/hooks.json (hooks merged at project root)"

    if [ "$has_claude" = true ]; then
      echo "@CLAUDE.md" > "$CONFIG_DIR/AGENTS.md"
      echo "  [+] AGENTS.md (references @CLAUDE.md)"
    else
      append_instructions "$CONFIG_DIR/AGENTS.md"
      echo "  [+] AGENTS.md (codex-vault section appended at project root)"
    fi

    # Enable hooks feature flag
    enable_codex_hooks "$CONFIG_DIR"

    # Install skills into project root .codex/skills/
    install_skills "$CONFIG_DIR" ".codex"
  else
    # Standalone: write directly into vault/ (original behavior)
    mkdir -p "$VAULT_DIR/.codex"

    merge_codex_hooks_json "$VAULT_DIR/.codex/hooks.json" "$HOOKS_REL/codex"
    echo "  [+] .codex/hooks.json (3 hooks)"

    # Enable hooks feature flag
    enable_codex_hooks "$VAULT_DIR"

    if [ "$has_claude" = true ]; then
      echo "@CLAUDE.md" > "$VAULT_DIR/AGENTS.md"
      echo "  [+] AGENTS.md (references @CLAUDE.md)"
    else
      append_instructions "$VAULT_DIR/AGENTS.md"
      echo "  [+] AGENTS.md"
    fi

    # Install skills into vault/.codex/skills/
    install_skills "$VAULT_DIR" ".codex"
  fi
  echo ""
}

# --- Run setup for each detected agent ---

for agent in "${AGENTS[@]}"; do
  "setup_$agent"
done

# --- Done ---

echo "=== Done ==="
echo ""

if [ "$MODE" = "integrated" ]; then
  echo "Vault created at: .vault/ (gitignored — per-user local data)"
  echo "Hooks registered at: $CONFIG_DIR/"
  echo ""
  echo "Next steps:"
  echo "  cd $PROJECT_DIR"
  for agent in "${AGENTS[@]}"; do
    case $agent in
      claude) echo "  claude                  # hooks + vault work out of the box" ;;
      codex)  echo "  codex                   # hooks + vault work out of the box" ;;
    esac
  done
else
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
fi

echo ""
echo "  Fill in brain/North Star.md with your goals, then start talking."
