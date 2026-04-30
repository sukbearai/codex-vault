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

Fill in `.vault/brain/North Star.md` with your goals, then start talking.

> **Integrated mode** (the default when you run `init` inside another project) creates `.vault/` — a hidden, gitignored directory so each developer keeps their own local vault without merge conflicts. **Standalone mode** (inside the codex-vault repo itself) still uses `vault/`.

<details>
<summary>Alternative: install from source</summary>

```bash
git clone https://github.com/sukbearai/codex-vault.git /tmp/codex-vault
bash /tmp/codex-vault/plugin/install.sh
```

> **Standalone mode**: run `install.sh` from inside the codex-vault repo itself to use `vault/` (not `.vault/`) as the working directory.
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

Hooks power the loop:

| Hook | When | What | Claude Code | Codex CLI |
|------|------|------|-------------|-----------|
| **session-start** | Agent starts | Injects North Star goals, recent git changes, active work, vault file listing | SessionStart | SessionStart |
| **classify-message** | Every message | Detects decisions, wins, project updates — hints the agent where to file them | UserPromptSubmit | UserPromptSubmit |
| **validate-write** | After writing `.md` / running Bash | Checks frontmatter and wikilinks (Claude); detects command failures (Codex) | PostToolUse (Write\|Edit) | PostToolUse (Bash) |

## Supported Agents

| Agent | Hooks | Skills | Status |
|-------|-------|--------|--------|
| Claude Code | 3 hooks via `.claude/settings.json` | `/dump` `/recall` `/ingest` `/wrap-up` `/lint` | Full support |
| Codex CLI | 3 hooks via `.codex/hooks.json` | `$dump` `$recall` `$ingest` `$wrap-up` `$lint` | Full support |
| Other | Write an adapter ([docs/adding-an-agent.md](docs/adding-an-agent.md)) | Depends on agent | Community |

## Vault Structure

In integrated mode the vault lives at `.vault/` (hidden, gitignored by default). In standalone mode it lives at `vault/`. The internal layout is the same:

```
.vault/                   (integrated) or vault/ (standalone)
  Home.md                 Entry point — current focus, quick links
  SCHEMA.md               Domain scope, tag taxonomy, page thresholds
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

Eight folders. One schema. Five note types. That's it.

## Skills

User-invoked skills — the agent suggests them, but only executes when you explicitly run one:

| Skill | What It Does |
|-------|-------------|
| `/dump` | Freeform capture — say anything, agent classifies and routes to the right notes |
| `/wrap-up` | End-of-session review — verify notes, update indexes, check links |
| `/ingest` | Process a source document into wiki pages with cross-links |
| `/recall` | On-demand memory retrieval — search the vault for a topic and synthesize |
| `/lint` | Vault health audit — 13 checks for broken links, orphans, stale content, tag drift, and more |

The classify hook detects intent (decision, win, project update, query, ingest) and suggests the right skill. By default, you decide whether to run it (**suggest mode**). Set `{"classify_mode": "auto"}` in `.vault/.codex-vault/config.json` (or `vault/.codex-vault/config.json` in standalone mode) to have the agent execute skills automatically (**auto mode**).

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

**`/lint`** — no arguments needed, runs a full vault health audit.

## Usage Scenarios

See [docs/usage.md](docs/usage.md) — 7 real scenarios from first session to project completion, with exact commands and expected output.

## What's New in v0.8.0

- **`/lint` skill** — 13-check vault health audit: broken links, orphan pages, index completeness, frontmatter validation, stale content, oversized pages, tag audit, log check, index bloat, log rotation, split suggestions, archive integrity, topic map
- **`SCHEMA.md`** — domain scope definition, tag taxonomy (declare-before-use), page thresholds (create/update/split/archive), frontmatter requirements
- **Contradiction tracking** — `contradictions` frontmatter field for bidirectional conflict marking; `/ingest` auto-detects contradictions with existing vault content
- **Batch ingest** — `/ingest` supports multiple sources at once with cross-source deduplication, single search pass, and consolidated index updates
- **Query writeback logic** — `/recall` uses a 4-criteria save / 3-criteria skip decision matrix; `synthesized_from` field tracks source pages
- **Obsidian integration guide** — [docs/obsidian.md](docs/obsidian.md) with Dataview queries, Graph View tips, and recommended settings
- **Pre-read protocol** — all 5 skills start with Step 0 context check (read `work/Index.md` + `SCHEMA.md`)
- **New frontmatter fields** — `type` (work/decision/source-summary/reference/thinking), `sources` (vault paths to source docs), `synthesized_from` (for reference notes)
- **Enhanced hooks** — session-start injects SCHEMA context (tag taxonomy + page thresholds); Claude validate-write checks tag whitelist and type field; Codex validate-write detects Bash command failures
- **`/wrap-up` enhancements** — archive with backlink migration, lint recommendation after 3+ note sessions
- **11 Pitfalls checklist** — common anti-patterns to avoid (in `plugin/instructions.md` and `vault/CLAUDE.md`)
- **5 template overhauls** — all templates include content structure guidance and new frontmatter fields

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
| Auto-execute skills | Set `{"classify_mode": "auto"}` in `.vault/.codex-vault/config.json` (or `vault/.codex-vault/config.json` in standalone) |
| New agent | Add hooks and skills in `plugin/` ([guide](docs/adding-an-agent.md)) |

## CLI

```bash
npx @suwujs/codex-vault init        # Install .vault/ + hooks into current project
npx @suwujs/codex-vault upgrade     # Upgrade hooks and skills (preserves vault data)
npx @suwujs/codex-vault uninstall   # Remove hooks and skills (preserves vault data)
npx @suwujs/codex-vault doctor      # Diagnose git conflicts from agent configs
npx @suwujs/codex-vault doctor --fix  # Auto-fix: gitignore, untrack, migrate vault/→.vault/
# init adds .vault/, .claude/, .codex/ to .gitignore automatically — each developer gets their own local vault.
```

### Fixing Git Conflicts in Teams

If `.claude/`, `.codex/`, or `vault/` files are already committed and causing merge conflicts:

```bash
# Diagnose (no changes made)
npx @suwujs/codex-vault doctor

# Auto-fix and commit
npx @suwujs/codex-vault doctor --fix
```

What `doctor --fix` does:

| Check | Issue | Fix |
|-------|-------|-----|
| gitignore | `.vault/` `.claude/` `.codex/` not in `.gitignore` | Append entries |
| tracked files | Agent files already committed to git | `git rm --cached` (removes from index, keeps local files) |
| vault migration | Legacy `vault/` should be `.vault/` | Rename + clean stale configs |
| codex-mem rename | Old `.codex-mem/` directory | Rename to `.codex-vault/` |
| stale configs | `.claude/` `.codex/` inside `.vault/` | Remove (should be at project root) |
| conflict markers | `<<<<<<<` in config files | Reports for manual resolution |
| broken JSON | Parse errors in settings/hooks | Reports, suggests `init` to regenerate |

No upgrade needed — `npx` always runs the latest version.

After fixing, each team member runs `npx @suwujs/codex-vault init` to get their own local agent configs.

## Testing

```bash
npm test                # Full E2E test suite
npm run test:cli        # CLI commands only (22 tests)
npm run test:hooks      # Hook scripts only (33 tests)
```

### Release

Publishing is handled by GitHub Actions. Add an npm automation token as the repository secret `NPM_TOKEN`, bump `package.json`, then push a matching version tag:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

## Requirements

- Git
- Python 3
- Node.js >= 18 (for CLI)
- One of: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex)
- Optional: [Obsidian](https://obsidian.md) (for graph view, backlinks, visual browsing)

## Inspired By

- [llm-wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) by Karpathy — the pattern

## License

MIT
