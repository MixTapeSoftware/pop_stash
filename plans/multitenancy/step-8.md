# Step 8: Team Invitation Flow

## Objective

Implement invite-to-team by email. Org owners can invite users by email, invitations are sent via email with a magic link, recipients can accept to join the org. Includes a team management UI in the dashboard for viewing members and sending invitations.

## Prerequisites

- Step 2 completed (auth system, UserNotifier, Swoosh)
- Step 3 completed (Organizations, Memberships contexts)
- Step 5 completed (Router, OrgPlug, dashboard auth)

## Implementation

### 1. Create invitations table

**Migration**: `priv/repo/migrations/TIMESTAMP_create_invitations.exs`

```elixir
defmodule PopStash.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :token, :binary, null: false
      add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :role, :string, null: false, default: "member"
      add :accepted_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:invitations, [:org_id])
    create index(:invitations, [:email])
    create index(:invitations, [:token], unique: true)
    # Prevent duplicate pending invitations for same email+org
    create unique_index(:invitations, [:org_id, :email],
      where: "accepted_at IS NULL",
      name: :invitations_pending_org_email_index)
  end
end
```

Note: `invitations` should be added to `@skip_org_id_tables` in `Repo` since invitations are queried cross-org (e.g., when accepting by token).

### 2. Create Invitation schema

**File**: `/workspace/lib/pop_stash/organizations/invitation.ex`

```elixir
defmodule PopStash.Organizations.Invitation do
  use PopStash.Schema

  alias PopStash.Accounts.User
  alias PopStash.Organizations.Organization

  @token_validity_days 7

  schema "invitations" do
    field :email, :string
    field :token, :binary
    field :role, :string, default: "member"
    field :accepted_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    belongs_to :organization, Organization, foreign_key: :org_id
    belongs_to :invited_by, User, foreign_key: :invited_by_id

    timestamps()
  end

  def token_validity_days, do: @token_validity_days

  @doc "Generates a URL-safe random token and its hash."
  def build_token do
    raw_token = :crypto.strong_rand_bytes(32)
    encoded = Base.url_encode64(raw_token, padding: false)
    hashed = :crypto.hash(:sha256, raw_token)
    {encoded, hashed}
  end

  @doc "Hashes an encoded token for lookup."
  def hash_token(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, raw} -> {:ok, :crypto.hash(:sha256, raw)}
      :error -> :error
    end
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
```

### 3. Add invitation functions to Memberships context

**File**: `/workspace/lib/pop_stash/memberships.ex` -- add:

