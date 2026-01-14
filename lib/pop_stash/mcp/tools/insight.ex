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
        description: "Save a persistent insight about the codebase.",
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
