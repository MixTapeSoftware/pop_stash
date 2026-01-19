# Step 4: Create new MCP step tools

## Context

We need five new MCP tools for step management. These tools allow Claude to interact with plan steps during execution.

## Tasks

Create the following MCP tools, following the pattern of existing tools in `lib/pop_stash/mcp/tools/`:

1. **`lib/pop_stash/mcp/tools/add_step.ex`**
   - Parameters:
     - plan_id (required): ID of the plan
     - description (required): What this step does
     - after_step (optional): Insert after this step number (float)
     - step_number (optional): Explicit step number (float)
     - created_by (optional): "user" | "agent" - defaults to "agent"
     - metadata (optional): Additional context
   - Calls `Memory.add_plan_step/3`
   - Returns created step with step_number, id, created_by

2. **`lib/pop_stash/mcp/tools/update_step.ex`**
   - Parameters:
     - step_id (required): ID of the step
     - status (optional): completed | failed (NOT in_progress - that's automatic)
     - result (optional): Execution result/notes
     - metadata (optional): Additional context
   - Calls `Memory.update_plan_step/2`
   - Returns updated step

3. **`lib/pop_stash/mcp/tools/peek_next_step.ex`**
   - Parameters:
     - plan_id (required): ID of the plan
   - Calls `Memory.get_next_plan_step/1` (read-only, no status change)
   - Returns next pending step or message if none left
   - Note: This is for debugging; HTTP API handles actual execution

4. **`lib/pop_stash/mcp/tools/get_plan_steps.ex`**
   - Parameters:
     - plan_id (required): ID of the plan
     - status (optional): Filter by status
   - Calls `Memory.list_plan_steps/2`
   - Returns compact list: step_number, status, created_by, step_id, description snippet

5. **`lib/pop_stash/mcp/tools/get_step.ex`**
   - Parameters:
     - step_id (required): ID of the step
   - Calls `Memory.get_plan_step_by_id/1`
   - Returns full step details

6. **Register all tools** in `lib/pop_stash/mcp/server.ex` (or wherever tools are registered)

## Dependencies

Requires step-2 (Memory context step functions) to be completed first.

## Acceptance

- All five tools compile without errors
- Tools are registered and appear in MCP tool list
- Test via MCP client:
  - Create plan, add steps with `add_step`
  - Query steps with `get_plan_steps`
  - Get individual step with `get_step`
  - Update step status with `update_step`
  - Peek at next step with `peek_next_step`
