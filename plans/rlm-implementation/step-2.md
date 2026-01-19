# Step 2: Add step management functions to Memory context

## Context

The Memory context needs functions to manage plan steps: creating, querying, and updating. These functions will be used by both MCP tools and the HTTP API.

## Tasks

Add the following functions to `lib/pop_stash/memory.ex`:

1. **add_plan_step(plan_id, description, opts \\ [])**
   - Options: after_step (float), step_number (float), created_by (string), metadata (map)
   - If `step_number` provided: use it directly
   - If `after_step` provided: calculate midpoint between that step and next
   - Otherwise: query max(step_number) and add 1.0
   - Handle concurrent additions properly (use database constraints)
   - Return {:ok, step} or {:error, changeset}

2. **get_next_plan_step(plan_id)**
   - Find first step with status "pending" ordered by step_number
   - Return step or nil (does NOT change status)

3. **get_next_step_and_mark_in_progress(plan_id)**
   - Atomic operation: find next pending step AND mark it in_progress
   - Use Ecto.Multi or a transaction to prevent race conditions
   - Return {:ok, step} or {:ok, nil} if no pending steps

4. **update_plan_step(step_id, attrs)**
   - Update status, result, metadata
   - Validate status transitions (should only go pending->in_progress->completed/failed)
   - Return {:ok, step} or {:error, changeset}

5. **list_plan_steps(plan_id, opts \\ [])**
   - Options: status (filter by status)
   - Always order by step_number ascending
   - Return list of steps

6. **get_plan_step(plan_id, step_number)**
   - Get a specific step by plan_id and step_number
   - Return step or nil

7. **get_plan_step_by_id(step_id)**
   - Get step by its primary key
   - Return step or nil

8. **list_plans(project_id, opts \\ [])**
   - Options: title (exact match filter)
   - Return list of plans with id, title, inserted_at

## Dependencies

Requires step-1 (PlanStep schema) to be completed first.

## Acceptance

- All functions compile without errors
- IEx testing:
  - Create a plan, add steps, verify step_number increments
  - Add step with after_step, verify midpoint calculation
  - Update step status, verify transitions work
  - List steps, verify ordering
- `get_next_step_and_mark_in_progress` is atomic (test with concurrent calls if possible)
