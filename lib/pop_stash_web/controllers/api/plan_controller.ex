defmodule PopStashWeb.API.PlanController do
  use PopStashWeb, :controller

  alias PopStash.Memory.Plan
  alias PopStash.Memory.PlanStep
  alias PopStash.Plans
  alias PopStash.Projects

  @doc """
  Lists all plans for the project.

  Optional query param: ?title=<title> for filtering by exact title.
  """
  def index(conn, params) do
    with {:ok, project_id} <- get_project_id(conn) do
      opts =
        case Map.get(params, "title") do
          nil -> []
          title -> [title: title]
        end

      plans = Plans.list_plans(project_id, opts)
      json(conn, %{plans: Enum.map(plans, &plan_json/1)})
    end
  end

  @doc """
  Creates a new plan.

  Expects JSON body: {"title": "...", "body": "..."}
  Optional: "tags", "files"
  """
  def create(conn, %{"title" => title, "body" => body} = params) do
    with {:ok, project_id} <- get_project_id(conn) do
      opts = build_plan_opts(params)

      case Plans.create_plan(project_id, title, body, opts) do
        {:ok, plan} ->
          conn
          |> put_status(:created)
          |> json(%{plan: plan_json(plan)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Invalid plan data", details: changeset_errors(changeset)})
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required fields: title, body"})
  end

  @doc """
  Gets a specific plan by ID.
  """
  def show(conn, %{"id" => plan_id}) do
    case Plans.get_plan_by_id(plan_id) do
      {:ok, plan} ->
        json(conn, %{plan: plan_json(plan)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Plan not found"})
    end
  end

  @doc """
  Gets the next pending step and marks it in_progress atomically.

  Returns:
  - {"status": "next", "step": {...}} - Got next step
  - {"status": "complete"} - All steps are done
  - {"status": "locked"} - Plan is locked by another agent
  - {"status": "not_active"} - Plan is paused, completed, or failed
  """
  def next_step(conn, %{"id" => plan_id}) do
    case Plans.get_next_step_and_mark_in_progress(plan_id) do
      {:ok, %PlanStep{} = step} ->
        json(conn, %{
          status: "next",
          step: step_json(step)
        })

      {:ok, :plan_completed} ->
        json(conn, %{status: "complete"})

      {:ok, :plan_locked} ->
        json(conn, %{status: "locked"})

      {:ok, :plan_not_active} ->
        json(conn, %{status: "not_active"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Plan not found"})
    end
  end

  @doc """
  Lists all steps for a plan.

  Optional query param: ?status=<status> for filtering by status.
  """
  def steps(conn, %{"id" => plan_id} = params) do
    opts =
      case Map.get(params, "status") do
        nil -> []
        status -> [status: status]
      end

    steps = Plans.list_plan_steps(plan_id, opts)
    json(conn, %{steps: Enum.map(steps, &step_json/1)})
  end

  @doc """
  Adds a step to a plan.

  Expects JSON body: {"description": "..."}
  Optional: "step_number", "after_step", "created_by", "metadata"
  """
  def add_step(conn, %{"id" => plan_id, "description" => description} = params) do
    opts = build_step_opts(params)

    case Plans.add_plan_step(plan_id, description, opts) do
      {:ok, step} ->
        conn
        |> put_status(:created)
        |> json(%{step: step_json(step)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Plan not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid step data", details: changeset_errors(changeset)})
    end
  end

  def add_step(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required field: description"})
  end

  # Helpers

  defp get_project_id(conn) do
    # Try to get project_id from X-Project-Id header first
    case get_req_header(conn, "x-project-id") do
      [project_id | _] when is_binary(project_id) and byte_size(project_id) > 0 ->
        {:ok, project_id}

      _ ->
        # Fall back to first available project
        case Projects.list() do
          [project | _] -> {:ok, project.id}
          [] -> {:error, :no_project}
        end
    end
  end

  defp build_plan_opts(params) do
    []
    |> maybe_add_opt(:tags, Map.get(params, "tags"))
    |> maybe_add_opt(:files, Map.get(params, "files"))
  end

  defp build_step_opts(params) do
    []
    |> maybe_add_opt(:step_number, Map.get(params, "step_number"))
    |> maybe_add_opt(:after_step, Map.get(params, "after_step"))
    |> maybe_add_opt(:created_by, Map.get(params, "created_by"))
    |> maybe_add_opt(:metadata, Map.get(params, "metadata"))
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp plan_json(%Plan{} = plan) do
    %{
      id: plan.id,
      title: plan.title,
      body: plan.body,
      status: plan.status,
      tags: plan.tags,
      files: plan.files,
      inserted_at: plan.inserted_at,
      updated_at: plan.updated_at
    }
  end

  defp step_json(%PlanStep{} = step) do
    %{
      id: step.id,
      plan_id: step.plan_id,
      step_number: step.step_number,
      description: step.description,
      status: step.status,
      result: step.result,
      created_by: step.created_by,
      metadata: step.metadata,
      inserted_at: step.inserted_at,
      updated_at: step.updated_at
    }
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
