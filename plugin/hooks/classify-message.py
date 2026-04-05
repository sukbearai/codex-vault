#!/usr/bin/env python3
"""Classify user messages and inject routing hints.

Lightweight version: 3 core signals (DECISION, WIN, PROJECT UPDATE).
Agent-agnostic — outputs hookSpecificOutput compatible with both
Claude Code and Codex CLI.
"""
import json
import sys
import re


SIGNALS = [
    {
        "name": "DECISION",
        "message": "DECISION detected — consider creating a Decision Record in work/active/ and logging in work/Index.md",
        "patterns": [
            "decided", "deciding", "decision", "we chose", "agreed to",
            "let's go with", "the call is", "we're going with",
        ],
    },
    {
        "name": "WIN",
        "message": "WIN detected — consider noting this achievement and linking from the work note",
        "patterns": [
            "shipped", "shipping", "launched", "launching",
            "completed", "completing", "released", "releasing",
            "deployed", "deploying", "achieved", "won", "praised",
            "kudos", "shoutout", "great feedback", "recognized",
        ],
    },
    {
        "name": "PROJECT UPDATE",
        "message": "PROJECT UPDATE detected — consider updating the active work note in work/active/",
        "patterns": [
            "project update", "sprint", "milestone",
            "shipped", "launched", "completed", "released", "deployed",
            "went live", "rolled out", "merged", "cut the release",
        ],
    },
]


def _match(patterns, text):
    for phrase in patterns:
        if re.search(r'(?<![a-zA-Z])' + re.escape(phrase) + r'(?![a-zA-Z])', text):
            return True
    return False


def classify(prompt):
    p = prompt.lower()
    return [s["message"] for s in SIGNALS if _match(s["patterns"], p)]


def main():
    try:
        input_data = json.load(sys.stdin)
    except (ValueError, EOFError, OSError):
        sys.exit(0)

    prompt = input_data.get("prompt", "")
    if not isinstance(prompt, str) or not prompt:
        sys.exit(0)

    try:
        signals = classify(prompt)
    except Exception:
        sys.exit(0)

    if signals:
        hints = "\n".join(f"- {s}" for s in signals)
        output = {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": (
                    "Content classification hints:\n"
                    + hints
                    + "\n\nUse proper templates, add [[wikilinks]], follow vault conventions."
                )
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
