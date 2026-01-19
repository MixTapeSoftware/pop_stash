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
        Add a step to a plan.

        Steps are executed sequentially by step_number. You can:
        - Add at the end (default): Just provide plan_id and description
        - Insert at position: Use step_number for explicit placement
        - Insert after a step: Use after_step to calculate midpoint

        Use this when you need to add tasks to an execution plan.
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
