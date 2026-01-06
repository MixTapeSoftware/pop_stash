defmodule PopStash.MCP.ServerTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Server

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, project: project}
  end

  defp msg(method, opts \\ []) do
    %{"jsonrpc" => "2.0", "method" => method, "id" => opts[:id] || 1}
    |> then(fn m -> if opts[:params], do: Map.put(m, "params", opts[:params]), else: m end)
  end

  describe "handle_message/2" do
    test "ping returns empty result", %{project: project} do
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}
      assert {:ok, response} = Server.handle_message(message, project)
      assert response.result == %{}
    end

    test "initialize returns server info with project", %{project: project} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2025-03-26"}
      }

      assert {:ok, response} = Server.handle_message(message, project)
      assert response.result.serverInfo.name == "PopStash"
      assert response.result.projectId == project.id
      assert response.result.projectName == project.name
    end

    test "tools/list returns available tools", %{project: project} do
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
      assert {:ok, response} = Server.handle_message(message, project)
      assert is_list(response.result.tools)
      assert Enum.any?(response.result.tools, &(&1.name == "ping"))
    end

    test "tools/call with ping returns pong", %{project: project} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "ping", "arguments" => %{}}
      }

      assert {:ok, response} = Server.handle_message(message, project)
      assert [%{text: "pong"}] = response.result.content
    end

    test "rejects invalid JSON-RPC", %{project: project} do
      message = %{"invalid" => "request"}
      assert {:error, response} = Server.handle_message(message, project)
      assert response.error.code == -32_600
    end

    test "unknown method returns error", %{project: project} do
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "unknown"}
      assert {:error, response} = Server.handle_message(message, project)
      assert response.error.code == -32_601
    end
  end

  describe "initialize" do
    test "rejects old protocol", %{project: project} do
      assert {:error, %{error: %{code: -32_602}}} =
               Server.handle_message(
                 msg("initialize", params: %{"protocolVersion" => "2020-01-01"}),
                 project
               )
    end

    test "requires protocol version", %{project: project} do
      assert {:error, %{error: %{code: -32_602}}} =
               Server.handle_message(msg("initialize", params: %{}), project)
    end
  end

  describe "tools/list" do
    test "returns tools without callbacks", %{project: project} do
      assert {:ok, %{result: %{tools: tools}}} =
               Server.handle_message(msg("tools/list"), project)

      assert Enum.any?(tools, &(&1.name == "ping"))
      refute Enum.any?(tools, &Map.has_key?(&1, :callback))
    end
  end

  describe "tools/call" do
    test "unknown tool returns error", %{project: project} do
      assert {:error, %{error: %{code: -32_601}}} =
               Server.handle_message(
                 msg("tools/call", params: %{"name" => "nope", "arguments" => %{}}),
                 project
               )
    end
  end

  describe "validation" do
    test "rejects missing jsonrpc", %{project: project} do
      assert {:error, _} =
               Server.handle_message(%{"method" => "ping", "id" => 1}, project)
    end

    test "rejects missing method", %{project: project} do
      assert {:error, _} =
               Server.handle_message(%{"jsonrpc" => "2.0", "id" => 1}, project)
    end
  end
end