```elixir
alias PopStash.Accounts.User
alias PopStash.Organizations.Invitation

@doc """
Creates an invitation and sends the invite email.
Only owners can invite. Returns {:ok, invitation} or {:error, reason}.
"""
def invite_member(%Scope{role: :owner, org_id: org_id, user_id: inviter_id}, email, opts \\ []) do
  role = Keyword.get(opts, :role, "member")
  {encoded_token, hashed_token} = Invitation.build_token()
  expires_at = DateTime.add(DateTime.utc_now(), Invitation.token_validity_days() * 86400, :second)

  invitation_attrs = %{
    email: String.downcase(String.trim(email)),
    token: hashed_token,
    org_id: org_id,
    invited_by_id: inviter_id,
    role: role,
    expires_at: expires_at
  }

  case insert_invitation(invitation_attrs) do
    {:ok, invitation} ->
      invitation = Repo.preload(invitation, :organization)
      PopStash.Accounts.UserNotifier.deliver_team_invitation(
        email,
        invitation.organization.name,
        encoded_token
      )
      {:ok, invitation}

    {:error, changeset} ->
      {:error, changeset}
  end
end

def invite_member(%Scope{}, _email, _opts), do: {:error, :unauthorized}

@doc """
Accepts an invitation by token. Creates membership if user exists,
or creates user + membership if new. Returns {:ok, %{user: user, org: org}} or {:error, reason}.
"""
def accept_invitation(encoded_token) do
  with {:ok, hashed} <- Invitation.hash_token(encoded_token),
       %Invitation{} = invitation <- Repo.get_by(Invitation, token: hashed),
       false <- Invitation.expired?(invitation),
       nil <- invitation.accepted_at do
    invitation = Repo.preload(invitation, :organization)

    Repo.transact(fn ->
      # Find or create user
      user =
        case Repo.get_by(User, email: invitation.email) do
          nil ->
            # Create user (they'll need to use magic link to log in)
            {:ok, user} =
              %User{}
              |> Ecto.Changeset.change(%{email: invitation.email})
              |> Repo.insert()
            user

          existing_user ->
            existing_user
        end

      # Create membership (ignore if already exists)
      case add_member(invitation.org_id, user.id, invitation.role) do
        {:ok, _member} -> :ok
        {:error, %Ecto.Changeset{errors: [{:org_id, _} | _]}} -> :ok  # already a member
        {:error, reason} -> {:error, reason}
      end

      # Mark invitation as accepted
      invitation
      |> Ecto.Changeset.change(accepted_at: DateTime.utc_now())
      |> Repo.update!()

      {:ok, %{user: user, org: invitation.organization}}
    end)
  else
    nil -> {:error, :invitation_not_found}
    true -> {:error, :invitation_expired}
    %DateTime{} -> {:error, :invitation_already_accepted}
    :error -> {:error, :invalid_token}
    error -> error
  end
end

@doc "Lists pending (not accepted, not expired) invitations for an org."
def list_pending_invitations(org_id) do
  now = DateTime.utc_now()

  Invitation
  |> where([i], i.org_id == ^org_id)
  |> where([i], is_nil(i.accepted_at))
  |> where([i], i.expires_at > ^now)
  |> order_by([i], desc: i.inserted_at)
  |> preload(:invited_by)
  |> Repo.all()
end

@doc "Cancels a pending invitation. Only owners can cancel."
def cancel_invitation(%Scope{role: :owner, org_id: org_id}, invitation_id) do
  case Repo.get_by(Invitation, id: invitation_id, org_id: org_id) do
    nil -> {:error, :not_found}
    invitation -> Repo.delete(invitation)
  end
end

def cancel_invitation(%Scope{}, _invitation_id), do: {:error, :unauthorized}

## Private

defp invitation_changeset(invitation, attrs) do
  invitation
  |> Ecto.Changeset.cast(attrs, [:email, :token, :org_id, :invited_by_id, :role, :expires_at])
  |> Ecto.Changeset.validate_required([:email, :token, :org_id, :role, :expires_at])
  |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
  |> Ecto.Changeset.validate_inclusion(:role, OrgMember.roles())
  |> Ecto.Changeset.unique_constraint([:org_id, :email], name: :invitations_pending_org_email_index,
       message: "has already been invited")
end

defp insert_invitation(attrs) do
  %Invitation{}
  |> invitation_changeset(attrs)
  |> Repo.insert()
end
```

### 4. Add invitation email to UserNotifier

**File**: `/workspace/lib/pop_stash/accounts/user_notifier.ex` -- add:

```elixir
def deliver_team_invitation(email, org_name, token) do
  deliver(email, "You've been invited to #{org_name} on PopStash", """
  Hi,

  You've been invited to join the "#{org_name}" team on PopStash.

  Click the link below to accept the invitation:

  #{PopStashWeb.Endpoint.url()}/invitations/#{token}

  This invitation expires in 7 days.

  If you didn't expect this, you can safely ignore this email.
  """)
end
```

### 5. Create Accept Invitation LiveView

**File**: `/workspace/lib/pop_stash_web/live/accept_invitation_live.ex`

```elixir
defmodule PopStashWeb.AcceptInvitationLive do
  use PopStashWeb, :live_view

  alias PopStash.Memberships

  def mount(%{"token" => token}, _session, socket) do
    case Memberships.accept_invitation(token) do
      {:ok, %{user: _user, org: org}} ->
        {:ok,
         socket
         |> put_flash(:info, "Welcome to #{org.name}! Sign in to get started.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :invitation_expired} ->
        {:ok,
         socket
         |> put_flash(:error, "This invitation has expired. Please ask for a new one.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :invitation_already_accepted} ->
        {:ok,
         socket
         |> put_flash(:info, "This invitation has already been accepted. Sign in to continue.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid or expired invitation link.")
         |> redirect(to: ~p"/users/log-in")}
    end
  end
end
```

### 6. Add invitation route

**File**: `/workspace/lib/pop_stash_web/router.ex` -- add to public routes:

```elixir
# In the unauthenticated scope (or a new scope without auth requirement)
scope "/", PopStashWeb do
  pipe_through [:browser]

  live_session :public,
    on_mount: [] do
    live "/invitations/:token", AcceptInvitationLive, :accept
  end
end
```

### 7. Create Team Management LiveView

