# Phase 1: MCP Foundation - Implementation Plan

## Overview

Build a minimal, idiomatic MCP server following Elixir/OTP best practices. Copy patterns from Tidewave but simplify and improve.

## Architecture

**3 core modules:**
1. `PopStash.MCP.Server` - JSON-RPC handling, tool dispatch
2. `PopStash.MCP.Router` - Plug-based HTTP endpoint  
3. `PopStash.MCP.Tools.Ping` - Example tool

**Principles:**
- Let it crash (supervisor restarts Bandit on failure)
- Explicit is better than implicit (clear error types)
- Convention over configuration (sensible defaults)
- Telemetry for observability
- Typespecs for public APIs

## Tasks

### 1. Add Dependencies

**Update `mix.exs`**:
```elixir
defp deps do
  [
    {:bandit, "~> 1.5"},
    {:jason, "~> 1.4"},
    {:plug, "~> 1.16"},
    {:telemetry, "~> 1.2"},
    
    # Dev/test only
    {:credo, "~> 1.7", only: [:dev, test], runtime: false}
  ]
end
```

---

### 2. Configuration

**Create `config/config.exs`**:
```elixir
import Config

config :pop_stash, PopStash.MCP,
  port: 4000,
  protocol_version: "2025-03-26"

import_config "#{config_env()}.exs"
```

**Create `config/dev.exs`**:
```elixir
import Config

config :pop_stash, PopStash.MCP,
  port: 4000
```

**Create `config/test.exs`**:
```elixir
import Config

# Don't start server in tests
config :pop_stash, start_server: false
```

**Create `config/prod.exs`**:
```elixir
import Config

# Runtime config in releases
```

---

### 3. Create MCP Server Module

**Create `lib/pop_stash/mcp/server.ex`**:

