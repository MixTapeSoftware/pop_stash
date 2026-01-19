# Step 6: Write tests for step CRUD operations

## Context

We need tests to verify the step management functionality works correctly, including edge cases like concurrent access and step number calculations.

## Tasks

1. **Add unit tests to `test/pop_stash/memory_test.exs`**:

   - `add_plan_step/3`:
     - Creates step with auto-incremented step_number (1.0, 2.0, 3.0...)
     - Creates step with explicit step_number
     - Creates step with after_step (midpoint calculation)
     - Handles after_step when no next step exists
     - Rejects duplicate step_numbers (unique constraint)
   
   - `get_next_plan_step/1`:
     - Returns first pending step by step_number
     - Returns nil when no pending steps
     - Skips in_progress/completed/failed steps
   
   - `get_next_step_and_mark_in_progress/1`:
     - Returns step and marks it in_progress atomically
     - Returns nil when no pending steps
     - Concurrent calls return different steps (if multiple pending)
   
   - `update_plan_step/2`:
     - Updates status to completed/failed
     - Updates result text
     - Updates metadata
   
   - `list_plan_steps/2`:
     - Returns steps ordered by step_number
     - Filters by status when provided
     - Returns empty list for plan with no steps
   
   - `list_plans/2`:
     - Returns all plans for project
     - Filters by title when provided

2. **Add integration tests for MCP tools** (if test infrastructure exists):
   - Full flow: create plan -> add steps -> get next -> update -> repeat

3. **Add controller tests** for HTTP API endpoints (optional but recommended):
   - Test JSON responses
   - Test 404 handling
   - Test concurrent next-step requests

## Dependencies

Requires step-2 (Memory functions), step-4 (MCP tools), step-5 (HTTP API) to be completed.

## Acceptance

- All tests pass: `mix test`
- No warnings or deprecations
- Tests cover the key scenarios listed above
- `mix test --failed` returns no failures
