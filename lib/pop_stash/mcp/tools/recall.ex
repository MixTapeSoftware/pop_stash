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
        Retrieve insights by key (exact match) or semantic search.

        Search tips:
        - Use exact keys like "auth-flow" for precise matches
        - Use natural language like "how authentication works" for semantic search
        - Semantic search finds conceptually similar content, not just keyword matches
        - To exclude words in your query explicitly, prefix the word with the - operator, e.g. "electric car" -tesla.
        - IMPORTANT: Keep search queries brief (under ~100 words). Long queries may fail or fall back to keyword-only search.

        Returns a ranked list of matching insights with match_type indicator.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            key: %{
              type: "string",
              description:
                "Exact insight key (e.g., 'auth-flow') or natural language query (e.g., 'user authentication')"
            },
            limit: %{
              type: "number",
              description: "Maximum results to return (default: 5)"
            }
          },
          required: ["key"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"key" => query} = params, %{project_id: project_id}) do
    limit = Map.get(params, "limit", 5)

    # Try exact match first
    case Memory.get_insight_by_key(project_id, query) do
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
            {:error, "Semantic search unavailable. Use exact key match."}

          {:error, :timeout} ->
            {:error, "Search timed out. Try using an exact insight key."}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
    end
  end

  defp format_insight(insight) do
    %{
      id: insight.id,
      key: insight.key,
      content: insight.content,
      thread_id: insight.thread_id,
      created_at: insight.inserted_at
    }
  end

  defp build_hint([]), do: "No insights yet."

  defp build_hint(recent) do
    keys =
      recent
      |> Enum.filter(& &1.key)
      |> Enum.map_join(", ", & &1.key)

    if keys == "", do: "No keyed insights.", else: "Recent keys: #{keys}"
  end
end
