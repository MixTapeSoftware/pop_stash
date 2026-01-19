## Ecto Guidelines

- **Prefer `Repo.transact` over `Ecto.Multi`** for transaction handling

  `Repo.transact/1` is cleaner and more readable for most use cases. It takes a function returning `{:ok, result}` or `{:error, reason}`.

  **Prefer this:**

      def get_next_step_and_mark_in_progress(plan_id) do
        Repo.transact(fn ->
          step =
            PlanStep
            |> where([s], s.plan_id == ^plan_id and s.status == "pending")
            |> order_by(asc: :step_number)
            |> limit(1)
            |> lock("FOR UPDATE SKIP LOCKED")
            |> Repo.one()

          case step do
            nil -> {:ok, nil}
            step ->
              step
              |> PlanStep.update_changeset(%{status: "in_progress"})
              |> Repo.update()
          end
        end)
      end

  **Avoid `Ecto.Multi` unless you need:**
  - Named operations for error reporting
  - Complex rollback logic
  - Inspection of intermediate results across many steps

- **Put changesets in the context where they're used, not in schema files**

  Changesets are typically only used in one context, so colocate them there.

  **Prefer this (in context module):**

      # lib/my_app/memory.ex
      defp status_changeset(plan, attrs) do
        plan
        |> cast(attrs, [:status])
        |> validate_inclusion(:status, ~w(idle running paused completed failed))
      end

  **Avoid this (in schema module):**

      # lib/my_app/memory/plan.ex
      def status_changeset(plan, attrs) do
        # ...
      end

  Schema files should generally only contain the schema definition and basic type information.
