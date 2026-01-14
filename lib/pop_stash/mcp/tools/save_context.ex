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
        description: "Save context for later. Use when switching tasks or context is long.",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Short name (e.g., 'auth-wip')"},
            summary: %{type: "string", description: "What you're working on"},
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
          required: ["name", "summary"]
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

    case Memory.create_context(project_id, args["name"], args["summary"], opts) do
      {:ok, context} ->
        {:ok,
         "Saved context '#{context.name}'. Use `restore_context` with name '#{context.name}' to restore. (thread_id: #{context.thread_id})"}

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
