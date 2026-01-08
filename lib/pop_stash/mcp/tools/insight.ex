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
            key: %{type: "string", description: "Optional key for retrieval"},
            content: %{type: "string", description: "The insight"}
          },
          required: ["content"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    opts = if args["key"], do: [key: args["key"]], else: []

    case Memory.create_insight(project_id, args["content"], opts) do
      {:ok, insight} ->
        key_text = if insight.key, do: " (key: #{insight.key})", else: ""
        {:ok, "Insight saved#{key_text}. Use `recall` to retrieve."}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
