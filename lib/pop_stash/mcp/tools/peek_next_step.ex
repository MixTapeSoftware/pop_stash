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
        Peek at the next pending step without changing its status (read-only).

        WHEN TO USE:
        - Checking what step is next without claiming it
        - Debugging plan execution flow
        - Inspecting plan progress
        - Previewing upcoming work

        HOW IT WORKS:
        - Returns first step with status "pending"
        - Ordered by step_number ascending
        - Does NOT change step status (read-only)
        - Does NOT claim the step for execution

        PEEK VS HTTP API:
        - peek_next_step: Read-only preview, doesn't claim step
        - HTTP API /next: Atomically claims step and marks in_progress
        - Use peek for inspection, HTTP API for actual execution

        TYPICAL WORKFLOW:
        1. get_plan_steps(plan_id: "...") to see all steps
        2. peek_next_step(plan_id: "...") to see what's next
        3. HTTP API /next to claim and execute

        RETURNS:
        - Step ID, step_number, description, status
        - Null if no pending steps (all done or in-progress)

        USE CASES:
        - "What's the next task in this plan?"
        - "Is there more work to do?"
        - "What step are we on?"
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
