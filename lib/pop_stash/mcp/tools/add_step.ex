defmodule PopStash.MCP.Tools.AddStep do
  @moduledoc """
  MCP tool for adding steps to a plan.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Plans

  @impl true
  def tools do
    [
      %{
        name: "add_step",
        description: """
        Add an executable step to a plan for the RLM (Reason-Loop-Memory) workflow.

        WHEN TO USE:
        - Breaking down a plan into actionable tasks
        - Adding steps to a newly created plan
        - Inserting additional steps into existing plan
        - Creating an execution checklist

        HOW STEPS WORK:
        - Steps execute sequentially by step_number (float)
        - Each step has a status: pending -> in_progress -> completed/failed
        - HTTP API claims next pending step and marks it in_progress
        - After execution, step is marked completed or failed
        - Agents may mark tasks outdated and/or add new tasks within the execution loop.
        - Agents may also look up previous decisions or insights to guide their work.
        - Only one agent at a time may work on a project

        PLACEMENT OPTIONS:
        1. Append (default): Just provide plan_id and description
           - Auto-assigns next step_number (e.g., if last is 3.0, adds 4.0)
        2. Insert after: Use after_step to insert between steps
           - Calculates midpoint (e.g., after_step: 2.0 inserts at 2.5)
        3. Explicit position: Use step_number for precise placement
           - Overrides after_step if both provided

        BEST PRACTICES:
        - Use clear, actionable descriptions ("Run tests", "Deploy to staging")
        - Add steps in logical execution order
        - Use created_by to distinguish agent vs user steps
        - Use metadata for additional context (file paths, commands, notes)

        TYPICAL WORKFLOW:
        1. save_plan(title: "Feature X", body: "Implementation plan...")
        2. add_step(plan_id: "...", description: "Create database migration")
        3. add_step(plan_id: "...", description: "Implement service layer")
        4. add_step(plan_id: "...", description: "Add tests")
        5. add_step(plan_id: "...", description: "Update documentation")

        Returns step_id and step_number for the new step.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            plan_id: %{
              type: "string",
              description: "ID of the plan to add the step to"
            },
            description: %{
              type: "string",
              description: "What this step does"
            },
            after_step: %{
              type: "number",
              description:
                "Insert after this step number (calculates midpoint between this and next step)"
            },
            step_number: %{
              type: "number",
              description: "Explicit step number (float). Overrides after_step if both provided."
            },
            created_by: %{
              type: "string",
              enum: ["user", "agent"],
              description: "Who created the step. Defaults to 'agent'."
            },
            metadata: %{
              type: "object",
              description: "Additional context for the step"
            }
          },
          required: ["plan_id", "description"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, _context) do
    plan_id = args["plan_id"]
    description = args["description"]

    opts =
      []
      |> maybe_add_opt(:step_number, args["step_number"])
      |> maybe_add_opt(:after_step, args["after_step"])
      |> maybe_add_opt(:created_by, args["created_by"] || "agent")
      |> maybe_add_opt(:metadata, args["metadata"])

    case Plans.add_plan_step(plan_id, description, opts) do
      {:ok, step} ->
        {:ok,
         """
         Added step #{step.step_number} to plan (step_id: #{step.id})

         Step number: #{step.step_number}
         Description: #{step.description}
         Created by: #{step.created_by}
         Status: #{step.status}
         """}

      {:error, :not_found} ->
        {:error, "Plan not found"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}

      {:error, reason} ->
        {:error, "Failed to add step: #{inspect(reason)}"}
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
