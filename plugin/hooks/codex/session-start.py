#!/usr/bin/env python3
"""Session-start hook for Codex CLI — injects vault context into the agent's prompt.

Outputs structured JSON: additionalContext for LLM.
Banner is written to stderr (Codex CLI does not render systemMessage).

Dynamic context: adapts git log window, reads full North Star,
shows all active work, and includes uncommitted changes.
"""
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path


def _find_vault_root():
    """Find vault root from CWD — check for Home.md/brain/, then vault/ subdir."""
    cwd = os.environ.get("CODEX_PROJECT_DIR", os.getcwd())
    if os.path.isfile(os.path.join(cwd, "Home.md")) or os.path.isdir(os.path.join(cwd, "brain")):
        return cwd
    vault_sub = os.path.join(cwd, "vault")
    if os.path.isdir(vault_sub) and (
        os.path.isfile(os.path.join(vault_sub, "Home.md")) or
        os.path.isdir(os.path.join(vault_sub, "brain"))
    ):
        return vault_sub
    return None


def _run_git(args, cwd, timeout=5):
    """Run git command and return stdout lines."""
    try:
        result = subprocess.run(
            ["git"] + args,
            capture_output=True, text=True, cwd=cwd, timeout=timeout,
        )
        return result.stdout.strip().splitlines() if result.stdout.strip() else []
    except Exception:
        return []


def _git_log_oneline(cwd, since=None, max_count=None):
    """Get git log --oneline entries."""
    args = ["log", "--oneline", "--no-merges"]
    if since:
        args.append(f"--since={since}")
    if max_count:
        args.extend(["-n", str(max_count)])
    return _run_git(args, cwd)


def _git_status_short(cwd):
    """Get git status --short output."""
    return _run_git(["status", "--short", "--", "."], cwd)


def _read_file(path):
    """Read file content, return empty string on error."""
    try:
        return Path(path).read_text(encoding="utf-8")
    except Exception:
        return ""


def _find_md_files(vault_dir):
    """Find all .md files in vault, excluding non-vault directories."""
    exclude = {".git", ".obsidian", "thinking", ".claude", ".codex",
               ".codex-vault", ".codex-mem", "node_modules"}
    files = []
    for root, dirs, filenames in os.walk(vault_dir):
        dirs[:] = [d for d in dirs if d not in exclude]
        for f in filenames:
            if f.endswith(".md"):
                rel = os.path.relpath(os.path.join(root, f), vault_dir)
                files.append(f"./{rel}")
    return sorted(files)


def _folder_summary(all_files):
    """Generate folder summary with file counts."""
    folders = Counter()
    for f in all_files:
        parts = f[2:].split("/")  # strip ./
        folders[parts[0] if len(parts) > 1 else "."] += 1
    return [f"  {folder}/ ({count} files)"
            for folder, count in folders.most_common()]


def _key_files(all_files):
    """Filter for key vault files."""
    pattern = re.compile(
        r"(Home|Index|North Star|Memories|Key Decisions|Patterns|log)\.md$")
    return [f for f in all_files if pattern.search(f)]


def _mtime_ok(vault_dir, rel_path, cutoff):
    """Check if file was modified after cutoff timestamp."""
    try:
        return os.path.getmtime(os.path.join(vault_dir, rel_path.lstrip("./"))) > cutoff
    except Exception:
        return False


def _north_star_goal(vault_dir):
    """Extract first goal from North Star for banner display."""
    ns_path = os.path.join(vault_dir, "brain", "North Star.md")
    if not os.path.isfile(ns_path):
        return None
    content = _read_file(ns_path)
    in_focus = False
    for line in content.splitlines():
        if re.match(r"^## Current Focus", line):
            in_focus = True
            continue
        if in_focus and line.startswith("## "):
            break
        if in_focus and re.match(r"^- .+", line):
            goal = line[2:].strip()
            return goal[:40] if goal else None
    return None


# ── Context builder (→ additionalContext for LLM) ──────────────────────


