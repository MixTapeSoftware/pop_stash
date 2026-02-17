# Step 1: Repo Enforcement + Scope Struct

## Objective

Add `Repo.transact/1`, `Repo.prepare_query/3`, `Repo.put_org_id/1`, and `Repo.default_options/1` to enforce org_id scoping at the database layer. Create the `PopStash.Scope` struct. Create test fixtures factory for organizations and users.

This step makes it impossible to query content tables without org_id set -- the critical safety net for data isolation.

## Prerequisites

- Step 0 completed (all tables exist, org_id columns on content tables)

## Implementation

### 1. Update Repo

**File**: `/workspace/lib/pop_stash/repo.ex`

Replace the entire file:

```elixir
defmodule PopStash.Repo do
  use Ecto.Repo,
    otp_app: :pop_stash,
    adapter: Ecto.Adapters.Postgres

  require Ecto.Query

  @tenant_key {__MODULE__, :org_id}

  # Tables that do NOT have org_id -- automatically skipped by prepare_query.
  # No need to pass skip_org_id: true when querying these tables.
  @skip_org_id_tables ~w(organizations users users_tokens org_members schema_migrations)

  @doc """
  Stores the current org_id in the process dictionary.
  Call once per request/process (in OrgPlug on_mount or MCP controller).
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
  Automatically injects org_id from process dictionary into all Repo operations.
  This feeds into prepare_query via the opts.
  """
  @impl true
  def default_options(_operation) do
    case get_org_id() do
      nil -> []
      org_id -> [org_id: org_id]
    end
  end

  @doc """
  Enforces org_id scoping on all READ queries.

  Behavior:
  - Tables in @skip_org_id_tables are automatically excluded
  - If skip_org_id: true is passed, the query runs unscoped (escape hatch)
  - If org_id is set (via process dictionary -> default_options), adds WHERE org_id = ?
  - If none of the above, raises to prevent accidental data leaks

  Note: prepare_query only intercepts reads (all, one, get, get_by, aggregate, exists).
  It does NOT intercept writes (insert, update, delete) -- org_id must be set on the
  changeset/struct explicitly for writes.
  """
  @impl true
  def prepare_query(_operation, query, opts) do
    cond do
      opts[:skip_org_id] || opts[:schema_migration] || skip_table?(query) ->
        {query, opts}

      org_id = opts[:org_id] ->
        {Ecto.Query.where(query, org_id: ^org_id), opts}

      true ->
        raise "expected org_id or skip_org_id to be set -- " <>
                "call Repo.put_org_id/1 before querying content tables"
    end
  end

  defp skip_table?(%{from: %{source: {table, _}}}) when table in @skip_org_id_tables, do: true
  defp skip_table?(_), do: false

  @doc """
  Runs a function inside a transaction with automatic ok/error handling.

  The function must return {:ok, result} or {:error, reason}.
  On {:ok, result}, the transaction commits and returns {:ok, result}.
  On {:error, reason}, the transaction rolls back and returns {:error, reason}.
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

### 2. Create Scope struct

**File**: `/workspace/lib/pop_stash/scope.ex`

```elixir
defmodule PopStash.Scope do
  @moduledoc """
  Organization-scoped access control struct.

  Passed to context functions to provide org_id for writes and role for
  authorization checks. Reads are handled automatically by Repo.prepare_query.
  """

  defstruct [:org_id, :user_id, :role]

  @type t :: %__MODULE__{
    org_id: binary() | nil,
    user_id: binary() | nil,
    role: :owner | :member | nil
  }

  @doc """
  Builds a scope from a user with their selected organization.

  Queries the org_members table to verify membership and get the role.
  Returns {:ok, scope} or {:error, reason}.
  """
  def from_user(%{selected_org_id: nil}), do: {:error, :no_org_selected}

  def from_user(%{selected_org_id: org_id, id: user_id}) when not is_nil(org_id) do
    alias PopStash.Organizations.OrgMember
    alias PopStash.Repo

    case Repo.get_by(OrgMember, org_id: org_id, user_id: user_id) do
      nil ->
        {:error, :not_org_member}

      %OrgMember{role: role} ->
        {:ok, %__MODULE__{
          org_id: org_id,
          user_id: user_id,
          role: String.to_existing_atom(role)
        }}
    end
  end

  @doc "Returns true if the scope has owner role."
  def owner?(%__MODULE__{role: :owner}), do: true
  def owner?(_), do: false