**File**: `/workspace/lib/pop_stash_web/dashboard/live/team_live/index.ex`

Dashboard page showing current members and pending invitations. Owners see invite form and can remove members/cancel invitations.

```elixir
defmodule PopStashWeb.Dashboard.TeamLive.Index do
  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memberships

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns.current_org
    members = Memberships.list_members(org.id)
    pending = Memberships.list_pending_invitations(org.id)

    {:ok,
     socket
     |> assign(:page_title, "Team")
     |> assign(:current_path, "/team")
     |> assign(:members, members)
     |> assign(:pending_invitations, pending)
     |> assign(:invite_form, to_form(%{"email" => ""}, as: "invite"))}
  end

  def handle_event("send_invite", %{"invite" => %{"email" => email}}, socket) do
    scope = socket.assigns.current_scope

    case Memberships.invite_member(scope, email) do
      {:ok, _invitation} ->
        pending = Memberships.list_pending_invitations(socket.assigns.current_org.id)

        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{email}")
         |> assign(:pending_invitations, pending)
         |> assign(:invite_form, to_form(%{"email" => ""}, as: "invite"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, invite_form: to_form(changeset, as: "invite"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only owners can invite members")}
    end
  end

  def handle_event("remove_member", %{"user-id" => user_id}, socket) do
    scope = socket.assigns.current_scope

    case Memberships.remove_member(scope, user_id) do
      {:ok, _} ->
        members = Memberships.list_members(socket.assigns.current_org.id)
        {:noreply, assign(socket, members: members)}

      {:error, :cannot_remove_last_owner} ->
        {:noreply, put_flash(socket, :error, "Cannot remove the last owner")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove member")}
    end
  end

  def handle_event("cancel_invitation", %{"invitation-id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Memberships.cancel_invitation(scope, id) do
      {:ok, _} ->
        pending = Memberships.list_pending_invitations(socket.assigns.current_org.id)
        {:noreply, assign(socket, pending_invitations: pending)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel invitation")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-slate-900">Team</h1>
      </div>

      <%!-- Invite Form (owners only) --%>
      <%= if PopStash.Scope.owner?(@current_scope) do %>
        <div class="bg-white rounded-lg border border-slate-200 p-6">
          <h2 class="text-lg font-semibold text-slate-800 mb-4">Invite a team member</h2>
          <.simple_form for={@invite_form} id="invite-form" phx-submit="send_invite" class="flex gap-3 items-end">
            <div class="flex-1">
              <.input field={@invite_form[:email]} type="email" label="Email address" placeholder="colleague@example.com" required />
            </div>
            <.button phx-disable-with="Sending...">Send Invite</.button>
          </.simple_form>
        </div>
      <% end %>

      <%!-- Current Members --%>
      <div class="bg-white rounded-lg border border-slate-200">
        <div class="px-6 py-4 border-b border-slate-200">
          <h2 class="text-lg font-semibold text-slate-800">Members ({length(@members)})</h2>
        </div>
        <div class="divide-y divide-slate-100">
          <div :for={member <- @members} id={"member-#{member.id}"} class="px-6 py-4 flex items-center justify-between">
            <div>
              <p class="font-medium text-slate-900">{member.user.email}</p>
              <p class="text-sm text-slate-500 capitalize">{member.role}</p>
            </div>
            <%= if PopStash.Scope.owner?(@current_scope) and member.user_id != @current_scope.user_id do %>
              <button
                phx-click="remove_member"
                phx-value-user-id={member.user_id}
                data-confirm="Remove this member from the team?"
                class="text-sm text-red-600 hover:text-red-800"
              >
                Remove
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Pending Invitations --%>
      <%= if @pending_invitations != [] do %>
        <div class="bg-white rounded-lg border border-slate-200">
          <div class="px-6 py-4 border-b border-slate-200">
            <h2 class="text-lg font-semibold text-slate-800">Pending Invitations</h2>
          </div>
          <div class="divide-y divide-slate-100">
            <div :for={inv <- @pending_invitations} id={"invitation-#{inv.id}"} class="px-6 py-4 flex items-center justify-between">
              <div>
                <p class="font-medium text-slate-900">{inv.email}</p>
                <p class="text-sm text-slate-500">
                  Invited {Calendar.strftime(inv.inserted_at, "%b %d, %Y")}
                  · Expires {Calendar.strftime(inv.expires_at, "%b %d, %Y")}
                </p>
              </div>
              <%= if PopStash.Scope.owner?(@current_scope) do %>
                <button
                  phx-click="cancel_invitation"
                  phx-value-invitation-id={inv.id}
                  class="text-sm text-slate-500 hover:text-red-600"
                >
                  Cancel
                </button>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
```

