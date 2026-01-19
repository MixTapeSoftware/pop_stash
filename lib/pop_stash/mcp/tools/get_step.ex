defmodule PopStash.MCP.Tools.GetStep do
  @moduledoc """
  MCP tool for getting full details of a single plan step.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Plans

  @impl true
  def tools do
    [
      %{
        name: "get_step",
        description: """
        Get full details of a specific plan step by its ID.

        Returns all step information including description, status, result, metadata, and timestamps.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            step_id: %{
              type: "string",
              description: "ID of the step"
            }
          },
          required: ["step_id"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"step_id" => step_id}, _context) do
    case Plans.get_plan_step_by_id(step_id) do
      nil ->
        {:error, "Step not found"}

      step ->
        {:ok, format_step(step)}
    end
  end

  defp format_step(step) do
    timestamp = Calendar.strftime(step.inserted_at, "%Y-%m-%d %H:%M UTC")

    metadata =
      if step.metadata && map_size(step.metadata) > 0 do
        "\n**Metadata:** #{inspect(step.metadata)}"
      else
        ""
      end

    result =
      if step.result do
        "\n**Result:** #{step.result}"
      else
        ""
      end

    """
    # Step #{step.step_number}

    **Step ID:** #{step.id}
    **Plan ID:** #{step.plan_id}
    **Status:** #{step.status}
    **Created by:** #{step.created_by}
    **Created:** #{timestamp}

    ## Description

    #{step.description}
    #{result}#{metadata}
    """
  end
end
