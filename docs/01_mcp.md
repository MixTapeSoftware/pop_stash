# Phase 1: MCP Foundation - Implementation Plan

## Overview

Build a minimal MCP server following Elixir/OTP conventions. Start simple, iterate.

## Architecture

```
┌─────────────────────────────────────────────┐
│              PopStash.Application           │
│                 (Supervisor)                │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│     Bandit (HTTP Server on port 4001)       │
│           └── PopStash.MCP.Router           │
│                 │                           │
│                 ├── POST /mcp/:project_id   │
│                 │     └── PopStash.MCP.Server│
│                 │           └── Tools.Ping  │
│                 │                           │
│                 └── GET /                   │
│                       └── Info page         │
└─────────────────────────────────────────────┘
```

**Modules:**
- `PopStash.MCP.Server` — JSON-RPC 2.0 handling, tool dispatch
- `PopStash.MCP.Router` — Plug-based HTTP endpoint with project routing
- `PopStash.MCP.Tools.Ping` — Validates end-to-end connectivity

**URL Structure:**
- `POST /mcp/:project_id` — Main MCP endpoint, scoped to project
- `GET /` — Info page showing available projects and tools

**Principles:**
- Let it crash (supervisor restarts on failure)
- Explicit over implicit
- Telemetry from day one

---

## Tasks

### 1. Add Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:bandit, "~> 1.5"},
    {:jason, "~> 1.4"},
    {:plug, "~> 1.16"},
    {:telemetry, "~> 1.2"},

    # Dev/test
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end
```

---

### 2. Configuration

```elixir
# config/config.exs
import Config

config :pop_stash,
  mcp_port: 4001,
  mcp_protocol_version: "2025-03-26"

import_config "#{config_env()}.exs"
```

```elixir
# config/dev.exs
import Config
```

```elixir
# config/test.exs
import Config

config :pop_stash, start_server: false
```

```elixir
# config/prod.exs
import Config
```

---

### 3. MCP Server

The server handles JSON-RPC 2.0 messages and dispatches tool calls.

```elixir
# lib/pop_stash/mcp/server.ex
defmodule PopStash.MCP.Server do
  @moduledoc """
  MCP server implementing JSON-RPC 2.0.

  Tool modules implement a `tools/0` callback returning a list of tool definitions.
  Each definition is a map with `:name`, `:description`, `:inputSchema`, and `:callback`.
  """

  require Logger

  @tool_modules [
    PopStash.MCP.Tools.Ping
  ]

  ## Public API

  @doc "Returns available tools (without callbacks, safe for JSON serialization)."
  def tools do
    @tool_modules
    |> Enum.flat_map(& &1.tools())
    |> Enum.map(&Map.drop(&1, [:callback]))
  end

  @doc """
  Handles a JSON-RPC 2.0 message.

  Returns `{:ok, response}`, `{:error, response}`, or `{:ok, :notification}`.
  The project_id is passed from the router (/mcp/:project_id).
  """
  def handle_message(message, project_id) do
    start_time = System.monotonic_time()

    result =
      with {:ok, msg} <- validate_jsonrpc(message) do
        route(msg, project_id)
      end

    emit_telemetry(message, result, start_time, project_id)
    result
  end

  ## Routing
  # All routes receive project_id for future use (Phase 1.5+)

  defp route(%{"method" => "ping", "id" => id}, _project_id) do
    {:ok, success(id, %{})}
  end

  defp route(%{"method" => "initialize", "id" => id, "params" => params}, project_id) do
    version = protocol_version()

    case validate_protocol_version(params["protocolVersion"]) do
      :ok ->
        {:ok,
         success(id, %{
           protocolVersion: version,
           capabilities: %{tools: %{listChanged: false}},
           serverInfo: %{name: "PopStash", version: app_version()},
           projectId: project_id,  # Include project_id in response
           tools: tools()
         })}

      {:error, reason} ->
        {:error, error(id, -32602, reason)}
    end
  end

  defp route(%{"method" => "tools/list", "id" => id}, _project_id) do
    {:ok, success(id, %{tools: tools()})}
  end

  defp route(%{"method" => "tools/call", "id" => id, "params" => params}, project_id) do
    call_tool(id, params, project_id)
  end

  defp route(%{"method" => method, "id" => id}, _project_id) do
    {:error, error(id, -32601, "Method not found: #{method}")}
  end

  defp route(%{"method" => _method}, _project_id) do
    {:ok, :notification}
  end

  ## Tool Dispatch

  defp call_tool(id, %{"name" => name, "arguments" => args}, project_id) do
    case find_tool(name) do
      {:ok, callback} -> execute_tool(id, name, callback, args, project_id)
      :error -> {:error, error(id, -32601, "Unknown tool: #{name}")}
    end
  end

  defp call_tool(id, _, _project_id) do
    {:error, error(id, -32602, "Missing 'name' or 'arguments'")}
  end

  defp find_tool(name) do
    @tool_modules
    |> Enum.flat_map(& &1.tools())
    |> Enum.find(&(&1.name == name))
    |> case do
      %{callback: cb} -> {:ok, cb}
      nil -> :error
    end
  end

  defp execute_tool(id, name, callback, args, project_id) do
    result =
      try do
        # Phase 1: callback.(args)
        # Phase 1.5+: callback.(args, project_id) — tools will be project-aware
        callback.(args)
      catch
        kind, reason ->
          Logger.error("Tool #{name} crashed: #{Exception.format(kind, reason, __STACKTRACE__)}")
          {:error, "Tool execution failed"}
      end

    _ = project_id  # Suppress unused warning until Phase 1.5

    case result do
      {:ok, text} when is_binary(text) ->
        {:ok, success(id, %{content: [%{type: "text", text: text}]})}

      {:ok, data} when is_map(data) ->
        {:ok, success(id, data)}

      {:error, msg} when is_binary(msg) ->
        {:ok, success(id, %{content: [%{type: "text", text: msg}], isError: true})}

      other ->
        Logger.warning("Tool #{name} returned invalid result: #{inspect(other)}")
        {:ok, success(id, %{content: [%{type: "text", text: "Invalid tool response"}], isError: true})}
    end
  end

  ## Validation

  defp validate_jsonrpc(%{"jsonrpc" => "2.0", "method" => m} = msg) when is_binary(m) do
    {:ok, msg}
  end

  defp validate_jsonrpc(_) do
    {:error, error(nil, -32600, "Invalid JSON-RPC 2.0 request")}
  end

  # Protocol versions are date-formatted strings. Lexicographic comparison works.
  defp validate_protocol_version(nil), do: {:error, "protocolVersion required"}

  defp validate_protocol_version(v) when is_binary(v) do
    if v >= protocol_version(), do: :ok, else: {:error, "Protocol version #{v} not supported"}
  end

  defp validate_protocol_version(_), do: {:error, "protocolVersion must be a string"}

  ## Response Builders

  defp success(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  defp error(id, code, message), do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}

  ## Config

  defp protocol_version, do: Application.get_env(:pop_stash, :mcp_protocol_version, "2025-03-26")

  defp app_version, do: Application.spec(:pop_stash, :vsn) |> to_string()

  ## Telemetry

  defp emit_telemetry(message, result, start_time, project_id) do
    :telemetry.execute(
      [:pop_stash, :mcp, :request],
      %{duration: System.monotonic_time() - start_time},
      %{
        method: message["method"],
        tool: get_in(message, ["params", "name"]),
        project_id: project_id,
        success: match?({:ok, _}, result)
      }
    )
  end
