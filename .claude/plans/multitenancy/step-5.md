# Step 5: Router & OrgPlug

## Overview
Create OrgPlug for LiveView on_mount, update router to remove BasicAuth and add UserAuth pipelines, create org selection LiveViews.

## Context
This step connects authentication (Step 2) with access control (Step 3) via the router and OrgPlug. OrgPlug assigns current_scope to socket.assigns and calls `Repo.put_org_id` to activate `prepare_query` enforcement for LiveView processes.

## Implementation

### 1. Create OrgPlug

**File**: `lib/pop_stash_web/plugs/org_plug.ex`

```elixir
defmodule PopStashWeb.OrgPlug do
  @moduledoc """
  Assigns the current organization scope to the connection.

  Provides two on_mount hooks:
  - :assign_current_org - Assigns org if selected (optional)
  - :ensure_org_selected - Requires org selection, redirects if missing
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias PopStash.Organizations
  alias PopStash.Scope

  def on_mount(:assign_current_org, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:cont, socket}

      user ->
        socket = assign_current_scope(socket, user)
        {:cont, socket}
    end
  end

  def on_mount(:ensure_org_selected, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, redirect(socket, to: "/users/log-in")}

      user ->
        socket = assign_current_scope(socket, user)

        case socket.assigns[:current_scope] do
          %Scope{org_id: nil} ->
            {:halt, redirect(socket, to: "/orgs/select")}

          %Scope{} ->
            {:cont, socket}

          nil ->
            {:halt, redirect(socket, to: "/orgs/select")}
        end
    end
  end

  defp assign_current_scope(socket, user) do
    case Scope.from_user(user) do
      {:ok, scope} ->
        # Set org_id in process dictionary for prepare_query enforcement
        PopStash.Repo.put_org_id(scope.org_id)

        socket
        |> assign(:current_scope, scope)
        |> assign(:current_org_id, scope.org_id)
        |> maybe_assign_org(scope.org_id)

      {:error, _} ->
        assign(socket, current_scope: nil, current_org_id: nil)
    end
  end

  defp maybe_assign_org(socket, org_id) do
    case Organizations.get(org_id) do
      {:ok, org} -> assign(socket, :current_org, org)
      _ -> socket
    end
  end
end
```

### 2. Update Router

**File**: `lib/pop_stash_web/router.ex`

```elixir
defmodule PopStashWeb.Router do
  use PopStashWeb, :router

  import PopStashWeb.Dashboard.Router
  import PopStashWeb.UserAuth

  ## Pipelines

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PopStashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
          "style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data: https:; " <>
          "font-src 'self' data:; " <>
          "connect-src 'self' ws://localhost:* wss://localhost:*"
    }
    plug :fetch_current_user  # From UserAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug :accepts, ["json"]
    plug PopStashWeb.Plugs.CheckLocalhost
  end

  ## Public routes

  scope "/", PopStashWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PopStashWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log-in", UserLoginLive, :new
    end

    post "/users/log-in", UserSessionController, :create
    get "/users/log-in/:token", UserSessionController, :verify_token
  end

  ## Authenticated routes (no org required)

  scope "/", PopStashWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {PopStashWeb.UserAuth, :ensure_authenticated},
        {PopStashWeb.OrgPlug, :assign_current_org}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email

      # Organization selection
      live "/orgs/select", OrgSelectionLive, :index
      live "/orgs/new", OrgFormLive, :new
    end

    delete "/users/log-out", UserSessionController, :delete
  end

  ## Org-scoped routes (requires org selection)

  scope "/", PopStashWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :org_scoped,
      on_mount: [
        {PopStashWeb.UserAuth, :ensure_authenticated},
        {PopStashWeb.OrgPlug, :ensure_org_selected}
      ] do
      # Dashboard at root (org scoped)
      pop_stash_dashboard("/")
    end
  end

  ## MCP endpoint (IP check only, unchanged)

  scope "/mcp", PopStashWeb do
    pipe_through :mcp

    get "/", MCPController, :index
    get "/:project_id", MCPController, :show
    post "/:project_id", MCPController, :handle
  end

  ## Dev routes

  if Application.compile_env(:pop_stash, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PopStashWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
```

