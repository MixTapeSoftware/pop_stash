defmodule PopStash.MCP.Tools.UpdateStep do
  @moduledoc """
  MCP tool for updating a plan step.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Plans

  @impl true
  def tools do
    [
      %{
        name: "update_step",
        description: """
        Update a plan step's status, result, or metadata.

        Status transitions:
        - pending -> completed | failed (marks complete without going through in_progress)
        - in_progress -> completed | failed

        Note: You cannot set status to "in_progress" directly. The HTTP API handles
        that automatically when claiming a step for execution.

        Use `complete_step` or `fail_step` for workflow transitions that also
        update the plan's status appropriately.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            step_id: %{
              type: "string",
              description: "ID of the step to update"
            },
            status: %{
              type: "string",
              enum: ["completed", "failed"],
              description: "New status (completed or failed only)"
            },
            result: %{
              type: "string",
              description: "Execution result or notes"
            },
            metadata: %{
              type: "object",
              description: "Additional context to merge with existing metadata"
            }
          },
          required: ["step_id"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, _context) do
    step_id = args["step_id"]

    attrs =
      %{}
      |> maybe_put("status", args["status"])
      |> maybe_put("result", args["result"])
      |> maybe_put("metadata", args["metadata"])

    if map_size(attrs) == 0 do
      {:error, "At least one of status, result, or metadata must be provided"}
    else
      do_update(step_id, attrs)
    end
  end

  defp do_update(step_id, attrs) do
    case Plans.update_plan_step(step_id, attrs) do
      {:ok, step} ->
        {:ok,
         """
         Updated step #{step.step_number} (step_id: #{step.id})

         Status: #{step.status}
         Result: #{step.result || "(none)"}
         """}

      {:error, :not_found} ->
        {:error, "Step not found"}

      {:error, :invalid_status_transition} ->
        {:error,
         "Invalid status transition. Valid transitions: pending -> completed/failed, in_progress -> completed/failed"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}

      {:error, reason} ->
        {:error, "Failed to update step: #{inspect(reason)}"}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
