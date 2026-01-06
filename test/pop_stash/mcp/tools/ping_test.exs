defmodule PopStash.MCP.Tools.PingTest do
  use ExUnit.Case, async: true
  alias PopStash.MCP.Tools.Ping

  test "tools/0 returns valid definition" do
    assert [%{name: "ping", callback: cb}] = Ping.tools()
    assert is_function(cb, 1)
  end

  test "execute returns pong" do
    assert {:ok, "pong"} = Ping.execute(%{})
  end
end