### 8. Add Team route to Dashboard

**File**: `/workspace/lib/pop_stash_web/dashboard/router.ex` -- add inside the live_session:

```elixir
live "/team", TeamLive.Index, :index
```

Also add a "Team" nav link to the dashboard sidebar.

### 9. Update Repo skip tables

**File**: `/workspace/lib/pop_stash/repo.ex` -- add `invitations` to skip list:

```elixir
@skip_org_id_tables ~w(organizations users users_tokens org_members invitations schema_migrations)
```

## Verification

```bash
mix phx.server

# Invitation flow:
# 1. Login as org owner
# 2. Navigate to /team
# 3. Enter colleague's email, send invite
# 4. Check /dev/mailbox for invitation email
# 5. Click invitation link (in incognito/different browser)
# 6. Verify redirect to login page with success flash
# 7. Login as the invited user
# 8. Verify they can see the org and its data

# Edge cases:
# 1. Invite existing user -- should just add membership
# 2. Invite new email -- should create user + membership
# 3. Duplicate invite -- should show error
# 4. Expired invite -- should show error
# 5. Non-owner tries to invite -- should show unauthorized error
# 6. Cancel invitation -- should remove from pending list
# 7. Remove member -- should remove from members list
# 8. Cannot remove last owner -- should show error
```

## Tests

**File**: `test/pop_stash/memberships/invitation_test.exs`

```elixir
defmodule PopStash.Memberships.InvitationTest do
  use PopStash.DataCase

  alias PopStash.Memberships
  alias PopStash.Scope

  setup do
    %{org: org, user: owner, scope: scope} = setup_org_context()
    %{org: org, owner: owner, scope: scope}
  end

  describe "invite_member/3" do
    test "creates invitation and returns it", %{scope: scope} do
      assert {:ok, invitation} = Memberships.invite_member(scope, "new@example.com")
      assert invitation.email == "new@example.com"
      assert invitation.role == "member"
      assert invitation.org_id == scope.org_id
      refute is_nil(invitation.expires_at)
    end

    test "normalizes email to lowercase", %{scope: scope} do
      assert {:ok, invitation} = Memberships.invite_member(scope, " UPPER@Example.COM ")
      assert invitation.email == "upper@example.com"
    end

    test "prevents duplicate pending invitations", %{scope: scope} do
      {:ok, _} = Memberships.invite_member(scope, "dupe@example.com")
      assert {:error, changeset} = Memberships.invite_member(scope, "dupe@example.com")
      assert %{org_id: ["has already been invited"]} = errors_on(changeset)
    end

    test "non-owner cannot invite", %{org: org} do
      member = user_fixture()
      org_member_fixture(org, member, "member")
      member_scope = %Scope{org_id: org.id, user_id: member.id, role: :member}

      assert {:error, :unauthorized} = Memberships.invite_member(member_scope, "test@example.com")
    end
  end

  describe "accept_invitation/1" do
    test "creates user and membership for new email", %{scope: scope, org: org} do
      {:ok, invitation} = Memberships.invite_member(scope, "brand-new@example.com")

      # We need the encoded token, which was passed to notifier
      # For test, build token directly
      {encoded, hashed} = PopStash.Organizations.Invitation.build_token()
      Repo.update_all(
        from(i in "invitations", where: i.id == ^invitation.id),
        set: [token: hashed]
      )

      assert {:ok, %{user: user, org: accepted_org}} = Memberships.accept_invitation(encoded)
      assert user.email == "brand-new@example.com"
      assert accepted_org.id == org.id
      assert Memberships.has_role?(org.id, user.id, :member)
    end

    test "adds existing user to org", %{scope: scope, org: org} do
      existing = user_fixture(%{email: "existing@example.com"})

      {encoded, hashed} = PopStash.Organizations.Invitation.build_token()
      {:ok, invitation} = Memberships.invite_member(scope, "existing@example.com")
      Repo.update_all(
        from(i in "invitations", where: i.id == ^invitation.id),
        set: [token: hashed]
      )

      assert {:ok, %{user: user, org: _}} = Memberships.accept_invitation(encoded)
      assert user.id == existing.id
      assert Memberships.has_role?(org.id, existing.id, :member)
    end

    test "returns error for expired invitation", %{scope: scope} do
      {encoded, hashed} = PopStash.Organizations.Invitation.build_token()
      {:ok, invitation} = Memberships.invite_member(scope, "expired@example.com")
      expired = DateTime.add(DateTime.utc_now(), -1, :day)
      Repo.update_all(
        from(i in "invitations", where: i.id == ^invitation.id),
        set: [token: hashed, expires_at: expired]
      )

      assert {:error, :invitation_expired} = Memberships.accept_invitation(encoded)
    end

    test "returns error for already accepted invitation", %{scope: scope} do
      {encoded, hashed} = PopStash.Organizations.Invitation.build_token()
      {:ok, invitation} = Memberships.invite_member(scope, "accepted@example.com")
      Repo.update_all(
        from(i in "invitations", where: i.id == ^invitation.id),
        set: [token: hashed, accepted_at: DateTime.utc_now()]
      )

      assert {:error, :invitation_already_accepted} = Memberships.accept_invitation(encoded)
    end

    test "returns error for invalid token" do
      assert {:error, :invalid_token} = Memberships.accept_invitation("bogus-token")
    end
  end

  describe "cancel_invitation/2" do
    test "owner can cancel pending invitation", %{scope: scope} do
      {:ok, invitation} = Memberships.invite_member(scope, "cancel-me@example.com")
      assert {:ok, _} = Memberships.cancel_invitation(scope, invitation.id)
      assert Memberships.list_pending_invitations(scope.org_id) == []
    end

    test "non-owner cannot cancel invitation", %{org: org} do
      member = user_fixture()
      org_member_fixture(org, member, "member")
      member_scope = %Scope{org_id: org.id, user_id: member.id, role: :member}

      assert {:error, :unauthorized} = Memberships.cancel_invitation(member_scope, Ecto.UUID.generate())
    end
  end

  describe "list_pending_invitations/1" do
    test "returns only pending non-expired invitations", %{scope: scope, org: org} do
      {:ok, _} = Memberships.invite_member(scope, "pending@example.com")
      pending = Memberships.list_pending_invitations(org.id)
      assert length(pending) == 1
      assert hd(pending).email == "pending@example.com"
    end
  end
end
```

