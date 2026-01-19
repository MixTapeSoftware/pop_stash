defmodule PopStash.Plans do
  @moduledoc """
  Context for managing plans and plan steps.

  Plans are versioned project documentation and roadmaps. Each plan can have
  multiple steps that can be executed sequentially by agents.

  ## Plan Statuses

  - `idle` - Ready for an agent to claim and work a step
  - `running` - An agent is actively working a step
  - `paused` - User stopped execution
  - `completed` - All steps done
  - `failed` - A step failed

  ## Step Statuses

  - `pending` - Not yet started
  - `in_progress` - Currently being worked on
  - `completed` - Successfully finished
  - `failed` - Failed during execution
  - `deferred` - Skipped, will not be executed
  - `outdated` - No longer relevant, won't be executed
  """

  import Ecto.Changeset

  alias PopStash.Memory.Plan
  alias PopStash.Memory.PlanStep
  alias PopStash.Plans.Query
  alias PopStash.Repo

  defmodule Query do
    @moduledoc false

    import Ecto.Query

    alias PopStash.Memory.Plan
    alias PopStash.Memory.PlanStep

    ## Plan Queries

    def for_project(query \\ Plan, project_id) do
      where(query, [p], p.project_id == ^project_id)
    end

    def with_id(query \\ Plan, id) do
      where(query, [p], p.id == ^id)
    end

    def with_title(query \\ Plan, title) do
      where(query, [p], p.title == ^title)
    end

    def with_plan_status(query \\ Plan, status) do
      where(query, [p], p.status == ^status)
    end

    def select_titles(query \\ Plan) do
      query
      |> select([p], p.title)
      |> distinct(true)
    end

    def ordered_by_inserted_at(query, direction \\ :desc) do
      order_by(query, [p], [{^direction, p.inserted_at}])
    end

    def ordered_by_title(query, direction \\ :asc) do
      order_by(query, [p], [{^direction, p.title}])
    end

    def limit(query, count) do
      Ecto.Query.limit(query, ^count)
    end

    def lock_for_update_skip_locked(query) do
      lock(query, "FOR UPDATE SKIP LOCKED")
    end

    ## Plan Step Queries

    def steps_for_plan(query \\ PlanStep, plan_id) do
      where(query, [s], s.plan_id == ^plan_id)
    end

    def with_status(query \\ PlanStep, status) do
      where(query, [s], s.status == ^status)
    end

    def with_step_number_greater_than(query \\ PlanStep, step_number) do
      where(query, [s], s.step_number > ^step_number)
    end

    def with_step_number(query \\ PlanStep, step_number) do
      where(query, [s], s.step_number == ^step_number)
    end

    def ordered_by_step_number(query, direction \\ :asc) do
      order_by(query, [s], [{^direction, s.step_number}])
    end

    def select_max_step_number(query \\ PlanStep) do
      select(query, [s], max(s.step_number))
    end

    def select_step_number(query \\ PlanStep) do
      select(query, [s], s.step_number)
    end

    def first(query) do
      Ecto.Query.limit(query, 1)
    end
  end

  @plan_statuses ~w(idle running paused completed failed)
  @step_statuses ~w(pending in_progress completed failed deferred outdated)

  ## Plans

  @doc """
  Creates a plan with a title and body content.

  ## Options
    * `:tags` - Optional list of tags
    * `:files` - Optional list of file paths
  """
  def create_plan(project_id, title, body, opts \\ []) do
    %Plan{}
    |> cast(
      %{
        project_id: project_id,
        title: title,
        body: body,
        tags: Keyword.get(opts, :tags, []),
        files: Keyword.get(opts, :files, [])
      },
      [:project_id, :title, :body, :tags, :files]
    )
    |> validate_required([:project_id, :title, :body])
    |> validate_length(:title, min: 1, max: 255)
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
    |> tap_ok(&broadcast(:plan_created, &1))
  end

  @doc """
  Gets a plan by title.
  """
  def get_plan(project_id, title) when is_binary(project_id) and is_binary(title) do
    Query.for_project(project_id)
    |> Query.with_title(title)
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Gets a plan by its ID.
  """
  def get_plan_by_id(plan_id) when is_binary(plan_id) do
    Plan
    |> Repo.get(plan_id)
    |> wrap_result()
  end

  @doc """
  Lists all plans for a project.

  ## Options
    * `:limit` - Maximum number of plans to return (default: 50)
    * `:title` - Filter by title (exact match)
  """
  def list_plans(project_id, opts \\ []) when is_binary(project_id) do
    limit = Keyword.get(opts, :limit, 50)
    title = Keyword.get(opts, :title)

    Query.for_project(project_id)
    |> maybe_filter_plan_title(title)
    |> Query.ordered_by_inserted_at(:desc)
    |> Query.limit(limit)
    |> Repo.all()
  end

  defp maybe_filter_plan_title(query, nil), do: query
  defp maybe_filter_plan_title(query, title), do: Query.with_title(query, title)

  @doc """
  Updates a plan's body.
  """
  def update_plan(plan_id, body) when is_binary(plan_id) and is_binary(body) do
    case Repo.get(Plan, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        plan
        |> cast(%{body: body}, [:body])
        |> validate_required([:body])
        |> Repo.update()
        |> tap_ok(&broadcast(:plan_updated, &1))
    end
  end

  @doc """
  Deletes a plan by ID.
  """
  def delete_plan(plan_id) when is_binary(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        case Repo.delete(plan) do
          {:ok, _} ->
            broadcast(:plan_deleted, plan.id)
            :ok

          error ->
            error
        end
    end
  end

  @doc """
  Lists all unique plan titles for a project.
  """
  def list_plan_titles(project_id) when is_binary(project_id) do
    Query.for_project(project_id)
    |> Query.select_titles()
    |> Query.ordered_by_title(:asc)
    |> Repo.all()
  end

  @doc """
  Pauses a plan, preventing further step execution.

  Can only pause a plan that is "idle" or "running".
  """
  def pause_plan(plan_id) when is_binary(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil ->
        {:error, :not_found}

      %{status: status} = plan when status in ~w(idle running) ->
        update_plan_status(plan, "paused")
        |> tap_ok(&broadcast(:plan_updated, &1))

      _plan ->
        {:error, :cannot_pause}
    end
  end

  @doc """
  Resumes a paused plan, allowing step execution to continue.
  """
  def resume_plan(plan_id) when is_binary(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil ->
        {:error, :not_found}

      %{status: "paused"} = plan ->
        update_plan_status(plan, "idle")
        |> tap_ok(&broadcast(:plan_updated, &1))

      _plan ->
        {:error, :not_paused}
    end
  end

  ## Plan Steps

  @doc """
  Adds a step to a plan.

  The step_number is automatically calculated unless explicitly provided.
  Steps belong to both the plan and its project for easier querying.

  ## Options
    * `:step_number` - Explicit step number (float)
    * `:after_step` - Insert after this step number (calculates midpoint)
    * `:created_by` - Who created the step ("user" or "agent", default: "user")
    * `:metadata` - Additional metadata map

  ## Examples

      # Add step at end (auto-increments)
      add_plan_step(plan_id, "Implement feature X")

      # Add step at specific position
      add_plan_step(plan_id, "Review code", step_number: 2.5)

      # Add step after step 1 (calculates midpoint between 1 and next)
      add_plan_step(plan_id, "Add tests", after_step: 1.0)
  """
  def add_plan_step(plan_id, description, opts \\ []) when is_binary(plan_id) do
    with {:ok, plan} <- get_plan_by_id(plan_id) do
      step_number = calculate_step_number(plan_id, opts)

      %PlanStep{}
      |> step_changeset(%{
        plan_id: plan_id,
        project_id: plan.project_id,
        step_number: step_number,
        description: description,
        created_by: Keyword.get(opts, :created_by, "user"),
        metadata: Keyword.get(opts, :metadata, %{})
      })
      |> Repo.insert()
      |> tap_ok(&broadcast(:plan_step_created, &1))
    end
  end

  defp calculate_step_number(plan_id, opts) do
    cond do
      step_number = Keyword.get(opts, :step_number) ->
        step_number

      after_step = Keyword.get(opts, :after_step) ->
        calculate_midpoint(plan_id, after_step)

      true ->
        get_next_step_number(plan_id)
    end
  end

  defp calculate_midpoint(plan_id, after_step) do
    next_step =
      Query.steps_for_plan(plan_id)
      |> Query.with_step_number_greater_than(after_step)
      |> Query.ordered_by_step_number(:asc)
      |> Query.select_step_number()
      |> Query.first()
      |> Repo.one()

    case next_step do
      nil -> after_step + 1.0
      next -> (after_step + next) / 2
    end
  end

  defp get_next_step_number(plan_id) do
    max_step =
      Query.steps_for_plan(plan_id)
      |> Query.select_max_step_number()
      |> Repo.one()

    case max_step do
      nil -> 1.0
      n -> n + 1.0
    end
  end

  @doc """
  Gets the next pending step for a plan without changing its status.

  Returns the first step with status "pending" ordered by step_number.
  Skips steps with status "deferred".
  """
  def get_next_plan_step(plan_id) when is_binary(plan_id) do
    Query.steps_for_plan(plan_id)
    |> Query.with_status("pending")
    |> Query.ordered_by_step_number(:asc)
    |> Query.first()
    |> Repo.one()
  end

  @doc """
  Atomically claims a plan and gets the next pending step.

  Uses plan-level locking to ensure only one agent can work on a plan at a time.
  The plan must be in "idle" status to be claimed.

  ## Returns

  - `{:ok, step}` - Successfully claimed plan and got a step to work on
  - `{:ok, :plan_locked}` - Another agent has the plan locked
  - `{:ok, :plan_completed}` - No more pending steps, plan marked completed
  - `{:ok, :plan_not_active}` - Plan is paused, completed, or failed

  ## Flow

  1. Agent calls this function
  2. If plan is idle, mark it "running" and return next pending step
  3. Agent works the step
  4. Agent calls `complete_plan_step/2` which marks plan back to "idle"
  5. Next iteration can claim the plan again
  """
  def get_next_step_and_mark_in_progress(plan_id) when is_binary(plan_id) do
    Repo.transact(fn ->
      plan =
        Query.with_id(plan_id)
        |> Query.with_plan_status("idle")
        |> Query.lock_for_update_skip_locked()
        |> Repo.one()

      case plan do
        nil -> get_plan_status_response(plan_id)
        plan -> claim_plan_and_get_step(plan)
      end
    end)
    |> tap_ok(fn
      step when is_struct(step, PlanStep) -> broadcast(:plan_step_updated, step)
      _ -> :ok
    end)
  end

  defp claim_plan_and_get_step(plan) do
    case get_next_actionable_step(plan.id) do
      nil ->
        update_plan_status(plan, "completed")
        {:ok, :plan_completed}

      step ->
        with {:ok, _plan} <- update_plan_status(plan, "running") do
          mark_step_in_progress(step)
        end
    end
  end

  defp get_plan_status_response(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil -> {:error, :not_found}
      %{status: "running"} -> {:ok, :plan_locked}
      %{status: status} when status in ~w(completed paused failed) -> {:ok, :plan_not_active}
      %{status: "idle"} -> {:ok, :plan_locked}
    end
  end

  defp get_next_actionable_step(plan_id) do
    Query.steps_for_plan(plan_id)
    |> Query.with_status("pending")
    |> Query.ordered_by_step_number(:asc)
    |> Query.first()
    |> Repo.one()
  end

  defp mark_step_in_progress(step) do
    step
    |> step_update_changeset(%{status: "in_progress"})
    |> Repo.update()
  end

  @doc """
  Completes a plan step and releases the plan for the next iteration.

  Marks the step as "completed" and the plan as "idle" so the next
  agent iteration can claim it.

  ## Options

  - `:result` - Optional result/output from the step execution
  - `:metadata` - Optional metadata to store with the step
  """
  def complete_plan_step(step_id, opts \\ []) when is_binary(step_id) do
    Repo.transact(fn ->
      case Repo.get(PlanStep, step_id) do
        nil ->
          {:error, :not_found}

        %{status: "in_progress"} = step ->
          result = Keyword.get(opts, :result)
          metadata = Keyword.get(opts, :metadata, %{})

          with {:ok, step} <- do_complete_step(step, result, metadata),
               {:ok, _plan} <- mark_plan_idle(step.plan_id) do
            {:ok, step}
          end

        _step ->
          {:error, :step_not_in_progress}
      end
    end)
    |> tap_ok(&broadcast(:plan_step_updated, &1))
  end

  defp do_complete_step(step, result, metadata) do
    attrs = %{status: "completed", result: result, metadata: Map.merge(step.metadata, metadata)}

    step
    |> step_update_changeset(attrs)
    |> Repo.update()
  end

  defp mark_plan_idle(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil -> {:error, :not_found}
      plan -> update_plan_status(plan, "idle")
    end
  end

  @doc """
  Marks a plan step as failed and releases the plan.

  The plan is marked as "failed" as well, stopping further step execution.

  ## Options

  - `:result` - Optional error message or failure details
  - `:metadata` - Optional metadata to store with the step
  """
  def fail_plan_step(step_id, opts \\ []) when is_binary(step_id) do
    Repo.transact(fn ->
      case Repo.get(PlanStep, step_id) do
        nil ->
          {:error, :not_found}

        %{status: "in_progress"} = step ->
          result = Keyword.get(opts, :result)
          metadata = Keyword.get(opts, :metadata, %{})

          with {:ok, step} <- do_fail_step(step, result, metadata),
               {:ok, _plan} <- mark_plan_failed(step.plan_id) do
            {:ok, step}
          end

        _step ->
          {:error, :step_not_in_progress}
      end
    end)
    |> tap_ok(&broadcast(:plan_step_updated, &1))
  end

  defp do_fail_step(step, result, metadata) do
    attrs = %{status: "failed", result: result, metadata: Map.merge(step.metadata, metadata)}

    step
    |> step_update_changeset(attrs)
    |> Repo.update()
  end

  defp mark_plan_failed(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil -> {:error, :not_found}
      plan -> update_plan_status(plan, "failed")
    end
  end

  @doc """
  Defers a plan step, skipping it during execution.

  Deferred steps are not picked up by `get_next_step_and_mark_in_progress/1`.
  """
  def defer_plan_step(step_id) when is_binary(step_id) do
    case Repo.get(PlanStep, step_id) do
      nil ->
        {:error, :not_found}

      %{status: "pending"} = step ->
        step
        |> step_update_changeset(%{status: "deferred"})
        |> Repo.update()
        |> tap_ok(&broadcast(:plan_step_updated, &1))

      _step ->
        {:error, :can_only_defer_pending}
    end
  end

  @doc """
  Undefers a plan step, making it pending again.
  """
  def undefer_plan_step(step_id) when is_binary(step_id) do
    case Repo.get(PlanStep, step_id) do
      nil ->
        {:error, :not_found}

      %{status: "deferred"} = step ->
        step
        |> step_update_changeset(%{status: "pending"})
        |> Repo.update()
        |> tap_ok(&broadcast(:plan_step_updated, &1))

      _step ->
        {:error, :not_deferred}
    end
  end

  @doc """
  Marks a plan step as outdated.

  Use this when a step is no longer relevant or has been superseded by new steps.
  Outdated steps are not picked up by `get_next_step_and_mark_in_progress/1`.

  Can mark pending or in_progress steps as outdated. If a step is in_progress,
  the plan is also released back to idle so execution can continue with the next step.

  ## Options

  - `:result` - Optional reason why the step became outdated
  - `:metadata` - Optional metadata to store with the step
  """
  def mark_plan_step_outdated(step_id, opts \\ []) when is_binary(step_id) do
    import Ecto.Query

    Repo.transact(fn ->
      step =
        PlanStep
        |> where([s], s.id == ^step_id)
        |> lock("FOR UPDATE SKIP LOCKED")
        |> Repo.one()

      case step do
        nil ->
          {:error, :not_found}

        %{status: status} = step when status in ~w(pending in_progress) ->
          do_mark_step_outdated(step, status, opts)

        _step ->
          {:error, :cannot_mark_outdated}
      end
    end)
    |> tap_ok(&broadcast(:plan_step_updated, &1))
  end

  defp do_mark_step_outdated(step, status, opts) do
    result = Keyword.get(opts, :result)
    metadata = Keyword.get(opts, :metadata, %{})

    attrs = %{
      status: "outdated",
      result: result,
      metadata: Map.merge(step.metadata, metadata)
    }

    with {:ok, updated_step} <- step |> step_update_changeset(attrs) |> Repo.update() do
      maybe_release_plan(updated_step, status)
    end
  end

  defp maybe_release_plan(step, "in_progress") do
    case mark_plan_idle(step.plan_id) do
      {:ok, _plan} -> {:ok, step}
      error -> error
    end
  end

  defp maybe_release_plan(step, _status), do: {:ok, step}

  @doc """
  Updates a plan step's status, result, or metadata.

  Note: For normal workflow, prefer `complete_plan_step/2` or `fail_plan_step/2`
  which also handle plan status transitions.

  Status transitions are validated:
  - pending -> in_progress | deferred | outdated
  - in_progress -> completed | failed | outdated
  - deferred -> pending
  - completed, failed, and outdated are terminal states
  """
  def update_plan_step(step_id, attrs) when is_binary(step_id) do
    case Repo.get(PlanStep, step_id) do
      nil ->
        {:error, :not_found}

      step ->
        attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

        if valid_step_status_transition?(step.status, Map.get(attrs, "status")) do
          step
          |> step_update_changeset(attrs)
          |> Repo.update()
          |> tap_ok(&broadcast(:plan_step_updated, &1))
        else
          {:error, :invalid_status_transition}
        end
    end
  end

  defp valid_step_status_transition?(_current, nil), do: true
  defp valid_step_status_transition?(current, new) when current == new, do: true
  defp valid_step_status_transition?("pending", "in_progress"), do: true
  defp valid_step_status_transition?("pending", "deferred"), do: true
  defp valid_step_status_transition?("pending", "outdated"), do: true
  defp valid_step_status_transition?("in_progress", "completed"), do: true
  defp valid_step_status_transition?("in_progress", "failed"), do: true
  defp valid_step_status_transition?("in_progress", "outdated"), do: true
  defp valid_step_status_transition?("deferred", "pending"), do: true
  defp valid_step_status_transition?(_, _), do: false

  @doc """
  Lists all steps for a plan.

  ## Options
    * `:status` - Filter by status (e.g., "pending", "in_progress", "completed", "failed")

  Results are always ordered by step_number ascending.
  """
  def list_plan_steps(plan_id, opts \\ []) when is_binary(plan_id) do
    status = Keyword.get(opts, :status)

    Query.steps_for_plan(plan_id)
    |> maybe_filter_step_status(status)
    |> Query.ordered_by_step_number(:asc)
    |> Repo.all()
  end

  defp maybe_filter_step_status(query, nil), do: query
  defp maybe_filter_step_status(query, status), do: Query.with_status(query, status)

  @doc """
  Gets a specific step by plan_id and step_number.
  """
  def get_plan_step(plan_id, step_number) when is_binary(plan_id) do
    Query.steps_for_plan(plan_id)
    |> Query.with_step_number(step_number)
    |> Repo.one()
  end

  @doc """
  Gets a step by its primary key ID.
  """
  def get_plan_step_by_id(step_id) when is_binary(step_id) do
    Repo.get(PlanStep, step_id)
  end

  ## Changesets

  defp step_changeset(step, attrs) do
    step
    |> cast(attrs, [
      :plan_id,
      :step_number,
      :description,
      :status,
      :result,
      :created_by,
      :metadata,
      :project_id
    ])
    |> validate_required([:plan_id, :step_number, :description, :project_id])
    |> validate_inclusion(:status, @step_statuses)
    |> validate_inclusion(:created_by, ~w(user agent))
    |> foreign_key_constraint(:plan_id)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:plan_id, :step_number])
  end

  defp step_update_changeset(step, attrs) do
    step
    |> cast(attrs, [:status, :result, :metadata])
    |> validate_inclusion(:status, @step_statuses)
  end

  defp update_plan_status(plan, status) do
    plan
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @plan_statuses)
    |> Repo.update()
  end

  ## Helpers

  defp wrap_result(nil), do: {:error, :not_found}
  defp wrap_result(record), do: {:ok, record}

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(PopStash.PubSub, "plans:events", {event, payload})
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(error, _fun), do: error
end
