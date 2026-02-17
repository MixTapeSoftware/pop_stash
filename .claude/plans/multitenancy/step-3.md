# Step 3: Core Access Control & Repo Enforcement

## Overview
Create the Scope module, Organizations context, and Memberships context. Add `Repo.transact` helper and `prepare_query` callback for automatic org_id enforcement on all queries.

## Context
These are the access control primitives that will be used throughout the application to enforce org-level isolation. The `prepare_query` callback is the critical safety net — it makes it impossible to accidentally query content without org_id scoping.

## Implementation

### 1. Create Scope Module

**File**: `lib/pop_stash/scope.ex`

```elixir
defmodule PopStash.Scope do
  @moduledoc """
  Provides organization-scoped access control utilities.

  Used throughout the application to ensure users can only access
  data within their selected organization.
  """

  alias PopStash.Accounts.User
  alias PopStash.Repo

  defstruct [:org_id, :user_id, :role]

  @type t :: %__MODULE__{
    org_id: binary() | nil,
    user_id: binary() | nil,
    role: :owner | :member | nil
  }

  @doc """
  Builds a scope from a user with their selected organization.
  Returns {:ok, scope} or {:error, reason}.

  Uses a single indexed query instead of preloading all memberships (N+1 fix).
  """
  def from_user(%User{selected_org_id: nil}), do: {:error, :no_org_selected}

  def from_user(%User{selected_org_id: org_id, id: user_id}) when not is_nil(org_id) do
    alias PopStash.Organizations.OrgMember

    case Repo.get_by(OrgMember, org_id: org_id, user_id: user_id) do
      nil -> {:error, :not_org_member}
      om ->
        {:ok, %__MODULE__{
          org_id: org_id,
          user_id: user_id,
          role: String.to_existing_atom(om.role)
        }}
    end
  end

  @doc """
  Checks if the scope has owner privileges.
  """
  def owner?(%__MODULE__{role: :owner}), do: true
  def owner?(_), do: false

  @doc """
  Validates that a record belongs to the scoped organization.
  """
  def validate_org_access(%__MODULE__{org_id: org_id}, %{org_id: record_org_id}) do
    if org_id == record_org_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  def validate_org_access(_, _), do: {:error, :invalid_scope}
end
```

### 2. Create Organization Schema

**File**: `lib/pop_stash/organizations/organization.ex`

```elixir
defmodule PopStash.Organizations.Organization do
  @moduledoc """
  Schema for organizations, the top-level tenant boundary.

  Organizations contain projects, users, and all associated data.
  """

  use PopStash.Schema
  import Ecto.Changeset

  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.SearchLog
  alias PopStash.Organizations.OrgMember
  alias PopStash.Projects.Project

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}

    has_many :projects, Project
    has_many :insights, Insight
    has_many :decisions, Decision
    has_many :search_logs, SearchLog
    has_many :org_members, OrgMember
    has_many :users, through: [:org_members, :user]

    timestamps()
  end

  # NOTE: Changesets moved to Organizations context per project guidelines
  # See lib/pop_stash/organizations.ex for create_changeset/2 and update_changeset/2

  def generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 100)
  end
end
```

### 3. Create OrgMember Schema

**File**: `lib/pop_stash/organizations/org_member.ex`

```elixir
defmodule PopStash.Organizations.OrgMember do
  @moduledoc """
  Join table between users and organizations with role information.

  Roles:
  - :owner - Full control, can manage members and delete org
  - :member - Can access and modify org data
  """

  use PopStash.Schema
  import Ecto.Changeset

  alias PopStash.Accounts.User
  alias PopStash.Organizations.Organization

  @roles ~w(owner member)

  schema "org_members" do
    field :role, :string, default: "member"

    belongs_to :organization, Organization
    belongs_to :user, User

    timestamps()
  end

  # NOTE: Changeset moved to Memberships context per project guidelines
  # See lib/pop_stash/memberships.ex for member_changeset/2

  def roles, do: @roles
end
```

### 4. Create Organizations Context

**File**: `lib/pop_stash/organizations.ex`

The `organizations` table is in `@skip_org_id_tables` so `prepare_query` automatically
skips org_id enforcement for all queries against this table.

