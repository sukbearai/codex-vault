# Adding an Agent Adapter

Codex-Vault is agent-agnostic. The `plugin/` directory contains shared hooks and instructions. Each agent needs an **adapter** that wires the hooks into the agent's configuration format.

## What You Need

1. **Hooks configuration** — tell the agent to run the 3 hook scripts at the right lifecycle events
2. **Instructions file** — give the agent the vault conventions (from `plugin/instructions.md`)
3. **(Optional) Commands** — if the agent supports custom commands/slash commands

## Hook Events

Codex-Vault uses 3 lifecycle events. Map them to your agent's equivalent:

| Codex-Vault Event | When | Claude Code Script | Codex CLI Script |
|-----------|------|--------|--------|
| SessionStart | Agent starts or resumes | `plugin/hooks/claude/session-start.py` | `plugin/hooks/codex/session-start.py` |
| UserPromptSubmit | User sends a message | `plugin/hooks/claude/classify-message.py` | `plugin/hooks/codex/classify-message.py` |
| PostToolUse (Write/Edit) | Agent writes a file | `plugin/hooks/claude/validate-write.py` | *(not supported — Codex only fires PostToolUse for Bash)* |

Each agent has its own hook scripts under `plugin/hooks/{claude,codex}/`. The scripts share the same core logic but differ in output format:
- **Claude Code**: uses `systemMessage` in JSON for terminal display
- **Codex CLI**: uses stderr for terminal feedback (Codex TUI doesn't render systemMessage)

All scripts read JSON from stdin and output JSON to stdout via the `hookSpecificOutput` protocol.

### Input (stdin)

**SessionStart**: `{ "session_id": "...", "cwd": "..." }`

**UserPromptSubmit**: `{ "session_id": "...", "prompt": "user's message" }`

**PostToolUse**: `{ "session_id": "...", "tool_name": "Write", "tool_input": { "file_path": "/path/to/file.md" } }`

### Output (stdout)

All hooks output JSON with the `hookSpecificOutput` protocol:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Text injected into the agent's context"
  }
}
```

Empty stdout or exit code 0 with no output = no hints to inject.

### Stderr (user feedback)

All hooks print brief status to stderr for user feedback (visible when running hooks manually or in verbose mode). This is informational only — agents may or may not pass stderr through to the terminal.

## Example: Adding a New Agent

Say you want to add support for `myagent`:

1. The shared hooks live in `plugin/hooks/`, skills in `plugin/skills/`
2. Create the hooks config file in whatever format `myagent` expects
3. Point each hook to the shared scripts in `plugin/hooks/`
4. Add a `setup_myagent` function in `plugin/install.sh` that installs hooks, skills, and instructions
5. Submit a PR

## Testing

After setup, verify:

1. Start the agent in the vault directory
2. Check that session context is injected (North Star, active work, etc.)
3. Say "I decided to use PostgreSQL" — check that a DECISION hint appears
4. Create a note — check that validate-write checks frontmatter
