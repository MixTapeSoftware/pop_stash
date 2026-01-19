# Step 7: Update documentation

## Context

The `.claude/rules/popstash.md` file needs to be updated to reflect the new step tools and RLM workflow. This ensures Claude knows how to use the new functionality.

## Tasks

1. **Update `.claude/rules/popstash.md`**:

   - Remove all references to `thread_id` for plans
   - Remove revision/versioning documentation for plans
   - Add new section for step tools:

   ```markdown
   ### Step Management Tools (for RLM execution)

   **add_step**
   - Parameters: plan_id (required), description (required), after_step (optional), step_number (optional), created_by (optional), metadata (optional)
   - Use to add steps to a plan, either appending or inserting after a specific step
   - Example: `add_step(plan_id: "...", description: "Run tests", after_step: 2.0)`

   **update_step**
   - Parameters: step_id (required), status (optional: completed|failed), result (optional), metadata (optional)
   - Use to mark steps completed or failed after execution
   - Example: `update_step(step_id: "...", status: "completed", result: "All tests passed")`

   **peek_next_step**
   - Parameters: plan_id (required)
   - Read-only: shows next pending step without changing status
   - Use for debugging or checking plan progress

   **get_plan_steps**
   - Parameters: plan_id (required), status (optional filter)
   - Returns compact overview of all steps with their status
   - Use to see plan progress at a glance

   **get_step**
   - Parameters: step_id (required)
   - Returns full step details including description, result, metadata
   ```

   - Update `save_plan` and `get_plan` documentation to remove thread_id references

2. **Optionally update `README.md`** with:
   - Tools table showing new step tools
   - Brief description of RLM workflow

## Dependencies

Requires all previous steps to be completed (tools and API must exist before documenting).

## Acceptance

- Documentation accurately reflects the new tools and their parameters
- No references to thread_id remain in plan-related documentation
- Examples are correct and would work if executed
- Run `mix precommit` to ensure no issues
