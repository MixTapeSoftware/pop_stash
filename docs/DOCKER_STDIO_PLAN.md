# Docker + MCP Proxy Implementation Plan

**Status**: ✅ Implemented  
**Goal**: Enable MCP clients (Zed, Claude Desktop, etc.) to connect via stdio using `mcp-proxy`, without requiring Elixir installed locally.

## Background

Currently, PopStash runs as an HTTP server on port 4001. While this works for Claude Code (via `"url"` config), other clients like Zed only support stdio transport. Additionally, requiring users to have Elixir/Mix installed creates friction.

**Previous approach** (rejected): Build custom stdio transport in Elixir, run Docker container per stdio session.

**Problems with previous approach**:
- ~500MB+ memory for embedding model **per client session**
- Cold start delay for each connection
- Reinventing transport layer that's already solved

**New approach**: Use `mcp-proxy` — a standard tool that bridges stdio to HTTP.

## Architecture

```
┌─────────────────┐    stdio    ┌─────────────────┐    HTTP    ┌─────────────────┐
│  Zed / Claude   │ ◄─────────► │    mcp-proxy    │ ─────────► │ Docker: PopStash│
│  Desktop        │             │  (local binary) │            │ (HTTP server)   │
└─────────────────┘             └─────────────────┘            └────────┬────────┘
                                                                        │
                                                               ┌────────▼────────┐
                                                               │  docker-compose │
                                                               │  - db (postgres)│
                                                               │  - typesense    │
                                                               └─────────────────┘
```

**Key insight**: One PopStash container serves all clients. The embedding model loads once. `mcp-proxy` is a lightweight local process that just translates stdio↔HTTP.

## End State

```bash
# 1. Start PopStash (one-time, runs in background)
cd pop_stash/service
docker compose up -d

# 2. Run database migrations
docker compose exec app bin/pop_stash eval "PopStash.Release.migrate()"

# 3. Create a project
docker compose exec app bin/pop_stash eval 'PopStash.CLI.project_new("My Project")'
# => Created project: abc123

# 4. Install mcp-proxy (skip if already installed)
# Option A: Docker (no additional dependencies)
docker pull ghcr.io/sparfenyuk/mcp-proxy:latest

# Option B: uv (recommended if you have uv)
uv tool install mcp-proxy

# Option C: pipx
pipx install mcp-proxy

# Option D: pip
pip install mcp-proxy

# 5. Configure MCP client (see below)
```

**MCP Client Config (Zed/Claude Desktop):**
```json
{
  "mcpServers": {
    "pop_stash": {
      "command": "mcp-proxy",
      "args": [
        "--transport", "streamablehttp",
        "http://localhost:4001/mcp/abc123"
      ]
    }
  }
}
```

**Claude Code (direct HTTP, no proxy needed):**
```json
{
  "pop_stash": {
    "url": "http://localhost:4001/mcp/abc123"
  }
}
```

## What is mcp-proxy?

[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) is a Python tool that bridges MCP transports:

- **stdio to SSE/StreamableHTTP**: MCP client speaks stdio, proxy connects to HTTP server
- Handles protocol translation, buffering, reconnection
- Standard tool in the MCP ecosystem

We use "stdio to StreamableHTTP" mode:
```bash
mcp-proxy --transport streamablehttp http://localhost:4001/mcp/PROJECT_ID
```

Multiple installation options available (Docker, uv, pipx, pip).

## Implementation Phases

### Phase 1: Verify Streamable HTTP Compatibility

PopStash's current HTTP endpoint is close to Streamable HTTP spec but may need minor adjustments.

**Streamable HTTP requirements:**
1. POST endpoint accepting JSON-RPC ✅ (have this)
2. Response `Content-Type: application/json` for single responses ⚠️ (verify)
3. Handle `Accept` header from client ⚠️ (may need to add)
4. Return proper status codes ✅ (have this)

**File**: `lib/pop_stash/mcp/router.ex` (modify)

```elixir
# Ensure proper content-type handling
post "/mcp/:project_id" do
  # ... existing code ...
  
  case Server.handle_message(conn.body_params, context) do
    {:ok, :notification} -> 
      send_resp(conn, 204, "")
    {:ok, response} -> 
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
    {:error, response} -> 
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
  end
end
```

**Testing:**
```bash
# Test with mcp-proxy (after docker compose up -d)
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' | \
  mcp-proxy --transport streamablehttp http://localhost:4001/mcp/test-project
```