**File**: `test/pop_stash_web/dashboard/team_live_test.exs`

```elixir
defmodule PopStashWeb.Dashboard.TeamLiveTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{user: user, org: org, scope: scope} = setup_org_context()
    Repo.update!(Ecto.Changeset.change(user, selected_org_id: org.id))
    conn = log_in_user(conn, user)

    {:ok, conn: conn, scope: scope, org: org, user: user}
  end

  test "renders team page with members", %{conn: conn, user: user} do
    {:ok, _view, html} = live(conn, ~p"/team")
    assert html =~ "Team"
    assert html =~ user.email
  end

  test "owner can send invitation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/team")

    html =
      view
      |> form("#invite-form", invite: %{email: "new-teammate@example.com"})
      |> render_submit()

    assert html =~ "Invitation sent"
    assert html =~ "new-teammate@example.com"
  end

  test "shows error for duplicate invitation", %{conn: conn, scope: scope} do
    PopStash.Memberships.invite_member(scope, "already-invited@example.com")

    {:ok, view, _html} = live(conn, ~p"/team")

    view
    |> form("#invite-form", invite: %{email: "already-invited@example.com"})
    |> render_submit()

    assert has_element?(view, "[role=alert]") or render(view) =~ "already been invited"
  end
end
```

## Dependencies

- Step 2 completed (auth system, UserNotifier for emails)
- Step 3 completed (Memberships.add_member, Organizations context)
- Step 5 completed (Dashboard router, OrgPlug, authenticated routes)

## Important Notes

- The invitation token uses the same pattern as UserToken (hash stored in DB, raw token in URL).
- Accepting an invitation does NOT automatically log the user in -- they get redirected to the login page. This avoids complexity around session management from unauthenticated context.
- If the invited email already has a user account, they just get the membership added. If it's a new email, a user is created (no password, they'll use magic link to log in).
- The `invitations` table is in `@skip_org_id_tables` because invitation acceptance happens in an unauthenticated context (no org_id in process dictionary).
- The unique partial index on `(org_id, email) WHERE accepted_at IS NULL` prevents re-inviting someone with a pending invitation, but allows re-inviting after acceptance.
