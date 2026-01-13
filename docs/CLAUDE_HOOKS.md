# Claude Hooks for PopStash

Automate context preservation using Claude Code's hooks system. Hooks can trigger PopStash operations at key moments like session end or before context switches.

## Quick Setup

Add to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Before stopping, evaluate if there is meaningful context to preserve. If so: (1) stash any work-in-progress with a descriptive name, (2) record any non-obvious insights discovered about the codebase, (3) document any architectural decisions made. Be concise and skip if this was a trivial session."
          }
        ]
      }
    ]
  }
}
```

## Hook Types

### `Stop` - Session End (Recommended)

Triggers when Claude is about to stop responding. Perfect for ensuring context is preserved.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Summarize this session and stash any important context using PopStash tools."
          }
        ]
      }
    ]
  }
}
```

### `PreToolUse` - Before Tool Execution

Triggers before a tool is called. Useful for auto-recalling context before file operations.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "edit_file|create_file",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check PopStash for any relevant decisions about this area before proceeding using get_decisions or recall."
          }
        ]
      }
    ]
  }
}
```

### `PostToolUse` - After Tool Execution

Triggers after a tool completes. Can react to specific tool usage.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "mcp__pop_stash__decide",
        "hooks": [
          {
            "type": "prompt", 
            "prompt": "A decision was just recorded. Confirm it was saved correctly."
          }
        ]
      }
    ]
  }
}
```

## Recommended Configurations

### Minimal - Auto-Stash on Stop

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "If there is meaningful work in progress, stash it with a descriptive name. If you learned something non-obvious about the codebase, record it as an insight. Only act if there's something valuable to save."
          }
        ]
      }
    ]
  }
}
```

### Standard - Stash + Decisions

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Before ending: (1) Stash any work-in-progress with a descriptive name like 'feature-auth-wip'. (2) Record insights about non-obvious codebase behavior. (3) Document any architectural decisions made. Skip if nothing meaningful to save."
          }
        ]
      }
    ]
  }
}
```

### Full - Context-Aware with Pre-Recall

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "edit_file",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Before editing, briefly check for relevant architectural decisions about this file's area using get_decisions."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Session ending. Preserve context: stash WIP, record insights, document decisions. Be concise and skip if trivial session."
          }
        ]
      }
    ]
  }
}
```

## Tool Matcher Patterns

PopStash tools use the pattern `mcp__pop_stash__<tool>`:

| Tool | Matcher |
|------|---------|
| All PopStash tools | `mcp__pop_stash__.*` |
| stash | `mcp__pop_stash__stash` |
| pop | `mcp__pop_stash__pop` |
| insight | `mcp__pop_stash__insight` |
| recall | `mcp__pop_stash__recall` |
| decide | `mcp__pop_stash__decide` |
| get_decisions | `mcp__pop_stash__get_decisions` |

Use `|` for multiple matchers: `edit_file|create_file`

## Tips

### Keep Prompts Focused

Hook prompts add to the conversation. Keep them concise:

```json
{
  "type": "prompt",
  "prompt": "Stash WIP if meaningful."
}
```

### Use Conditional Logic in Prompts

The AI will naturally skip if there's nothing to do:

```json
{
  "type": "prompt",
  "prompt": "Only if this session had meaningful work: stash context. Otherwise do nothing."
}
```

### Combine with AGENTS.md

Hooks work best alongside AGENTS.md guidance. The hook handles "don't forget to stash" while AGENTS.md guides *what* to stash and *how* to name things.

## Example: Full Project Setup

`.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Session ending. If meaningful work occurred: (1) stash WIP with descriptive name, (2) record non-obvious insights, (3) document decisions. Skip if trivial session."
          }
        ]
      }
    ]
  }
}
```

`.claude/mcp_servers.json`:
```json
{
  "pop_stash": {
    "url": "http://localhost:4001/mcp/YOUR_PROJECT_ID"
  }
}
```

`AGENTS.md` (excerpt):
```markdown
## Memory & Context Management (PopStash)

You have access to PopStash for persistent memory. Hooks will prompt you 
to save context at session end, but proactively stash/insight/decide 
during the session when you discover something valuable.
```

## Limitations

- Hook prompts add to conversation context
- `Stop` hooks only fire on graceful stops, not crashes/timeouts
- Keep prompts brief to avoid bloating context
- Hooks run in sequence; multiple hooks stack their prompts
