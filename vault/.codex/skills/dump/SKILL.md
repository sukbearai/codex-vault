---
name: dump
description: "Freeform capture — dump anything (notes, ideas, decisions, links) and it gets classified and routed to the right vault location. Triggers: 'dump this', 'capture', 'save this thought', 'note this down', 'remember this', 'jot down'."
license: MIT
metadata:
  author: sukbearai
  version: "1.0.0"
  homepage: "https://github.com/sukbearai/codex-mem"
---

Process the following freeform dump. For each distinct piece of information:

1. **Classify** it: decision, project update, win/achievement, or general work note.
2. **Search first**: Check if a related note already exists. Prefer updating over creating.
3. **Create or update** the appropriate note:
   - Correct folder (work/active/, brain/, etc.)
   - Full YAML frontmatter (date, description, tags)
   - All relevant [[wikilinks]]
4. **Update indexes**: `work/Index.md`, `brain/` notes as needed.
5. **Cross-link**: Every new note links to at least one existing note.

After processing, summarize:
- What was captured and where
- New notes created (with paths)
- Existing notes updated
- Anything unclear (ask the user)

Content to process:
$ARGUMENTS
