# Claude Hooks for PopStash

**⚠️ IMPORTANT: Configure these hooks to ensure agents use PopStash effectively.**

Automate context management using Claude Code's hooks system. Without hooks, agents may forget to recall previous context or preserve their work. These hooks ensure every session starts with relevant context and ends with preserved knowledge.

## Quick Setup (Recommended)

**This configuration is strongly recommended for all PopStash projects.**

Add to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Before starting work, search for relevant architectural decisions and insights about this task using get_decisions and recall."
          }
        ]
      }
    ],
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

### `SessionStart` - Session Beginning (Recommended)

Triggers at the start of a new session. Perfect for loading relevant context before starting work.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Before starting, search for relevant decisions and insights related to this task using recall and get_decisions."
          }
        ]
      }
    ]
  }
}
```

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

### Minimal - Context Recall on Start

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Search for relevant architectural decisions and insights related to this task using get_decisions and recall before starting work."
          }
        ]
      }
    ]
  }
}
```

### Standard - Start with Context + Auto-Stash on Stop

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Before starting, search for relevant decisions and insights about this task area. Use get_decisions to find architectural decisions and recall to find related insights."
          }
        ]
      }
    ],
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

### Full - Context-Aware Throughout Session

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Start by searching for relevant context: (1) Use get_decisions to find architectural decisions about the task area, (2) Use recall to find related insights, (3) Use pop to check for recent work-in-progress stashes."
          }
        ]
      }
    ],
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

### SessionStart Hook Best Practices

The `SessionStart` hook is powerful but should be used carefully:

- **Be specific about the task area**: Instead of "search for everything", prompt the agent to search for context related to the specific task
- **Use semantic search**: The agent can use natural language to find relevant decisions/insights even if they don't know exact keys
- **Balance recall with action**: Don't let context retrieval dominate the session - the prompt should encourage quick, relevant searches
- **Let the agent judge relevance**: Trust the agent to determine which recalled context is actually useful

Good example:
```json
{
  "type": "prompt",
  "prompt": "Briefly search for relevant decisions and insights about this task using get_decisions and recall."
}
```

Too verbose:
```json
{
  "type": "prompt",
  "prompt": "Search for all decisions, then search for all insights, then search for all stashes, then summarize everything you found before starting work."
}
```

### Combine with AGENTS.md

Hooks work best alongside AGENTS.md guidance. The hook handles "don't forget to recall context" while AGENTS.md guides *how* to effectively use that context.

## Example: Full Project Setup

`.claude/settings.json`:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Search for relevant context before starting: (1) Use get_decisions for architectural decisions about this task area, (2) Use recall for related insights, (3) Use pop for recent WIP stashes."
          }
        ]
      }
    ],
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
