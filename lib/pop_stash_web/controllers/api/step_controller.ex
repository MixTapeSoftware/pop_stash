defmodule PopStashWeb.API.StepController do
  use PopStashWeb, :controller

  alias PopStash.Memory.PlanStep
  alias PopStash.Plans

  @doc """
  Gets a specific step by ID.
  """
  def show(conn, %{"id" => step_id}) do
    case Plans.get_plan_step_by_id(step_id) do
      %PlanStep{} = step ->
        json(conn, %{step: step_json(step)})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Step not found"})
    end
  end

  @doc """
  Updates a step's status, result, or metadata.

  Expects JSON body with any of: "status", "result", "metadata"

  When status is "completed" or "failed", this automatically handles plan status
  transitions (releases the plan back to idle or marks it failed).
  """
  def update(conn, %{"id" => step_id} = params) do
    attrs = build_update_attrs(params)

    if map_size(attrs) == 0 do
      send_error(conn, :bad_request, "No valid fields to update (status, result, metadata)")
    else
      step_id
      |> perform_step_update(attrs, params)
      |> handle_update_result(conn)
    end
  end

  # Helpers

  defp perform_step_update(step_id, attrs, params) do
    case Map.get(attrs, "status") do
      "completed" ->
        opts = build_completion_opts(params)
        Plans.complete_plan_step(step_id, opts)

      "failed" ->
        opts = build_completion_opts(params)
        Plans.fail_plan_step(step_id, opts)

      _ ->
        Plans.update_plan_step(step_id, attrs)
    end
  end

  defp handle_update_result({:ok, step}, conn) do
    json(conn, %{step: step_json(step)})
  end

  defp handle_update_result({:error, :not_found}, conn) do
    send_error(conn, :not_found, "Step not found")
  end

  defp handle_update_result({:error, :invalid_status_transition}, conn) do
    send_error(conn, :unprocessable_entity, "Invalid status transition")
  end

  defp handle_update_result({:error, :step_not_in_progress}, conn) do
    send_error(conn, :unprocessable_entity, "Step must be in_progress to complete or fail")
  end

  defp handle_update_result({:error, changeset}, conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid step data", details: changeset_errors(changeset)})
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  defp build_update_attrs(params) do
    %{}
    |> maybe_put_attr("status", Map.get(params, "status"))
    |> maybe_put_attr("result", Map.get(params, "result"))
    |> maybe_put_attr("metadata", Map.get(params, "metadata"))
  end

  defp build_completion_opts(params) do
    []
    |> maybe_add_opt(:result, Map.get(params, "result"))
    |> maybe_add_opt(:metadata, Map.get(params, "metadata"))
  end

  defp maybe_put_attr(attrs, _key, nil), do: attrs
  defp maybe_put_attr(attrs, key, value), do: Map.put(attrs, key, value)

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

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
