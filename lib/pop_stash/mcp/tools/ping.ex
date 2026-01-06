defmodule PopStash.MCP.Tools.Ping do
  @moduledoc "Health check tool."

  @spec tools() :: [map()]
  def tools do
    [
      %{
        name: "ping",
        description: "Health check. Returns 'pong'.",
        inputSchema: %{type: "object", properties: %{}},
        callback: &execute/1
      }
    ]
  end

  @spec execute(map()) :: {:ok, String.t()}
  def execute(_args), do: {:ok, "pong"}
end
