# Phoenix + LiveView Migration Plan for PopStash

## Overview

Convert PopStash from a standalone Elixir/Plug app to a Phoenix application while maintaining 100% backward compatibility with the existing MCP server. This is **Phase 1: Phoenix Setup Only** - no LiveView UI implementation yet.

**Architecture Strategy:** Dual-Port (MCP on 4001, Phoenix on 4000)

## Current State

- Elixir 1.18 app with Ecto + Postgres + pgvector
- Bandit HTTP server (Plug-based) on port 4001
- Custom Plug.Router for MCP JSON-RPC endpoints
- Phoenix.PubSub already in supervision tree ✓
- Comprehensive test coverage for contexts and MCP tools

## Target State (Phase 1)

- Phoenix Endpoint on port 4000 with minimal scaffold
- MCP server remains on port 4001 (unchanged)
- Shared infrastructure (Repo, PubSub, contexts)
- Basic Phoenix structure ready for future LiveView UI
- Both servers in same supervision tree
- Simple welcome page to verify Phoenix is working

**Out of Scope (Future Phases):**
- LiveView pages for stashes, insights, decisions
- UI components and forms
- Real-time features
- Search interface

---

## Phase 1: Add Phoenix Dependencies

### Dependencies to Add (mix.exs)

```elixir
# Phoenix core
{:phoenix, "~> 1.8.1"},
{:phoenix_html, "~> 4.1"},
{:phoenix_live_view, "~> 1.1.0"},
{:phoenix_live_dashboard, "~> 0.8.3"},
{:gettext, "~> 0.26"},  # i18n support

# Asset pipeline
{:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
{:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
{:heroicons,
  github: "tailwindlabs/heroicons",
  tag: "v2.2.0",
  sparse: "optimized",
  app: false,
  compile: false,
  depth: 1},

# Development/test tools
{:phoenix_live_reload, "~> 1.2", only: :dev},
{:lazy_html, ">= 0.1.0", only: :test}  # Fast HTML parsing for LiveView tests
```

**Notes:**
- Using Phoenix 1.8.1+ (latest stable)
- `lazy_html` replaces `floki` for faster LiveView testing
- `heroicons` provides SVG icons that work well with Tailwind
- `gettext` for future i18n support
- Asset tools use `runtime: Mix.env() == :dev` per current conventions

### Configuration Changes

**config/config.exs** - Add Phoenix endpoint:
```elixir
# Phoenix Endpoint configuration
config :pop_stash, PopStashWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PopStashWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: PopStash.PubSub,
  live_view: [signing_salt: "GENERATE_SECRET_WITH_mix_phx.gen.secret_32"]

# Asset bundlers (esbuild for JS, Tailwind for CSS)
config :esbuild,
  version: "0.21.5",
  pop_stash: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.15",
  pop_stash: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Gettext for i18n
config :pop_stash, PopStashWeb.Gettext, default_locale: "en"
```

**Important:** Generate signing salt with `mix phx.gen.secret 32`

**config/dev.exs** - Add development config:
```elixir
config :pop_stash, PopStashWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "DEV_SECRET_64_CHARS_MIN",
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/pop_stash_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ],
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:pop_stash, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:pop_stash, ~w(--watch)]}
  ]
```

**Note:** Added `live_reload` patterns for proper hot-reloading of templates and components.

**config/test.exs** - Disable Phoenix in tests:
```elixir
config :pop_stash, PopStashWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TEST_SECRET_64_CHARS_MIN",
  server: false
```

**config/runtime.exs** - Production config:
```elixir
if config_env() == :prod do
  phoenix_port = String.to_integer(System.get_env("PHOENIX_PORT") || "4000")
  phoenix_secret = System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE not set")
  phoenix_host = System.get_env("PHX_HOST") || "localhost"
  
  config :pop_stash, PopStashWeb.Endpoint,
    url: [host: phoenix_host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: phoenix_port],
    secret_key_base: phoenix_secret,
    server: true
end
```

**Update mix.exs aliases:**
```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
    "ecto.setup": ["ecto.create", "ecto.migrate"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
    "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
    "assets.build": ["tailwind pop_stash", "esbuild pop_stash"],
    "assets.deploy": ["tailwind pop_stash --minify", "esbuild pop_stash --minify", "phx.digest"],
    lint: ["format --check-formatted", "credo --strict", "sobelow --config"]
  ]
end
```

**Critical File:** `mix.exs`

---

## Phase 2: Update Supervision Tree

**File:** `lib/pop_stash/application.ex`

Add Phoenix.Endpoint before Bandit:

