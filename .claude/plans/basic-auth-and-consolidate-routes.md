# Plan: Add Basic Auth and Consolidate Routes

## Summary

Add HTTP Basic Authentication to protect all browser routes, consolidate the dashboard to the root route, and integrate MCP info styling with the dashboard. This plan addresses the security gap where browser routes are currently unprotected.

## Architecture Decisions

1. **Single credential set**: Basic auth with one username/password (can extend later if needed)
2. **Fail-secure defaults**: Return 503 if credentials not configured in production
3. **Browser pipeline integration**: Add BasicAuth directly to `:browser` pipeline (protects all browser routes)
4. **Keep MCP Info as controller**: No need for LiveView overhead for a static documentation page
5. **Grouped config keys**: Use `config :pop_stash, :basic_auth, [username: ..., password: ...]`

## Implementation Steps

### Step 0: Consolidate runtime.exs (PREREQUISITE)

**File:** `config/runtime.exs`

**Problem:** Currently has two `if config_env() == :prod do` blocks (lines 23-68 and 124-166), creating maintenance hazard.

**Action:** Merge the two blocks into a single prod configuration block before proceeding with other changes.

### Step 1: Create BasicAuth Plug

**File:** `lib/pop_stash_web/plugs/basic_auth.ex`

```elixir
defmodule PopStashWeb.Plugs.BasicAuth do
  @moduledoc """
  HTTP Basic Authentication plug with environment-aware behavior.

  Wraps Plug.BasicAuth with:
  - Skip auth when `:skip_basic_auth` config is true (dev/test)
  - Return 503 if credentials not configured (fail secure)
  - Configurable realm for browser auth dialogs

  ## Configuration

      # Production (runtime.exs)
      config :pop_stash, :basic_auth,
        username: System.get_env("BASIC_AUTH_USERNAME"),
        password: System.get_env("BASIC_AUTH_PASSWORD")

      # Dev/Test
      config :pop_stash, :skip_basic_auth, true
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    cond do
      skip_auth?() ->
        conn

      not credentials_configured?() ->
        Logger.error("Basic auth credentials not configured - returning 503")
        conn
        |> send_resp(503, "Service unavailable - authentication not configured")
        |> halt()

      true ->
        realm = Keyword.get(opts, :realm, "PopStash Dashboard")
        Plug.BasicAuth.basic_auth(conn, username: username(), password: password(), realm: realm)
    end
  end

  defp skip_auth?, do: Application.get_env(:pop_stash, :skip_basic_auth, false)

  defp credentials_configured? do
    config = Application.get_env(:pop_stash, :basic_auth, [])
    Keyword.get(config, :username) != nil and Keyword.get(config, :password) != nil
  end

  defp username, do: Application.get_env(:pop_stash, :basic_auth, []) |> Keyword.get(:username)
  defp password, do: Application.get_env(:pop_stash, :basic_auth, []) |> Keyword.get(:password)
end
```

### Step 2: Update Router

**File:** `lib/pop_stash_web/router.ex`

**Changes:**

1. Add `PopStashWeb.Plugs.BasicAuth` to the `:browser` pipeline (after existing plugs)
2. Remove the `get "/", PageController, :home` route
3. Move `pop_stash_dashboard("/")` from `/pop_stash` scope to root `/` scope
4. Keep `/mcp-info` in browser scope (will inherit basic auth from pipeline)
5. Keep `/mcp/*` in `:mcp` pipeline (IP check only, no basic auth)

**New route structure:**
```
/              -> PopStash Dashboard (browser pipeline with basic auth)
/mcp-info      -> MCP Info page (browser pipeline with basic auth)
/mcp/*         -> MCP API endpoints (mcp pipeline, IP check only)
/dev/dashboard -> LiveDashboard (dev only, browser pipeline with basic auth)
```

**Updated browser pipeline:**
```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {PopStashWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers, %{...}
  plug PopStashWeb.Plugs.BasicAuth  # Add this
end
```

### Step 3: Update MCP Info Controller

**File:** `lib/pop_stash_web/controllers/mcp_controller.ex`

**Action:** Update the `info/2` action to use dashboard layout for consistent styling:

```elixir
def info(conn, _params) do
  # ... existing logic to gather tools, projects, port ...

  conn
  |> put_layout(html: {PopStashWeb.Layouts, :app})
  |> render(:info, tools: tools, projects: projects, port: port)
end
```

**Note:** Keep this as a controller action, not a LiveView. It's a static documentation page.

### Step 4: Configuration Updates

**File:** `config/runtime.exs` - Add to consolidated prod block:

```elixir
# Basic auth credentials (required for production)
config :pop_stash, :basic_auth,
  username: System.get_env("BASIC_AUTH_USERNAME"),
  password: System.get_env("BASIC_AUTH_PASSWORD")
```

**File:** `config/dev.exs` - Add:

```elixir
# Skip basic auth in development
config :pop_stash, :skip_basic_auth, true
```

**File:** `config/test.exs` - Add:

```elixir
# Skip basic auth in tests
config :pop_stash, :skip_basic_auth, true
```

### Step 5: Find and Update Internal Links

