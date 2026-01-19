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
        Save a project plan, roadmap, or implementation strategy.

        WHEN TO USE:
        - Creating project roadmaps and milestones
        - Documenting architecture designs
        - Planning feature implementations
        - Breaking down complex work into steps
        - Preserving implementation strategies

        PLANS VS OTHER TOOLS:
        - Contexts: Temporary working state (use save_context)
        - Insights: Persistent knowledge (use insight)
        - Decisions: Architectural choices (use decide)
        - Plans: Structured roadmaps with executable steps

        PLANS ARE IMMUTABLE:
        - Unlike contexts/insights/decisions, plans do NOT use thread_id
        - Plans cannot be revised - create a new plan instead
        - Plans support executable steps via step management tools

        WORKING WITH STEPS:
        - Returns plan_id which you use with step tools
        - Use add_step to add executable tasks to the plan
        - Use get_plan_steps to see progress
        - Use peek_next_step to see what's next
        - Use update_step to mark steps completed

        BEST PRACTICES:
        - Use descriptive titles (e.g., "Q1 2024 Roadmap", "Auth Implementation")
        - Include goals, approach, and architecture in body
        - Use markdown for formatting (headers, lists, code blocks)
        - Add tags for categorization: ["feature", "architecture", "roadmap"]
        - Reference related files in the files array

        Returns plan_id for use with step management tools.
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