```elixir
defmodule PopStash.MCP.Server do
  @moduledoc """
  MCP (Model Context Protocol) server implementing JSON-RPC 2.0.
  
  Handles protocol messages and dispatches tool calls to registered tools.
  Tools are registered at compile-time via module attributes for zero-cost dispatch.
  """

  require Logger

  @protocol_version Application.compile_env(:pop_stash, [PopStash.MCP, :protocol_version])
  @server_name "PopStash"
  @server_version Mix.Project.config()[:version]

  # Compile-time tool registry
  @tools [
    PopStash.MCP.Tools.Ping.tools()
  ]
         |> List.flatten()
         |> Enum.map(&validate_tool!/1)

  @tool_schemas Enum.map(@tools, &Map.drop(&1, [:callback]))
  @tool_dispatch Map.new(@tools, &{&1.name, &1.callback})

  @type message :: map()
  @type response :: map()
  @type error_code :: integer()

  ## Public API

  @doc """
  Returns the list of available tool schemas (without callbacks).
  """
  @spec tools :: [map()]
  def tools, do: @tool_schemas

  @doc """
  Handles an incoming JSON-RPC 2.0 message.
  
  Returns `{:ok, response}` on success or `{:error, response}` for protocol errors.
  Tool execution errors are returned as successful responses with `isError: true`.
  """
  @spec handle_message(message()) :: {:ok, response()} | {:error, response()}
  def handle_message(message) do
    start_time = System.monotonic_time()
    
    result =
      with {:ok, validated} <- validate_jsonrpc(message),
           {:ok, response} <- route_message(validated) do
        {:ok, response}
      else
        {:error, error_response} -> {:error, error_response}
      end
    
    emit_telemetry(message, result, start_time)
    result
  end

  ## Message Routing

  defp route_message(%{"method" => "ping", "id" => id}) do
    {:ok, success_response(id, %{})}
  end

  defp route_message(%{"method" => "initialize", "id" => id, "params" => params}) do
    with :ok <- validate_protocol_version(params["protocolVersion"]) do
      {:ok,
       success_response(id, %{
         protocolVersion: @protocol_version,
         capabilities: %{
           tools: %{listChanged: false}
         },
         serverInfo: %{
           name: @server_name,
           version: @server_version
         },
         tools: @tool_schemas
       })}
    else
      {:error, reason} -> {:error, error_response(id, -32602, reason)}
    end
  end

  defp route_message(%{"method" => "tools/list", "id" => id}) do
    {:ok, success_response(id, %{tools: @tool_schemas})}
  end

  defp route_message(%{"method" => "tools/call", "id" => id, "params" => params}) do
    call_tool(id, params)
  end

  defp route_message(%{"method" => method, "id" => id}) do
    {:error, error_response(id, -32601, "Method not found: #{method}")}
  end

  defp route_message(%{"method" => _method}) do
    # Notification (no id) - ignore per JSON-RPC spec
    {:ok, :no_response}
  end

  ## Tool Dispatch

  defp call_tool(id, %{"name" => name, "arguments" => args}) do
    case Map.fetch(@tool_dispatch, name) do
      {:ok, callback} ->
        execute_tool(id, name, callback, args)

      :error ->
        {:error, error_response(id, -32601, "Unknown tool: #{name}")}
    end
  end

  defp call_tool(id, _params) do
    {:error, error_response(id, -32602, "Invalid params: missing 'name' or 'arguments'")}
  end

  defp execute_tool(id, name, callback, args) do
    try do
      case callback.(args) do
        {:ok, text} when is_binary(text) ->
          {:ok, success_response(id, text_content(text))}

        {:ok, result} when is_map(result) ->
          {:ok, success_response(id, result)}

        {:error, message} when is_binary(message) ->
          {:ok, success_response(id, text_content(message, error: true))}

        other ->
          Logger.warning("Tool #{name} returned unexpected value: #{inspect(other)}")
          {:ok, success_response(id, text_content("Tool returned invalid response", error: true))}
      end
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__
        Logger.error("Tool #{name} crashed: #{Exception.format(kind, reason, stacktrace)}")

        error_text = """
        Tool execution failed: #{Exception.message(Exception.normalize(kind, reason, stacktrace))}
        """

        {:ok, success_response(id, text_content(error_text, error: true))}
    end
  end

  ## Validation

  defp validate_jsonrpc(%{"jsonrpc" => "2.0", "method" => method, "id" => id} = msg)
       when is_binary(method) and (is_binary(id) or is_integer(id)) do
    {:ok, msg}
  end

  defp validate_jsonrpc(%{"jsonrpc" => "2.0", "method" => method} = msg)
       when is_binary(method) do
    # Notification (no id required)
    {:ok, msg}
  end

  defp validate_jsonrpc(_msg) do
    {:error, error_response(nil, -32600, "Invalid JSON-RPC 2.0 request")}
  end

  defp validate_protocol_version(nil) do
    {:error, "Protocol version is required"}
  end

  defp validate_protocol_version(version) when is_binary(version) do
    if version >= @protocol_version do
      :ok
    else
      {:error, "Unsupported protocol version. Server requires #{@protocol_version} or later"}
    end
  end

  defp validate_protocol_version(_) do
    {:error, "Protocol version must be a string"}
  end

  ## Tool Validation (compile-time)

  defp validate_tool!(%{name: name, description: desc, inputSchema: schema, callback: cb} = tool)
       when is_binary(name) and is_binary(desc) and is_map(schema) and is_function(cb, 1) do
    tool
  end

  defp validate_tool!(tool) do
    raise ArgumentError, """
    Invalid tool definition: #{inspect(tool)}
    
    Tools must have:
      - name: string
      - description: string
      - inputSchema: map (JSON Schema)
      - callback: function/1
    """
  end

  ## Response Helpers

  defp success_response(id, result) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: result
    }
  end

  defp error_response(id, code, message) when is_integer(code) and is_binary(message) do
    %{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: code,
        message: message
      }
    }
  end

  defp text_content(text, opts \\ []) when is_binary(text) do
    content = %{
      content: [%{type: "text", text: text}]
    }

    if Keyword.get(opts, :error, false) do
      Map.put(content, :isError, true)
    else
      content
    end
  end

  ## Telemetry

  defp emit_telemetry(message, result, start_time) do
    duration = System.monotonic_time() - start_time

    metadata = %{
      method: message["method"],
      tool: get_in(message, ["params", "name"]),
      success: match?({:ok, _}, result)
    }

    :telemetry.execute(
      [:pop_stash, :mcp, :request],
      %{duration: duration},
      metadata
    )
  end
end
```

---

### 4. Create HTTP Router

**Create `lib/pop_stash/mcp/router.ex`**:

