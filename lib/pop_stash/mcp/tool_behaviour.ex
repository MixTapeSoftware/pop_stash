defmodule PopStash.MCP.ToolBehaviour do
  @moduledoc """
  Behaviour for MCP tool modules.
  """

  @callback tools() :: [map()]
end
