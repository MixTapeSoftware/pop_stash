defmodule PopStash.MCP.Tools.PeekNextStep do
  @moduledoc """
  MCP tool for peeking at the next pending step in a plan.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Plans

  @impl true
  def tools do
    [
      %{
        name: "peek_next_step",
        description: """
        Peek at the next pending step in a plan without changing its status.

        This is a read-only operation for debugging or inspection.
        For actual execution, use the HTTP API which atomically claims steps.

        Returns the first step with status "pending" ordered by step_number.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            plan_id: %{
              type: "string",
              description: "ID of the plan"
            }
          },
          required: ["plan_id"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"plan_id" => plan_id}, _context) do
    case Plans.get_next_plan_step(plan_id) do
      nil ->
        {:ok, "No pending steps. The plan may be completed or all steps are in progress/done."}

      step ->
        {:ok,
         """
         Next pending step:

         Step ID: #{step.id}
         Step number: #{step.step_number}
         Description: #{step.description}
         Created by: #{step.created_by}
         Status: #{step.status}
         """}
    end
  end
end
