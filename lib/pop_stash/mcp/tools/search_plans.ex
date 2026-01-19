defmodule PopStash.MCP.Tools.SearchPlans do
  @moduledoc """
  MCP tool for semantic search of plans.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "search_plans",
        description: """
        Search plans using semantic similarity across all content.

        WHEN TO USE:
        - Finding plans related to a concept or topic
        - Not sure of exact plan title
        - Discovering plans with specific information
        - Exploring what's been planned in an area
        - Need to find related planning documents

        HOW IT WORKS:
        - Vector-based semantic search across title, body, and tags
        - Finds relevant plans even when exact keywords don't match
        - Returns ranked results by relevance

        SEARCH TIPS:
        - Use natural language (e.g., "authentication implementation")
        - Ask questions (e.g., "how should we handle errors?")
        - Use descriptive phrases (e.g., "database migration strategy")
        - To exclude words, prefix with - (e.g., "deployment -docker")
        - Keep queries brief (under ~100 words)
        - Long queries may fail or fall back to keyword-only search

        WHEN TO USE get_plan INSTEAD:
        - You know the exact plan title
        - You want to list all plans
        - You need a specific plan by title

        WORKING WITH RESULTS:
        - Each result includes plan_id
        - Store plan_id for use with step management tools
        - Use get_plan with exact title to see full plan

        Returns ranked list with previews and plan_id for each result.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "Natural language search query"
            },
            limit: %{
              type: "integer",
              description: "Maximum number of results to return (default: 10)"
            }
          },
          required: ["query"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"query" => query} = args, %{project_id: project_id}) do
    limit = Map.get(args, "limit", 10)

    case Memory.search_plans(project_id, query, limit: limit) do
      {:ok, []} ->
        Memory.log_search(project_id, query, :plans, :semantic,
          tool: "search_plans",
          result_count: 0,
          found: false
        )

        {:ok,
         """
         No plans found matching "#{query}".

         Try:
         - Using different keywords or phrases
         - Using `get_plan` with `list_titles: true` to see all available plans
         - Using `save_plan` to create a new plan
         """}

      {:ok, results} ->
        Memory.log_search(project_id, query, :plans, :semantic,
          tool: "search_plans",
          result_count: length(results),
          found: true
        )

        format_results(results, query)

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  defp format_results(plans, query) do
    header = "Plans matching \"#{query}\" (#{length(plans)} found):\n\n"
    formatted = Enum.map_join(plans, "\n---\n\n", &format_plan/1)
    {:ok, header <> formatted}
  end

  defp format_plan(plan) do
    timestamp = Calendar.strftime(plan.inserted_at, "%Y-%m-%d %H:%M UTC")
    preview = String.slice(plan.body, 0, 300)

    preview =
      if String.length(plan.body) > 300 do
        preview <> "..."
      else
        preview
      end

    tags =
      if plan.tags && plan.tags != [] do
        "\n**Tags:** #{Enum.join(plan.tags, ", ")}"
      else
        ""
      end

    """
    **#{plan.title}**
    #{preview}
    #{tags}
    *Created: #{timestamp}*

    _Use `get_plan` with title "#{plan.title}" to see the full plan._
    """
  end
end
