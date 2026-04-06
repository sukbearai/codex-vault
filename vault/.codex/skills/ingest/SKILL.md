---
name: ingest
description: "Import external content (URLs, files, text) into the vault as structured source notes. Triggers: 'ingest', 'import this', 'save this article', 'add source', 'read and save'."
license: MIT
metadata:
  author: sukbearai
  version: "1.0.0"
  homepage: "https://github.com/sukbearai/codex-mem"
---

Ingest a source into the vault. Follow these steps:

### 1. Locate the Source

The user provides either:
- A filename in `sources/` (e.g., `sources/karpathy-llm-wiki.md`)
- A URL to fetch (use `defuddle parse <url> --md` or `curl` to save to `sources/` first)

If a URL, save the raw content to `sources/` before proceeding — sources are the immutable record.

### 2. Read the Source

Read the full source document. Do not skim — ingestion depends on thorough reading.

### 3. Discuss Key Takeaways

Present the top 3-5 takeaways to the user. Ask:
- Which points are most relevant to current work?
- Any connections to existing vault notes?
- Anything to skip or emphasize?

Wait for user input before proceeding.

### 4. Create a Source Summary

Create a note in `work/active/` using the **Source Summary** template:
- Fill in all YAML frontmatter (date, description, source, tags)
- Write Key Takeaways, Summary, Connections (with [[wikilinks]]), Quotes/Data Points
- The `source` field should reference the file in `sources/` or the original URL

### 5. Update Indexes

- Add the summary to `work/Index.md` under a "Sources" section (create the section if it doesn't exist)
- Update relevant `brain/` notes if the source contains decisions (`Key Decisions.md`), patterns (`Patterns.md`), or context worth remembering (`Memories.md`)

### 6. Cross-Link

Check existing vault notes for connections:
- Do any active projects relate to this source?
- Does the source reinforce or challenge any existing decisions?
- Add [[wikilinks]] in both directions where relevant

### 7. Report

Summarize what was done:
- Source file location
- Summary note created (path)
- Indexes updated
- Cross-links added
- Brain notes updated (if any)

Source to process:
$ARGUMENTS
