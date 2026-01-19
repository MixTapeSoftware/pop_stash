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
        Retrieve saved contexts by exact name or semantic search.

        WHEN TO USE:
        - Resuming work on a previous task
        - Need context from a related investigation
        - Starting work in a familiar area
        - Picking up where you left off

        SEARCH MODES:
        - Exact match: Use the exact title (e.g., "login-refactor")
        - Semantic search: Use natural language (e.g., "authentication work")
        - Semantic finds conceptually similar contexts, not just keyword matches

        SEARCH TIPS:
        - Exact names are tried first, then semantic search
        - To exclude words, prefix with - (e.g., "electric car" -tesla)
        - Keep queries brief (under ~100 words)
        - Long queries may fail or fall back to keyword-only search

        THREAD_ID IN RESULTS:
        - Each result includes a thread_id
        - Store thread_id if you plan to create a revision later
        - Pass it to save_context to link related work

        Returns ranked list with match_type indicator (exact or semantic).
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
    case Memory.get_context_by_title(project_id, query) do
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
      name: context.title,
      summary: context.body,
      files: Map.get(context, :files, []),
      thread_id: context.thread_id,
      created_at: context.inserted_at
    }
  end

  defp build_hint([]), do: "No contexts yet."

  defp build_hint(recent) do
    "Recent contexts: " <> Enum.map_join(recent, ", ", & &1.title)
  end
end
