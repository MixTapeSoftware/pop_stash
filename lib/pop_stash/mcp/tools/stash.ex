defmodule PopStash.MCP.Tools.Stash do
  @moduledoc """
  MCP tool for creating stashes.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "stash",
        description: "Save context for later. Use when switching tasks or context is long.",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Short name (e.g., 'auth-wip')"},
            summary: %{type: "string", description: "What you're working on"},
            files: %{type: "array", items: %{type: "string"}}
          },
          required: ["name", "summary"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    case Memory.create_stash(
           project_id,
           args["name"],
           args["summary"],
           files: Map.get(args, "files", [])
         ) do
      {:ok, stash} ->
        {:ok, "Stashed '#{stash.name}'. Use `pop` with name '#{stash.name}' to restore."}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
