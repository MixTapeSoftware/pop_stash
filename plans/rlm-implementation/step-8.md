# Step 8: Update planner agent and execution script to enforce tests and code quality checks

## Context

The planner agent helps users create well-structured plans with discrete steps. Currently, it focuses on breaking work into steps with context, tasks, dependencies, and acceptance criteria. However, it doesn't explicitly prompt users to consider what tests should be written for each step, or remind them to run linters and formatters.

Additionally, the `ps-execute.sh` script needs to instruct Claude to run code quality checks before marking each step complete.

Adding tests and running code quality checks should be first-class considerations during both planning and execution.

## Tasks

1. **Update the planner agent prompt** in `plan.md` (Planner Agent section):

   Add guidance for the planner to:
   - Ask about testing requirements for each step
   - Suggest including a "Tests" or "Testing" section in each step-N.md file
   - Recommend what tests should be added (unit tests, integration tests, etc.)
   - Consider test coverage as part of acceptance criteria
   - Remind users to run linters and formatters if available in the project

2. **Update the step-N.md format** in `plan.md`:

   Add a `## Tests` section and update `## Acceptance` to include code quality:

   ```markdown
   # Step N: Description

   ## Context
   ...

   ## Tasks
   ...

   ## Tests
   - Unit tests for [specific functions/modules]
   - Integration tests for [specific flows]
   - Update existing tests if behavior changes

   ## Dependencies
   ...

   ## Acceptance
   - All new tests pass
   - Existing tests still pass
   - Code passes linter/formatter checks (if available: `mix format`, `mix credo`, etc.)
   - [other criteria]
   ```

3. **Update `ps-execute.sh`** to instruct Claude to run code quality checks:

   Update the Claude invocation prompt to include:

   ```bash
   claude -p "Execute this task:

   $STEP_DESC

   Instructions:
   - Complete the tasks described above
   - Before marking complete, run any available linters, formatters, and tests:
     - Elixir: \`mix format\`, \`mix credo\`, \`mix test\` (or \`mix precommit\` if available)
     - JavaScript/TypeScript: \`npm run lint\`, \`npm test\`
     - Python: \`ruff format\`, \`ruff check\`, \`pytest\`
     - Rust: \`cargo fmt\`, \`cargo clippy\`, \`cargo test\`
     - Or use the project's precommit/CI script if one exists
   - Fix any issues found before marking the step complete
   - When complete, call update_step with step_id='$STEP_ID', status='completed', and a brief result summary
   - If you cannot complete the task, call update_step with status='failed' and explain why in the result
   - If you discover additional work is needed, use add_step with after_step=$STEP_NUM"
   ```

4. **Update guidelines** to emphasize:
   - Each step that adds or modifies code should include test requirements
   - Tests should be scoped to what the step changes (not broader)
   - Test files and test names should be specified when known
   - Always run available linters and formatters before marking a step complete
   - If a project has a precommit script or similar (e.g., `mix precommit`), prefer using it

## Dependencies

None - this is documentation/prompt updates only.

## Acceptance

- Planner agent prompt includes testing guidance
- Planner agent prompt includes linter/formatter guidance
- Step template includes a Tests section
- Step template acceptance criteria mention code quality checks
- `ps-execute.sh` prompt instructs Claude to run linters/formatters/tests before marking complete
- Guidelines mention test and code quality considerations
- Running `mix precommit` still passes (no code changes)