```elixir
defmodule PopStash.Organizations do
  @moduledoc """
  Context for managing organizations.
  """

  import Ecto.Query

  alias PopStash.Memberships
  alias PopStash.Organizations.Organization
  alias PopStash.Repo

  ## Changesets (per project guidelines: changesets in context, not schema)

  defp create_changeset(organization, attrs) do
    organization
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :settings])
    |> Ecto.Changeset.validate_required([:name, :slug])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 255)
    |> Ecto.Changeset.validate_length(:slug, min: 1, max: 100)
    |> Ecto.Changeset.validate_format(:slug, ~r/^[a-z0-9-]+$/,
         message: "must contain only lowercase letters, numbers, and hyphens")
    |> Ecto.Changeset.unique_constraint(:slug)
  end

  defp update_changeset(organization, attrs) do
    organization
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :settings])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 255)
    |> Ecto.Changeset.validate_length(:slug, min: 1, max: 100)
    |> Ecto.Changeset.validate_format(:slug, ~r/^[a-z0-9-]+$/,
         message: "must contain only lowercase letters, numbers, and hyphens")
    |> Ecto.Changeset.unique_constraint(:slug)
  end

  @doc """
  Creates an organization and adds the creator as owner.
  """
  def create(name, creator_user_id, opts \\ []) do
    slug = Keyword.get(opts, :slug) || Organization.generate_slug(name)

    Repo.transact(fn ->
      with {:ok, org} <-
             %Organization{}
             |> create_changeset(%{name: name, slug: slug})
             |> Repo.insert(),
           {:ok, _member} <- Memberships.add_member(org.id, creator_user_id, "owner") do
        {:ok, org}
      end
    end)
  end

  @doc """
  Gets an organization by ID.
  """
  def get(id) do
    case Repo.get(Organization, id) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Gets an organization by slug.
  """
  def get_by_slug(slug) do
    case Repo.get_by(Organization, slug: slug) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Lists all organizations a user belongs to.
  """
  def list_for_user(user_id) do
    Organization
    |> join(:inner, [o], om in assoc(o, :org_members))
    |> where([o, om], om.user_id == ^user_id)
    |> preload([o, om], org_members: om)
    |> order_by([o], o.name)
    |> Repo.all()
  end

  @doc """
  Updates organization details.
  """
  def update(org_id, attrs) do
    case get(org_id) do
      {:ok, org} ->
        org
        |> update_changeset(attrs)
        |> Repo.update()

      error -> error
    end
  end

  @doc """
  Deletes an organization (owner only).
  """
  def delete(org_id) do
    case get(org_id) do
      {:ok, org} -> Repo.delete(org)
      error -> error
    end
  end
end
```

### 5. Create Memberships Context

**File**: `lib/pop_stash/memberships.ex`

The `org_members` table is in `@skip_org_id_tables` so `prepare_query` automatically
skips org_id enforcement for all queries against this table.