```elixir
def start(_type, _args) do
  children =
    [
      PopStash.Repo,
      {Phoenix.PubSub, name: PopStash.PubSub},
      {Task.Supervisor, name: PopStash.TaskSupervisor, max_children: 50}
    ]
    |> maybe_add(start_phoenix?(), PopStashWeb.Endpoint)
    |> maybe_add(typesense_enabled?(), {TypesenseEx, typesense_config()})
    |> maybe_add(embeddings_enabled?(), embeddings_child_spec())
    |> maybe_add(typesense_enabled?() and embeddings_enabled?(), PopStash.Search.Indexer)
    |> maybe_add(start_mcp_server?(), {Bandit, plug: PopStash.MCP.Router, port: mcp_port()})

  Supervisor.start_link(children, strategy: :one_for_one, name: PopStash.Supervisor)
end

defp start_phoenix?, do: Application.get_env(:pop_stash, :start_phoenix, true)
defp start_mcp_server?, do: Application.get_env(:pop_stash, :start_mcp_server, true)
```

**Update test config:**
```elixir
# config/test.exs
config :pop_stash,
  start_phoenix: false,
  start_mcp_server: false
```

**Critical File:** `lib/pop_stash/application.ex`

---

## Phase 3: Create Minimal Phoenix Web Structure

### Directory Structure (Minimal Scaffold)

```
lib/pop_stash_web/
├── endpoint.ex
├── router.ex
├── telemetry.ex
├── gettext.ex
├── components/
│   ├── core_components.ex
│   └── layouts.ex
└── controllers/
    ├── page_html.ex
    └── page_controller.ex
```

**Note:** No LiveView modules yet - this is just the minimum Phoenix setup.

### Core Module (lib/pop_stash_web.ex)

Standard Phoenix 1.7 web module with:
- `router/0` - Router macros
- `controller/0` - Controller macros
- `live_view/0` - LiveView macros
- `live_component/0` - LiveComponent macros
- `html/0` - Component macros
- `verified_routes/0` - Route helpers

### Endpoint (lib/pop_stash_web/endpoint.ex)

```elixir
defmodule PopStashWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :pop_stash

  socket "/live", Phoenix.LiveView.Socket
  socket "/phoenix/live_reload/socket", Phoenix.LiveReload.Socket
  
  plug Plug.Static, at: "/", from: :pop_stash, only: PopStashWeb.static_paths()
  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json]
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, store: :cookie, key: "_pop_stash_key"
  plug PopStashWeb.Router
end
```

### Router (lib/pop_stash_web/router.ex)

```elixir
defmodule PopStashWeb.Router do
  use PopStashWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PopStashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", PopStashWeb do
    pipe_through :browser

    get "/", PageController, :home
  end
end
```

**Note:** Just a simple welcome page for now. LiveView routes will be added in future phases.

---

## Phase 4: Asset Pipeline Setup

### Directory Structure

```
assets/
├── css/
│   └── app.css
├── js/
│   ├── app.js
│   └── hooks.js
├── vendor/
│   └── topbar.js
└── tailwind.config.js
```

### assets/css/app.css

```css
@import "tailwindcss/base";
@import "tailwindcss/components";
@import "tailwindcss/utilities";
```

### assets/js/app.js

```javascript
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
```

### assets/tailwind.config.js

```javascript
module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/pop_stash_web.ex",
    "../lib/pop_stash_web/**/*.*ex"
  ],
  theme: {
    extend: {},
  },
  plugins: [require("@tailwindcss/forms")],
}
```

---

## Phase 5: Core Components and Layouts

### Components to Create

1. **lib/pop_stash_web/components/core_components.ex**
   - Standard Phoenix 1.7 components (buttons, inputs, tables, modals, flash)

2. **lib/pop_stash_web/components/layouts.ex**
   - Root and app layouts

3. **lib/pop_stash_web/components/layouts/root.html.heex**
   - Base HTML with meta tags, CSS/JS imports

4. **lib/pop_stash_web/components/layouts/app.html.heex**
   - Navigation header with project context
   - Links to Stashes, Insights, Decisions, Search, Projects

---

## Phase 6: Implement LiveView Pages

### Pattern: PubSub Subscriptions

All LiveViews subscribe to `"memory:events"` on mount for real-time updates:

```elixir
def mount(params, session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
  end
  # ...
end

def handle_info({:stash_created, stash}, socket) do
  # Update assigns with new stash
end
```

### LiveViews to Implement

1. **ProjectLive.Index** - List/create projects
2. **StashLive.Index** - Browse stashes with real-time updates
3. **StashLive.Show** - View/edit single stash
4. **InsightLive.Index** - Browse insights with key-based filtering
5. **InsightLive.Show** - View/edit single insight
6. **DecisionLive.Index** - Browse decisions by topic
7. **DecisionLive.Show** - View decision history for a topic
8. **SearchLive.Index** - Unified semantic search across all entities

