# PopStash

Memory and context management for AI agents. Save context, record insights, document decisions—then retrieve them semantically or by exact match.

**Status: Experimental**

**Thesis**: recording and providing access to previous decisions and insights improves agent outcomes. 

It's now common practice to record decisions, insights, plans, outcomes to Markdown files when working with LLM agents. PopStash turns
those files into database records with embeddings that are then used to provide semantic search via TypeSense. This allows for flexible recovery
of context without forcing the entire history into the context window.

We also gain the ability to build tooling around the database and TypeSense index so that humans can evaluate, prune, and augment this data. Teams can connect to the same database, allowing for cross-organizational sharing of insights.

## What It Does

PopStash is an MCP server that gives AI agents persistent memory:

- **Stash/Pop**: Save and retrieve working context when switching tasks
- **Insight/Recall**: Record and search persistent knowledge about your codebase  
- **Decide/Get Decisions**: Document architectural decisions with full history

All retrieval supports both exact matching and semantic search powered by local embeddings.

## Quick Start

### Option A: Docker (Recommended)

No Elixir installation required.

```bash
# 1. Clone and start PopStash
git clone https://github.com/your-org/pop_stash.git
cd pop_stash/service
docker compose up -d

# 2. Run database migrations
docker compose exec app bin/pop_stash eval "PopStash.Release.migrate()"

# 3. Create a project for your codebase
docker compose exec app bin/pop_stash eval 'PopStash.CLI.project_new("My Project")'
# => Created project: abc123

# 4. Install mcp-proxy (for Zed/Claude Desktop - skip if using Claude Code)
uv tool install mcp-proxy      # recommended
# or: pipx install mcp-proxy
# or: pip install mcp-proxy
# or: docker pull ghcr.io/sparfenyuk/mcp-proxy:latest
```

### Option B: Local Development

Requires Elixir 1.18+.

```bash
# 1. Start dependencies (Postgres + Typesense)
docker compose up -d db typesense

# 2. Install dependencies and setup database
mix deps.get
mix ecto.setup

# 3. Start the MCP server
mix run --no-halt

# 4. Create a project for your codebase
mix pop_stash.project.new "My Project"
```

> **Note**: On first boot, the server downloads the embedding model (~90MB). This may take a minute depending on your connection.

## MCP Client Configuration

### Claude Code (direct HTTP)

Add to your workspace's `.claude/mcp_servers.json`:

```json
{
  "pop_stash": {
    "url": "http://localhost:4001/mcp/YOUR_PROJECT_ID"
  }
}
```

#### Auto-Stash with Claude Hooks (Optional)

Use Claude hooks to automatically preserve context at session end. Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "If meaningful work occurred: stash WIP, record insights, document decisions. Be brief."
          }
        ]
      }
    ]
  }
}
```

See [docs/CLAUDE_HOOKS.md](docs/CLAUDE_HOOKS.md) for more hook configurations.

### Zed / Claude Desktop (via mcp-proxy)

Add to your MCP client config:

```json
{
  "mcpServers": {
    "pop_stash": {
      "command": "mcp-proxy",
      "args": [
        "--transport", "streamablehttp",
        "http://localhost:4001/mcp/YOUR_PROJECT_ID"
      ]
    }
  }
}
```

For Claude Desktop on macOS, the config file is at:
`~/Library/Application Support/Claude/claude_desktop_config.json`

For Claude Desktop on Windows:
`%APPDATA%\Claude\claude_desktop_config.json`

### Other MCP Clients

Connect to `http://localhost:4001/mcp/YOUR_PROJECT_ID` via HTTP with JSON-RPC transport. Supports MCP protocol version `2025-03-26`.

## AGENTS.md Integration

The AGENTS.md prompt tells AI agents when and how to use PopStash. Add it to your project's `AGENTS.md` file so agents automatically leverage persistent memory.

<details>
<summary>View the AGENTS.md prompt</summary>

