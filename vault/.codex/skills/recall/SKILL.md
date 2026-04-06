---
name: recall
description: "Search vault memory for a topic — finds relevant notes across brain, work, reference, and sources. Triggers: 'recall', 'what do I know about', 'search memory', 'find notes about', 'look up'."
license: MIT
metadata:
  author: sukbearai
  version: "1.0.0"
  homepage: "https://github.com/sukbearai/codex-mem"
---

Search the vault for information about the given topic.

### 1. Parse the Query

Extract the key topic or question from the user's input.

### 2. Search the Vault

Two-pass search — semantic first, keyword fallback:

**Pass 1 — Frontmatter scan (semantic):**
Read the first 5 lines (YAML frontmatter) of every `.md` file in the vault. Use the `description` and `tags` fields to judge relevance semantically — match by meaning, not just keywords. For example, a query about "caching" should match a note with description "Redis selection for session storage".

Scan in priority order:
1. `brain/` — persistent memory
2. `work/active/` — current projects
3. `reference/` — saved analyses
4. `work/archive/` — completed work
5. `sources/` — raw source documents

**Pass 2 — Keyword grep (fallback):**
If Pass 1 finds fewer than 2 relevant files, supplement with a keyword grep across file contents.

### 3. Read Matches

Read the top 3-5 relevant files in full. Prioritize files where the topic appears in:
- The description or tags (strongest signal)
- Headings
- Multiple times in the body

### 4. Synthesize

Present what the vault knows about this topic:
- **Found in**: list the files (as [[wikilinks]])
- **Summary**: synthesize the relevant information across all matches
- **Connections**: note any links between the matched notes
- **Gaps**: flag if the vault has limited or no information on this topic

### 5. Offer Writeback

If the synthesis is substantial (combines 3+ sources), offer to save it as a reference note.

Topic to recall:
$ARGUMENTS
