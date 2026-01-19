defmodule PopStash.MCP.Tools.SavePlan do
  @moduledoc """
  MCP tool for saving plans.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Plans

  @impl true
  def tools do
    [
      %{
        name: "save_plan",
        description: """
        Save a project plan or roadmap.

        Plans capture project roadmaps, architecture designs, or implementation strategies.

        Use this to:
        - Document project roadmaps and milestones
        - Save architecture design documents
        - Track implementation plans
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description: "Plan title (e.g., 'Q1 2024 Roadmap', 'Authentication Architecture')"
            },
            body: %{
              type: "string",
              description: "Plan content (supports markdown)"
            },
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Optional tags for categorization"
            },
            files: %{
              type: "array",
              items: %{type: "string"},
              description: "Optional list of related file paths"
            }
          },
          required: ["title", "body"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    opts = [
      tags: Map.get(args, "tags", []),
      files: Map.get(args, "files", [])
    ]

    case Plans.create_plan(project_id, args["title"], args["body"], opts) do
      {:ok, plan} ->
        {:ok,
         """
         Saved plan "#{plan.title}" (plan_id: #{plan.id})

         Use `get_plan` with title "#{plan.title}" to retrieve it.
         Use `search_plans` to find plans by content.
         Use the plan_id with step tools to add and manage plan steps.
         """}

      {:error, %Ecto.Changeset{errors: [project_id: _]}} ->
        {:error, "Project not found"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}

      {:error, reason} ->
        {:error, "Failed to save plan: #{inspect(reason)}"}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