end
```

---

### 4. HTTP Router

```elixir
# lib/pop_stash/mcp/router.ex
defmodule PopStash.MCP.Router do
  @moduledoc """
  HTTP router for MCP server.

  - `POST /mcp/:project_id` — JSON-RPC endpoint, scoped to project
  - `GET /` — Info page

  Localhost-only for security.
  """

  use Plug.Router
  require Logger

  plug :match
  plug :check_localhost
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :dispatch

  # Main MCP endpoint — project_id required in URL
  post "/mcp/:project_id" do
    project_id = conn.path_params["project_id"]

    # For Phase 1, just pass project_id through (no DB validation yet)
    # Phase 1.5 will add: with {:ok, project} <- PopStash.Projects.get(project_id)
    case PopStash.MCP.Server.handle_message(conn.body_params, project_id) do
      {:ok, :notification} -> send_resp(conn, 204, "")
      {:ok, response} -> json(conn, 200, response)
      {:error, response} -> json(conn, 200, response)
    end
  end

  get "/" do
    tools = PopStash.MCP.Server.tools()
    port = Application.get_env(:pop_stash, :mcp_port, 4001)

    html = """
    <!DOCTYPE html>
    <html>
    <head><title>PopStash MCP</title>
    <style>body{font-family:system-ui;max-width:700px;margin:40px auto;padding:0 20px}
    code{background:#f4f4f4;padding:2px 6px;border-radius:3px}
    pre{background:#f4f4f4;padding:12px;border-radius:4px;overflow-x:auto}
    .note{background:#fffbeb;border:1px solid #f59e0b;padding:12px;border-radius:4px;margin:12px 0}</style>
    </head>
    <body>
    <h1>PopStash MCP Server</h1>
    <p>POST JSON-RPC 2.0 to <code>/mcp/:project_id</code></p>

    <div class="note">
      <strong>Project ID Required:</strong> Each workspace needs its own project ID in the URL.
      <br>Create one with: <code>mix pop_stash.project.new "My Project"</code>
    </div>

    <h2>Tools (#{length(tools)})</h2>
    <ul>#{Enum.map_join(tools, fn t -> "<li><b>#{t.name}</b> — #{t.description}</li>" end)}</ul>

    <h2>Claude Code Setup</h2>
    <p>Add to your workspace <code>.claude/mcp_servers.json</code>:</p>
    <pre>{
  "pop_stash": {
    "url": "http://localhost:#{port}/mcp/YOUR_PROJECT_ID"
  }
}</pre>
    </body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  match _, do: send_resp(conn, 404, "Not found")

  ## Security

  defp check_localhost(conn, _opts) do
    if localhost?(conn.remote_ip) do
      conn
    else
      Logger.warning("Rejected non-localhost request from #{:inet.ntoa(conn.remote_ip)}")
      conn |> send_resp(403, "Localhost only") |> halt()
    end
  end

  defp localhost?({127, _, _, _}), do: true
  defp localhost?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp localhost?(_), do: false

  ## Helpers

  defp json(conn, status, data) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end
end
```

---

### 5. Ping Tool

```elixir
# lib/pop_stash/mcp/tools/ping.ex
defmodule PopStash.MCP.Tools.Ping do
  @moduledoc "Health check tool."

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

  def execute(_args), do: {:ok, "pong"}
end
```

---

### 6. Application

```elixir
# lib/pop_stash/application.ex
defmodule PopStash.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:pop_stash, :start_server, true) do
        port = Application.get_env(:pop_stash, :mcp_port, 4001)
        [{Bandit, plug: PopStash.MCP.Router, port: port}]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: PopStash.Supervisor)
  end
end
```

```elixir
# mix.exs (application section)
def application do
  [
    mod: {PopStash.Application, []},
    extra_applications: [:logger]
  ]
end
```

---

### 7. Tests

```elixir
# test/test_helper.exs
ExUnit.start()
```

```elixir
# test/pop_stash/mcp/server_test.exs
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
      assert {:error, %{error: %{code: -32602}}} =
               Server.handle_message(
                 msg("initialize", params: %{"protocolVersion" => "2020-01-01"}),
                 @test_project_id
               )
    end

    test "requires protocol version" do
      assert {:error, %{error: %{code: -32602}}} =
               Server.handle_message(msg("initialize", params: %{}), @test_project_id)
    end
  end

  describe "tools/list" do
    test "returns tools without callbacks" do
      assert {:ok, %{result: %{tools: tools}}} = Server.handle_message(msg("tools/list"), @test_project_id)
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
      assert {:error, %{error: %{code: -32601}}} =
               Server.handle_message(
                 msg("tools/call", params: %{"name" => "nope", "arguments" => %{}}),
                 @test_project_id
               )
    end
  end

  describe "validation" do
    test "rejects missing jsonrpc" do
      assert {:error, _} = Server.handle_message(%{"method" => "ping", "id" => 1}, @test_project_id)
    end

    test "rejects missing method" do
      assert {:error, _} = Server.handle_message(%{"jsonrpc" => "2.0", "id" => 1}, @test_project_id)
    end

    test "unknown method" do
      assert {:error, %{error: %{code: -32601}}} = Server.handle_message(msg("unknown"), @test_project_id)
    end
  end
end
```

```elixir
# test/pop_stash/mcp/router_test.exs
defmodule PopStash.MCP.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias PopStash.MCP.Router

  @opts Router.init([])
  @test_project_id "test_project_123"

  defp call(conn), do: %{conn | remote_ip: {127, 0, 0, 1}} |> Router.call(@opts)

  test "GET / returns HTML" do
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
      conn(:post, "/mcp/#{@test_project_id}", Jason.encode!(%{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{protocolVersion: "2025-03-26"}
      }))
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
```

```elixir
# test/pop_stash/mcp/tools/ping_test.exs
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
```

---

### 8. Verification

After implementation, verify everything works:

```bash
# 1. Install dependencies
mix deps.get

# 2. Run tests
mix test

# 3. Start server
mix run --no-halt

# 4. Test ping (in another terminal)
# Note: project_id is required in the URL (use any string for now)
curl -X POST http://localhost:4001/mcp/test_project \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'

# Expected: {"jsonrpc":"2.0","id":1,"result":{}}

# 5. Test initialize
curl -X POST http://localhost:4001/mcp/test_project \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}'

# Expected: includes "projectId":"test_project" in response

# 6. Test tool call
curl -X POST http://localhost:4001/mcp/test_project \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ping","arguments":{}}}'

# Expected: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"pong"}]}}

# 7. Visit info page
open http://localhost:4001
```

---

## File Checklist

```
lib/
├── pop_stash/
│   ├── application.ex
│   └── mcp/
│       ├── router.ex
│       ├── server.ex
│       └── tools/
│           └── ping.ex
config/
├── config.exs
├── dev.exs
├── test.exs
└── prod.exs
test/
├── test_helper.exs
└── pop_stash/
    └── mcp/
        ├── router_test.exs
        ├── server_test.exs
        └── tools/
            └── ping_test.exs
```

---

## Done When

- [x] `mix test` passes
- [x] `curl` to `/mcp/:project_id` ping returns `{"jsonrpc":"2.0","id":1,"result":{}}`
- [x] `curl` to `/mcp/:project_id` tool call returns `pong` in content
- [x] Info page renders at `http://localhost:4001`
- [x] Remote IP rejected with 403
- [ ] (Phase 1.5) Project validation on every request
- [ ] (Phase 1.5) Mix tasks: `mix pop_stash.project.new/list/delete`
