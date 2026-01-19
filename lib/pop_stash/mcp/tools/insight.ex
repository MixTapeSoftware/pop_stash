defmodule PopStash.MCP.Tools.Insight do
  @moduledoc """
  MCP tool for creating insights.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "insight",
        description: """
        Save persistent knowledge about the codebase that's worth remembering.

        WHEN TO USE:
        - Discovered something non-obvious about how code works
        - Learned how components interact
        - Found undocumented behavior or patterns
        - Identified conventions or best practices
        - Uncovered gotchas or common pitfalls

        WHAT MAKES A GOOD INSIGHT:
        - "The auth middleware silently converts guest users to anonymous sessions"
        - "API rate limits reset at UTC midnight, not rolling 24h windows"
        - "All database queries timeout after 15s (configured in repo.ex)"
        - "WebSocket connections are auto-reconnected with exponential backoff"

        THREAD_ID MECHANICS:
        - Omit thread_id for NEW insights (system generates one)
        - Pass back thread_id to create a REVISION (refines/corrects previous insight)
        - All revisions share the same thread_id
        - Use timestamps to determine latest version

        BEST PRACTICES:
        - Keep insights atomic - one concept per insight
        - Use descriptive titles for easy searching (e.g., "auth/session-handling")
        - Link to specific files or code locations when relevant
        - Update insights when you learn more (pass thread_id)

        TYPICAL WORKFLOW:
        1. insight(body: "Rate limits reset at midnight", title: "api/rate-limits")
        2. ... later discover more details ...
        3. insight(body: "Rate limits reset at UTC midnight per-key", title: "api/rate-limits", thread_id: "ithr_xyz")

        Returns thread_id for creating revisions.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{type: "string", description: "Optional title for the insight"},
            body: %{type: "string", description: "The insight content"},
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Optional tags for categorization"
            },
            thread_id: %{
              type: "string",
              description:
                "Optional thread ID to connect revisions (omit for new, pass back for revisions)"
            }
          },
          required: ["body"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    opts =
      []
      |> maybe_add_opt(:title, args["title"])
      |> maybe_add_opt(:tags, args["tags"])
      |> maybe_add_opt(:thread_id, args["thread_id"])

    case Memory.create_insight(project_id, args["body"], opts) do
      {:ok, insight} ->
        title_text = if insight.title, do: " (title: #{insight.title})", else: ""

        {:ok,
         "Insight saved#{title_text}. Use `recall` to retrieve. (thread_id: #{insight.thread_id})"}

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
