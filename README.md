# Dossier Project Plan

**Project Status: EXPERIMENTAL**

## Overview

Agents can be briliant wrecking balls if the lack the appropriate context. We can throw a markdown file
into the project root and hope for the best or we can build systems that help agents coordinate, pick
up where they left off, and record insights for future use as they work. 

*That's Dossier*

It's the missing infrastructure layer between your AI agents and sanity: memory, coordination (via tasks and locks), observability.

### Dossier's Focus

| What Dossier Does | What It Doesn't Do |
|-------------------|-------------------|
| Remembers context across sessions | Call LLMs (agents do that) |
| Prevents agents from colliding | Execute code or write files |
| Tracks what happened and what it cost | Orchestrate workflows |
| Works with Claude Code, Cursor, Cline | Replace your agents |
---

## Quick Start (< 5 Minutes)

Five minutes from now, your AI agents will have memory, coordination, and (some) accountability.

Here's how:

```bash
# 1. Clone and start (30 seconds)
git clone https://github.com/MixTapeSoftware/dossier.git
cd dossier
docker compose up -d

# 2. Add to your MCP config (60 seconds)
# ~/.config/claude/claude_desktop_config.json
{
  "mcpServers": {
    "dossier": {
      "command": "mix",
      "args": ["run", "--no-halt"],
      "cwd": "/path/to/dossier"
    }
  }
}

# 3. Restart Claude Code. That's it.
```

**What just changed:**

| Before | After |
|--------|-------|
| Every session starts from zero | Agent remembers everything |
| Multiple agents = file conflicts | Automatic coordination |
| "What did it do?" 🤷 | Full timeline at localhost:3301 |
| Context dies when window fills | `stash` and `pop` — nothing lost |

**Try it now:** Ask Claude to "start a task on the auth module." Watch it automatically check for conflicts, load relevant context, and acquire locks.
