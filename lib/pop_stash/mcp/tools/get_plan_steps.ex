defmodule PopStash.MCP.Tools.GetPlanSteps do
  @moduledoc """
  MCP tool for listing steps in a plan.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Plans

  @impl true
  def tools do
    [
      %{
        name: "get_plan_steps",
        description: """
        List all steps for a plan.

        Returns a compact list with step number, status, created_by, step_id, and description snippet.
        Steps are always ordered by step_number ascending.

        Use the status filter to see only pending, in_progress, completed, failed, deferred, or outdated steps.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            plan_id: %{
              type: "string",
              description: "ID of the plan"
            },
            status: %{
              type: "string",
              enum: ["pending", "in_progress", "completed", "failed", "deferred", "outdated"],
              description: "Filter by status (optional)"
            }
          },
          required: ["plan_id"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"plan_id" => plan_id} = args, _context) do
    opts =
      case args["status"] do
        nil -> []
        status -> [status: status]
      end

    steps = Plans.list_plan_steps(plan_id, opts)

    if steps == [] do
      status_msg =
        case args["status"] do
          nil -> ""
          status -> " with status '#{status}'"
        end

      {:ok, "No steps found#{status_msg}. Use `add_step` to add steps to the plan."}
    else
      header = "Steps (#{length(steps)}):\n\n"

      formatted = Enum.map_join(steps, "\n", &format_step/1)

      {:ok, header <> formatted}
    end
  end

  defp format_step(step) do
    snippet = String.slice(step.description, 0, 60)

    snippet =
      if String.length(step.description) > 60 do
        snippet <> "..."
      else
        snippet
      end

    status_icon = status_icon(step.status)

    "#{status_icon} #{step.step_number} | #{step.status} | #{step.created_by} | #{step.id} | #{snippet}"
  end

  defp status_icon("pending"), do: "○"
  defp status_icon("in_progress"), do: "◐"
  defp status_icon("completed"), do: "●"
  defp status_icon("failed"), do: "✗"
  defp status_icon("deferred"), do: "⊘"
  defp status_icon("outdated"), do: "◌"
  defp status_icon(_), do: "?"
end
