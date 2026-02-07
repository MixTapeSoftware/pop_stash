# Phase 1: MCP Foundation — Implementation Steps

Based on `01_mcp.md`. Execute in order.

---

## Current State

- Project exists at `pop_stash/`
- Has `mix.exs` with basic deps (credo, mimic, sobelow, tidewave)
- No config directory
- No application module
- Old `lib/dossier.ex` needs cleanup

---

## Step 1: Update mix.exs

Add required dependencies and application config:

```elixir
defmodule PopStash.MixProject do
  use Mix.Project

  def project do
    [
      app: :pop_stash,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {PopStash.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Runtime
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:telemetry, "~> 1.2"},

      # Dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.10", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.1", only: :dev}
    ]
  end
end
```

**Run:** `mix deps.get`

---

## Step 2: Create config files

```bash
mkdir -p config
```

### config/config.exs
```elixir
import Config

config :pop_stash,
  mcp_port: 4001,
  mcp_protocol_version: "2025-03-26"

import_config "#{config_env()}.exs"
```

### config/dev.exs
```elixir
import Config
```

### config/test.exs
```elixir
import Config

config :pop_stash, start_server: false
```

### config/prod.exs
```elixir
import Config
```

---

## Step 3: Clean up old files

```bash
rm lib/dossier.ex
rm test/dossier_test.exs
```

---

## Step 4: Create directory structure

```bash
mkdir -p lib/pop_stash/mcp/tools
mkdir -p test/pop_stash/mcp/tools
```

---

## Step 5: Create lib/pop_stash/application.ex

```elixir
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

---

## Step 6: Create lib/pop_stash/mcp/tools/ping.ex

```elixir
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

## Step 7: Create lib/pop_stash/mcp/server.ex

Copy the full `PopStash.MCP.Server` module from `01_mcp.md` (lines 91-273).

Key points:
- `@tool_modules` list contains `PopStash.MCP.Tools.Ping`
- Handles `ping`, `initialize`, `tools/list`, `tools/call` methods
- Validates JSON-RPC 2.0 format
- Emits telemetry events

---

## Step 8: Create lib/pop_stash/mcp/router.ex

Copy the full `PopStash.MCP.Router` module from `01_mcp.md` (lines 280-358).

Key points:
- `POST /mcp` — JSON-RPC endpoint
- `GET /` — Info page with tool list
- Localhost-only security check

---

## Step 9: Create test files

### test/test_helper.exs
```elixir
ExUnit.start()
```

### test/pop_stash/mcp/server_test.exs
Copy from `01_mcp.md` (lines 428-498).

### test/pop_stash/mcp/router_test.exs
Copy from `01_mcp.md` (lines 501-529).

### test/pop_stash/mcp/tools/ping_test.exs
Copy from `01_mcp.md` (lines 532-543).

---

## Step 10: Verify

```bash
# Compile
mix compile

# Run tests
mix test

# Start server
mix run --no-halt

# In another terminal, test endpoints:
curl -X POST http://localhost:4001/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'

curl -X POST http://localhost:4001/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ping","arguments":{}}}'

# Open info page
open http://localhost:4001
```

---

## Final File Structure

```
pop_stash/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   └── prod.exs
├── lib/
│   └── pop_stash/
│       ├── application.ex
│       └── mcp/
│           ├── router.ex
│           ├── server.ex
│           └── tools/
│               └── ping.ex
├── test/
│   ├── test_helper.exs
│   └── pop_stash/
│       └── mcp/
│           ├── router_test.exs
│           ├── server_test.exs
│           └── tools/
│               └── ping_test.exs
└── mix.exs
```

---

## Done When

- [x] `mix compile` succeeds with no warnings
- [x] `mix test` passes (all green — 15 tests)
- [x] `mix credo` passes (no issues)
- [ ] `curl` to `/mcp` with ping method returns `{"jsonrpc":"2.0","id":1,"result":{}}`
- [ ] `curl` to `/mcp` with tools/call ping returns `pong` in content
- [ ] `http://localhost:4001` shows info page with ping tool listed
- [ ] Non-localhost requests return 403

## Implementation Complete

All code implemented on **2025-01-16**. Run `mix run --no-halt` to start the server and verify the remaining curl tests.