---

### Phase 2: Release Configuration

Add Elixir release support for Docker deployment.

**File**: `mix.exs` (modify)

```elixir
def project do
  [
    app: :pop_stash,
    version: "0.1.0",
    elixir: "~> 1.18",
    elixirc_paths: elixirc_paths(Mix.env()),
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    aliases: aliases(),
    releases: releases()
  ]
end

defp releases do
  [
    pop_stash: [
      applications: [runtime_tools: :permanent]
    ]
  ]
end
```

**File**: `lib/pop_stash/release.ex` (create)

```elixir
defmodule PopStash.Release do
  @moduledoc """
  Release tasks for migrations and setup.
  """
  
  @app :pop_stash

  def migrate do
    load_app()
    
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  
  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
```

**File**: `lib/pop_stash/cli.ex` (create)

```elixir
defmodule PopStash.CLI do
  @moduledoc """
  CLI commands for release eval.
  """

  def project_new(name, description \\ nil) do
    {:ok, _} = Application.ensure_all_started(:pop_stash)
    
    attrs = %{name: name}
    attrs = if description, do: Map.put(attrs, :description, description), else: attrs
    
    case PopStash.Projects.create(attrs) do
      {:ok, project} ->
        IO.puts("Created project: #{project.id}")
        IO.puts("")
        IO.puts("MCP client config:")
        IO.puts(~s|  mcp-proxy --transport streamablehttp http://localhost:4001/mcp/#{project.id}|)
        
      {:error, changeset} ->
        IO.puts("Error: #{inspect(changeset.errors)}")
    end
  end

  def project_list do
    {:ok, _} = Application.ensure_all_started(:pop_stash)
    
    projects = PopStash.Projects.list()
    
    if projects == [] do
      IO.puts("No projects yet.")
      IO.puts("Create one with: docker compose exec app bin/pop_stash eval 'PopStash.CLI.project_new(\"Name\")'")
    else
      IO.puts("Projects:")
      for p <- projects do
        IO.puts("  #{p.id}  #{p.name}")
      end
    end
  end
end
```

---

### Phase 3: Docker Setup

**File**: `Dockerfile` (create)

```dockerfile
# Build stage
FROM elixir:1.18-otp-27-alpine AS build

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git build-base

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build environment
ENV MIX_ENV=prod

# Copy dependency files
COPY mix.exs mix.lock ./
COPY config config

# Install and compile dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY lib lib
COPY priv priv

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.20 AS runtime

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs libgcc

WORKDIR /app

# Copy release from build stage
COPY --from=build /app/_build/prod/rel/pop_stash ./

# Expose MCP port
EXPOSE 4001

CMD ["bin/pop_stash", "start"]
```

**File**: `.dockerignore` (create)

```
# Build artifacts
_build/
deps/
.elixir_ls/

# Git
.git/
.gitignore

# Documentation
docs/
*.md

# Test
test/
cover/

# Dev/IDE
.vscode/
.idea/
.zed/
.claude/
.expert/
.cache/

# Misc
erl_crash.dump
*.local.exs
```

---

### Phase 4: Docker Compose Updates

**File**: `docker-compose.yml` (modify)

```yaml
services:
  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: pop_stash_dev
    ports:
      - "127.0.0.1:5433:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - popstash

  typesense:
    image: typesense/typesense:27.1
    environment:
      TYPESENSE_API_KEY: pop_stash_dev_key
      TYPESENSE_DATA_DIR: /data
    ports:
      - "127.0.0.1:8108:8108"
    volumes:
      - typesense_data:/data
    networks:
      - popstash

  app:
    build: .
    ports:
      - "127.0.0.1:4001:4001"
    environment:
      DATABASE_URL: ecto://postgres:postgres@db:5432/pop_stash_dev
      TYPESENSE_URL: http://typesense:8108
      TYPESENSE_API_KEY: pop_stash_dev_key
      MCP_PORT: 4001
    depends_on:
      db:
        condition: service_healthy
      typesense:
        condition: service_started
    networks:
      - popstash

networks:
  popstash:
    name: popstash_network

volumes:
  pgdata:
  typesense_data:
```

---

### Phase 5: Documentation

**File**: `README.md` (modify)

Update with Docker-first installation:

