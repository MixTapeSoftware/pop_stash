defmodule PopStash.MCP.Tools.RestoreContext do
  @moduledoc """
  MCP tool for retrieving contexts by exact name or semantic search.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "restore_context",
        description: """
        Retrieve contexts by name (exact match) or semantic search.

        Search tips:
        - Use exact names like "login-refactor" for precise matches
        - Use natural language like "changes to the login page" for semantic search
        - Semantic search finds conceptually similar contexts, not just keyword matches
        - To exclude words in your query explicitly, prefix the word with the - operator, e.g. "electric car" -tesla.
        - IMPORTANT: Keep search queries brief (under ~100 words). Long queries may fail or fall back to keyword-only search.

        Returns a ranked list of matching contexts with match_type indicator.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description:
                "Exact context name (e.g., 'login-refactor') or natural language query (e.g., 'authentication changes')"
            },
            limit: %{
              type: "number",
              description: "Maximum results to return (default: 5)"
            }
          },
          required: ["name"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"name" => query} = params, %{project_id: project_id}) do
    limit = Map.get(params, "limit", 5)

    # Try exact match first
    case Memory.get_context_by_name(project_id, query) do
      {:ok, context} ->
        {:ok, %{results: [format_context(context)], match_type: "exact"}}

      {:error, :not_found} ->
        # Fall back to semantic search
        case Memory.search_contexts(project_id, query, limit: limit) do
          {:ok, []} ->
            Memory.log_search(project_id, query, :contexts, :semantic,
              tool: "restore_context",
              result_count: 0,
              found: false
            )

            recent = Memory.list_contexts(project_id) |> Enum.take(5)
            hint = build_hint(recent)
            {:ok, %{results: [], message: "No contexts found matching '#{query}'. #{hint}"}}

          {:ok, results} ->
            Memory.log_search(project_id, query, :contexts, :semantic,
              tool: "restore_context",
              result_count: length(results),
              found: true
            )

            {:ok, %{results: Enum.map(results, &format_context/1), match_type: "semantic"}}

          {:error, :embeddings_disabled} ->
            {:error, "Semantic search unavailable. Use exact name match."}

          {:error, :timeout} ->
            {:error, "Search timed out. Try using an exact context name."}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
    end
  end

  defp format_context(context) do
    %{
      id: context.id,
      name: context.name,
      summary: context.summary,
      files: Map.get(context, :files, []),
      created_at: context.inserted_at
    }
  end

  defp build_hint([]), do: "No contexts yet."

  defp build_hint(recent) do
    "Recent contexts: " <> Enum.map_join(recent, ", ", & &1.name)
  end
end
