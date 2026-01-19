# Step 0: Remove thread_id from plans schema

## Context

Plans currently have a `thread_id` field for revision tracking. For RLM, we're simplifying plans to remove this concept. Plans become simpler: just id, title, body, tags, files, project_id.

## Tasks

1. Create migration `priv/repo/migrations/[timestamp]_remove_thread_from_plans.exs`:
   - Remove `thread_id` column from `plans` table
   - Remove any thread-related indexes

2. Update `lib/pop_stash/memory/plan.ex`:
   - Remove `thread_id` field from schema
   - Remove `thread_prefix/0` function if it exists
   - Remove any thread-related validation or logic

3. Update `lib/pop_stash/memory.ex` plan functions:
   - Simplify `create_plan/4` - remove thread_id option
   - Simplify `get_plan/2` - remove thread lookup logic
   - Remove `get_plan_by_thread/2` if it exists
   - Remove `list_plan_revisions/2` if it exists
   - Remove `list_plan_thread/2` if it exists
   - Simplify `list_plan_titles/1`

## Dependencies

None - this is the first step.

## Acceptance

- Migration runs successfully: `mix ecto.migrate`
- Plan schema compiles without thread_id references
- Existing tests pass (may need updates if they reference thread_id)
- `mix compile` succeeds with no warnings about removed functions
