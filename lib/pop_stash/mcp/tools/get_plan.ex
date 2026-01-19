defmodule PopStash.MCP.Tools.GetPlan do
  @moduledoc """
  MCP tool for retrieving plans.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory
  alias PopStash.Plans

  @impl true
  def tools do
    [
      %{
        name: "get_plan",
        description: """
        Retrieve project plans by title or search for plans.

        Plans capture roadmaps, architecture, and implementation strategies.

        Search modes:
        - Provide `title` only: Returns the plan with that title
        - Provide `list_titles: true`: Lists all plan titles in the project
        - Provide nothing: Lists recent plans
        - Use natural language in `title` for semantic search if no exact match

        Titles are matched case-sensitively for exact lookups.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description:
                "Plan title for exact match (e.g., 'Q1 2024 Roadmap') or natural language query for semantic search"
            },
            list_titles: %{
              type: "boolean",
              description: "If true, returns only the list of unique plan titles"
            },
            limit: %{
              type: "integer",
              description: "Maximum number of plans to return (default: 10)"
            }
          },
          required: []
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  # List all plan titles
  def execute(%{"list_titles" => true}, %{project_id: project_id}) do
    titles = Plans.list_plan_titles(project_id)

    if titles == [] do
      {:ok, "No plans saved yet. Use `save_plan` to create your first plan."}
    else
      title_list = Enum.map_join(titles, "\n", &"  • #{&1}")
      {:ok, "Plan titles:\n#{title_list}"}
    end
  end

  # Get a plan by title (with fallback to semantic search)
  def execute(%{"title" => title} = args, %{project_id: project_id}) do
    limit = Map.get(args, "limit", 10)

    case Plans.get_plan(project_id, title) do
      {:ok, plan} ->
        {:ok, format_plan(plan)}

      {:error, :not_found} ->
        search_plans_by_title(project_id, title, limit)
    end
  end

  # List recent plans
  def execute(args, %{project_id: project_id}) do
    limit = Map.get(args, "limit", 10)
    plans = Plans.list_plans(project_id, limit: limit)
    format_plans_list(plans)
  end

  defp search_plans_by_title(project_id, query, limit) do
    case Memory.search_plans(project_id, query, limit: limit) do
      {:ok, []} ->
        Memory.log_search(project_id, query, :plans, :semantic,
          tool: "get_plan",
          result_count: 0,
          found: false
        )

        {:ok,
         "No plan found with title \"#{query}\". Use `get_plan` with `list_titles: true` to see available plans."}

      {:ok, results} ->
        Memory.log_search(project_id, query, :plans, :semantic,
          tool: "get_plan",
          result_count: length(results),
          found: true
        )

        header = "Plans matching \"#{query}\" (#{length(results)} found via semantic search):\n\n"
        formatted = Enum.map_join(results, "\n---\n\n", &format_plan_summary/1)
        {:ok, header <> formatted}

      {:error, _reason} ->
        {:ok,
         "No plan found with title \"#{query}\". Use `get_plan` with `list_titles: true` to see available plans."}
    end
  end

  defp format_plans_list([]) do
    {:ok, "No plans saved yet. Use `save_plan` to create your first plan."}
  end

  defp format_plans_list(plans) do
    header = "Recent plans (#{length(plans)}):\n\n"
    formatted = Enum.map_join(plans, "\n---\n\n", &format_plan_summary/1)
    {:ok, header <> formatted}
  end

  defp format_plan(plan) do
    timestamp = Calendar.strftime(plan.inserted_at, "%Y-%m-%d %H:%M UTC")

    tags =
      if plan.tags && plan.tags != [] do
        "\n**Tags:** #{Enum.join(plan.tags, ", ")}"
      else
        ""
      end

    """
    # #{plan.title}

    #{plan.body}
    #{tags}
    *Created: #{timestamp}*
    """
  end

  defp format_plan_summary(plan) do
    timestamp = Calendar.strftime(plan.inserted_at, "%Y-%m-%d %H:%M UTC")
    preview = String.slice(plan.body, 0, 200)

    preview =
      if String.length(plan.body) > 200 do
        preview <> "..."
      else
        preview
      end

    tags =
      if plan.tags && plan.tags != [] do
        " • Tags: #{Enum.join(plan.tags, ", ")}"
      else
        ""
      end

    """
    **#{plan.title}**
    #{preview}
    *Created: #{timestamp}#{tags}*
    """
  end
end
