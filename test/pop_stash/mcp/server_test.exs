defmodule PopStash.MCP.ServerTest do
  use ExUnit.Case, async: true
  alias PopStash.MCP.Server

  @test_project_id "test_project_123"

  defp msg(method, opts \\ []) do
    %{"jsonrpc" => "2.0", "method" => method, "id" => opts[:id] || 1}
    |> then(fn m -> if opts[:params], do: Map.put(m, "params", opts[:params]), else: m end)
  end

  describe "ping" do
    test "returns empty result" do
      assert {:ok, %{result: %{}}} = Server.handle_message(msg("ping"), @test_project_id)
    end
  end

  describe "initialize" do
    test "returns capabilities with project_id" do
      assert {:ok, %{result: result}} =
               Server.handle_message(
                 msg("initialize", params: %{"protocolVersion" => "2025-03-26"}),
                 @test_project_id
               )

      assert result.serverInfo.name == "PopStash"
      assert result.projectId == @test_project_id
      assert is_list(result.tools)
    end

    test "rejects old protocol" do
      assert {:error, %{error: %{code: -32_602}}} =
               Server.handle_message(
                 msg("initialize", params: %{"protocolVersion" => "2020-01-01"}),
                 @test_project_id
               )
    end

    test "requires protocol version" do
      assert {:error, %{error: %{code: -32_602}}} =
               Server.handle_message(msg("initialize", params: %{}), @test_project_id)
    end
  end

  describe "tools/list" do
    test "returns tools without callbacks" do
      assert {:ok, %{result: %{tools: tools}}} =
               Server.handle_message(msg("tools/list"), @test_project_id)

      assert Enum.any?(tools, &(&1.name == "ping"))
      refute Enum.any?(tools, &Map.has_key?(&1, :callback))
    end
  end

  describe "tools/call" do
    test "calls ping" do
      assert {:ok, %{result: %{content: [%{text: "pong"}]}}} =
               Server.handle_message(
                 msg("tools/call", params: %{"name" => "ping", "arguments" => %{}}),
                 @test_project_id
               )
    end

    test "unknown tool" do
      assert {:error, %{error: %{code: -32_601}}} =
               Server.handle_message(
                 msg("tools/call", params: %{"name" => "nope", "arguments" => %{}}),
                 @test_project_id
               )
    end
  end

  describe "validation" do
    test "rejects missing jsonrpc" do
      assert {:error, _} =
               Server.handle_message(%{"method" => "ping", "id" => 1}, @test_project_id)
    end

    test "rejects missing method" do
      assert {:error, _} =
               Server.handle_message(%{"jsonrpc" => "2.0", "id" => 1}, @test_project_id)
    end

    test "unknown method" do
      assert {:error, %{error: %{code: -32_601}}} =
               Server.handle_message(msg("unknown"), @test_project_id)
    end
  end
end
