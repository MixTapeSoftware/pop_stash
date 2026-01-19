# Step 1: Create plan_steps table and PlanStep schema

## Context

We need a new table to store steps associated with plans. Steps are mutable (status/result can change) and use float step_numbers to allow insertion between existing steps.

## Tasks

1. Create migration `priv/repo/migrations/[timestamp]_create_plan_steps.exs`:

```elixir
create table(:plan_steps) do
  add :plan_id, references(:plans, on_delete: :delete_all), null: false
  add :step_number, :float, null: false  # Float allows insertion (2.5 between 2 and 3)
  add :description, :text, null: false
  add :status, :string, default: "pending"  # pending | in_progress | completed | failed
  add :result, :text  # Execution result/notes
  add :created_by, :string, default: "user"  # "user" | "agent"
  add :metadata, :map, default: %{}
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  
  timestamps()
end

create index(:plan_steps, [:plan_id])
create index(:plan_steps, [:project_id])
create index(:plan_steps, [:status])
create unique_index(:plan_steps, [:plan_id, :step_number])
```

2. Create `lib/pop_stash/memory/plan_step.ex`:
   - Define schema with all fields
   - Add `changeset/2` function with validations:
     - Required: plan_id, step_number, description, project_id
     - Validate status is one of: pending, in_progress, completed, failed
     - Validate created_by is one of: user, agent
   - Add `update_changeset/2` for status/result updates

3. Update `lib/pop_stash/memory/plan.ex`:
   - Add `has_many :steps, PopStash.Memory.PlanStep`

## Dependencies

Requires step-0 (thread_id removal) to be completed first.

## Acceptance

- Migration runs successfully: `mix ecto.migrate`
- PlanStep schema compiles
- Can create a step via IEx: `%PlanStep{} |> PlanStep.changeset(%{...}) |> Repo.insert()`
- Plan preloads steps correctly: `Repo.get(Plan, id) |> Repo.preload(:steps)`