```markdown
## Memory & Context Management (PopStash)

You have access to PopStash, a persistent memory system via MCP. Use it to maintain
context across sessions and preserve important knowledge about this codebase.

### When to Use Each Tool

**`stash` / `pop` - Working Context**
- STASH when: switching tasks, context is getting long, before exploring tangents
- POP when: resuming work, need previous context, starting a related task
- Use short descriptive names like "auth-refactor", "bug-123-investigation"

**`insight` / `recall` - Persistent Knowledge**
- INSIGHT when: you discover something non-obvious about the codebase, learn how
  components interact, find undocumented behavior, identify patterns or conventions
- RECALL when: starting work in an unfamiliar area, before making architectural
  changes, when something "should work" but doesn't
- Good insights: "The auth middleware silently converts guest users to anonymous
  sessions", "API rate limits reset at UTC midnight, not rolling 24h"

**`decide` / `get_decisions` - Architectural Decisions**
- DECIDE when: making or encountering significant technical choices, choosing between
  approaches, establishing patterns for the codebase
- GET_DECISIONS when: about to make changes in an area, wondering "why is it done
  this way?", onboarding to a new part of the codebase
- Decisions are immutable - new decisions on the same topic preserve history

### Best Practices

1. **Be proactive**: Don't wait to be asked. Stash context before it's lost.
2. **Search first**: Before diving into unfamiliar code, recall/get_decisions for that area.
3. **Atomic insights**: One concept per insight. Easier to find and stays relevant.
4. **Descriptive keys**: Use hierarchical keys like "auth/session-handling" or "api/rate-limits".
5. **Link decisions to code**: Reference specific files/functions when documenting decisions.
```

</details>

## MCP Tools

| Tool | Purpose | Key Parameters |
|------|---------|----------------|
| `stash` | Save working context for later | `name` (string), `summary` (string), `files` (array, optional) |
| `pop` | Retrieve stashes by name or semantic search | `name` (string - exact or query), `limit` (number, default: 5) |
| `insight` | Save persistent knowledge about the codebase | `content` (string), `key` (string, optional) |
| `recall` | Retrieve insights by key or semantic search | `key` (string - exact or query), `limit` (number, default: 5) |
| `decide` | Record an architectural decision | `topic` (string), `decision` (string), `reasoning` (string, optional) |
| `get_decisions` | Query decisions by topic or semantic search | `topic` (string, optional), `limit` (number, default: 10), `list_topics` (boolean) |

### Search Behavior

All retrieval tools (`pop`, `recall`, `get_decisions`) support:
- **Exact match**: Use precise names/keys/topics for direct lookup
- **Semantic search**: Use natural language queries to find conceptually similar content
- **Exclusion**: Prefix words with `-` to exclude them (e.g., "auth -oauth")

Exact matches return immediately. If no exact match is found, semantic search kicks in automatically.

## Testing the Server

```bash
# Check server status
curl http://localhost:4001/

# Initialize connection (required first)
curl -X POST http://localhost:4001/mcp/YOUR_PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}'

# List available tools
curl -X POST http://localhost:4001/mcp/YOUR_PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# Call a tool (e.g., stash)
curl -X POST http://localhost:4001/mcp/YOUR_PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"stash","arguments":{"name":"test","summary":"Testing the API"}}}'
```

## Architecture

- **Database**: PostgreSQL with pgvector extension for embeddings
- **Search**: Typesense for fast full-text and vector search
- **Embeddings**: Local model (`sentence-transformers/all-MiniLM-L6-v2`) via Bumblebee/EXLA
- **MCP Server**: Bandit HTTP server with JSON-RPC transport
- **Storage**: All data keyed by `project_id` and `agent_id` for multi-project support

## Configuration

### Environment Variables (Docker/Production)

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection URL | Required |
| `TYPESENSE_URL` | Typesense server URL | Required |
| `TYPESENSE_API_KEY` | Typesense API key | Required |
| `MCP_PORT` | HTTP server port | `4001` |
| `POOL_SIZE` | Database connection pool size | `10` |

### Local Development

See `config/config.exs` and `config/dev.exs` for:
- Database connection (default: `localhost:5433`)
- Typesense settings (default: `localhost:8108`)
- Embeddings model and dimensions
- MCP server port (default: `4001`)

## Development

```bash
# Run tests
mix test

# Run linters
mix lint

# Reset database
mix ecto.reset

# Reindex search (after schema changes)
mix pop_stash.reindex_search

# List projects
docker compose exec app bin/pop_stash eval "PopStash.CLI.project_list()"
```

## License

MIT