### 3. Create Org Selection LiveView

**File**: `lib/pop_stash_web/live/org_selection_live.ex`

```elixir
defmodule PopStashWeb.OrgSelectionLive do
  use PopStashWeb, :live_view

  alias PopStash.Accounts
  alias PopStash.Organizations

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    orgs = Organizations.list_for_user(user.id)

    socket =
      socket
      |> assign(:page_title, "Select Organization")
      |> assign(:orgs, orgs)

    {:ok, socket}
  end

  def handle_event("select_org", %{"org_id" => org_id}, socket) do
    case Accounts.select_org(socket.assigns.current_user, org_id) do
      {:ok, _user} ->
        {:noreply, redirect(socket, to: ~p"/")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to select organization")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        Select Organization
        <:subtitle>Choose which organization to work in</:subtitle>
      </.header>

      <div class="mt-8 space-y-4">
        <%= for org <- @orgs do %>
          <div class="border rounded-lg p-4 hover:bg-gray-50 cursor-pointer"
               phx-click="select_org" phx-value-org_id={org.id}>
            <h3 class="text-lg font-semibold">{org.name}</h3>
            <p class="text-sm text-gray-600">{org.slug}</p>
          </div>
        <% end %>
      </div>

      <div class="mt-8">
        <.link navigate={~p"/orgs/new"} class="text-blue-600 hover:underline">
          Create new organization
        </.link>
      </div>
    </div>
    """
  end
end
```

### 4. Create Org Form LiveView

**File**: `lib/pop_stash_web/live/org_form_live.ex`

```elixir
defmodule PopStashWeb.OrgFormLive do
  use PopStashWeb, :live_view

  alias PopStash.Accounts
  alias PopStash.Organizations

  def mount(_params, _session, socket) do
    form = to_form(%{"name" => ""}, as: "org")

    socket =
      socket
      |> assign(:page_title, "Create Organization")
      |> assign(:form, form)

    {:ok, socket}
  end

  def handle_event("save", %{"org" => %{"name" => name}}, socket) do
    user = socket.assigns.current_user

    case Organizations.create(name, user.id) do
      {:ok, org} ->
        # Select the new org
        {:ok, _user} = Accounts.select_org(user, org.id)

        {:noreply, redirect(socket, to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header>
        Create Organization
        <:subtitle>Set up a new workspace for your team</:subtitle>
      </.header>

      <.simple_form for={@form} id="org_form" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Organization Name" required />
        <:actions>
          <.button phx-disable-with="Creating..." class="w-full">
            Create Organization
          </.button>
        </:actions>
      </.simple_form>

      <div class="mt-4">
        <.link navigate={~p"/orgs/select"} class="text-sm text-gray-600 hover:underline">
          Back to organization selection
        </.link>
      </div>
    </div>
    """
  end
end
```

## Verification

```bash
# Start server
mix phx.server

# Test flow:
# 1. Visit http://localhost:4000
# 2. Should redirect to /users/log-in
# 3. Enter email, receive magic link
# 4. Click link, should redirect to /orgs/select
# 5. Create or select org
# 6. Should redirect to dashboard (/)
# 7. Verify dashboard loads with current_scope
```

## Tests

**File**: `test/pop_stash_web/plugs/org_plug_test.exs`

```elixir
defmodule PopStashWeb.OrgPlugTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest

  test "redirects to org selection if no org selected", %{conn: conn} do
    user = insert(:user, selected_org_id: nil)
    conn = log_in_user(conn, user)

    {:error, {:redirect, %{to: path}}} = live(conn, ~p"/")
    assert path == "/orgs/select"
  end

  test "allows access when org selected", %{conn: conn} do
    org = insert(:organization)
    user = insert(:user, selected_org_id: org.id)
    insert(:org_member, org_id: org.id, user_id: user.id)

    conn = log_in_user(conn, user)

    {:ok, _view, _html} = live(conn, ~p"/")
  end
end
```

## Dependencies
- Step 2 completed (authentication working)
- Step 3 completed (Scope, Organizations exist)

## Next Step
Step 6 will update all dashboard LiveViews to use scoped context calls and current_scope.
