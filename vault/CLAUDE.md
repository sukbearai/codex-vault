# Codex-Vault — Core Instructions

A structured knowledge vault maintained by an LLM agent. You write notes, maintain links, and keep indexes current. The human curates sources, directs analysis, and asks questions.

**The vault (.vault/ or vault/) is a managed knowledge base directory.** Do not proactively read vault files — all vault interaction goes through skills (/dump, /recall, /ingest, /lint, /wrap-up). The session-start hook automatically injects the necessary context (North Star, active projects, recent changes). Only read vault files when executing a vault skill.

## Vault Structure

| Folder | Purpose |
|--------|---------|
| `Home.md` | Vault entry point — quick links, current focus |
| `brain/` | Persistent memory — goals, decisions, patterns |
| `work/` | Work notes index (`Index.md`) |
| `work/active/` | Current projects (move to archive when done) |
| `work/archive/` | Completed work |
| `templates/` | Note templates with YAML frontmatter |
| `sources/` | Raw source documents — immutable, LLM reads only |
| `thinking/` | Scratchpad — promote findings, then delete |
| `reference/` | Saved answers and analyses from query writeback |

## Schema

`SCHEMA.md` lives at the vault root and defines domain scope, naming rules, and tag taxonomy. The agent reads this file at session start — its Tag Taxonomy and Page Thresholds are injected into session context automatically.

If a vault has no `SCHEMA.md`, all schema-related features are skipped (backward compatible).

### Tag Taxonomy

All available tags are declared in `SCHEMA.md` under `## Tag Taxonomy`. Rules:

- **Declare before use**: new tags must be added to `SCHEMA.md` before being used in a note's frontmatter
- **Validation**: the validate-write hook warns when a note uses a tag not in the taxonomy (warning only — does not block writes)
- **Format**: each tag is a line `- tagname — description` under the `## Tag Taxonomy` heading

### Page Thresholds

`SCHEMA.md` defines when to create, update, split, or archive pages:

- **Create**: topic appears in 2+ sources, or is a core topic of a single source
- **Update**: prefer updating existing pages over creating new ones when new info relates
- **Split**: pages over 200 lines should be split by subtopic with mutual links
- **Archive**: fully outdated content moves to `work/archive/`

### Contradictions

When new information contradicts existing vault content, use the `contradictions` frontmatter field:

- `contradictions`: a list of page names that hold conflicting information
- Always mark contradictions **bidirectionally** — both pages reference each other
- In the note body, describe the contradiction explicitly with both positions and dates
- Never silently overwrite old information — preserve the conflict for the human to resolve
- The `/ingest` skill includes a contradiction detection step automatically

## Session Lifecycle

### Start

The SessionStart hook injects: North Star goals, schema (tag taxonomy + page thresholds), recent git changes, active work, vault file listing. You start with context, not a blank slate.

### Work

1. The classify hook detects intent and suggests skills — **do not auto-execute**. Suggest the skill to the user and let them decide.
2. Available skills: `/dump`, `/recall`, `/ingest`, `/wrap-up`, `/lint`
3. Search before creating — check if a related note exists (use `/recall <topic>` for targeted vault search)
4. Update `work/Index.md` if a new note was created

### End

When the user says "wrap up" or similar:
1. Verify new notes have frontmatter and wikilinks
2. Update `work/Index.md` with any new or completed notes
3. Archive completed projects: move from `work/active/` to `work/archive/`
4. Check if `brain/` notes need updating with new decisions or patterns

## Creating Notes

1. **Always use YAML frontmatter**: `date`, `description` (~150 chars), `tags`, and optionally `contradictions`
2. **Use templates** from `templates/`
3. **Place files correctly**: active work in `work/active/`, completed in `work/archive/`, source summaries in `work/active/` (tag: `source-summary`), drafts in `thinking/`
4. **Name files descriptively** — use the note title as filename
5. **Tags must be declared** in `SCHEMA.md` Tag Taxonomy before use (if SCHEMA.md exists)

## Linking — Critical

**Graph-first.** Folders group by purpose, links group by meaning. A note lives in one folder but links to many notes.

**A note without links is a bug.** Every new note must link to at least one existing note via `[[wikilinks]]`.

Link syntax:
- `[[Note Title]]` — standard wikilink
- `[[Note Title|display text]]` — aliased
- `[[Note Title#Heading]]` — deep link

### When to Link

- Work note ↔ Decision Record (bidirectional)
- Index → all work notes
- North Star → active projects
- Memories → source notes
- Contradictions → both directions (via frontmatter and inline links)

## Memory System

All persistent memory lives in `brain/`:

| File | Stores |
|------|--------|
| `North Star.md` | Goals and focus areas — read every session |
| `Memories.md` | Index of memory topics |
| `Key Decisions.md` | Decisions worth recalling across sessions |
| `Patterns.md` | Recurring patterns discovered across work |

When asked to "remember" something: write to the appropriate `brain/` file with a wikilink to context.

## Sources & Ingest

`sources/` holds raw source documents (articles, papers, web clips). This is the immutable layer — the agent reads from it but never modifies source files.

- Drop raw files into `sources/` (markdown preferred) or use `/ingest` with a URL
- `/ingest` reads the source, discusses key takeaways, then creates a **Source Summary** in `work/active/` with tag `source-summary`
- Before creating the summary, `/ingest` runs **contradiction detection** — searching existing vault notes for conflicting information
- The summary uses the Source Summary template: Key Takeaways, Summary, Connections, Quotes/Data Points
- Every ingest updates `work/Index.md` (Sources section) and checks for cross-links to existing notes
- If the source contains decisions or patterns, update the relevant `brain/` notes too
- Source summaries link back to the raw source via the `source` frontmatter field

