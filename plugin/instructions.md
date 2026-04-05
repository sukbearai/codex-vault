# Loom — Core Instructions

A structured knowledge vault maintained by an LLM agent. You write notes, maintain links, and keep indexes current. The human curates sources, directs analysis, and asks questions.

## Vault Structure

| Folder | Purpose |
|--------|---------|
| `Home.md` | Vault entry point — quick links, current focus |
| `brain/` | Persistent memory — goals, decisions, patterns |
| `work/` | Work notes index (`Index.md`) |
| `work/active/` | Current projects (move to archive when done) |
| `work/archive/` | Completed work |
| `templates/` | Note templates with YAML frontmatter |
| `thinking/` | Scratchpad — promote findings, then delete |

## Session Lifecycle

### Start

The SessionStart hook injects: North Star goals, recent git changes, active work, vault file listing. You start with context, not a blank slate.

### Work

1. Classify what the user says (the hook helps with hints)
2. Search before creating — check if a related note exists
3. Create or update the right note with proper frontmatter and wikilinks
4. Update `work/Index.md` if a new note was created

### End

When the user says "wrap up" or similar:
1. Verify new notes have frontmatter and wikilinks
2. Update `work/Index.md` with any new or completed notes
3. Archive completed projects: move from `work/active/` to `work/archive/`
4. Check if `brain/` notes need updating with new decisions or patterns

## Creating Notes

1. **Always use YAML frontmatter**: `date`, `description` (~150 chars), `tags`
2. **Use templates** from `templates/`
3. **Place files correctly**: active work in `work/active/`, completed in `work/archive/`, drafts in `thinking/`
4. **Name files descriptively** — use the note title as filename

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

## Memory System

All persistent memory lives in `brain/`:

| File | Stores |
|------|--------|
| `North Star.md` | Goals and focus areas — read every session |
| `Memories.md` | Index of memory topics |
| `Key Decisions.md` | Decisions worth recalling across sessions |
| `Patterns.md` | Recurring patterns discovered across work |

When asked to "remember" something: write to the appropriate `brain/` file with a wikilink to context.

## Rules

- Preserve existing frontmatter when editing notes
- Always check for and suggest connections between notes
- Every note must have a `description` field (~150 chars)
- When reorganizing, never delete without user confirmation
- Use `[[wikilinks]]` not markdown links
