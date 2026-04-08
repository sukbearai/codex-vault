---
name: recall
description: "Query the vault knowledge graph — navigate compiled knowledge via index and wikilinks, not brute-force search. Triggers: 'recall', 'what do I know about', 'search memory', 'find notes about', 'look up'."
license: MIT
metadata:
  author: sukbearai
  version: "2.0.0"
  homepage: "https://github.com/sukbearai/codex-vault"
---

Query the vault's compiled knowledge about the given topic.

The vault is a knowledge graph, not a file store. Navigate it — don't grep it.

### Step 0: Orient

Before any search:
1. Read `work/Index.md` — this is the knowledge catalog, your primary navigation tool
2. Read `SCHEMA.md` (if exists) — understand the domain scope and tag taxonomy
3. Scan `brain/Memories.md` — check if this topic has been explicitly remembered

### Step 1: Navigate the Index

Read `work/Index.md` and identify pages relevant to the query by:
- Section headings (Active, Archive, Sources, Reference)
- Note titles and descriptions
- Look for the topic or related concepts in the index entries

This is the **primary discovery mechanism** — the index is a curated catalog, not a raw file listing.

### Step 2: Follow the Graph

For each relevant page found in Step 1:
1. Read the page in full
2. Extract all `[[wikilinks]]` from the page body
3. Follow the most relevant links — read those pages too
4. Repeat one more hop if the topic spans multiple domains

This graph traversal discovers connections that keyword search would miss. A page about "funding rate" might link to [[Key Decisions]] which links to [[Rule B calibration]] — follow the trail.

### Step 3: Targeted Search (supplement, not primary)

Only if Steps 1-2 found fewer than 2 relevant pages, supplement with:

**Frontmatter scan:** Check `description` and `tags` fields across vault files. Match semantically — "caching" should match "Redis selection for session storage".

**Keyword grep:** Search file contents for the query terms. This is the last resort, not the first.

Priority order for scanning:
1. `brain/` — persistent memory (always check)
2. `work/active/` — current projects
3. `reference/` — saved analyses
4. `work/archive/` — completed work
5. `sources/` — raw source documents

### Step 4: Synthesize

Present what the vault knows, citing the knowledge graph:
- **Found in**: list the pages as [[wikilinks]]
- **Path**: show how you navigated (Index → Page A → [[link]] → Page B)
- **Summary**: synthesize the information across all pages
- **Connections**: note relationships between the matched pages (shared tags, mutual links, contradictions)
- **Gaps**: flag if the vault has limited or no coverage — suggest what to `/ingest`

### Step 5: Writeback Decision

Evaluate whether the answer is worth saving as a reference note.

**Save** (create `reference/` note) when any one condition is met:
- Comparison: the answer compares 3+ entities or concepts side-by-side
- Deep synthesis: the answer draws from 5+ vault pages
- Novel connection: the answer reveals a cross-domain link not obvious in any single page
- High reconstruction cost: re-deriving the answer would require reading 5+ pages

**Do not save** when:
- Simple lookup: the answer comes directly from 1-2 pages with no synthesis
- Redundant: the answer largely duplicates an existing page
- Ephemeral: the question is one-off and the answer will not be reused

**When saving:**
1. Create a reference note in `reference/` using the Reference Note template
2. Fill `synthesized_from` in frontmatter with the list of vault pages used
3. In related work notes, add a [[wikilink]] to the new reference note under `## Related`
4. Update `work/Index.md` under the `## Reference` section
5. Append to `log.md`: `## [YYYY-MM-DD] query | <question summary> → saved to reference/<note>`

**When not saving:**
- Append to `log.md`: `## [YYYY-MM-DD] query | <question summary> → answered inline`

Topic to recall:
$ARGUMENTS
