---
name: wrap-up
description: "End-of-session wrap-up — commits changes, updates indexes, captures decisions made. Triggers: 'wrap up', 'end session', 'save progress', 'commit and close', 'done for today'."
license: MIT
metadata:
  author: sukbearai
  version: "1.0.0"
  homepage: "https://github.com/sukbearai/codex-mem"
---

Session wrap-up. Review what was done and leave the vault clean.

### 1. Review
Scan the conversation for notes created or modified. List them all.

### 2. Verify Quality
For each note: frontmatter complete? At least one [[wikilink]]? Correct folder?

### 3. Check Indexes
- `work/Index.md` — new notes linked? Completed projects moved?
- `brain/Memories.md` — Recent Context updated?
- `brain/Key Decisions.md` — new decisions captured?
- `brain/Patterns.md` — new patterns observed?

### 4. Check for Orphans
Any new notes not linked from at least one other note?

### 5. Archive Check
Notes in `work/active/` that should move to `work/archive/`?

### 6. Report
- **Done**: what was captured
- **Fixed**: issues resolved
- **Flagged**: needs user input
- **Suggested**: improvements for next time