```elixir
defmodule PopStash.MCP.Router do
  @moduledoc """
  Plug-based HTTP router for MCP server.
  
  - POST /mcp - JSON-RPC 2.0 endpoint
  - GET / - Health check / info page
  
  Security: Localhost-only by default.
  """

  use Plug.Router
  require Logger

  plug :match
  plug :check_remote_ip
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :dispatch

  ## Routes

  post "/mcp" do
    message = conn.body_params

    case PopStash.MCP.Server.handle_message(message) do
      {:ok, response} ->
        send_json(conn, 200, response)

      {:error, error_response} ->
        send_json(conn, 200, error_response)

      {:ok, :no_response} ->
        # Notification - no response per JSON-RPC spec
        send_resp(conn, 204, "")
    end
  end

  get "/" do
    tools = PopStash.MCP.Server.tools()

    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>PopStash MCP Server</title>
      <style>
        body { font-family: system-ui; max-width: 800px; margin: 40px auto; padding: 0 20px; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
        pre { background: #f4f4f4; padding: 12px; border-radius: 4px; overflow-x: auto; }
      </style>
    </head>
    <body>
      <h1>PopStash MCP Server</h1>
      <p>Model Context Protocol server for AI coding agents.</p>
      
      <h2>Endpoint</h2>
      <p>POST JSON-RPC 2.0 messages to <code>/mcp</code></p>
      
      <h2>Available Tools (#{length(tools)})</h2>
      <ul>
        #{Enum.map_join(tools, fn t -> "<li><strong>#{t.name}</strong> - #{t.description}</li>" end)}
      </ul>
      
      <h2>Integration</h2>
      <p>Add to <code>.claude/mcp_servers.json</code>:</p>
      <pre>{
  "pop_stash": {
    "url": "http://localhost:#{port()}/mcp"
  }
}</pre>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  ## Security

  defp check_remote_ip(conn, _opts) do
    if local_request?(conn.remote_ip) do
      conn
    else
      Logger.warning("Rejected remote MCP request from #{inspect(conn.remote_ip)}")

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "Forbidden: MCP server only accepts localhost connections")
      |> halt()
    end
  end

  # IPv4 localhost
  defp local_request?({127, 0, 0, _}), do: true
  # IPv6 localhost
  defp local_request?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # IPv4-mapped IPv6 localhost (::ffff:127.0.0.1)
  defp local_request?({0, 0, 0, 0, 0, 65535, 32512, 1}), do: true
  defp local_request?(_), do: false

  ## Helpers

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp port do
    Application.get_env(:pop_stash, PopStash.MCP)[:port] || 4000
  end
end
```

---

### 5. Create Ping Tool

**Create `lib/pop_stash/mcp/tools/ping.ex`**:

```elixir
defmodule PopStash.MCP.Tools.Ping do
  @moduledoc """
  Simple health check tool for MCP protocol validation.
  
  Always returns "pong" to confirm the server is responding.
  """

  @doc """
  Returns tool definitions for registration.
  """
  @spec tools :: [map()]
  def tools do
    [
      %{
        name: "ping",
        description: """
        Health check that returns 'pong'. Used to validate MCP connection.
        """,
        inputSchema: %{
          type: "object",
          properties: %{},
          required: []
        },
        callback: &execute/1
      }
    ]
  end

  @doc """
  Executes the ping tool.
  
  ## Examples
  
      iex> PopStash.MCP.Tools.Ping.execute(%{})
      {:ok, "pong"}
  """
  @spec execute(map()) :: {:ok, String.t()}
  def execute(_args) do
    {:ok, "pong"}
  end
end
```

---

### 6. Create Application Supervisor

**Create `lib/pop_stash/application.ex`**:

```elixir
defmodule PopStash.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = children(Application.get_env(:pop_stash, :start_server, true))

    opts = [strategy: :one_for_one, name: PopStash.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Start HTTP server in dev/prod, skip in test
  defp children(true) do
    port = Application.get_env(:pop_stash, PopStash.MCP)[:port] || 4000

    [
      {Bandit, plug: PopStash.MCP.Router, port: port, startup_log: false}
    ]
  end

  defp children(false), do: []
end
```

**Update `mix.exs`**:
```elixir
def application do
  [
    mod: {PopStash.Application, []},
    extra_applications: [:logger]
  ]
end

def project do
  [
    app: :pop_stash,
    version: "0.1.0",
    elixir: "~> 1.18",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    aliases: aliases()
  ]
end

defp aliases do
  [
    "mcp.server": ["run --no-halt"]
  ]
end
```

