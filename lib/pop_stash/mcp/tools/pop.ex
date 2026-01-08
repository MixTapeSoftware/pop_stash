defmodule PopStash.MCP.Tools.Pop do
  @moduledoc """
  MCP tool for retrieving stashes by exact name or semantic search.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "pop",
        description: """
        Retrieve stashes by name (exact match) or semantic search.

        Search tips:
        - Use exact names like "login-refactor" for precise matches
        - Use natural language like "changes to the login page" for semantic search
        - Semantic search finds conceptually similar stashes, not just keyword matches
        - To exclude words in your query explicitly, prefix the word with the - operator, e.g. "electric car" -tesla.

        Returns a ranked list of matching stashes with match_type indicator.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description:
                "Exact stash name (e.g., 'login-refactor') or natural language query (e.g., 'authentication changes')"
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
    case Memory.get_stash_by_name(project_id, query) do
      {:ok, stash} ->
        {:ok, %{results: [format_stash(stash)], match_type: "exact"}}

      {:error, :not_found} ->
        # Fall back to semantic search
        case Memory.search_stashes(project_id, query, limit: limit) do
          {:ok, []} ->
            recent = Memory.list_stashes(project_id) |> Enum.take(5)
            hint = build_hint(recent)
            {:ok, %{results: [], message: "No stashes found matching '#{query}'. #{hint}"}}

          {:ok, results} ->
            {:ok, %{results: Enum.map(results, &format_stash/1), match_type: "semantic"}}

          {:error, :embeddings_disabled} ->
            {:error, "Semantic search unavailable. Use exact name match."}

          {:error, :timeout} ->
            {:error, "Search timed out. Try using an exact stash name."}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
    end
  end

  defp format_stash(stash) do
    %{
      id: stash.id,
      name: stash.name,
      summary: stash.summary,
      files: Map.get(stash, :files, []),
      created_at: stash.inserted_at
    }
  end

  defp build_hint([]), do: "No stashes yet."

  defp build_hint(recent) do
    "Recent stashes: " <> Enum.map_join(recent, ", ", & &1.name)
  end
end
