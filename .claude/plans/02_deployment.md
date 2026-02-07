# PopStash Deployment Guide

## Quick Start (Docker)

```bash
# Clone and start everything
git clone https://github.com/MixTapeSoftware/pop_stash.git
cd pop_stash
docker compose up -d

# That's it. Server is running at http://localhost:4001
# A default project was auto-created. Get its ID:
docker compose exec app bin/pop_stash project list
```

## Quick Start (Without Docker)

```bash
# Prerequisites: Elixir 1.18+, PostgreSQL 16+ with pgvector

# Clone
git clone https://github.com/MixTapeSoftware/pop_stash.git
cd pop_stash

# Setup (creates DB, runs migrations, creates default project)
bin/setup

# Start server
bin/server
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Compose                           │
│                                                              │
│  ┌─────────────────────┐     ┌─────────────────────────┐    │
│  │    pop_stash app    │     │    PostgreSQL 16        │    │
│  │                     │     │    + pgvector           │    │
│  │  - Elixir/OTP       │────▶│                         │    │
│  │  - Bandit HTTP      │     │  Port: 5432 (internal)  │    │
│  │  - Nx/Bumblebee     │     │                         │    │
│  │                     │     └─────────────────────────┘    │
│  │  Port: 4001         │                                    │
│  └─────────────────────┘                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Docker Setup

### Files

```
pop_stash/
├── Dockerfile              # Multi-stage build with bundled ML models
├── docker-compose.yml      # App + PostgreSQL
├── docker/
│   └── entrypoint.sh       # Runs setup on first boot, then starts server
└── bin/
    ├── setup               # One-time initialization
    ├── server              # Start the server
    └── pop_stash           # CLI wrapper
```

### Dockerfile

```dockerfile
# Dockerfile
# Multi-stage build for PopStash
# Bundles Nx/Bumblebee models for fast startup

# =============================================================================
# Stage 1: Build
# =============================================================================
FROM hexpm/elixir:1.18.1-erlang-27.2-debian-bookworm-20241202-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install dependencies first (cache layer)
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy source
COPY config config
COPY lib lib
COPY priv priv

# Compile application
RUN mix compile

# Download and cache Nx/Bumblebee models
# This makes the image larger but startup instant
RUN mix run -e "PopStash.Memory.Embeddings.download_model()"

# Build release
RUN mix release

# =============================================================================
# Stage 2: Runtime
# =============================================================================
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Create non-root user
RUN useradd --create-home --shell /bin/bash pop_stash
RUN chown -R pop_stash:pop_stash /app
USER pop_stash

# Copy release from builder
COPY --from=builder --chown=pop_stash:pop_stash /app/_build/prod/rel/pop_stash ./

# Copy cached models from builder
COPY --from=builder --chown=pop_stash:pop_stash /root/.cache/bumblebee /home/pop_stash/.cache/bumblebee

# Copy entrypoint
COPY --chown=pop_stash:pop_stash docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Expose port
EXPOSE 4001

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:4001/ || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["server"]
```

### docker-compose.yml

```yaml
# docker-compose.yml
services:
  app:
    build: .
    ports:
      - "4001:4001"
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/pop_stash
      MCP_PORT: 4001
      SECRET_KEY_BASE: ${SECRET_KEY_BASE:-generate-a-real-secret-for-production}
      # Set to "true" to skip auto-creating default project
      SKIP_DEFAULT_PROJECT: ${SKIP_DEFAULT_PROJECT:-false}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    volumes:
      # Persist model cache (optional, models are bundled but this speeds rebuilds)
      - model_cache:/home/pop_stash/.cache/bumblebee

  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: pop_stash
    ports:
      # Expose for local development; remove in production
      - "127.0.0.1:5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  pgdata:
  model_cache:
```

### docker/entrypoint.sh

```bash
#!/bin/bash
set -e

# docker/entrypoint.sh
# Entrypoint for PopStash Docker container
# Runs migrations and creates default project on first boot

MARKER_FILE="/app/.pop_stash_initialized"

log() {
    echo "[entrypoint] $1"
}

wait_for_db() {
    log "Waiting for database..."
    until /app/bin/pop_stash eval "PopStash.Repo.query(\"SELECT 1\")" > /dev/null 2>&1; do
        sleep 1
    done
    log "Database is ready"
}

run_migrations() {
    log "Running database migrations..."
    /app/bin/pop_stash eval "PopStash.Release.migrate()"
    log "Migrations complete"
}

create_default_project() {
    if [ "$SKIP_DEFAULT_PROJECT" = "true" ]; then
        log "Skipping default project creation (SKIP_DEFAULT_PROJECT=true)"
        return
    fi

    log "Checking for default project..."
    if /app/bin/pop_stash eval "PopStash.Release.default_project_exists?()" | grep -q "true"; then
        log "Default project already exists"
    else
        log "Creating default project..."
        /app/bin/pop_stash eval "PopStash.Release.create_default_project()"
        log "Default project created"
    fi
}

