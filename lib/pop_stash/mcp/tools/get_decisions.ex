defmodule PopStash.MCP.Tools.GetDecisions do
  @moduledoc """
  MCP tool for querying decisions.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "get_decisions",
        description: """
        Query recorded decisions by topic or semantic search.

        Search tips:
        - Use exact topic names like "authentication" for precise matches
        - Use natural language like "security considerations" for semantic search
        - To exclude words in your query explicitly, prefix the word with the - operator, e.g. "electric car" -tesla.
        - Use list_topics to discover available topic names
        - Omit topic to list recent decisions
        - IMPORTANT: Keep search queries brief (under ~100 words). Long queries may fail or fall back to keyword-only search.

        Topics are matched case-insensitively for exact matches.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            topic: %{
              type: "string",
              description:
                "Exact topic name (e.g., 'authentication') or natural language query (e.g., 'how we handle security')"
            },
            limit: %{
              type: "integer",
              description: "Maximum number of decisions to return (default: 10)"
            },
            list_topics: %{
              type: "boolean",
              description:
                "If true, returns only the list of unique topics (ignores other params)"
            }
          },
          required: []
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"list_topics" => true}, %{project_id: project_id}) do
    topics = Memory.list_decision_topics(project_id)

    if topics === [] do
      {:ok, "No decisions recorded yet."}
    else
      topic_list = Enum.map_join(topics, "\n", &"  • #{&1}")
      {:ok, "Decision topics:\n#{topic_list}"}
    end
  end

  def execute(%{"topic" => topic} = args, %{project_id: project_id}) do
    limit = Map.get(args, "limit", 10)

    # Try exact topic match first
    case Memory.list_decisions(project_id, topic: topic, limit: limit) do
      [] ->
        search_decisions_by_topic(project_id, topic, limit)

      decisions ->
        format_decisions(decisions, topic, "exact")
    end
  end

  def execute(args, %{project_id: project_id}) do
    limit = Map.get(args, "limit", 10)
    decisions = Memory.list_decisions(project_id, limit: limit)
    format_decisions(decisions, nil, "list")
  end

  defp search_decisions_by_topic(project_id, topic, limit) do
    case Memory.search_decisions(project_id, topic, limit: limit) do
      {:ok, []} ->
        Memory.log_search(project_id, topic, :decisions, :semantic,
          tool: "get_decisions",
          result_count: 0,
          found: false
        )

        format_decisions([], topic, "exact")

      {:ok, results} ->
        Memory.log_search(project_id, topic, :decisions, :semantic,
          tool: "get_decisions",
          result_count: length(results),
          found: true
        )

        format_decisions(results, topic, "semantic")

      {:error, _reason} ->
        format_decisions([], topic, "exact")
    end
  end

  defp format_decisions([], nil, _match_type) do
    {:ok, "No decisions recorded yet. Use `decide` to record architectural decisions."}
  end

  defp format_decisions([], topic, _match_type) do
    {:ok,
     "No decisions found for topic \"#{topic}\". Use `get_decisions` with `list_topics: true` to see available topics."}
  end

  defp format_decisions(decisions, topic, match_type) do
    header =
      case {topic, match_type} do
        {nil, _} ->
          "Recent decisions (#{length(decisions)}):\n\n"

        {_, "semantic"} ->
          "Decisions matching \"#{topic}\" (#{length(decisions)} found via semantic search):\n\n"

        {_, _} ->
          "Decisions for \"#{topic}\" (#{length(decisions)} found, most recent first):\n\n"
      end

    formatted = Enum.map_join(decisions, "\n---\n\n", &format_decision/1)
    {:ok, header <> formatted}
  end

  defp format_decision(decision) do
    base = """
    **Topic:** #{decision.topic}
    **Decision:** #{decision.decision}
    """

    with_reasoning =
      if decision.reasoning do
        base <> "**Reasoning:** #{decision.reasoning}\n"
      else
        base
      end

    timestamp = Calendar.strftime(decision.inserted_at, "%Y-%m-%d %H:%M UTC")
    with_reasoning <> "*Recorded: #{timestamp}*"
  end
end
