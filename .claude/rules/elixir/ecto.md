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