```elixir
defmodule PopStash.Memberships do
  @moduledoc """
  Context for managing organization memberships and roles.
  """

  import Ecto.Query

  alias PopStash.Accounts.User
  alias PopStash.Organizations.OrgMember
  alias PopStash.Organizations.Organization
  alias PopStash.Repo
  alias PopStash.Scope

  ## Changesets (per project guidelines: changesets in context, not schema)

  defp member_changeset(org_member, attrs) do
    org_member
    |> Ecto.Changeset.cast(attrs, [:role, :org_id, :user_id])
    |> Ecto.Changeset.validate_required([:role, :org_id, :user_id])
    |> Ecto.Changeset.validate_inclusion(:role, OrgMember.roles())
    |> Ecto.Changeset.foreign_key_constraint(:org_id)
    |> Ecto.Changeset.foreign_key_constraint(:user_id)
    |> Ecto.Changeset.unique_constraint([:org_id, :user_id])
  end

  @doc """
  Adds a user to an organization with the specified role.
  """
  def add_member(org_id, user_id, role \\ "member") do
    %OrgMember{}
    |> member_changeset(%{
      org_id: org_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Removes a user from an organization.
  Only owners can remove members.
  Prevents removing the last owner.
  """
  def remove_member(%Scope{} = scope, user_id) do
    unless Scope.owner?(scope) do
      {:error, :unauthorized}
    else
      owner_count =
        OrgMember
        |> where([om], om.org_id == ^scope.org_id and om.role == "owner")
        |> Repo.aggregate(:count)

      target_member =
        OrgMember
        |> where([om], om.org_id == ^scope.org_id and om.user_id == ^user_id)
        |> Repo.one()

      case target_member do
        nil ->
          {:error, :not_found}

        %{role: "owner"} when owner_count == 1 ->
          {:error, :cannot_remove_last_owner}

        member ->
          case Repo.delete(member) do
            {:ok, _} -> :ok
            error -> error
          end
      end
    end
  end

  @doc """
  Updates a member's role.
  Only owners can change roles.
  """
  def update_member_role(%Scope{} = scope, user_id, new_role) do
    if Scope.owner?(scope) do
      org_member =
        OrgMember
        |> where([om], om.org_id == ^scope.org_id and om.user_id == ^user_id)
        |> Repo.one()

      case org_member do
        nil ->
          {:error, :not_found}

        om ->
          om
          |> Ecto.Changeset.change(role: new_role)
          |> Repo.update()
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Lists all members of an organization.
  """
  def list_members(org_id) do
    OrgMember
    |> where([om], om.org_id == ^org_id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Checks if a user has a specific role in an organization.
  """
  def has_role?(org_id, user_id, required_role) do
    OrgMember
    |> where([om], om.org_id == ^org_id and om.user_id == ^user_id)
    |> select([om], om.role)
    |> Repo.one()
    |> case do
      nil -> false
      role -> role == to_string(required_role)
    end
  end

  @doc """
  Gets a user's role in an organization.
  """
  def get_role(org_id, user_id) do
    OrgMember
    |> where([om], om.org_id == ^org_id and om.user_id == ^user_id)
    |> select([om], om.role)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_member}
      role -> {:ok, String.to_existing_atom(role)}
    end
  end
end
```

### 6. Update Repo with prepare_query, transact, and org_id helpers

**File**: `lib/pop_stash/repo.ex`

This is the core enforcement mechanism. Every query that touches a table with `org_id`
will be automatically scoped. Tables without `org_id` are listed in `@skip_org_id_tables`
and are automatically excluded — no need to pass `skip_org_id: true` on every call.

```elixir
defmodule PopStash.Repo do
  use Ecto.Repo,
    otp_app: :pop_stash,
    adapter: Ecto.Adapters.Postgres

  require Ecto.Query

  @tenant_key {__MODULE__, :org_id}

  # Tables that don't have org_id — automatically skipped by prepare_query
  @skip_org_id_tables ~w(organizations users users_tokens org_members)

  @doc """
  Stores the current org_id in the process dictionary.
  Call once per request (in OrgPlug or MCP controller).
  """
  def put_org_id(org_id) do
    Process.put(@tenant_key, org_id)
  end

  @doc """
  Gets the current org_id from the process dictionary.
  """
  def get_org_id do
    Process.get(@tenant_key)
  end

  @doc """
  Automatically injects org_id from process dictionary into all operations.
  """
  @impl true
  def default_options(_operation) do
    [org_id: get_org_id()]
  end

  @doc """
  Enforces org_id scoping on all queries.

  - Tables in `@skip_org_id_tables` are automatically excluded
  - If `skip_org_id: true` is passed, the query runs unscoped (escape hatch)
  - If `org_id` is set, adds `WHERE org_id = ?` to the query
  - If neither is set, raises to prevent accidental data leaks

  Ecto internal operations (schema_migrations, preloads) are automatically skipped.
  """
  @impl true
  def prepare_query(_operation, query, opts) do
    cond do
      opts[:skip_org_id] || opts[:schema_migration] || skip_table?(query) ->
        {query, opts}

      org_id = opts[:org_id] ->
        {Ecto.Query.where(query, org_id: ^org_id), opts}

      true ->
        raise "expected org_id or skip_org_id to be set"
    end
  end

  defp skip_table?(%{from: %{source: {table, _}}}) when table in @skip_org_id_tables, do: true
  defp skip_table?(_), do: false

  @doc """
  Runs a transaction with automatic error handling.

  The function should return {:ok, result} or {:error, reason}.
  """
  def transact(fun) when is_function(fun, 0) do
    transaction(fn ->
      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> rollback(reason)
      end
    end)
  end
end
```