initialize() {
    wait_for_db
    run_migrations
    create_default_project
    touch "$MARKER_FILE"
    log "Initialization complete"
}

case "$1" in
    server)
        # Always run migrations (idempotent) and check default project
        initialize
        log "Starting PopStash server on port ${MCP_PORT:-4001}..."
        exec /app/bin/pop_stash start
        ;;
    migrate)
        wait_for_db
        run_migrations
        ;;
    setup)
        initialize
        ;;
    eval)
        shift
        exec /app/bin/pop_stash eval "$@"
        ;;
    *)
        exec /app/bin/pop_stash "$@"
        ;;
esac
```

---

## Without Docker

### Prerequisites

- **Elixir** 1.18+ with OTP 27+
- **PostgreSQL** 16+ with pgvector extension
- **Git**

#### macOS

```bash
brew install elixir postgresql@16
# Install pgvector
brew install pgvector

# Start PostgreSQL
brew services start postgresql@16
```

#### Ubuntu/Debian

```bash
# Elixir (via asdf recommended)
asdf plugin add elixir
asdf install elixir 1.18.1-otp-27
asdf global elixir 1.18.1-otp-27

# PostgreSQL with pgvector
sudo apt install postgresql-16 postgresql-16-pgvector
sudo systemctl start postgresql
```

### bin/setup

```bash
#!/bin/bash
set -e

# bin/setup
# One-time setup script for PopStash
# Safe to run multiple times (idempotent)

cd "$(dirname "$0")/.."

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[setup]${NC} $1"; }
success() { echo -e "${GREEN}[setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[setup]${NC} $1"; }
error() { echo -e "${RED}[setup]${NC} $1"; exit 1; }

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v elixir &> /dev/null; then
        error "Elixir not found. Install with: brew install elixir (macOS) or see https://elixir-lang.org/install.html"
    fi

    if ! command -v psql &> /dev/null; then
        error "PostgreSQL not found. Install with: brew install postgresql@16 (macOS)"
    fi

    # Check Elixir version
    ELIXIR_VERSION=$(elixir --version | grep "Elixir" | cut -d' ' -f2)
    log "Found Elixir $ELIXIR_VERSION"

    success "Prerequisites OK"
}

# Install Elixir dependencies
install_deps() {
    log "Installing Elixir dependencies..."

    # Install hex and rebar if needed
    mix local.hex --force --if-missing
    mix local.rebar --force --if-missing

    # Get dependencies
    mix deps.get

    success "Dependencies installed"
}

# Setup database
setup_database() {
    log "Setting up database..."

    # Check if database exists
    if mix ecto.create 2>&1 | grep -q "already exists"; then
        log "Database already exists"
    else
        success "Database created"
    fi

    # Run migrations
    log "Running migrations..."
    mix ecto.migrate

    success "Database ready"
}

# Download ML models (for semantic search)
download_models() {
    log "Downloading ML models (this may take a few minutes on first run)..."

    # This triggers Bumblebee to download all-MiniLM-L6-v2
    mix run -e "PopStash.Memory.Embeddings.download_model()" 2>/dev/null || {
        warn "Model download skipped (will download on first use)"
    }

    success "Models ready"
}

# Create default project
create_default_project() {
    log "Checking for default project..."

    # Check if default project exists
    PROJECT_EXISTS=$(mix run -e "
        case PopStash.Projects.get_by_name(\"default\") do
            {:ok, _} -> IO.puts(\"exists\")
            {:error, :not_found} -> IO.puts(\"not_found\")
        end
    " 2>/dev/null)

    if [ "$PROJECT_EXISTS" = "exists" ]; then
        log "Default project already exists"
    else
        log "Creating default project..."
        mix pop_stash.project.new "default" --description "Default project (auto-created)"
        success "Default project created"
    fi
}

# Compile
compile() {
    log "Compiling..."
    mix compile
    success "Compiled"
}

# Main
main() {
    echo ""
    echo "================================"
    echo "   PopStash Setup"
    echo "================================"
    echo ""

    check_prerequisites
    install_deps
    compile
    setup_database
    download_models
    create_default_project

    echo ""
    success "Setup complete!"
    echo ""
    echo "To start the server:"
    echo "  bin/server"
    echo ""
    echo "Or with docker:"
    echo "  docker compose up -d"
    echo ""
    echo "Server will be available at: http://localhost:4001"
    echo ""

    # Show default project info
    log "Your default project:"
    mix pop_stash.project.list 2>/dev/null || true
    echo ""
}

main "$@"
```

### bin/server

```bash
#!/bin/bash
set -e

# bin/server
# Start the PopStash MCP server

cd "$(dirname "$0")/.."

# Default values
PORT="${MCP_PORT:-4001}"
ENV="${MIX_ENV:-dev}"

echo "[server] Starting PopStash on port $PORT (env: $ENV)"

if [ "$ENV" = "prod" ]; then
    # Production: use release
    exec _build/prod/rel/pop_stash/bin/pop_stash start
else
    # Development: use mix
    exec mix run --no-halt
fi
```

### bin/pop_stash

```bash
#!/bin/bash
set -e

# bin/pop_stash
# CLI wrapper for PopStash commands

cd "$(dirname "$0")/.."

case "$1" in
    setup)
        exec bin/setup
        ;;
    server)
        exec bin/server
        ;;
    project)
        shift
        case "$1" in
            new)
                shift
                exec mix pop_stash.project.new "$@"
                ;;
            list)
                exec mix pop_stash.project.list
                ;;
            delete)
                shift
                exec mix pop_stash.project.delete "$@"
                ;;
            *)
                echo "Usage: bin/pop_stash project {new|list|delete}"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "PopStash CLI"
        echo ""
        echo "Usage:"
        echo "  bin/pop_stash setup           # Run one-time setup"
        echo "  bin/pop_stash server          # Start the MCP server"
        echo "  bin/pop_stash project new     # Create a new project"
        echo "  bin/pop_stash project list    # List all projects"
        echo "  bin/pop_stash project delete  # Delete a project"
        echo ""
        exit 1
        ;;
