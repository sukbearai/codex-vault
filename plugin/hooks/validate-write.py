#!/usr/bin/env python3
"""Post-write validation for vault notes.

Checks frontmatter and wikilinks on any .md file written to the vault.
Agent-agnostic — outputs hookSpecificOutput compatible with both
Claude Code and Codex CLI.
"""
import json
import sys
import os
from pathlib import Path


def main():
    try:
        input_data = json.load(sys.stdin)
    except (ValueError, EOFError, OSError):
        sys.exit(0)

    tool_input = input_data.get("tool_input")
    if not isinstance(tool_input, dict):
        sys.exit(0)

    file_path = tool_input.get("file_path", "")
    if not isinstance(file_path, str) or not file_path:
        sys.exit(0)

    if not file_path.endswith(".md"):
        sys.exit(0)

    normalized = file_path.replace("\\", "/")
    basename = os.path.basename(normalized)

    # Skip non-vault files
    skip_names = {"README.md", "CHANGELOG.md", "CONTRIBUTING.md", "CLAUDE.md", "AGENTS.md", "LICENSE"}
    if basename in skip_names:
        sys.exit(0)
    if basename.startswith("README.") and basename.endswith(".md"):
        sys.exit(0)

    skip_paths = [".claude/", ".codex/", ".mind/", "templates/", "thinking/", "node_modules/", "plugin/", "adapters/", "docs/"]
    if any(skip in normalized for skip in skip_paths):
        sys.exit(0)

    warnings = []

    try:
        content = Path(file_path).read_text(encoding="utf-8")

        if not content.startswith("---"):
            warnings.append("Missing YAML frontmatter")
        else:
            parts = content.split("---", 2)
            if len(parts) >= 3:
                fm = parts[1]
                if "tags:" not in fm:
                    warnings.append("Missing `tags` in frontmatter")
                if "description:" not in fm:
                    warnings.append("Missing `description` in frontmatter (~150 chars)")

        if len(content) > 300 and "[[" not in content:
            warnings.append("No [[wikilinks]] found — every note should link to at least one other note")

    except Exception:
        sys.exit(0)

    if warnings:
        hint_list = "\n".join(f"  - {w}" for w in warnings)
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": f"Vault warnings for `{basename}`:\n{hint_list}\nFix these before moving on."
            }
        }
        json.dump(output, sys.stdout)
        sys.stdout.flush()

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
