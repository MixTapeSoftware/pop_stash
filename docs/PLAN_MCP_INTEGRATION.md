# Plan MCP Integration

## Overview

This document describes the integration of plan management into the PopStash MCP server. Plans are versioned documents for project roadmaps, architecture designs, and implementation strategies.

## What Was Added

### New MCP Tools (3 total)

Three new MCP tools were added to expose plan functionality to AI assistants:

1. **`save_plan`** - Create and save versioned plans
2. **`get_plan`** - Retrieve plans by title/version or list available plans
3. **`search_plans`** - Semantic search across all plan content

### Files Created

```
lib/pop_stash/mcp/tools/
├── save_plan.ex       # Save versioned plans
├── get_plan.ex        # Retrieve plans with multiple query modes
└── search_plans.ex    # Semantic search for plans
```

### Files Modified

- `lib/pop_stash/mcp/server.ex` - Registered the three new tools in `@tool_modules`
- `README.md` - Added plan tools to documentation table and usage guidance

## Tool Details

### 1. save_plan

Creates a new versioned plan document.

**Parameters:**
- `title` (required, string) - Plan title (e.g., "Q1 2024 Roadmap")
- `version` (required, string) - Version identifier (e.g., "v1.0", "2024-01-15")
- `body` (required, string) - Plan content (supports markdown)
- `tags` (optional, array of strings) - Tags for categorization

**Constraints:**
- The combination of `title` + `version` must be unique within a project
- This allows multiple versions of the same plan to coexist

**Example:**
```json
{
  "title": "Authentication Architecture",
  "version": "v1.0",
  "body": "## Overview\n\nWe will use JWT tokens with refresh token rotation...",
  "tags": ["security", "architecture"]
}
```

### 2. get_plan

Retrieves plans with multiple query modes for flexibility.

**Parameters:**
- `title` (optional, string) - Plan title for exact match or semantic search query
- `version` (optional, string) - Specific version to retrieve (requires title)
- `all_versions` (optional, boolean) - List all versions of a plan (requires title)
- `list_titles` (optional, boolean) - List all unique plan titles
- `limit` (optional, integer, default: 10) - Maximum results to return

**Query Modes:**

1. **List all plan titles**: `{"list_titles": true}`
2. **Get latest version by title**: `{"title": "Q1 Roadmap"}`
3. **Get specific version**: `{"title": "Q1 Roadmap", "version": "v1.0"}`
4. **List all versions of a plan**: `{"title": "Q1 Roadmap", "all_versions": true}`
5. **Semantic search**: `{"title": "authentication strategy"}` (fallback if no exact match)
6. **List recent plans**: `{}` or `{"limit": 5}`

**Behavior:**
- Exact title matches return immediately
- If no exact match, falls back to semantic search
- Returns formatted plan content with metadata

### 3. search_plans

Performs semantic vector search across all plan content (title, body, tags).

**Parameters:**
- `query` (required, string) - Natural language search query
- `limit` (optional, integer, default: 10) - Maximum results to return

**Search Features:**
- Vector-based semantic similarity
- Searches across title, body, and tags
- Supports exclusion with `-` prefix (e.g., "deployment -docker")
- Natural language queries work best

**Example Queries:**
- "authentication implementation"
- "how should we handle errors?"
- "database migration strategy"
- "deployment -docker"

## Integration Points

### Memory Module

All plan operations delegate to the existing `PopStash.Memory` module:

- `Memory.create_plan/5` - Create new plan
- `Memory.get_plan/3` - Get specific plan by title and version
- `Memory.get_latest_plan/2` - Get latest version of a plan
- `Memory.list_plans/2` - List plans with optional filters
- `Memory.list_plan_versions/2` - List all versions of a plan
- `Memory.list_plan_titles/1` - List unique plan titles
- `Memory.search_plans/3` - Semantic search via Typesense

### Search Integration

Plans integrate with the existing Typesense search infrastructure:

- `PopStash.Search.Typesense.search_plans/3` - Vector search implementation
- Embeddings generated via `PopStash.Embeddings.embed/1`
- Search logs recorded via `Memory.log_search/4`