esac
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgres://localhost/pop_stash_dev` | PostgreSQL connection string |
| `MCP_PORT` | `4001` | HTTP server port |
| `SECRET_KEY_BASE` | (generated) | Secret for signing (required in prod) |
| `SKIP_DEFAULT_PROJECT` | `false` | Set to `true` to skip auto-creating default project |
| `POOL_SIZE` | `10` | Database connection pool size |

### Using an External Database

```bash
# With Docker
docker compose up -d app  # Skip the db service

# Set DATABASE_URL to your external DB
DATABASE_URL=postgres://user:pass@your-db-host:5432/pop_stash \
docker compose up -d app
```

```yaml
# Or in docker-compose.override.yml
services:
  app:
    environment:
      DATABASE_URL: postgres://user:pass@your-db-host:5432/pop_stash
    depends_on: []  # Remove db dependency
```

### Production Checklist

- [ ] Set `SECRET_KEY_BASE` to a secure random value
- [ ] Use external PostgreSQL with backups
- [ ] Configure TLS termination (nginx, Caddy, etc.)
- [ ] Set appropriate `POOL_SIZE` for your workload
- [ ] Configure log aggregation
- [ ] Set up monitoring (SigNoz optional integration)

---

## Release Module

Add this module for release-time operations:

```elixir
# lib/pop_stash/release.ex
defmodule PopStash.Release do
  @moduledoc """
  Release-time operations for PopStash.
  Called from Docker entrypoint and bin scripts.
  """

  @app :pop_stash

  @doc "Run all pending migrations"
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc "Rollback migrations"
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc "Check if default project exists"
  def default_project_exists? do
    load_app()
    start_repo()

    case PopStash.Projects.get_by_name("default") do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @doc "Create the default project"
  def create_default_project do
    load_app()
    start_repo()

    case PopStash.Projects.create(%{
      name: "default",
      description: "Default project (auto-created on first boot)"
    }) do
      {:ok, project} ->
        IO.puts("Created default project: #{project.id}")
        {:ok, project}

      {:error, changeset} ->
        IO.puts("Failed to create default project: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_repo do
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto_sql)
    PopStash.Repo.start_link()
  end
end
```

---

## Troubleshooting

### Database connection refused

```bash
# Check if PostgreSQL is running
docker compose ps db
# or
pg_isready -h localhost

# Check logs
docker compose logs db
```

### Model download slow/failing

```bash
# Models are bundled in Docker image, but for local dev:
# Manually trigger download
mix run -e "PopStash.Memory.Embeddings.download_model()"

# Check Hugging Face cache
ls -la ~/.cache/bumblebee/
```

### Port already in use

```bash
# Find what's using port 4001
lsof -i :4001

# Use a different port
MCP_PORT=4002 bin/server
```

### Reset everything

```bash
# Docker
docker compose down -v  # Removes volumes too
docker compose up -d

# Local
mix ecto.drop
bin/setup
```

---

## Next Steps

After setup:

1. **Get your project ID**:
   ```bash
   bin/pop_stash project list
   # or
   docker compose exec app bin/pop_stash project list
   ```

2. **Configure your MCP client** (e.g., `.claude/mcp_servers.json`):
   ```json
   {
     "pop_stash": {
       "url": "http://localhost:4001/mcp/YOUR_PROJECT_ID"
     }
   }
   ```

3. **Test the connection**:
   ```bash
   curl -X POST http://localhost:4001/mcp/YOUR_PROJECT_ID \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
   ```

4. **Create additional projects** (optional):
   ```bash
   bin/pop_stash project new "My Other Project"
   ```
