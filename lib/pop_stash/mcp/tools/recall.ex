defmodule PopStash.MCP.Tools.Recall do
  @moduledoc """
  MCP tool for retrieving insights by exact key or semantic search.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "recall",
        description: """
        Retrieve saved insights by exact title or semantic search.

        WHEN TO USE:
        - Starting work in unfamiliar code area
        - Before making architectural changes
        - When something "should work" but doesn't
        - Onboarding to a new part of the codebase
        - Need to remember how something was designed

        SEARCH MODES:
        - Exact match: Use the exact title (e.g., "auth/session-handling")
        - Semantic search: Use natural language (e.g., "how authentication works")
        - Semantic finds conceptually similar content, not just keyword matches

        SEARCH TIPS:
        - Exact titles are tried first, then semantic search
        - To exclude words, prefix with - (e.g., "electric car" -tesla)
        - Keep queries brief (under ~100 words)
        - Long queries may fail or fall back to keyword-only search

        THREAD_ID IN RESULTS:
        - Each result includes a thread_id
        - Store thread_id if you discover more details later
        - Pass it to insight to create a revision (refinement)

        BEST PRACTICE:
        - Search before diving into unfamiliar code
        - Insights capture hard-won knowledge - use them!

        Returns ranked list with match_type indicator (exact or semantic).
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description:
                "Exact insight title (e.g., 'auth-flow') or natural language query (e.g., 'user authentication')"
            },
            limit: %{
              type: "number",
              description: "Maximum results to return (default: 5)"
            }
          },
          required: ["title"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"title" => query} = params, %{project_id: project_id}) do
    limit = Map.get(params, "limit", 5)

    # Try exact match first
    case Memory.get_insight_by_title(project_id, query) do
      {:ok, insight} ->
        {:ok, %{results: [format_insight(insight)], match_type: "exact"}}

      {:error, :not_found} ->
        # Fall back to semantic search
        case Memory.search_insights(project_id, query, limit: limit) do
          {:ok, []} ->
            Memory.log_search(project_id, query, :insights, :semantic,
              tool: "recall",
              result_count: 0,
              found: false
            )

            recent = Memory.list_insights(project_id, limit: 5)
            hint = build_hint(recent)
            {:ok, %{results: [], message: "No insights found matching '#{query}'. #{hint}"}}

          {:ok, results} ->
            Memory.log_search(project_id, query, :insights, :semantic,
              tool: "recall",
              result_count: length(results),
              found: true
            )

            {:ok, %{results: Enum.map(results, &format_insight/1), match_type: "semantic"}}

          {:error, :embeddings_disabled} ->
            {:error, "Semantic search unavailable. Use exact title match."}

          {:error, :timeout} ->
            {:error, "Search timed out. Try using an exact insight title."}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
    end
  end

  defp format_insight(insight) do
    %{
      id: insight.id,
      title: insight.title,
      body: insight.body,
      thread_id: insight.thread_id,
      created_at: insight.inserted_at
    }
  end

  defp build_hint([]), do: "No insights yet."

  defp build_hint(recent) do
    titles =
      recent
      |> Enum.filter(& &1.title)
      |> Enum.map_join(", ", & &1.title)

    if titles == "", do: "No titled insights.", else: "Recent titles: #{titles}"
  end
end
