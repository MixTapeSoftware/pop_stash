defmodule PopStash.MCP.Tools.Decide do
  @moduledoc """
  MCP tool for recording architectural decisions.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "decide",
        description: """
        Record an architectural or important or key technical decision. Decisions are immutable - \
        recording a new decision with the same title creates a new entry, preserving history. \
        Use this to document choices like "We chose Phoenix LiveView over React because..."
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description:
                "What area this decision affects (e.g., 'authentication', 'database', 'api-design')"
            },
            body: %{
              type: "string",
              description: "What was decided"
            },
            reasoning: %{
              type: "string",
              description: "Why this decision was made (optional but recommended)"
            },
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Optional tags for categorization (e.g., ['api', 'breaking-change'])"
            },
            thread_id: %{
              type: "string",
              description:
                "Optional thread ID to connect revisions (omit for new, pass back for revisions)"
            }
          },
          required: ["title", "body"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    opts =
      []
      |> maybe_add_opt(:reasoning, args["reasoning"])
      |> maybe_add_opt(:tags, args["tags"])
      |> maybe_add_opt(:thread_id, args["thread_id"])

    case Memory.create_decision(project_id, args["title"], args["body"], opts) do
      {:ok, decision} ->
        {:ok,
         """
         Decision recorded for title "#{decision.title}".
         Use `get_decisions` to retrieve decisions by title.
         (thread_id: #{decision.thread_id})
         """}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