---

### 7. Tests

**Update `test/test_helper.exs`**:
```elixir
ExUnit.start()
```

**Create `test/pop_stash/mcp/server_test.exs`**:
```elixir
defmodule PopStash.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias PopStash.MCP.Server

  describe "handle_message/1 - ping" do
    test "responds to ping" do
      assert {:ok, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "ping"
               })

      assert response.id == 1
      assert response.result == %{}
    end
  end

  describe "handle_message/1 - initialize" do
    test "returns server capabilities with valid protocol version" do
      assert {:ok, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "initialize",
                 "params" => %{"protocolVersion" => "2025-03-26"}
               })

      assert response.result.protocolVersion == "2025-03-26"
      assert response.result.serverInfo.name == "PopStash"
      assert is_list(response.result.tools)
    end

    test "rejects old protocol version" do
      assert {:error, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "initialize",
                 "params" => %{"protocolVersion" => "2024-01-01"}
               })

      assert response.error.code == -32602
      assert response.error.message =~ "Unsupported protocol version"
    end

    test "requires protocol version" do
      assert {:error, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "initialize",
                 "params" => %{}
               })

      assert response.error.code == -32602
    end
  end

  describe "handle_message/1 - tools/list" do
    test "returns available tools" do
      assert {:ok, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "tools/list"
               })

      assert is_list(response.result.tools)
      assert Enum.any?(response.result.tools, &(&1.name == "ping"))
    end

    test "tools do not include callbacks" do
      assert {:ok, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "tools/list"
               })

      refute Enum.any?(response.result.tools, &Map.has_key?(&1, :callback))
    end
  end

  describe "handle_message/1 - tools/call" do
    test "calls ping tool successfully" do
      assert {:ok, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "tools/call",
                 "params" => %{
                   "name" => "ping",
                   "arguments" => %{}
                 }
               })

      assert response.result.content == [%{type: "text", text: "pong"}]
      refute Map.has_key?(response.result, :isError)
    end

    test "returns error for unknown tool" do
      assert {:error, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "tools/call",
                 "params" => %{
                   "name" => "nonexistent",
                   "arguments" => %{}
                 }
               })

      assert response.error.code == -32601
      assert response.error.message =~ "Unknown tool"
    end

    test "returns error for missing parameters" do
      assert {:error, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "tools/call",
                 "params" => %{"name" => "ping"}
               })

      assert response.error.code == -32602
    end
  end

  describe "handle_message/1 - validation" do
    test "rejects messages without jsonrpc version" do
      assert {:error, response} =
               Server.handle_message(%{
                 "id" => 1,
                 "method" => "ping"
               })

      assert response.error.code == -32600
    end

    test "rejects messages without method" do
      assert {:error, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1
               })

      assert response.error.code == -32600
    end

    test "rejects unknown methods" do
      assert {:error, response} =
               Server.handle_message(%{
                 "jsonrpc" => "2.0",
                 "id" => 1,
                 "method" => "unknown"
               })

      assert response.error.code == -32601
    end
  end
end
```

**Create `test/pop_stash/mcp/tools/ping_test.exs`**:
```elixir
defmodule PopStash.MCP.Tools.PingTest do
  use ExUnit.Case, async: true

  alias PopStash.MCP.Tools.Ping

  describe "tools/0" do
    test "returns list with ping tool definition" do
      assert [tool] = Ping.tools()

      assert tool.name == "ping"
      assert is_binary(tool.description)
      assert tool.inputSchema.type == "object"
      assert is_function(tool.callback, 1)
    end
  end

  describe "execute/1" do
    test "returns pong" do
      assert {:ok, "pong"} = Ping.execute(%{})
    end

    test "ignores arguments" do
      assert {:ok, "pong"} = Ping.execute(%{"unused" => "arg"})
    end
  end
end
```

