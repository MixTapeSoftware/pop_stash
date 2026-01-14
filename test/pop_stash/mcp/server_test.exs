defmodule PopStash.MCP.ServerTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Server

  import PopStash.Fixtures

  setup do
    project = project_fixture()

    context = %{
      project_id: project.id,
      project_name: project.name
    }

    {:ok, context: context, project: project}
  end

  defp msg(method, opts \\ []) do
    %{"jsonrpc" => "2.0", "method" => method, "id" => opts[:id] || 1}
    |> then(fn m -> if opts[:params], do: Map.put(m, "params", opts[:params]), else: m end)
  end

  describe "handle_message/2" do
    test "initialize returns server info with project", %{context: context, project: project} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2025-03-26"}
      }

      assert {:ok, response} = Server.handle_message(message, context)
      assert response.result.serverInfo.name == "PopStash"
      assert response.result.projectId == project.id
      assert response.result.projectName == project.name
    end

    test "tools/list returns available tools", %{context: context} do
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
      assert {:ok, response} = Server.handle_message(message, context)
      assert is_list(response.result.tools)
      assert Enum.any?(response.result.tools, &(&1.name == "save_context"))
      assert Enum.any?(response.result.tools, &(&1.name == "decide"))
    end

    test "rejects invalid JSON-RPC", %{context: context} do
      message = %{"invalid" => "request"}
      assert {:error, response} = Server.handle_message(message, context)
      assert response.error.code == -32_600
    end

    test "unknown method returns error", %{context: context} do
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "unknown"}
      assert {:error, response} = Server.handle_message(message, context)
      assert response.error.code == -32_601
    end
  end

  describe "initialize" do
    test "rejects old protocol", %{context: context} do
      assert {:error, %{error: %{code: -32_602}}} =
               Server.handle_message(
                 msg("initialize", params: %{"protocolVersion" => "2020-01-01"}),
                 context
               )
    end

    test "requires protocol version", %{context: context} do
      assert {:error, %{error: %{code: -32_602}}} =
               Server.handle_message(msg("initialize", params: %{}), context)
    end
  end

  describe "tools/list" do
    test "returns tools without callbacks", %{context: context} do
      assert {:ok, %{result: %{tools: tools}}} =
               Server.handle_message(msg("tools/list"), context)

      assert Enum.any?(tools, &(&1.name == "save_context"))
      refute Enum.any?(tools, &Map.has_key?(&1, :callback))
    end
  end

  describe "tools/call" do
    test "unknown tool returns error", %{context: context} do
      assert {:error, %{error: %{code: -32_601}}} =
               Server.handle_message(
                 msg("tools/call", params: %{"name" => "nope", "arguments" => %{}}),
                 context
               )
    end
  end

  describe "validation" do
    test "rejects missing jsonrpc", %{context: context} do
      assert {:error, _} =
               Server.handle_message(%{"method" => "tools/list", "id" => 1}, context)
    end

    test "rejects missing method", %{context: context} do
      assert {:error, _} =
               Server.handle_message(%{"jsonrpc" => "2.0", "id" => 1}, context)
    end
  end

  describe "decision tools" do
    test "decide tool records a decision", %{context: context} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "decide",
          "arguments" => %{
            "title" => "testing",
            "body" => "Use ExUnit",
            "reasoning" => "Built into Elixir"
          }
        }
      }

      assert {:ok, response} = Server.handle_message(message, context)
      assert [%{text: text}] = response.result.content
      assert text =~ "Decision recorded"
    end

    test "get_decisions tool queries decisions", %{context: context} do
      # First record a decision
      decide_msg = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "decide",
          "arguments" => %{"title" => "auth", "body" => "Use Guardian"}
        }
      }

      Server.handle_message(decide_msg, context)

      # Then query it
      query_msg = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_decisions",
          "arguments" => %{"title" => "auth"}
        }
      }

      assert {:ok, response} = Server.handle_message(query_msg, context)
      assert [%{text: text}] = response.result.content
      assert text =~ "Use Guardian"
    end
  end
end
