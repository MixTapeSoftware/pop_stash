defmodule PopStash.MCP.Tools.Recall do
  @moduledoc """
  MCP tool for retrieving insights by exact key match.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "recall",
        description: "Retrieve an insight by exact key.",
        inputSchema: %{
          type: "object",
          properties: %{
            key: %{type: "string", description: "Exact insight key"}
          },
          required: ["key"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"key" => key}, %{project_id: project_id}) do
    case Memory.get_insight_by_key(project_id, key) do
      {:ok, insight} ->
        {:ok, insight.content}

      {:error, :not_found} ->
        recent = Memory.list_insights(project_id, limit: 5)

        hint =
          if recent == [] do
            "No insights yet."
          else
            keys =
              recent
              |> Enum.filter(& &1.key)
              |> Enum.map(& &1.key)
              |> Enum.join(", ")

            if keys == "", do: "No keyed insights.", else: "Keys: #{keys}"
          end

        {:error, "Insight '#{key}' not found. #{hint}"}
    end
  end
end