end
```

### 3. Create test fixtures

**File**: `/workspace/test/support/fixtures/multitenancy_fixtures.ex`

```elixir
defmodule PopStash.MultitenancyFixtures do
  @moduledoc """
  Test fixtures for organizations, users, and memberships.
  """

  alias PopStash.Repo

  def organization_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        id: Ecto.UUID.generate(),
        name: "Test Org #{System.unique_integer([:positive])}",
        slug: "test-org-#{System.unique_integer([:positive])}",
        settings: %{},
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })

    {id, attrs} = Map.pop(attrs, :id)

    Repo.insert_all("organizations", [Map.put(attrs, :id, id)],
      returning: false,
      skip_org_id: true
    )

    Repo.get!(PopStash.Organizations.Organization, id)
  end

  def user_fixture(attrs \\ %{}) do
    id = Ecto.UUID.generate()

    attrs =
      Enum.into(attrs, %{
        id: id,
        email: "user#{System.unique_integer([:positive])}@example.com",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })

    Repo.insert_all("users", [attrs], returning: false, skip_org_id: true)
    Repo.get!(PopStash.Accounts.User, attrs.id)
  end

  def org_member_fixture(org, user, role \\ "member") do
    attrs = %{
      id: Ecto.UUID.generate(),
      org_id: org.id,
      user_id: user.id,
      role: role,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    Repo.insert_all("org_members", [attrs], returning: false, skip_org_id: true)
    Repo.get_by!(PopStash.Organizations.OrgMember, org_id: org.id, user_id: user.id)
  end

  @doc """
  Creates an org + user + owner membership and sets org_id in process dictionary.
  Useful as a one-liner setup in tests.
  """
  def setup_org_context(attrs \\ %{}) do
    org = organization_fixture(attrs)
    user = user_fixture(Map.get(attrs, :user_attrs, %{}))
    _member = org_member_fixture(org, user, "owner")

    scope = %PopStash.Scope{org_id: org.id, user_id: user.id, role: :owner}
    PopStash.Repo.put_org_id(org.id)

    %{org: org, user: user, scope: scope}
  end
end
```

### 4. Update DataCase to import fixtures and set org_id

**File**: `/workspace/test/support/data_case.ex`

Add to the `using` block:

```elixir
import PopStash.MultitenancyFixtures
```

### 5. Update existing tests to set org_id

Existing tests in `test/pop_stash/projects_test.exs` and `test/pop_stash/memory_test.exs` will fail because `prepare_query` now requires org_id. Update them to use `setup_org_context/0`.

**File**: `test/pop_stash/projects_test.exs` -- add setup block:

```elixir
setup do
  %{org: org} = setup_org_context()
  %{org: org}
end
```

The tests should work without further changes because `Repo.put_org_id/1` is called by `setup_org_context/0` and `prepare_query` will auto-scope reads. However, `Projects.create/2` needs to set `org_id` on the changeset -- that change happens in Step 4. For now, tests that call `Projects.create` will need the `org_id` added to the changeset manually or the create function updated.

**Decision**: To keep tests passing between steps, update `Projects.create/2` to also accept and pass through `org_id` from opts in this step (a small forward-compatible change). The full Scope-based API comes in Step 4.

## Verification

```bash
# Compile
mix compile --warnings-as-errors

# Test in IEx
iex -S mix

# Without org_id set, querying content table raises
PopStash.Repo.all(PopStash.Projects.Project)
# ** (RuntimeError) expected org_id or skip_org_id to be set

# Set org_id
org = PopStash.Repo.one(PopStash.Organizations.Organization)
PopStash.Repo.put_org_id(org.id)

# Now content queries work
PopStash.Repo.all(PopStash.Projects.Project)
# Returns only projects for that org

# Excluded tables work without org_id
PopStash.Repo.put_org_id(nil)
PopStash.Repo.all(PopStash.Organizations.Organization)
# Works fine
```

## Tests

**File**: `test/pop_stash/repo_test.exs`

```elixir
defmodule PopStash.RepoTest do
  use PopStash.DataCase

  alias PopStash.Organizations.Organization
  alias PopStash.Projects.Project
  alias PopStash.Repo

  describe "prepare_query/3" do
    test "raises when no org_id is set for content tables" do
      Repo.put_org_id(nil)

      assert_raise RuntimeError, ~r/expected org_id or skip_org_id/, fn ->
        Repo.all(Project)
      end
    end

    test "automatically scopes queries when org_id is set" do
      %{org: org1} = setup_org_context()
      org2 = organization_fixture(%{name: "Other Org", slug: "other-org"})

      # Insert projects directly to bypass context logic
      Repo.insert_all("projects", [
        %{id: Ecto.UUID.generate(), name: "Org1 Project", org_id: org1.id,
          tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ], skip_org_id: true)

      Repo.insert_all("projects", [
        %{id: Ecto.UUID.generate(), name: "Org2 Project", org_id: org2.id,
          tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ], skip_org_id: true)

      Repo.put_org_id(org1.id)
      projects = Repo.all(Project)

      assert length(projects) == 1
      assert hd(projects).name == "Org1 Project"
    end

    test "skip_org_id_tables are automatically excluded" do
      Repo.put_org_id(nil)

      # Should not raise -- organizations is in skip list
      orgs = Repo.all(Organization)
      assert is_list(orgs)
    end

    test "skip_org_id: true bypasses enforcement" do
      Repo.put_org_id(nil)

      # Should not raise with explicit skip
      projects = Repo.all(Project, skip_org_id: true)
      assert is_list(projects)
    end
  end

  describe "transact/1" do
    test "commits on {:ok, result}" do
      assert {:ok, :success} = Repo.transact(fn -> {:ok, :success} end)
    end

    test "rolls back on {:error, reason}" do
      assert {:error, :failure} = Repo.transact(fn -> {:error, :failure} end)
    end
  end

  describe "put_org_id/1 and get_org_id/0" do
    test "stores and retrieves org_id from process dictionary" do
      id = Ecto.UUID.generate()
      Repo.put_org_id(id)
      assert Repo.get_org_id() == id
    end

    test "returns nil when not set" do
      Repo.put_org_id(nil)
      assert Repo.get_org_id() == nil
    end
  end
end
```

**File**: `test/pop_stash/scope_test.exs`

```elixir
defmodule PopStash.ScopeTest do
  use PopStash.DataCase

  alias PopStash.Scope

  describe "from_user/1" do
    test "returns scope when user has selected org and is a member" do
      org = organization_fixture()
      user = user_fixture(%{selected_org_id: org.id})
      _member = org_member_fixture(org, user, "owner")

      assert {:ok, scope} = Scope.from_user(user)
      assert scope.org_id == org.id
      assert scope.user_id == user.id
      assert scope.role == :owner
    end

    test "returns error when user has no selected org" do
      user = user_fixture(%{selected_org_id: nil})
      assert {:error, :no_org_selected} = Scope.from_user(user)
    end

    test "returns error when user is not a member of selected org" do
      org = organization_fixture()
      user = user_fixture(%{selected_org_id: org.id})
      # No membership created

      assert {:error, :not_org_member} = Scope.from_user(user)
    end
  end

  describe "owner?/1" do
    test "returns true for owner role" do
      assert Scope.owner?(%Scope{role: :owner})
    end

    test "returns false for member role" do
      refute Scope.owner?(%Scope{role: :member})
    end

    test "returns false for nil" do
      refute Scope.owner?(nil)
    end
  end
end
```

## Dependencies

- Step 0 completed (tables and schemas exist)

## Incremental Test Fixes

After adding `prepare_query`, ALL existing tests that query content tables will fail unless org_id is set. Fix every broken test in this step:

1. Update `test/pop_stash/projects_test.exs` to use `setup_org_context/0` in setup
2. Update `test/pop_stash/memory_test.exs` to use `setup_org_context/0` in setup
3. Update any other test files that query content tables
4. Run `mix test` and ensure all tests pass before moving to Step 2

Do NOT defer test fixes to a later step.

## Important Notes

- After this step, ALL queries to content tables require `Repo.put_org_id/1` to be called first. This will break any test or IEx session that doesn't set it.
- The `setup_org_context/0` fixture is the standard way to set up org context in tests.
- The `Repo.insert_all` calls in fixtures use `skip_org_id: true` because `prepare_query` only intercepts reads, but `default_options` adds org_id to all operations. Using `skip_org_id: true` on raw inserts avoids interference.
