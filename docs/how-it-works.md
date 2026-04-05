# How Loom Works

## The Core Loop

Loom gives LLM agents persistent memory through a simple loop:

```
Session N: agent reads vault → works with you → writes notes → git commit
Session N+1: agent reads vault (with N's notes) → continues where you left off
```

No databases, no embeddings, no cloud services. Just markdown files and git.

## Three Hooks

The entire automation layer is 3 hook scripts:

### 1. session-start.sh

Runs when the agent starts. Reads the vault and injects context into the agent's prompt:

- **North Star** — your goals (from `brain/North Star.md`)
- **Recent changes** — what happened in the last 48 hours (from `git log`)
- **Active work** — current projects (from `work/active/`)
- **Vault files** — complete file listing so the agent knows what exists

This is the "recall" step — the agent starts with context, not a blank slate.

### 2. classify-message.py

Runs on every user message. Scans for keywords and injects routing hints:

- "We decided to..." → hint: create a Decision Record
- "Shipped the feature" → hint: note the win
- "Sprint update" → hint: update the active work note

The agent is free to ignore hints. They're nudges, not commands.

### 3. validate-write.py

Runs after the agent writes or edits a `.md` file. Checks:

- Has YAML frontmatter? (date, description, tags)
- Has at least one `[[wikilink]]`?
- Is in the right folder?

If something's missing, the agent gets a warning and fixes it.

## The Vault

Six folders, three note types:

- `brain/` — persistent memory (goals, decisions, patterns)
- `work/active/` — current projects
- `work/archive/` — completed projects
- `templates/` — note templates with YAML frontmatter
- `thinking/` — scratchpad (promote findings, then delete)
- `Home.md` — entry point

## Why Markdown + Git

- **Portable** — works with any editor, any agent, any OS
- **Auditable** — `git log` shows exactly what changed and when
- **Durable** — survives agent changes, service shutdowns, API deprecations
- **Composable** — Obsidian for visual browsing, grep for search, git for history

## Why Hooks (Not RAG)

RAG re-derives knowledge from scratch on every query. Loom compiles knowledge once (into structured notes with links) and keeps it current. The agent reads the compiled wiki, not raw chunks.

Hooks are the key mechanism because they're:
- **Agent-agnostic** — Claude Code and Codex CLI both support the same hook protocol
- **Zero infrastructure** — shell scripts, no servers
- **Transparent** — you can read every hook, modify them, add your own