```markdown
## Quick Start

### Prerequisites

- Docker and Docker Compose
- mcp-proxy (for stdio clients like Zed/Claude Desktop)

### Installation

# 1. Clone and start PopStash
git clone https://github.com/you/pop_stash.git
cd pop_stash/service
docker compose up -d

# 2. Run database migrations
docker compose exec app bin/pop_stash eval "PopStash.Release.migrate()"

# 3. Create a project
docker compose exec app bin/pop_stash eval 'PopStash.CLI.project_new("My Project")'
# => Created project: abc123

# 4. Install mcp-proxy (for Zed/Claude Desktop - skip if already installed)
uv tool install mcp-proxy      # or: pipx install mcp-proxy
                               # or: docker pull ghcr.io/sparfenyuk/mcp-proxy:latest

### MCP Client Configuration

#### Claude Code (direct HTTP)

Add to `.claude/mcp_servers.json`:

{
  "pop_stash": {
    "url": "http://localhost:4001/mcp/YOUR_PROJECT_ID"
  }
}

#### Zed / Claude Desktop (via mcp-proxy)

{
  "mcpServers": {
    "pop_stash": {
      "command": "mcp-proxy",
      "args": [
        "--transport", "streamablehttp",
        "http://localhost:4001/mcp/YOUR_PROJECT_ID"
      ]
    }
  }
}
```

---

## File Checklist

| File | Action | Phase |
|------|--------|-------|
| `lib/pop_stash/mcp/router.ex` | Verify/modify content-type | 1 |
| `mix.exs` | Add releases config | 2 |
| `lib/pop_stash/release.ex` | Create | 2 |
| `lib/pop_stash/cli.ex` | Create | 2 |
| `Dockerfile` | Create | 3 |
| `.dockerignore` | Create | 3 |
| `docker-compose.yml` | Modify (add app service) | 4 |
| `README.md` | Modify | 5 |

---

## What We're NOT Building

- ~~Custom stdio transport module~~ (mcp-proxy handles this)
- ~~Docker entrypoint complexity~~ (just use release start)
- ~~Per-session Docker containers~~ (one server, multiple clients)
- ~~Transport protocol code~~ (leverage ecosystem tools)

---

## Testing Plan

### Phase 1: Streamable HTTP compatibility
```bash
# Start server locally
mix run --no-halt

# Test with curl
curl -X POST http://localhost:4001/mcp/test-project \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}'

# Test with mcp-proxy
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' | \
  mcp-proxy --transport streamablehttp http://localhost:4001/mcp/test-project
```

### Phase 4: Full Docker integration
```bash
# Build and start
docker compose up -d --build

# Run migrations
docker compose exec app bin/pop_stash eval "PopStash.Release.migrate()"

# Create project
docker compose exec app bin/pop_stash eval 'PopStash.CLI.project_new("Test")'

# Test HTTP endpoint
curl http://localhost:4001/

# Test with mcp-proxy
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
  mcp-proxy --transport streamablehttp http://localhost:4001/mcp/PROJECT_ID
```

### Integration test with real client
1. Start docker-compose
2. Create project
3. Configure Zed with mcp-proxy
4. Verify MCP tools work from Zed

---

## Estimated Effort

| Phase | Time |
|-------|------|
| Phase 1: Verify Streamable HTTP | 30 min |
| Phase 2: Release config | 1 hour |
| Phase 3: Docker setup | 1 hour |
| Phase 4: Compose updates | 30 min |
| Phase 5: Documentation | 30 min |
| Testing & debugging | 1-2 hours |
| **Total** | **4-6 hours** |

---

## Comparison: Old Plan vs New Plan

| Aspect | Old (Custom Stdio) | New (mcp-proxy) |
|--------|-------------------|-----------------|
| Memory per client | ~500MB (embedding model) | ~0 (shared server) |
| Cold start | Yes, per session | No, server always running |
| Code to maintain | ~200 lines Elixir | ~0 (use ecosystem) |
| Docker complexity | Entrypoint modes, eval | Simple release start |
| Dependency | Docker | Docker + mcp-proxy |

**Users need Docker for PopStash and mcp-proxy for stdio clients.** Multiple mcp-proxy installation options available (uv, pipx, pip, or Docker).

---

## Future Enhancements

- [ ] Create `bin/popstash` wrapper script for common commands
- [ ] Add health check endpoint for Docker
- [ ] Consider publishing pre-built Docker image to GHCR
- [ ] Add `docker compose` profile for dev vs prod