**Create `test/pop_stash/mcp/router_test.exs`**:
```elixir
defmodule PopStash.MCP.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias PopStash.MCP.Router

  @opts Router.init([])

  describe "GET /" do
    test "returns HTML info page" do
      conn =
        conn(:get, "/")
        |> put_remote_ip({127, 0, 0, 1})
        |> Router.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "PopStash MCP Server"
    end
  end

  describe "POST /mcp" do
    test "handles valid ping request" do
      conn =
        conn(:post, "/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))
        |> put_req_header("content-type", "application/json")
        |> put_remote_ip({127, 0, 0, 1})
        |> Router.call(@opts)

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["result"] == %{}
    end

    test "handles invalid JSON" do
      conn =
        conn(:post, "/mcp", "not json")
        |> put_req_header("content-type", "application/json")
        |> put_remote_ip({127, 0, 0, 1})
        |> Router.call(@opts)

      assert conn.status == 400
    end
  end

  describe "security" do
    test "allows localhost IPv4" do
      conn =
        conn(:get, "/")
        |> put_remote_ip({127, 0, 0, 1})
        |> Router.call(@opts)

      assert conn.status == 200
    end

    test "allows localhost IPv6" do
      conn =
        conn(:get, "/")
        |> put_remote_ip({0, 0, 0, 0, 0, 0, 0, 1})
        |> Router.call(@opts)

      assert conn.status == 200
    end

    test "rejects remote IP" do
      conn =
        conn(:get, "/")
        |> put_remote_ip({192, 168, 1, 100})
        |> Router.call(@opts)

      assert conn.status == 403
      assert conn.resp_body =~ "Forbidden"
    end
  end

  defp put_remote_ip(conn, ip) do
    %{conn | remote_ip: ip}
  end
end
```

Run: `mix test`

---

### 8. Update README

**Update `README.md`**:

```markdown
# PopStash

Infrastructure layer for AI coding agents providing Memory, Coordination, and Observability via MCP (Model Context Protocol).

## Quick Start

```bash
# Install dependencies
mix deps.get

# Start MCP server
mix mcp.server
```

Server runs on `http://localhost:4000` (localhost-only for security).

## Claude Code Integration

Add to `.claude/mcp_servers.json`:

```json
{
  "pop_stash": {
    "url": "http://localhost:4000/mcp"
  }
}
```

Restart Claude Code to connect.

## Available Tools

- `ping` - Health check (returns "pong")

## Development

```bash
# Run tests
mix test

# Run with coverage
mix test --cover

# Lint code
mix credo

# Format code
mix format
```

## Configuration

Edit `config/dev.exs`:

```elixir
config :pop_stash, PopStash.MCP,
  port: 4000
```

## Adding Tools

1. Create tool module in `lib/pop_stash/mcp/tools/`
2. Add to tool list in `lib/pop_stash/mcp/server.ex`

Example:

```elixir
defmodule PopStash.MCP.Tools.MyTool do
  def tools do
    [
      %{
        name: "my_tool",
        description: "What it does",
        inputSchema: %{
          type: "object",
          required: ["param"],
          properties: %{
            param: %{type: "string", description: "Parameter description"}
          }
        },
        callback: &execute/1
      }
    ]
  end

  def execute(%{"param" => value}) do
    {:ok, "Result: #{value}"}
  end
end
```

## License

Apache 2.0
```

---

## Success Criteria

- ✅ Server starts on http://localhost:4000
- ✅ GET / shows tool list and integration instructions
- ✅ POST /mcp handles JSON-RPC 2.0 correctly
- ✅ Localhost-only security enforced (IPv4 + IPv6)
- ✅ Telemetry events emitted for observability
- ✅ Tests pass with >90% coverage
- ✅ Credo passes with no warnings
- ✅ All public functions have typespecs
- ✅ Claude Code connects successfully
- ✅ ping tool returns "pong"

## Task Checklist

- [ ] 1. Add dependencies
- [ ] 2. Configuration
- [ ] 3. MCP Server module
- [ ] 4. HTTP Router
- [ ] 5. Ping tool
- [ ] 6. Application supervisor
- [ ] 7. Tests
- [ ] 8. Update README

## Key Improvements Over Initial Plan

1. **Proper error handling** - `{:ok, response} | {:error, response}` instead of always `{:ok, _}`
2. **Telemetry** - Emit events for observability
3. **Typespecs** - All public APIs documented
4. **Config environments** - Proper dev/test/prod split
5. **Tool validation** - Compile-time checks for well-formed tools
6. **Better HTML page** - Shows tools and integration instructions
7. **Async tests** - Faster test runs
8. **Security logging** - Warn on rejected remote requests
9. **Better docs** - Examples in moduledocs, integration guide
10. **Idiomatic Elixir** - Pattern matching, guards, proper use of with/case

## Next Steps

Phase 2: Database setup (PostgreSQL, Ecto, pgvector)
