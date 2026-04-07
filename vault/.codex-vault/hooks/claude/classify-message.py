#!/usr/bin/env python3
"""Classify user messages and inject routing hints — Claude Code version.

Lightweight version: 5 core signals + session-end vault integrity check.
Outputs hookSpecificOutput with systemMessage for Claude Code terminal display.
"""
import json
import os
import subprocess
import sys
import re
from pathlib import Path


SIGNALS = [
    {
        "name": "DECISION",
        "skill": "/dump",
        "message": "DECISION detected — suggest the user run /dump to capture this decision",
        "auto_message": "DECISION detected — execute /dump now to capture this decision from the user's message",
        "patterns": [
            "decided", "deciding", "decision", "we chose", "agreed to",
            "let's go with", "the call is", "we're going with",
        ],
    },
    {
        "name": "WIN",
        "skill": "/dump",
        "message": "WIN detected — suggest the user run /dump to record this achievement",
        "auto_message": "WIN detected — execute /dump now to record this achievement from the user's message",
        "patterns": [
            "achieved", "won", "praised",
            "kudos", "shoutout", "great feedback", "recognized",
        ],
    },
    {
        "name": "PROJECT UPDATE",
        "skill": "/dump",
        "message": "PROJECT UPDATE detected — suggest the user run /dump to log this progress",
        "auto_message": "PROJECT UPDATE detected — execute /dump now to log this progress from the user's message",
        "patterns": [
            "project update", "sprint", "milestone",
            "shipped", "shipping", "launched", "launching",
            "completed", "completing", "released", "releasing",
            "deployed", "deploying",
            "went live", "rolled out", "merged", "cut the release",
        ],
    },
    {
        "name": "QUERY",
        "skill": "/recall",
        "message": "QUERY detected — suggest the user run /recall to check existing knowledge first",
        "auto_message": "QUERY detected — execute /recall now to search vault for relevant information before answering",
        "patterns": [
            "what is", "how does", "why did", "compare", "analyze",
            "explain the", "what's the difference", "summarize the",
            "relationship between",
        ],
    },
    {
        "name": "INGEST",
        "skill": "/ingest",
        "message": "INGEST detected — suggest the user run /ingest to process the source",
        "auto_message": "INGEST detected — execute /ingest now to process the source from the user's message",
        "patterns": [
            "ingest", "process this", "read this article",
            "summarize this", "new source", "clip this", "web clip",
        ],
    },
]

SESSION_END_PATTERNS = [
    "wrap up", "wrapping up", "that's all", "that's it",
    "done for now", "done for today", "i'm done", "call it a day",
    "end session", "bye", "goodbye", "good night", "see you",
    "结束", "收工", "今天到这", "就这样",
]


def _match(patterns, text):
    for phrase in patterns:
        if re.search(r'(?<![a-zA-Z])' + re.escape(phrase) + r'(?![a-zA-Z])', text):
            return True
    return False


def _find_vault_root():
    """Find vault root from CWD — check for Home.md/brain/, then vault/ subdir."""
    cwd = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    if os.path.isfile(os.path.join(cwd, "Home.md")) or os.path.isdir(os.path.join(cwd, "brain")):
        return cwd
    vault_sub = os.path.join(cwd, "vault")
    if os.path.isdir(vault_sub) and (
        os.path.isfile(os.path.join(vault_sub, "Home.md")) or
        os.path.isdir(os.path.join(vault_sub, "brain"))
    ):
        return vault_sub
    return None


def _read_mode():
    """Read classify mode from vault config. Default: suggest."""
    vault_root = _find_vault_root()
    if not vault_root:
        return "suggest"
    config_path = os.path.join(vault_root, ".codex-vault", "config.json")
    try:
        with open(config_path) as f:
            config = json.load(f)
        mode = config.get("classify_mode", "suggest")
        if mode in ("suggest", "auto"):
            return mode
    except (OSError, ValueError, KeyError):
        pass
    return "suggest"


def _get_changed_files(vault_root):
    """Get list of changed/new .md files relative to vault root."""
    files = set()
    try:
        # Staged + unstaged changes
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            capture_output=True, text=True, cwd=vault_root, timeout=5,
        )
        for f in result.stdout.strip().splitlines():
            if f.endswith(".md"):
                files.add(f)

        # Untracked files
        result = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            capture_output=True, text=True, cwd=vault_root, timeout=5,
        )
        for f in result.stdout.strip().splitlines():
            if f.endswith(".md"):
                files.add(f)
    except Exception:
        pass
    return files