**Important**: The `prepare_query` callback intercepts these Ecto operations:
- `Repo.all/2`
- `Repo.one/2`
- `Repo.get/3`
- `Repo.get_by/3`
- `Repo.aggregate/3`

It does NOT intercept `Repo.insert/2`, `Repo.update/2`, or `Repo.delete/2` — those
are write operations where the org_id is set explicitly on the struct/changeset.

### 7. Accounts Context — No Changes Needed

**File**: `lib/pop_stash/accounts.ex`

The Accounts context queries the `users` and `users_tokens` tables. Both are in
`@skip_org_id_tables`, so `prepare_query` automatically skips them. No changes
needed to the generated `phx.gen.auth` code for org_id handling.

## Verification

```bash
# Test in IEx
iex -S mix

# Without org_id set, querying a content table should raise
PopStash.Repo.all(PopStash.Projects.Project)
# ** (RuntimeError) expected org_id or skip_org_id to be set

# Set org_id
PopStash.Repo.put_org_id(org.id)

# Now queries work and are automatically scoped
PopStash.Repo.all(PopStash.Projects.Project)
# Returns only projects for org.id

# Excluded tables work without org_id
PopStash.Repo.all(PopStash.Organizations.Organization)
# Returns all organizations
```

## Tests

**File**: `test/pop_stash/repo_test.exs`

```elixir
defmodule PopStash.RepoTest do
  use PopStash.DataCase

  alias PopStash.Projects.Project
  alias PopStash.Repo

  describe "prepare_query org_id enforcement" do
    test "raises when no org_id is set" do
      Repo.put_org_id(nil)

      assert_raise RuntimeError, ~r/expected org_id or skip_org_id/, fn ->
        Repo.all(Project)
      end
    end

    test "automatically scopes queries when org_id is set" do
      org1 = insert(:organization)
      org2 = insert(:organization)
      insert(:project, org_id: org1.id, name: "Org1 Project")
      insert(:project, org_id: org2.id, name: "Org2 Project")

      Repo.put_org_id(org1.id)
      projects = Repo.all(Project)

      assert length(projects) == 1
      assert hd(projects).name == "Org1 Project"
    end

    test "skip_org_id bypasses enforcement" do
      insert(:organization, name: "Test Org")

      Repo.put_org_id(nil)
      orgs = Repo.all(PopStash.Organizations.Organization)

      assert length(orgs) >= 1
    end
  end
end
```

**File**: `test/pop_stash/organizations_test.exs`

```elixir
defmodule PopStash.OrganizationsTest do
  use PopStash.DataCase

  alias PopStash.Memberships
  alias PopStash.Organizations

  describe "create/3" do
    test "creates org and adds creator as owner" do
      user = insert(:user)

      assert {:ok, org} = Organizations.create("Test Org", user.id)
      assert org.name == "Test Org"
      assert org.slug == "test-org"

      assert Memberships.has_role?(org.id, user.id, :owner)
    end
  end
end
```

## Dependencies
- Step 0 completed (tables exist)
- Step 1 completed (org_id columns exist)

## Next Step
Step 4 will update existing contexts (Projects, Memory, Activity) to accept Scope parameters.
With `prepare_query` in place, reads are automatically scoped — contexts primarily need
Scope for write operations and authorization logic.

## Notes
- **Scope.from_user optimized**: Uses single indexed query instead of N+1 preload
- **Changesets in contexts**: Moved from schema files per project guidelines
- **remove_member enhanced**: Checks deletion success and prevents removing last owner
- **Organizations slug generation**: Remains in schema for reusability across contexts
- **prepare_query**: Enforces org_id at Repo level — impossible to forget scoping
- **@skip_org_id_tables**: organizations, users, users_tokens, org_members are auto-skipped by table name — no `skip_org_id: true` needed
- **skip_org_id: true**: Still available as an escape hatch for edge cases (e.g., ad-hoc queries, raw Ecto.Query without a schema)
- **Write operations**: Not intercepted by prepare_query — org_id set on changeset/struct
- **Preloads**: Ecto handles preloads internally, they are automatically skipped