### Bulk Ingest

When multiple sources are provided at once (multiple URLs, multiple files, or a batch of unprocessed files in `sources/`), `/ingest` switches to **batch mode** to avoid redundant work:

- All sources are read before any notes are created
- Entities and concepts are deduplicated across sources — shared topics get higher priority
- The vault is searched once for all entities, not once per source
- `work/Index.md` is updated once after all notes are written, not after each note
- A single log entry records the entire batch operation
- Contradictions between sources and existing vault content are detected in bulk

See the `/ingest` skill for the full 7-step batch flow.

## Operation Log

Append to `log.md` after significant operations: ingests, decisions, project archives, maintenance passes.

- Format: `## [YYYY-MM-DD] <type> | <title>` followed by bullet points
- Types: `ingest`, `session`, `query`, `maintenance`, `decision`, `archive`
- Don't log every small edit — only operations that change the vault's knowledge state
- Entries are append-only; never edit or delete previous entries

## Query Writeback

When `/recall` synthesizes an answer from multiple vault notes, it evaluates whether the answer is worth persisting as a reference note.

**Decision criteria** (save when any one is met):
- Comparison of 3+ entities, deep synthesis from 5+ pages, novel cross-domain connection, or high reconstruction cost (5+ pages to re-derive)

**Not saved** when the answer is a simple lookup (1-2 pages), redundant with existing content, or ephemeral.

**Reference notes** use the `synthesized_from` frontmatter field — a list of vault page names that were combined to produce the answer. This field enables traceability: you can see which source pages contributed to a synthesized reference.

All recall operations are logged to `log.md` as type `query`, whether or not a reference note is created.

See the `/recall` skill for the full decision matrix.

## Vault Location

The vault may live at the project root, in a `.vault/` subdirectory (default for integrated installs, gitignored), or in a `vault/` subdirectory (legacy/standalone). Use the SessionStart context to determine the actual path. All folder references above (e.g. `brain/`, `work/active/`) are relative to the vault root.

## Rules

- Preserve existing frontmatter when editing notes
- Always check for and suggest connections between notes
- Every note must have a `description` field (~150 chars)
- When reorganizing, never delete without user confirmation
- Use `[[wikilinks]]` not markdown links
- Respect the Tag Taxonomy in `SCHEMA.md` — declare new tags before using them
- Mark contradictions bidirectionally — never silently overwrite conflicting information

## Note Types

The optional `type` frontmatter field classifies notes. Allowed values:

- `work` — work notes / projects
- `decision` — decision records
- `source-summary` — source material summaries
- `reference` — synthesized reference notes
- `thinking` — drafts / temporary ideas

The field is optional for backward compatibility. When present, the validate-write hook warns if the value is not in the allowed list. Templates include the correct `type` value by default.

## Source Traceability

The optional `sources` frontmatter field records vault paths to source documents that informed a note, e.g. `sources: [sources/article-name.md]`. Use this when a note's information comes from raw documents in `sources/`. This complements the existing `source` field (singular) used in Source Summary templates for the primary source URL or filename.

## Archive and Backlink Migration

When archiving a completed page from `work/active/` to `work/archive/`:

1. Move the file
2. Search the vault for all `[[wikilinks]]` referencing it — update paths if needed
3. Move the entry in `work/Index.md` from Active to Archive
4. For fully abandoned pages (not just completed), replace inbound wikilinks with plain text + "(archived)"

## Topic Map

When the vault grows beyond 200 notes, consider creating `_meta/topic-map.md` — a high-level navigation page that groups notes by subject area, providing structure beyond what `work/Index.md` alone can offer. The `/lint` skill suggests this automatically.

## Pre-Read Protocol

Every vault skill begins with a Step 0 context check: confirm session-start context is loaded, and if this is the first vault skill use in the session, read `work/Index.md` and `SCHEMA.md` before proceeding. This ensures the agent always operates with current vault state.


## Pitfalls — 常见错误

以下是 vault 维护中最常见的反模式，务必避免：

1. **不要修改 sources/ 下的文件** — 源材料是不可变的。修正和补充写在 wiki 笔记中。
2. **不要跳过上下文确认** — 每次操作前确认 session-start 已注入 vault 上下文。跳过会导致重复创建和遗漏关联。
3. **不要忘记更新 Index 和 log** — 跳过这步会让 vault 退化为一堆散文件。Index 和 log 是导航骨架。
4. **不要为偶然提及创建页面** — 遵守 Page Thresholds：出现在 2+ 个源中或是某源的核心主题才建页。脚注里出现一次不够。
5. **不要创建孤立页面** — 每个笔记至少链接 1 个现有页面。孤立页面等于不存在。
6. **不要省略 frontmatter** — date、tags、description 是必填项，支撑搜索、过滤和过期检测。
7. **不要使用未声明的 tag** — 自由标签会退化为噪音。新 tag 先加到 SCHEMA.md 的 Tag Taxonomy。
8. **不要让页面超过 200 行** — 保持 30 秒可读。超过的拆分为子主题页面并互相链接。
9. **不要批量更新 10+ 页面前不确认** — 如果一次 ingest 要改 10+ 个现有页面，先和用户确认范围。
10. **不要静默覆盖矛盾信息** — 标注双方立场和日期，在 frontmatter 标记 contradictions，交给用户判断。
11. **不要忘记 log 轮转** — log.md 超过 500 条时，重命名为 `log-YYYY.md` 并新建空 log.md。