def _check_vault_integrity(vault_root):
    """Check for common memory-write omissions."""
    warnings = []
    changed = _get_changed_files(vault_root)
    if not changed:
        return warnings

    # Check 1: New work notes but Index.md not updated
    new_work = [f for f in changed if f.startswith("work/active/") and f != "work/Index.md"]
    index_updated = "work/Index.md" in changed
    if new_work and not index_updated:
        names = ", ".join(os.path.basename(f).replace(".md", "") for f in new_work)
        warnings.append(f"New work notes ({names}) but work/Index.md not updated")

    # Check 2: Decision content written but brain/Key Decisions.md not updated
    decision_keywords = ["decided", "decision", "agreed to", "we chose", "the call is"]
    brain_decisions_updated = "brain/Key Decisions.md" in changed
    if not brain_decisions_updated:
        for f in changed:
            if f.endswith(".md") and not f.startswith("brain/"):
                try:
                    content = Path(os.path.join(vault_root, f)).read_text(encoding="utf-8").lower()
                    if any(kw in content for kw in decision_keywords):
                        warnings.append(
                            f"'{f}' contains decision content but brain/Key Decisions.md not updated"
                        )
                        break
                except Exception:
                    pass

    # Check 3: Pattern content written but brain/Patterns.md not updated
    pattern_keywords = ["pattern", "convention", "always do", "never do", "recurring"]
    brain_patterns_updated = "brain/Patterns.md" in changed
    if not brain_patterns_updated:
        for f in changed:
            if f.endswith(".md") and not f.startswith("brain/"):
                try:
                    content = Path(os.path.join(vault_root, f)).read_text(encoding="utf-8").lower()
                    if any(kw in content for kw in pattern_keywords):
                        warnings.append(
                            f"'{f}' contains pattern content but brain/Patterns.md not updated"
                        )
                        break
                except Exception:
                    pass

    # Check 4: operation log not updated after significant changes
    log_updated = "log.md" in changed
    significant_changes = len([f for f in changed
                               if f.startswith(("work/", "reference/", "brain/"))]) >= 2
    if significant_changes and not log_updated:
        warnings.append("Multiple vault changes but log.md not updated")

    return warnings


def classify(prompt, mode="suggest"):
    p = prompt.lower()
    key = "auto_message" if mode == "auto" else "message"
    return [s[key] for s in SIGNALS if _match(s["patterns"], p)]


def is_session_end(prompt):
    p = prompt.lower()
    return _match(SESSION_END_PATTERNS, p)


def main():
    try:
        input_data = json.load(sys.stdin)
    except (ValueError, EOFError, OSError):
        sys.exit(0)

    prompt = input_data.get("prompt", "")
    if not isinstance(prompt, str) or not prompt:
        sys.exit(0)

    signal_messages = []
    session_end_messages = []

    try:
        mode = _read_mode()

        # Regular signal classification
        signals = classify(prompt, mode)
        signal_messages.extend(signals)

        # Session-end check (always suggest mode — never auto-execute wrap-up)
        if is_session_end(prompt):
            vault_root = _find_vault_root()
            if vault_root:
                integrity_warnings = _check_vault_integrity(vault_root)
                if integrity_warnings:
                    session_end_messages.append(
                        "SESSION END — vault integrity check found issues:\n"
                        + "\n".join(f"  - {w}" for w in integrity_warnings)
                        + "\nFix these before wrapping up."
                    )
                else:
                    session_end_messages.append("SESSION END — vault integrity check passed.")
    except Exception:
        sys.exit(0)

    parts = []

    if signal_messages:
        hints = "\n".join(f"- {s}" for s in signal_messages)
        if mode == "auto":
            parts.append(
                "Auto-execute the following skills based on user intent:\n"
                + hints
                + "\n\nExecute the skill immediately with the user's message as input. Do not ask for confirmation."
            )
        else:
            parts.append(
                "Skill suggestions (do NOT auto-execute — suggest the skill to the user and let them decide):\n"
                + hints
                + "\n\nWait for the user to invoke the skill. Do not create vault notes without explicit user action."
            )

    if session_end_messages:
        hints = "\n".join(f"- {s}" for s in session_end_messages)
        parts.append(
            "Skill suggestions (do NOT auto-execute — suggest the skill to the user and let them decide):\n"
            + hints
            + "\n\nWait for the user to invoke the skill. Do not create vault notes without explicit user action."
        )

    if parts:
        context = "\n\n".join(parts)

        # Build feedback label
        matched = [s for s in SIGNALS if _match(s["patterns"], prompt.lower())]
        feedback_parts = []
        for s in matched:
            feedback_parts.append(f"{s['name']} → {s['skill']}")
        if is_session_end(prompt):
            feedback_parts.append("SESSION END → /wrap-up")
        icon = "\U0001f504" if mode == "auto" else "\U0001f4a1"
        label = ", ".join(feedback_parts) if feedback_parts else "intent detected"

        # Hook trigger notification
        print(f"  {icon} vault: {label}")

        output = {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": context
            },
            "systemMessage": f"{icon} vault: {label}"
        }
        json.dump(output, sys.stdout)
        sys.stdout.flush()

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