**Key Features:**
- Real-time updates from MCP operations via PubSub
- Tag filtering and search
- Expiration UI for stashes
- Decision timeline view
- Inline editing

**Reference:** `lib/pop_stash/memory.ex` for PubSub broadcast patterns

---

## Phase 7: Testing Strategy

### Test Structure

```
test/
├── pop_stash/              # Existing (unchanged)
│   ├── memory_test.exs
│   ├── projects_test.exs
│   └── mcp/
├── pop_stash_web/          # NEW
│   ├── controllers/
│   └── live/
└── support/
    ├── conn_case.ex        # NEW
    ├── data_case.ex        # Existing
    └── fixtures.ex         # Existing
```

### New Test Support

**test/support/conn_case.ex:**
```elixir
defmodule PopStashWeb.ConnCase do
  use ExUnit.CaseTemplate
  
  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import PopStashWeb.ConnCase
      
      @endpoint PopStashWeb.Endpoint
    end
  end
  
  setup tags do
    PopStash.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
```

### Example LiveView Test

```elixir
defmodule PopStashWeb.StashLiveTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest
  
  test "receives real-time updates", %{conn: conn} do
    {:ok, project} = Projects.create("Test Project")
    {:ok, view, _html} = live(conn, ~p"/#{project.id}/stashes")
    
    # Create stash (triggers PubSub)
    {:ok, _stash} = Memory.create_stash(project.id, "new", "summary")
    
    # Verify LiveView updated
    assert render(view) =~ "new"
  end
end
```

**Test Execution:**
- Existing: `mix test test/pop_stash/`
- Phoenix: `mix test test/pop_stash_web/`
- All: `mix test`

---

## Phase 8: Docker and Deployment

### docker-compose.yml Updates

```yaml
services:
  app:
    ports:
      - "127.0.0.1:4001:4001"  # MCP server
      - "127.0.0.1:4000:4000"  # Phoenix UI (NEW)
    environment:
      MCP_PORT: "4001"
      PHOENIX_PORT: "4000"              # NEW
      SECRET_KEY_BASE: "GENERATE_64"    # NEW
      PHX_HOST: "localhost"             # NEW
```

**Critical File:** `docker-compose.yml`

---

## Migration Checklist

### Step-by-Step Execution

1. **Phase 1: Dependencies**
   - Add deps to mix.exs
   - Add config entries
   - Run `mix deps.get`

2. **Phase 2: Supervision**
   - Update Application.start/2
   - Test boot: `iex -S mix`

3. **Phase 3: Structure**
   - Create lib/pop_stash_web/ modules
   - Create Endpoint, Router

4. **Phase 4: Assets**
   - Create assets/ directory
   - Run `mix assets.setup && mix assets.build`

5. **Phase 5: Components**
   - Create CoreComponents, Layouts

6. **Phase 6: LiveViews**
   - Implement all LiveView pages
   - Add PubSub subscriptions

7. **Phase 7: Tests**
   - Create ConnCase
   - Add LiveView tests

8. **Phase 8: Docker**
   - Update docker-compose.yml
   - Test both ports

---

## Verification

**After Each Phase:**
- Run existing tests: `mix test test/pop_stash/`
- Verify MCP server: `curl http://localhost:4001/`
- Check supervision tree: `:observer.start()`

**Final Integration Test:**
1. Start: `mix phx.server`
2. MCP endpoint: `curl -X POST http://localhost:4001/mcp/:project_id`
3. Phoenix UI: Open `http://localhost:4000`
4. Real-time: Make MCP call, watch UI update

---

## Key Architectural Decisions

1. **Dual-Port Architecture**
   - MCP on 4001 (unchanged), Phoenix on 4000 (new)
   - Zero breaking changes for MCP clients
   - Clean separation of concerns

2. **Shared Infrastructure**
   - Both use PopStash.Repo, Phoenix.PubSub
   - Both use same context modules (Memory, Projects)
   - Real-time updates via PubSub events

3. **Router Coexistence**
   - Keep Plug.Router for MCP (simpler for JSON-RPC)
   - Phoenix.Router for web UI (better for LiveView)

4. **Real-time Updates**
   - LiveViews subscribe to `"memory:events"`
   - Get updates from MCP operations automatically
   - No polling, no manual refresh

---

## Critical Files

1. `mix.exs`
2. `lib/pop_stash/application.ex`
3. `lib/pop_stash/memory.ex` (reference for PubSub patterns)
4. `docker-compose.yml`
