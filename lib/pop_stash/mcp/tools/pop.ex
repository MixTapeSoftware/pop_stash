defmodule PopStash.MCP.Tools.Pop do
  @moduledoc """
  MCP tool for retrieving stashes by exact name match.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "pop",
        description: "Retrieve a stash by exact name.",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Exact stash name"}
          },
          required: ["name"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"name" => name}, %{project_id: project_id}) do
    case Memory.get_stash_by_name(project_id, name) do
      {:ok, stash} ->
        files =
          if stash.files == [],
            do: "",
            else: "\n\nFiles: #{Enum.join(stash.files, ", ")}"

        {:ok, "#{stash.summary}#{files}"}

      {:error, :not_found} ->
        recent = Memory.list_stashes(project_id) |> Enum.take(5)

        hint =
          if recent == [] do
            "No stashes yet."
          else
            "Available: " <> Enum.map_join(recent, ", ", & &1.name)
          end

        {:error, "Stash '#{name}' not found. #{hint}"}
    end
  end
end
