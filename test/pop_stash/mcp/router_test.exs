defmodule PopStash.MCP.RouterTest do
  use PopStash.DataCase, async: true

  import Plug.Test
  import Plug.Conn

  alias PopStash.MCP.Router

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, project: project}
  end

  describe "POST /mcp/:project_id" do
    test "handles valid JSON-RPC request", %{project: project} do
      conn =
        conn(:post, "/mcp/#{project.id}", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "ping"
        })
        |> put_req_header("content-type", "application/json")
        |> put_private(:remote_ip, {127, 0, 0, 1})
        |> Router.call([])

      assert conn.status == 200
      assert %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}} = Jason.decode!(conn.resp_body)
    end

    test "returns 404 for unknown project" do
      unknown_id = Ecto.UUID.generate()

      conn =
        conn(:post, "/mcp/#{unknown_id}", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "ping"
        })
        |> put_req_header("content-type", "application/json")
        |> put_private(:remote_ip, {127, 0, 0, 1})
        |> Router.call([])

      assert conn.status == 404
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32_001
      assert response["error"]["message"] =~ "Project not found"
    end

    test "initialize includes project info", %{project: project} do
      conn =
        conn(:post, "/mcp/#{project.id}", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => "2025-03-26"}
        })
        |> put_req_header("content-type", "application/json")
        |> put_private(:remote_ip, {127, 0, 0, 1})
        |> Router.call([])

      assert conn.status == 200
      result = Jason.decode!(conn.resp_body)["result"]
      assert result["projectId"] == project.id
      assert result["projectName"] == project.name
    end

    test "tools/call ping returns pong", %{project: project} do
      conn =
        conn(:post, "/mcp/#{project.id}", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "ping", "arguments" => %{}}
        })
        |> put_req_header("content-type", "application/json")
        |> put_private(:remote_ip, {127, 0, 0, 1})
        |> Router.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert [%{"text" => "pong"}] = response["result"]["content"]
    end

    test "POST /mcp without project_id returns 404" do
      conn =
        conn(:post, "/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})
        |> put_req_header("content-type", "application/json")
        |> put_private(:remote_ip, {127, 0, 0, 1})
        |> Router.call([])

      assert conn.status == 404
    end
  end

  describe "GET /" do
    test "returns info page with project list" do
      project = project_fixture(name: "Listed Project")

      conn =
        conn(:get, "/")
        |> put_private(:remote_ip, {127, 0, 0, 1})
        |> Router.call([])

      assert conn.status == 200
      assert conn.resp_body =~ "PopStash MCP Server"
      assert conn.resp_body =~ project.id
      assert conn.resp_body =~ "Listed Project"
    end
  end

  describe "localhost security" do
    test "rejects non-localhost requests", %{project: project} do
      conn =
        conn(:post, "/mcp/#{project.id}", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "ping"
        })
        |> put_req_header("content-type", "application/json")
        |> Map.put(:remote_ip, {192, 168, 1, 100})
        |> Router.call([])

      assert conn.status == 403
    end
  end
end
