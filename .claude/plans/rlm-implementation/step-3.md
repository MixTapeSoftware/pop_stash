# Step 3: Update existing MCP tools (save_plan, get_plan)

## Context

The existing plan MCP tools need to be simplified to remove thread_id references. They should work with the new simplified plan model.

## Tasks

1. **Update `lib/pop_stash/mcp/tools/save_plan.ex`**:
   - Remove `thread_id` parameter from tool definition
   - Remove thread_id from description text
   - Simplify the execute function to not handle thread_id
   - Ensure it returns `plan_id` in the response (for use with step tools)

2. **Update `lib/pop_stash/mcp/tools/get_plan.ex`**:
   - Remove `all_revisions` parameter
   - Remove `thread_id` from response
   - Remove any thread-related logic
   - Simplify to just title lookup

3. **Verify `search_plans` tool** (`lib/pop_stash/mcp/tools/search_plans.ex`):
   - Should need no changes, but verify it doesn't reference thread_id

## Dependencies

Requires step-0 (Memory context plan function updates) to be completed first.

## Acceptance

- Both tools compile without errors
- MCP tool definitions don't mention thread_id or revisions
- Test via MCP client:
  - `save_plan(title: "Test", body: "...")` returns a plan_id
  - `get_plan(title: "Test")` returns the plan without thread_id
  - `search_plans(query: "test")` works as before
