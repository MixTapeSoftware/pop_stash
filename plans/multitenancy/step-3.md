# Step 3: Organizations + Memberships Contexts

## Objective

Create the `PopStash.Organizations` and `PopStash.Memberships` context modules with full CRUD operations, role management, and member lifecycle. These contexts query tables in `@skip_org_id_tables` so they work without `Repo.put_org_id`.

## Prerequisites

- Step 0 completed (tables exist)
- Step 1 completed (Repo.transact available, Scope struct exists)

## Implementation

### 1. Create Organizations context

**File**: `/workspace/lib/pop_stash/organizations.ex`

```elixir
defmodule PopStash.Organizations do
  @moduledoc """
  Context for managing organizations.

  The organizations table is in @skip_org_id_tables, so prepare_query
  automatically skips org_id enforcement for all queries in this context.
  """

  import Ecto.Query

  alias PopStash.Organizations.Organization
  alias PopStash.Repo

  ## Changesets (in context per project guidelines, not in schema)

  # Intentionally NO unsafe_validate_unique on :slug.
  # Slug uniqueness only disclosed on submit, not during phx-change validation.
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
    |> Ecto.Changeset.cast(attrs, [:name, :settings])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 255)
  end

  ## Query Module

  defmodule Query do
    @moduledoc false
    import Ecto.Query
    alias PopStash.Organizations.Organization

    def for_user(query \\ Organization, user_id) do
      join(query, :inner, [o], om in assoc(o, :org_members))
      |> where([_o, om], om.user_id == ^user_id)
      |> order_by([o], o.name)
    end
  end

  ## Public API

  @doc "Creates an organization with the given name. Does NOT create membership (use with Accounts.register_user_with_org or Memberships.add_member separately)."
  def create(attrs) when is_map(attrs) do
    %Organization{}
    |> create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Creates an org and adds creator as owner, atomically."
  def create_with_owner(name, creator_user_id, opts \\ []) do
    alias PopStash.Memberships

    slug = Keyword.get(opts, :slug) || Organization.generate_slug(name)

    Repo.transact(fn ->
      with {:ok, org} <- create(%{name: name, slug: slug}),
           {:ok, _member} <- Memberships.add_member(org.id, creator_user_id, "owner") do
        {:ok, org}
      end
    end)
  end

  def get(id) do
    case Repo.get(Organization, id) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  def get_by_slug(slug) do
    case Repo.get_by(Organization, slug: slug) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  def list_for_user(user_id) do
    Query.for_user(user_id)
    |> Repo.all()
  end

  def update(%Organization{} = org, attrs) do
    org
    |> update_changeset(attrs)
    |> Repo.update()
  end

  def delete(%Organization{} = org) do
    Repo.delete(org)
  end
end
```

### 2. Create Memberships context

**File**: `/workspace/lib/pop_stash/memberships.ex`

```elixir
defmodule PopStash.Memberships do
  @moduledoc """
  Context for managing organization memberships and roles.

  The org_members table is in @skip_org_id_tables, so prepare_query
  automatically skips org_id enforcement.
  """

  import Ecto.Query

  alias PopStash.Organizations.OrgMember
  alias PopStash.Repo
  alias PopStash.Scope

  ## Changesets (in context per project guidelines)

  defp member_changeset(org_member, attrs) do
    org_member
    |> Ecto.Changeset.cast(attrs, [:role, :org_id, :user_id])
    |> Ecto.Changeset.validate_required([:role, :org_id, :user_id])
    |> Ecto.Changeset.validate_inclusion(:role, OrgMember.roles())
    |> Ecto.Changeset.foreign_key_constraint(:org_id)
    |> Ecto.Changeset.foreign_key_constraint(:user_id)
    |> Ecto.Changeset.unique_constraint([:org_id, :user_id])
  end

  ## Public API

  def add_member(org_id, user_id, role \\ "member") do
    %OrgMember{}
    |> member_changeset(%{org_id: org_id, user_id: user_id, role: role})
    |> Repo.insert()
  end

  def remove_member(%Scope{role: :owner, org_id: org_id}, target_user_id) do
    case get_member(org_id, target_user_id) do
      nil ->
        {:error, :not_found}

      %{role: "owner"} = member ->
        owner_count = count_owners(org_id)

        if owner_count <= 1 do
          {:error, :cannot_remove_last_owner}
        else
          Repo.delete(member)
        end

      member ->
        Repo.delete(member)
    end
  end

  def remove_member(%Scope{}, _target_user_id), do: {:error, :unauthorized}

  def update_role(%Scope{role: :owner, org_id: org_id}, target_user_id, new_role) do
    case get_member(org_id, target_user_id) do
      nil ->
        {:error, :not_found}

      member ->
        member
        |> Ecto.Changeset.change(role: new_role)
        |> Repo.update()
    end
  end

  def update_role(%Scope{}, _target_user_id, _new_role), do: {:error, :unauthorized}

  def list_members(org_id) do
    OrgMember
    |> where([om], om.org_id == ^org_id)
    |> preload(:user)
    |> Repo.all()
  end

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

  ## Private

  defp get_member(org_id, user_id) do
    Repo.get_by(OrgMember, org_id: org_id, user_id: user_id)
  end

  defp count_owners(org_id) do
    OrgMember
    |> where([om], om.org_id == ^org_id and om.role == "owner")
    |> Repo.aggregate(:count)
  end
end
```

## Verification

```bash
iex -S mix

# Create org with owner
user = PopStash.Repo.one(PopStash.Accounts.User)
{:ok, org} = PopStash.Organizations.create_with_owner("My Org", user.id)

# List user's orgs
PopStash.Organizations.list_for_user(user.id)

# Check membership
PopStash.Memberships.has_role?(org.id, user.id, :owner)
# true

# List members
PopStash.Memberships.list_members(org.id)
```

