defmodule PopStash.MCP.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn
  alias PopStash.MCP.Router

  @opts Router.init([])
  @test_project_id "test_project_123"

  defp call(conn), do: %{conn | remote_ip: {127, 0, 0, 1}} |> Router.call(@opts)

  test "GET / returns HTML with project_id info" do
    conn = conn(:get, "/") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "PopStash"
    assert conn.resp_body =~ "project_id"
  end

  test "POST /mcp/:project_id handles ping" do
    conn =
      conn(:post, "/mcp/#{@test_project_id}", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["result"] == %{}
  end

  test "POST /mcp/:project_id initialize includes project_id" do
    conn =
      conn(
        :post,
        "/mcp/#{@test_project_id}",
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: %{protocolVersion: "2025-03-26"}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 200
    result = Jason.decode!(conn.resp_body)["result"]
    assert result["projectId"] == @test_project_id
  end

  test "POST /mcp without project_id returns 404" do
    conn =
      conn(:post, "/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 404
  end

  test "rejects non-localhost" do
    conn =
      conn(:get, "/")
      |> Map.put(:remote_ip, {8, 8, 8, 8})
      |> Router.call(@opts)

    assert conn.status == 403
  end
end
