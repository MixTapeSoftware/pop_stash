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
        Query recorded decisions. Provide a topic to get all decisions for that topic, \
        or omit topic to list recent decisions. Topics are matched case-insensitively.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            topic: %{
              type: "string",
              description: "Topic to query (optional - if omitted, lists recent decisions)"
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

  def execute(args, %{project_id: project_id}) do
    limit = Map.get(args, "limit", 10)
    opts = [limit: limit]
    opts = if topic = args["topic"], do: Keyword.put(opts, :topic, topic), else: opts

    decisions = Memory.list_decisions(project_id, opts)

    format_decisions(decisions, args["topic"])
  end

  defp format_decisions([], nil) do
    {:ok, "No decisions recorded yet. Use `decide` to record architectural decisions."}
  end

  defp format_decisions([], topic) do
    {:ok,
     "No decisions found for topic \"#{topic}\". Use `get_decisions` with `list_topics: true` to see available topics."}
  end

  defp format_decisions(decisions, topic) do
    header =
      if topic do
        "Decisions for \"#{topic}\" (#{length(decisions)} found, most recent first):\n\n"
      else
        "Recent decisions (#{length(decisions)}):\n\n"
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