## Tests

**File**: `test/pop_stash/organizations_test.exs`

```elixir
defmodule PopStash.OrganizationsTest do
  use PopStash.DataCase

  alias PopStash.Memberships
  alias PopStash.Organizations

  describe "create_with_owner/3" do
    test "creates org and adds creator as owner" do
      user = user_fixture()

      assert {:ok, org} = Organizations.create_with_owner("Test Org", user.id)
      assert org.name == "Test Org"
      assert org.slug == "test-org"
      assert Memberships.has_role?(org.id, user.id, :owner)
    end

    test "generates slug from name" do
      user = user_fixture()
      {:ok, org} = Organizations.create_with_owner("My Cool Org!", user.id)
      assert org.slug == "my-cool-org"
    end

    test "accepts custom slug" do
      user = user_fixture()
      {:ok, org} = Organizations.create_with_owner("Org", user.id, slug: "custom-slug")
      assert org.slug == "custom-slug"
    end

    test "fails on duplicate slug" do
      user = user_fixture()
      {:ok, _} = Organizations.create_with_owner("Org", user.id, slug: "taken")
      assert {:error, _} = Organizations.create_with_owner("Org 2", user.id, slug: "taken")
    end
  end

  describe "get_by_slug/1" do
    test "returns org when exists" do
      user = user_fixture()
      {:ok, org} = Organizations.create_with_owner("Test", user.id)

      assert {:ok, found} = Organizations.get_by_slug(org.slug)
      assert found.id == org.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Organizations.get_by_slug("nonexistent")
    end
  end

  describe "list_for_user/1" do
    test "returns all orgs user belongs to" do
      user = user_fixture()
      {:ok, org1} = Organizations.create_with_owner("Alpha", user.id)
      {:ok, org2} = Organizations.create_with_owner("Beta", user.id)

      orgs = Organizations.list_for_user(user.id)
      assert length(orgs) == 2
      slugs = Enum.map(orgs, & &1.slug)
      assert org1.slug in slugs
      assert org2.slug in slugs
    end

    test "does not return orgs user does not belong to" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, _} = Organizations.create_with_owner("User1 Org", user1.id)
      {:ok, _} = Organizations.create_with_owner("User2 Org", user2.id)

      orgs = Organizations.list_for_user(user1.id)
      assert length(orgs) == 1
      assert hd(orgs).name == "User1 Org"
    end
  end
end
```

**File**: `test/pop_stash/memberships_test.exs`

```elixir
defmodule PopStash.MembershipsTest do
  use PopStash.DataCase

  alias PopStash.Memberships
  alias PopStash.Scope

  describe "add_member/3" do
    test "adds user to org with role" do
      org = organization_fixture()
      user = user_fixture()

      assert {:ok, member} = Memberships.add_member(org.id, user.id, "member")
      assert member.role == "member"
    end

    test "prevents duplicate membership" do
      org = organization_fixture()
      user = user_fixture()

      {:ok, _} = Memberships.add_member(org.id, user.id)
      assert {:error, _} = Memberships.add_member(org.id, user.id)
    end
  end

  describe "remove_member/2" do
    test "owner can remove member" do
      org = organization_fixture()
      owner = user_fixture()
      member = user_fixture()
      org_member_fixture(org, owner, "owner")
      org_member_fixture(org, member, "member")

      scope = %Scope{org_id: org.id, user_id: owner.id, role: :owner}
      assert {:ok, _} = Memberships.remove_member(scope, member.id)
    end

    test "member cannot remove others" do
      org = organization_fixture()
      member1 = user_fixture()
      member2 = user_fixture()
      org_member_fixture(org, member1, "member")
      org_member_fixture(org, member2, "member")

      scope = %Scope{org_id: org.id, user_id: member1.id, role: :member}
      assert {:error, :unauthorized} = Memberships.remove_member(scope, member2.id)
    end

    test "cannot remove last owner" do
      org = organization_fixture()
      owner = user_fixture()
      org_member_fixture(org, owner, "owner")

      scope = %Scope{org_id: org.id, user_id: owner.id, role: :owner}
      assert {:error, :cannot_remove_last_owner} = Memberships.remove_member(scope, owner.id)
    end
  end

  describe "has_role?/3" do
    test "returns true when user has role" do
      org = organization_fixture()
      user = user_fixture()
      org_member_fixture(org, user, "owner")

      assert Memberships.has_role?(org.id, user.id, :owner)
    end

    test "returns false when user does not have role" do
      org = organization_fixture()
      user = user_fixture()
      org_member_fixture(org, user, "member")

      refute Memberships.has_role?(org.id, user.id, :owner)
    end

    test "returns false when user is not a member" do
      org = organization_fixture()
      user = user_fixture()

      refute Memberships.has_role?(org.id, user.id, :member)
    end
  end
end
```

## Dependencies

- Step 0 completed (tables exist)
- Step 1 completed (Repo.transact, fixtures available)

## Important Notes

- Both Organizations and Memberships query `@skip_org_id_tables` so they work without `Repo.put_org_id`.
- The `Organizations.create/1` function takes a map (not name + user_id) and does NOT create membership. This is a lower-level function used by `Accounts.register_user_with_org/1`. For the higher-level "create org with owner" flow, use `Organizations.create_with_owner/3`.
- The `add_member` changeset uses `Ecto.Changeset.cast` with `:org_id` and `:user_id` because these are set programmatically (from function params), not from user input. In a web form context, they would be excluded from cast -- but this is a context-only function, not a form handler.
