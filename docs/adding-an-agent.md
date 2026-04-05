# Adding an Agent Adapter

Loom is agent-agnostic. The `plugin/` directory contains shared hooks and instructions. Each agent needs an **adapter** that wires the hooks into the agent's configuration format.

## What You Need

1. **Hooks configuration** — tell the agent to run the 3 hook scripts at the right lifecycle events
2. **Instructions file** — give the agent the vault conventions (from `plugin/instructions.md`)
3. **(Optional) Commands** — if the agent supports custom commands/slash commands

## Hook Events

Loom uses 3 lifecycle events. Map them to your agent's equivalent:

| Loom Event | When | Script |
|-----------|------|--------|
| SessionStart | Agent starts or resumes | `bash plugin/hooks/session-start.sh` |
| UserPromptSubmit | User sends a message | `python3 plugin/hooks/classify-message.py` |
| PostToolUse (Write/Edit) | Agent writes a file | `python3 plugin/hooks/validate-write.py` |

All scripts read JSON from stdin and output JSON to stdout. The input/output schemas follow the Claude Code hook protocol, which Codex CLI also supports.

### Input (stdin)

**SessionStart**: `{ "session_id": "...", "cwd": "..." }`

**UserPromptSubmit**: `{ "session_id": "...", "prompt": "user's message" }`

**PostToolUse**: `{ "session_id": "...", "tool_name": "Write", "tool_input": { "file_path": "/path/to/file.md" } }`

### Output (stdout)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Text injected into the agent's context"
  }
}
```

Empty stdout or exit code 0 with no output = no hints to inject.

## Example: Adding a New Agent

Say you want to add support for `myagent`:

1. Create `adapters/myagent/`
2. Create the hooks config file in whatever format `myagent` expects
3. Point each hook to the shared scripts in `plugin/hooks/`
4. Generate the instructions file from `plugin/instructions.md`
5. Update `plugin/install.sh` to detect `myagent` and run setup
6. Submit a PR

## Testing

After setup, verify:

1. Start the agent in the vault directory
2. Check that session context is injected (North Star, active work, etc.)
3. Say "I decided to use PostgreSQL" — check that a DECISION hint appears
4. Create a note — check that validate-write checks frontmatter
