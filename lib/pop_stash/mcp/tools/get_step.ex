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
        Get full details of a specific step including result and metadata.

        WHEN TO USE:
        - Need complete step information
        - Want to see execution result
        - Inspecting step metadata
        - Debugging a specific step
        - Reviewing step history

        RETURNS:
        - Step ID, plan ID, step number
        - Status (pending, in_progress, completed, failed, etc.)
        - Full description (not truncated)
        - Execution result (if step has been executed)
        - Metadata (additional context)
        - Created by (agent or user)
        - Timestamps

        TYPICAL WORKFLOW:
        1. get_plan_steps(plan_id: "...") to see compact list
        2. Find step_id of interest
        3. get_step(step_id: "...") to see full details

        USE CASES:
        - "What was the result of this step?"
        - "Why did this step fail?"
        - "What metadata is attached to this step?"
        - "When was this step created/completed?"

        For compact overview of all steps, use get_plan_steps instead.
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
