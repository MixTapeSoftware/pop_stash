defmodule PopStash.MCP.Tools.SaveContext do
  @moduledoc """
  MCP tool for creating contexts.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "save_context",
        description: """
        Save working context to preserve progress across sessions.

        WHEN TO USE:
        - Switching between tasks or projects
        - Context is getting long (>20 messages)
        - Before exploring tangents or alternative approaches
        - Pausing work to come back later
        - Want to preserve your thought process

        THREAD_ID MECHANICS:
        - Omit thread_id for NEW context (system generates one)
        - Pass back thread_id from previous save to create a REVISION
        - All revisions share the same thread_id
        - Use timestamps to determine latest version

        BEST PRACTICES:
        - Use short descriptive titles (e.g., "auth-refactor", "bug-123")
        - Include current state and next steps in body
        - Add files you're working on for quick reference
        - Use tags to categorize: ["bug", "feature", "investigation"]

        TYPICAL WORKFLOW:
        1. save_context(title: "auth-fix", body: "Fixed token validation, next: test refresh")
        2. ... work on other things ...
        3. restore_context(name: "auth-fix") to resume
        4. save_context(title: "auth-fix", body: "Completed refresh tests", thread_id: "cthr_xyz")

        Returns thread_id for creating revisions.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            title: %{type: "string", description: "Short title (e.g., 'auth-wip')"},
            body: %{type: "string", description: "What you're working on"},
            files: %{type: "array", items: %{type: "string"}},
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
          required: ["title", "body"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    opts =
      [
        files: Map.get(args, "files", []),
        tags: Map.get(args, "tags", [])
      ]
      |> maybe_add_thread_id(args["thread_id"])

    case Memory.create_context(project_id, args["title"], args["body"], opts) do
      {:ok, context} ->
        {:ok,
         "Saved context '#{context.title}'. Use `restore_context` with title '#{context.title}' to restore. (thread_id: #{context.thread_id})"}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp maybe_add_thread_id(opts, nil), do: opts
  defp maybe_add_thread_id(opts, thread_id), do: Keyword.put(opts, :thread_id, thread_id)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