def _build_context(vault_dir):
    lines = []
    lines.append("## Session Context")
    lines.append("")

    # Date
    lines.append("### Date")
    now = datetime.now()
    lines.append(f"{now.strftime('%Y-%m-%d')} ({now.strftime('%A')})")
    lines.append("")

    # North Star — full file
    lines.append("### North Star")
    ns_path = os.path.join(vault_dir, "brain", "North Star.md")
    if os.path.isfile(ns_path):
        lines.append(_read_file(ns_path))
    else:
        lines.append("(No North Star found — create brain/North Star.md to set goals)")
    lines.append("")

    # Recent changes — adaptive window
    lines.append("### Recent Changes")
    commits_48h = _git_log_oneline(vault_dir, since="48 hours ago")
    if commits_48h:
        lines.append("(last 48 hours)")
        lines.extend(commits_48h[:15])
    else:
        commits_7d = _git_log_oneline(vault_dir, since="7 days ago")
        if commits_7d:
            lines.append("(nothing in 48h — showing last 7 days)")
            lines.extend(commits_7d[:15])
        else:
            lines.append("(nothing recent — showing last 5 commits)")
            commits = _git_log_oneline(vault_dir, max_count=5)
            lines.extend(commits if commits else ["(no git history)"])
    lines.append("")

    # Recent operations from log.md
    lines.append("### Recent Operations")
    log_path = os.path.join(vault_dir, "log.md")
    if os.path.isfile(log_path):
        entries = [l for l in _read_file(log_path).splitlines()
                   if l.startswith("## [")]
        lines.extend(entries[-5:] if entries else ["(no entries in log.md)"])
    else:
        lines.append("(no log.md)")
    lines.append("")

    # Active work
    lines.append("### Active Work")
    active_dir = os.path.join(vault_dir, "work", "active")
    if os.path.isdir(active_dir):
        work_files = sorted(f for f in os.listdir(active_dir) if f.endswith(".md"))
        if work_files:
            for f in work_files:
                lines.append(f.replace(".md", ""))
        else:
            lines.append("(none)")
    else:
        lines.append("(no work/active/ directory)")
    lines.append("")

    # Uncommitted changes
    lines.append("### Uncommitted Changes")
    changes = _git_status_short(vault_dir)
    lines.extend(changes[:20] if changes else ["(working tree clean)"])
    lines.append("")

    # Recently modified brain files
    lines.append("### Recently Modified Brain Files")
    brain_dir = os.path.join(vault_dir, "brain")
    if os.path.isdir(brain_dir):
        cutoff = datetime.now().timestamp() - 7 * 86400
        recent = sorted(
            f.replace(".md", "")
            for f in os.listdir(brain_dir)
            if f.endswith(".md") and os.path.getmtime(os.path.join(brain_dir, f)) > cutoff
        )
        if recent:
            lines.append("(modified in last 7 days)")
            lines.extend(recent)
        else:
            lines.append("(no recent changes)")
    lines.append("")

    # Vault file listing — tiered
    lines.append("### Vault Files")
    all_files = _find_md_files(vault_dir)
    n = len(all_files)

    if n <= 20:
        lines.extend(all_files)

    elif n <= 50:
        hot = [f for f in all_files
               if not re.match(r"\./sources/|\./work/archive/", f)]
        cold = n - len(hot)
        lines.extend(hot)
        if cold > 0:
            lines.append("")
            lines.append(f"(+ {cold} files in sources/ and work/archive/ — use /recall to search)")

    elif n <= 150:
        lines.append(f"({n} files — showing summary)")
        lines.append("")
        lines.extend(_folder_summary(all_files))
        lines.append("")
        lines.append("Recently modified (7 days):")
        cutoff = datetime.now().timestamp() - 7 * 86400
        recent = [f for f in all_files if _mtime_ok(vault_dir, f, cutoff)]
        lines.extend(recent if recent else ["  (none)"])
        lines.append("")
        lines.append("Key files:")
        lines.extend(_key_files(all_files))

    else:
        lines.append(f"({n} files — showing summary)")
        lines.append("")
        lines.extend(_folder_summary(all_files))
        lines.append("")
        lines.append("Recently modified (3 days):")
        cutoff = datetime.now().timestamp() - 3 * 86400
        recent = [f for f in all_files if _mtime_ok(vault_dir, f, cutoff)]
        lines.extend(recent if recent else ["  (none)"])
        lines.append("")
        lines.append("Key files:")
        lines.extend(_key_files(all_files))
        lines.append("")
        lines.append("Use /recall <topic> to search the vault.")

    return "\n".join(lines)