### Database Schema

Plans use the existing `plans` table:

```elixir
schema "plans" do
  field :title, :string
  field :version, :string
  field :body, :string
  field :tags, {:array, :string}, default: []
  field :embedding, Pgvector.Ecto.Vector
  
  belongs_to :project, PopStash.Projects.Project
  
  timestamps()
end
```

**Unique constraint:** `[:project_id, :title, :version]`

## Usage Patterns

### For AI Assistants

**When to use plans:**
- Documenting project roadmaps and milestones
- Creating architecture design documents
- Planning feature implementations across iterations
- Tracking project evolution over time

**Best practices:**
1. Use semantic version numbers (v1.0, v2.0) or dates (2024-01-15)
2. Include detailed context in the body (supports markdown)
3. Use tags to categorize related plans
4. Search before creating to avoid duplicates
5. Create new versions rather than updating existing ones

### Example Workflows

**Document a new roadmap:**
```
1. save_plan(title="Q1 2024 Roadmap", version="v1.0", body="...")
2. Later: save_plan(title="Q1 2024 Roadmap", version="v1.1", body="...updated...")
```

**Find relevant planning docs:**
```
1. search_plans(query="authentication strategy")
2. get_plan(title="Auth Architecture", version="v2.0")
```

**Explore available plans:**
```
1. get_plan(list_titles=true) - See all plan titles
2. get_plan(title="Q1 Roadmap", all_versions=true) - See version history
```

## Relationship to Other Memory Types

Plans complement the existing memory types:

| Memory Type | Purpose | Mutability | Versioning |
|-------------|---------|------------|------------|
| **Contexts** | Temporary working context | Mutable | No |
| **Insights** | Persistent knowledge | Mutable | No |
| **Decisions** | Architectural decisions | Immutable | History via new entries |
| **Plans** | Project documentation | Immutable | Explicit versions |

**When to use which:**
- **Context**: "I'm working on refactoring the auth module"
- **Insight**: "The auth middleware converts guest users to anonymous sessions"
- **Decision**: "We decided to use JWT tokens because..." (topic: "authentication")
- **Plan**: Full architecture doc or roadmap for authentication system (versioned)

## Testing

Compilation verified with no errors:
```bash
mix compile
# Compiling 73 files (.ex)
# Generated pop_stash app
```

Manual testing can be done via:
```bash
# Start the server
mix phx.server

# Test save_plan
curl -X POST http://localhost:4001/mcp/YOUR_PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"save_plan","arguments":{"title":"Test Plan","version":"v1.0","body":"# Test\nThis is a test plan."}}}'

# Test get_plan
curl -X POST http://localhost:4001/mcp/YOUR_PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_plan","arguments":{"title":"Test Plan"}}}'

# Test search_plans
curl -X POST http://localhost:4001/mcp/YOUR_PROJECT_ID \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_plans","arguments":{"query":"test"}}}'
```

## Implementation Notes

### Error Handling

All tools include comprehensive error handling:
- Unique constraint violations provide helpful messages
- Missing projects return clear error messages
- Search failures gracefully fall back to empty results
- Validation errors are formatted for readability

### Search Logging

All search operations (both exact and semantic) are logged via `Memory.log_search/4`:
- Tool name recorded (`get_plan`, `search_plans`)
- Collection type: `:plans`
- Search type: `:semantic` or `:exact`
- Result count and success status

### Broadcasting

Plan operations broadcast events to Phoenix PubSub:
- `:plan_created`
- `:plan_updated`
- `:plan_deleted`

This enables real-time updates and monitoring.

## Future Enhancements

Potential improvements:
1. Plan templates for common document types
2. Plan dependencies/relationships
3. Diff viewing between plan versions
4. Plan approval workflows
5. Export plans to various formats (PDF, HTML, etc.)
6. Plan archival/deprecation

## Conclusion

The plan MCP integration provides AI assistants with a robust system for managing versioned project documentation. It seamlessly integrates with the existing memory infrastructure while providing specialized functionality for long-form planning documents.