**Action:** Search for existing links pointing to `/pop_stash/*` and update them to point to `/`

```bash
# Find all references to /pop_stash paths
grep -r "pop_stash" lib/pop_stash_web --include="*.ex" --include="*.heex"
grep -r "/pop_stash" lib/pop_stash_web --include="*.ex" --include="*.heex"
```

Update any found links from `/pop_stash/...` to `/...`

### Step 6: Cleanup PageController

**File:** `lib/pop_stash_web/controllers/page_controller.ex`

**Action:** Remove the file entirely (no longer needed). The dashboard is now at root.

**Files to also check for removal:**
- `lib/pop_stash_web/controllers/page_html.ex`
- `lib/pop_stash_web/controllers/page_html/home.html.heex`
- `test/pop_stash_web/controllers/page_controller_test.exs`

### Step 7: Create Tests

**File:** `test/pop_stash_web/plugs/basic_auth_test.exs`

**Test cases:**

1. Auth bypassed when `skip_basic_auth: true`
2. Returns 401 Unauthorized when no credentials provided
3. Returns 401 Unauthorized with wrong credentials
4. Returns 200 OK with correct credentials
5. Returns 503 Service Unavailable when credentials not configured in production mode
6. Realm is set correctly in WWW-Authenticate header

**File:** `test/pop_stash_web/controllers/mcp_controller_test.exs`

**Update existing tests:**
- Update any tests for `/pop_stash/*` routes to use `/` instead
- Ensure `/mcp-info` tests still work with basic auth in test mode (should be skipped)

## Files to Modify

| File | Action |
|------|--------|
| `config/runtime.exs` | **Consolidate duplicate prod blocks first**, then add basic auth config |
| `lib/pop_stash_web/plugs/basic_auth.ex` | Create new plug |
| `lib/pop_stash_web/router.ex` | Add plug to :browser pipeline, move dashboard to root, remove PageController route |
| `lib/pop_stash_web/controllers/mcp_controller.ex` | Update `info/2` to use dashboard layout |
| `config/dev.exs` | Add `skip_basic_auth: true` |
| `config/test.exs` | Add `skip_basic_auth: true` |
| `lib/pop_stash_web/controllers/page_controller.ex` | Remove |
| `lib/pop_stash_web/controllers/page_html.ex` | Remove if exists |
| `lib/pop_stash_web/controllers/page_html/home.html.heex` | Remove if exists |
| `test/pop_stash_web/controllers/page_controller_test.exs` | Remove if exists |
| `test/pop_stash_web/plugs/basic_auth_test.exs` | Create |
| `test/pop_stash_web/controllers/mcp_controller_test.exs` | Update route references |

## Environment Variables (Production)

```bash
BASIC_AUTH_USERNAME=admin
BASIC_AUTH_PASSWORD=<secure-password>
```

**Important:** These must be set in production or the application will return 503 for browser routes (fail-secure behavior).

## Verification Steps

### 1. Dev mode (auth disabled by default)

```bash
mix phx.server
curl -I http://localhost:4001/
# Should return 200 OK (dashboard, no auth required)

curl -I http://localhost:4001/mcp-info
# Should return 200 OK (no auth required)
```

### 2. Dev mode with auth enabled (for testing)

Temporarily in `config/dev.exs`:
```elixir
config :pop_stash, :skip_basic_auth, false
config :pop_stash, :basic_auth,
  username: "admin",
  password: "secret"
```

```bash
curl -I http://localhost:4001/
# Should return 401 Unauthorized

curl -I -u admin:secret http://localhost:4001/
# Should return 200 OK

curl -I -u admin:wrong http://localhost:4001/
# Should return 401 Unauthorized
```

### 3. MCP endpoints (no basic auth, only IP check)

```bash
curl -I http://localhost:4001/mcp/test-project
# Should work with IP check only, no basic auth prompt
# (Will fail if not from allowed IP, but won't ask for credentials)
```

### 4. Production simulation (missing credentials)

Temporarily in `config/dev.exs`:
```elixir
config :pop_stash, :skip_basic_auth, false
# Don't set :basic_auth config
```

```bash
curl -I http://localhost:4001/
# Should return 503 Service Unavailable
# Check logs for "Basic auth credentials not configured" error
```

### 5. Run full test suite

```bash
mix test
mix precommit
```

All tests should pass. No routes should be broken.

## Security Notes

1. **HTTPS Required**: Basic auth sends credentials in base64 encoding (not encrypted). Always use HTTPS in production.

2. **Single Credential Set**: This implementation uses one username/password for all users. If you need multiple users or user-specific permissions, you'll need a different authentication system.

3. **MCP Endpoints Unaffected**: The `/mcp/*` API endpoints remain protected only by IP checking (no basic auth). This is intentional as programmatic MCP clients cannot handle browser auth dialogs.

4. **Fail-Secure Default**: If credentials are not configured in production, browser routes return 503 instead of allowing unauthenticated access.

## Future Considerations

- If multiple users or role-based access is needed, consider migrating to a proper authentication system (e.g., using `phx.gen.auth`)
- Consider adding rate limiting to prevent brute force attacks on the basic auth
- Consider adding an audit log for failed authentication attempts