# ── ANSI colors (oh-my-codex style) ──────────────────────────────────

RESET = "\x1b[0m"
BOLD = "\x1b[1m"
DIM = "\x1b[2m"
CYAN = "\x1b[36m"
GREEN = "\x1b[32m"
YELLOW = "\x1b[33m"
SEP = f" {DIM}|{RESET} "


def _c(code, text):
    return f"{code}{text}{RESET}"


# ── Banner builder (→ stderr for terminal) ────────────────────────────


def _build_banner(vault_dir):
    # --- Line 1: statusline ---
    elements = []

    # Git branch
    branch = _run_git(["rev-parse", "--abbrev-ref", "HEAD"], vault_dir)
    if branch:
        elements.append(_c(CYAN, branch[0]))

    # North Star goal
    goal = _north_star_goal(vault_dir)
    if goal:
        elements.append(f"\U0001f3af {goal}")
    else:
        elements.append(_c(DIM, "\U0001f3af no goal set"))

    # Active work
    active_dir = os.path.join(vault_dir, "work", "active")
    work_files = sorted(
        f.replace(".md", "")
        for f in os.listdir(active_dir) if f.endswith(".md")
    ) if os.path.isdir(active_dir) else []
    if work_files:
        names = ", ".join(work_files[:3])
        suffix = f" +{len(work_files) - 3}" if len(work_files) > 3 else ""
        elements.append(_c(GREEN, f"active:{len(work_files)}") + _c(DIM, f" {names}{suffix}"))
    else:
        elements.append(_c(DIM, "active:0"))

    # Changes
    changes = _git_status_short(vault_dir)
    if changes:
        elements.append(_c(YELLOW, f"changes:{len(changes)}"))
    else:
        elements.append(_c(GREEN, "clean"))

    label = _c(BOLD, "[Vault]")
    statusline = label + " " + SEP.join(elements)

    # --- Line 2+: recent commits ---
    lines = ["", statusline]
    commits = _git_log_oneline(vault_dir, since="7 days ago")
    if not commits:
        commits = _git_log_oneline(vault_dir, max_count=3)
    if commits:
        for c in commits[:3]:
            # hash in cyan, message in dim
            parts = c.split(" ", 1)
            if len(parts) == 2:
                lines.append(f"  {_c(DIM, parts[0])} {_c(DIM, parts[1])}")
            else:
                lines.append(f"  {_c(DIM, c)}")

    # --- Line: vault file count ---
    all_files = _find_md_files(vault_dir)
    lines.append(_c(DIM, f"  {len(all_files)} notes"))
    lines.append("")

    return "\n".join(lines)


# ── Main ───────────────────────────────────────────────────────────────


def main():
    vault_dir = _find_vault_root()
    if not vault_dir:
        output = {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": "## Session Context\n\n(No vault found)"
            }
        }
        sys.stdout.write(json.dumps(output) + "\n")
        sys.exit(0)

    # Read hook input for session metadata
    try:
        event = json.load(sys.stdin)
    except Exception:
        event = {}

    context = _build_context(vault_dir)

    # hookSpecificOutput + additionalContext → injected into LLM context
    output = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": context
        }
    }
    sys.stdout.write(json.dumps(output) + "\n")
    sys.stdout.flush()
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Never block session start
        sys.exit(0)
