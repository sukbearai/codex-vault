# Codex-Vault

[English](README.md) | [中文](README.zh-CN.md)

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
# From your project directory:
npx @suwujs/codex-vault init
claude                                  # or: codex
```

Fill in `vault/brain/North Star.md` with your goals, then start talking.

<details>
<summary>Alternative: install from source</summary>

```bash
git clone https://github.com/sukbearai/codex-vault.git /tmp/codex-vault
bash /tmp/codex-vault/plugin/install.sh
```

> **Standalone mode**: run `install.sh` from inside the codex-vault repo itself to use `vault/` as the working directory.
</details>

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

| Agent | Hooks | Skills | Status |
|-------|-------|--------|--------|
| Claude Code | 3 hooks via `.claude/settings.json` | `/dump` `/recall` `/ingest` `/wrap-up` | Full support |
| Codex CLI | 3 hooks via `.codex/hooks.json` | `$dump` `$recall` `$ingest` `$wrap-up` | Full support |
| Other | Write an adapter ([docs/adding-an-agent.md](docs/adding-an-agent.md)) | Depends on agent | Community |

## Vault Structure

```
vault/
  Home.md                 Entry point — current focus, quick links
  log.md                  Append-only operation log — grep-parseable
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
  sources/                Raw source documents — immutable, LLM reads only
  reference/              Saved answers and analyses from query writeback
```

Eight folders. Five note types. That's it.

## Skills

User-invoked skills — the agent suggests them, but only executes when you explicitly run one:

| Skill | What It Does |
|-------|-------------|
| `/dump` | Freeform capture — say anything, agent classifies and routes to the right notes |
| `/wrap-up` | End-of-session review — verify notes, update indexes, check links |
| `/ingest` | Process a source document into wiki pages with cross-links |
| `/recall` | On-demand memory retrieval — search the vault for a topic and synthesize |

The classify hook detects intent (decision, win, project update, query, ingest) and suggests the right skill. You decide whether to run it — the agent never auto-writes vault notes.

Claude Code uses `/skill-name`, Codex CLI uses `$skill-name`. Both read from their respective `.claude/skills/` and `.codex/skills/` directories.

### Prompt Templates

Copy-paste ready — replace `<>` with your content:

**`/dump`**
```
/dump We decided to use <option A> over <option B> because <reason>
/dump <project> is done. Key outcome: <what was achieved>
/dump Pattern noticed: <description>
/dump Remember: <anything you want the agent to recall next session>
```

**`/recall`**
```
/recall <keyword>
/recall how did we decide on <topic>
/recall <project> progress
```

**`/ingest`**
```
/ingest <URL>
/ingest sources/<filename>.md
```

**`/wrap-up`** — no arguments needed, the agent scans the session automatically.

## Usage Scenarios

See [docs/usage.md](docs/usage.md) — 7 real scenarios from first session to project completion, with exact commands and expected output.

## Design Principles

1. **Data sovereignty** — your markdown, your git, your machine. No cloud lock-in.
2. **Agent-agnostic** — hooks are the universal interface. One vault, multiple agents.
3. **Minimal by default** — 3 hooks, ~100 lines of instructions. Add complexity only when needed.
4. **Graph-first** — folders group by purpose, [[wikilinks]] group by meaning. Links are the primary organization tool.
5. **Future-proof** — if models get built-in memory, the vault still has value as auditable, portable, git-tracked local storage.

## Customization

| What | How |
|------|-----|
| Your goals | Edit `brain/North Star.md` |
| New note types | Add templates to `templates/`, update `plugin/instructions.md` |
| More signals | Add patterns to `plugin/hooks/classify-message.py` |
| New agent | Add hooks and skills in `plugin/` ([guide](docs/adding-an-agent.md)) |

## Requirements

- Git
- Python 3
- One of: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex)
- Optional: [Obsidian](https://obsidian.md) (for graph view, backlinks, visual browsing)

## Inspired By

- [llm-wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) by Karpathy — the pattern

## License

MIT
