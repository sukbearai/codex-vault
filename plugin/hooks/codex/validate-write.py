#!/usr/bin/env python3
"""PostToolUse hook for Codex CLI — Bash command validation.

Checks Bash command output for hard failures (command not found,
permission denied, missing paths) and non-zero exit codes with
informative output. Modeled after oh-my-codex's native PostToolUse.
"""
import json
import re
import sys


HARD_FAILURE_PATTERNS = re.compile(
    r"command not found|permission denied|no such file or directory",
    re.IGNORECASE,
)


def _safe_string(value):
    return value if isinstance(value, str) else ""


def _safe_int(value):
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip().lstrip("-").isdigit():
        return int(value.strip())
    return None


def _parse_tool_response(raw):
    """Try to parse tool_response as JSON dict."""
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                return parsed
        except (ValueError, TypeError):
            pass
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, EOFError, OSError):
        sys.exit(0)

    tool_name = _safe_string(payload.get("tool_name", "")).strip()
    if tool_name != "Bash":
        sys.exit(0)

    # Extract command and response
    tool_input = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    command = _safe_string(tool_input.get("command", "")).strip()

    raw_response = payload.get("tool_response")
    parsed = _parse_tool_response(raw_response)

    exit_code = None
    stdout_text = ""
    stderr_text = ""

    if parsed:
        exit_code = _safe_int(parsed.get("exit_code")) or _safe_int(parsed.get("exitCode"))
        stdout_text = _safe_string(parsed.get("stdout", "")).strip()
        stderr_text = _safe_string(parsed.get("stderr", "")).strip()
    else:
        stdout_text = _safe_string(raw_response).strip()

    combined = f"{stderr_text}\n{stdout_text}".strip()
    if not combined:
        sys.exit(0)

    # Check for hard failures
    if HARD_FAILURE_PATTERNS.search(combined):
        output = {
            "decision": "block",
            "reason": "Bash output indicates a command/setup failure that should be fixed before retrying.",
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": (
                    "Bash reported `command not found`, `permission denied`, or a missing file/path. "
                    "Verify the command, dependency installation, PATH, file permissions, "
                    "and referenced paths before retrying."
                ),
            },
        }
        sys.stdout.write(json.dumps(output) + "\n")
        sys.stdout.flush()
        sys.exit(0)

    # Check for non-zero exit code with informative output
    if exit_code is not None and exit_code != 0 and len(combined) > 0:
        output = {
            "decision": "block",
            "reason": "Bash command returned a non-zero exit code but produced useful output that should be reviewed before retrying.",
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": (
                    "The Bash output appears informative despite the non-zero exit code. "
                    "Review and report the output before retrying instead of assuming the command simply failed."
                ),
            },
        }
        sys.stdout.write(json.dumps(output) + "\n")
        sys.stdout.flush()
        sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
