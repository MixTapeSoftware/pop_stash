# Remove Agents Model

**Status**: Planned  
**Effort**: ~30 minutes

## Why

The `Agent` model tracks connected MCP clients but provides no value:
- A new agent is created on every HTTP request
- `created_by` is stored but never queried
- Status tracking (active/idle/disconnected) is unused

Remove it.

## Approach

Since there's no production data, modify migrations directly and run `mix ecto.reset`.

## Changes

### Delete

```
lib/pop_stash/agents.ex
lib/pop_stash/agents/agent.ex
lib/pop_stash/agents/           (directory)
priv/repo/migrations/20260106210757_create_agents.exs
test/pop_stash/agents_test.exs
```

### Modify Migrations

Remove `created_by` column and foreign key from:
- `priv/repo/migrations/20260106210924_create_stashes.exs`
- `priv/repo/migrations/20260106210957_create_insights.exs`
- `priv/repo/migrations/20260107164545_create_decisions.exs`

### Modify Schemas

Remove `belongs_to(:agent, ...)` from:
- `lib/pop_stash/memory/stash.ex`
- `lib/pop_stash/memory/insight.ex`
- `lib/pop_stash/memory/decision.ex`

### Modify Memory Context

In `lib/pop_stash/memory.ex`, update function signatures:

```elixir
# Before
def create_stash(project_id, agent_id, name, summary, opts \\ [])
def create_insight(project_id, agent_id, content, opts \\ [])
def create_decision(project_id, agent_id, topic, decision, opts \\ [])

# After
def create_stash(project_id, name, summary, opts \\ [])
def create_insight(project_id, content, opts \\ [])
def create_decision(project_id, topic, decision, opts \\ [])
```

Remove `created_by` from changesets and foreign key constraints.

### Modify Router

In `lib/pop_stash/mcp/router.ex`:
- Remove `get_or_create_agent/1` function
- Remove `agent_id` from context map
- Remove `alias PopStash.Agents`

### Modify Tools

Remove `agent_id` from pattern match in execute/2:
- `lib/pop_stash/mcp/tools/stash.ex`
- `lib/pop_stash/mcp/tools/insight.ex`
- `lib/pop_stash/mcp/tools/decide.ex`

### Modify Server

In `lib/pop_stash/mcp/server.ex`:
- Update docstring (remove agent_id reference)

### Modify Tests

Update setup blocks to remove agent creation:
- `test/pop_stash/mcp/server_test.exs`
- `test/pop_stash/mcp/tools/decide_test.exs`
- `test/pop_stash/mcp/tools/get_decisions_test.exs`
- `test/pop_stash/mcp/tools/pop_test.exs`
- `test/pop_stash/mcp/tools/stash_test.exs` (if exists)
- `test/pop_stash/mcp/tools/insight_test.exs` (if exists)
- `test/pop_stash/mcp/tools/recall_test.exs` (if exists)

### Modify Mix Task

In `lib/mix/tasks/pop_stash.project.delete.ex`:
- Remove "Agents" from deletion confirmation message

## Execution Order

1. Delete files (agents module, schema, migration, test)
2. Edit migrations (remove created_by)
3. Edit schemas (remove belongs_to)
4. Edit memory.ex (update signatures)
5. Edit router.ex (remove agent handling)
6. Edit tools (remove agent_id from pattern matches)
7. Edit tests (remove agent setup)
8. Run `mix ecto.reset`
9. Run `mix test`
10. Run `mix compile --warnings-as-errors`
11. Rebuild Docker: `docker compose build app`
