# Loom

> A knowledge vault that works with any LLM agent.
> Your notes, your git, your data.

## The Problem

LLM agents forget everything between sessions. You re-explain the same context, lose decisions made three conversations ago, and the knowledge never compounds.

## The Solution

A structured vault + 3 hooks that give your agent persistent memory. Works with **Claude Code** and **Codex CLI**. Just markdown and git.

```
You: "start session"
Agent: *reads North Star, checks active projects, scans recent changes*
Agent: "You're working on the API redesign. Last session you decided
        to split the coordinator pattern. There's an open question
        about error handling."
```

## 30-Second Start

```bash
git clone https://github.com/nicefacer/loom.git
cd loom
bash plugin/install.sh          # detects your agent, generates config
cd vault
claude                          # or: codex
```

Fill in `brain/North Star.md` with your goals, then start talking.

## How It Works

```
You speak
    |
    v
classify hook (categorizes: decision? win? project update?)
    |
    v
Agent writes notes (guided by instructions.md)
    |
    v
validate hook (checks: frontmatter? wikilinks? correct folder?)
    |
    v
git commit (persistent)
    |
    v
Next session → session-start hook injects context back
```

Three hooks power the loop:

| Hook | When | What |
|------|------|------|
| **session-start** | Agent starts | Injects North Star goals, recent git changes, active work, vault file listing |
| **classify-message** | Every message | Detects decisions, wins, project updates — hints the agent where to file them |
| **validate-write** | After writing `.md` | Checks frontmatter and wikilinks — catches mistakes before they stick |

## Supported Agents

| Agent | Hooks | Commands | Status |
|-------|-------|----------|--------|
| Claude Code | 3 hooks via `.claude/settings.json` | `/standup` `/dump` `/wrap-up` | Full support |
| Codex CLI | 3 hooks via `.codex/hooks.json` | Natural language (no slash commands) | Full support |
| Other | Write an adapter ([docs/adding-an-agent.md](docs/adding-an-agent.md)) | Depends on agent | Community |

## Vault Structure

```
vault/
  Home.md                 Entry point — current focus, quick links
  brain/
    North Star.md         Goals and focus — read every session
    Memories.md           Memory index
    Key Decisions.md      Decisions worth recalling
    Patterns.md           Recurring patterns
  work/
    Index.md              Map of all work notes
    active/               Current projects
    archive/              Completed work
  templates/              Note templates (Work Note, Decision Record, Thinking Note)
  thinking/               Scratchpad — promote findings, then delete
```

Six folders. Three note types. That's it.

## Commands (Claude Code)

| Command | What It Does |
|---------|-------------|
| `/standup` | Morning kickoff — loads context, reviews yesterday, suggests priorities |
| `/dump` | Freeform capture — say anything, agent routes it to the right notes |
| `/wrap-up` | End-of-session review — verify notes, update indexes, check links |

Codex CLI users: say "start session", "capture this: ...", or "wrap up" in natural language. The hooks handle the rest.

## Design Principles

1. **Data sovereignty** — your markdown, your git, your machine. No cloud lock-in.
2. **Agent-agnostic** — hooks are the universal interface. One vault, multiple agents.
3. **Minimal by default** — 3 hooks, ~80 lines of instructions. Add complexity only when needed.
4. **Graph-first** — folders group by purpose, [[wikilinks]] group by meaning. Links are the primary organization tool.
5. **Future-proof** — if models get built-in memory, the vault still has value as auditable, portable, git-tracked local storage.

## Customization

| What | How |
|------|-----|
| Your goals | Edit `brain/North Star.md` |
| New note types | Add templates to `templates/`, update `plugin/instructions.md` |
| More signals | Add patterns to `plugin/hooks/classify-message.py` |
| New agent | Create an adapter in `adapters/` ([guide](docs/adding-an-agent.md)) |

## Requirements

- Git
- Python 3
- One of: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex)
- Optional: [Obsidian](https://obsidian.md) (for graph view, backlinks, visual browsing)

## Inspired By

- [llm-wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) by Karpathy — the pattern
- [obsidian-mind](https://github.com/nicefacer/obsidian-mind) — full-featured implementation for engineer performance tracking

## License

MIT
