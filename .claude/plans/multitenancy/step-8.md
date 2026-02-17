# Step 8: Testing & Polish

## Overview
Add comprehensive testing, verify cross-org isolation (including prepare_query enforcement), performance testing, and final polish.

## Context
Final step to ensure quality, security, and performance before shipping multi-tenancy. With `prepare_query` in place, we can now test that direct Repo queries are also automatically scoped.

## Implementation

### 1. Unit Tests

#### Organizations Context Tests

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

    test "generates unique slug from name" do
      user = insert(:user)

      {:ok, org1} = Organizations.create("My Org", user.id)
      assert org1.slug == "my-org"

      {:ok, org2} = Organizations.create("My Org!", user.id, slug: "my-org-2")
      assert org2.slug == "my-org-2"
    end
  end

  describe "get_by_slug/1" do
    test "returns org when exists" do
      user = insert(:user)
      {:ok, org} = Organizations.create("Test", user.id)

      assert {:ok, found} = Organizations.get_by_slug("test")
      assert found.id == org.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Organizations.get_by_slug("nonexistent")
    end
  end
end
```

#### Memberships Context Tests

**File**: `test/pop_stash/memberships_test.exs`

```elixir
defmodule PopStash.MembershipsTest do
  use PopStash.DataCase

  alias PopStash.Memberships
  alias PopStash.Scope

  describe "add_member/3" do
    test "adds user to organization with role" do
      org = insert(:organization)
      user = insert(:user)

      assert {:ok, member} = Memberships.add_member(org.id, user.id, "member")
      assert member.role == "member"
      assert member.org_id == org.id
      assert member.user_id == user.id
    end

    test "prevents duplicate memberships" do
      org = insert(:organization)
      user = insert(:user)

      {:ok, _} = Memberships.add_member(org.id, user.id)
      assert {:error, _} = Memberships.add_member(org.id, user.id)
    end
  end

  describe "remove_member/2" do
    test "owner can remove member" do
      org = insert(:organization)
      owner = insert(:user)
      member = insert(:user)

      insert(:org_member, org_id: org.id, user_id: owner.id, role: "owner")
      insert(:org_member, org_id: org.id, user_id: member.id, role: "member")

      owner_scope = %Scope{org_id: org.id, user_id: owner.id, role: :owner}

      assert :ok = Memberships.remove_member(owner_scope, member.id)
    end

    test "member cannot remove other members" do
      org = insert(:organization)
      member1 = insert(:user)
      member2 = insert(:user)

      insert(:org_member, org_id: org.id, user_id: member1.id, role: "member")
      insert(:org_member, org_id: org.id, user_id: member2.id, role: "member")

      member_scope = %Scope{org_id: org.id, user_id: member1.id, role: :member}

      assert {:error, :unauthorized} = Memberships.remove_member(member_scope, member2.id)
    end
  end
end
```

### 2. Integration Tests

#### Cross-Org Isolation Tests

**File**: `test/pop_stash/cross_org_isolation_test.exs`

```elixir
defmodule PopStash.CrossOrgIsolationTest do
  use PopStash.DataCase

  alias PopStash.Projects
  alias PopStash.Memory
  alias PopStash.Repo
  alias PopStash.Scope

  setup do
    # Org 1
    org1 = insert(:organization, name: "Org 1")
    user1 = insert(:user, selected_org_id: org1.id)
    insert(:org_member, org_id: org1.id, user_id: user1.id)
    scope1 = %Scope{org_id: org1.id, user_id: user1.id, role: :member}

    # Org 2
    org2 = insert(:organization, name: "Org 2")
    user2 = insert(:user, selected_org_id: org2.id)
    insert(:org_member, org_id: org2.id, user_id: user2.id)
    scope2 = %Scope{org_id: org2.id, user_id: user2.id, role: :member}

    {:ok, scope1: scope1, scope2: scope2, org1: org1, org2: org2}
  end

  test "user cannot access projects from other org", %{scope1: scope1, org2: org2} do
    project2 = insert(:project, org_id: org2.id)

    Repo.put_org_id(scope1.org_id)
    assert {:error, :not_found} = Projects.get(scope1, project2.id)
  end

  test "user cannot create insight in other org's project", %{scope1: scope1, org2: org2} do
    project2 = insert(:project, org_id: org2.id)

    Repo.put_org_id(scope1.org_id)
    assert {:error, :project_not_found} =
             Memory.create_insight(scope1, project2.id, "Test insight")
  end

  test "user only sees their org's data in lists", %{scope1: scope1, scope2: scope2, org1: org1, org2: org2} do
    insert(:project, org_id: org1.id, name: "Org1 Project")
    insert(:project, org_id: org2.id, name: "Org2 Project")

    Repo.put_org_id(scope1.org_id)
    projects1 = Projects.list(scope1)

    Repo.put_org_id(scope2.org_id)
    projects2 = Projects.list(scope2)

    assert length(projects1) == 1
    assert hd(projects1).name == "Org1 Project"

    assert length(projects2) == 1
    assert hd(projects2).name == "Org2 Project"
  end

  test "prepare_query prevents direct Repo access to other org's data" do
    org1 = insert(:organization)
    org2 = insert(:organization)
    insert(:project, org_id: org1.id, name: "Org1 Project")
    insert(:project, org_id: org2.id, name: "Org2 Project")

    # Even with direct Repo.all, prepare_query scopes by org_id
    Repo.put_org_id(org1.id)
    projects = Repo.all(PopStash.Projects.Project)

    assert length(projects) == 1
    assert hd(projects).name == "Org1 Project"
  end

  test "prepare_query raises when no org_id is set" do
    Repo.put_org_id(nil)

    assert_raise RuntimeError, ~r/expected org_id or skip_org_id/, fn ->
      Repo.all(PopStash.Projects.Project)
    end
  end
end
```

#### Authentication Flow Test

**File**: `test/pop_stash_web/auth_flow_test.exs`

```elixir
defmodule PopStashWeb.AuthFlowTest do
  use PopStashWeb.ConnCase
  import Phoenix.LiveViewTest

  test "complete passwordless auth flow", %{conn: conn} do
    user = insert(:user, email: "test@example.com")

    # Visit login page
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    # Submit email
    lv
    |> form("#login_form", user: %{email: "test@example.com"})
    |> render_submit()

    # Verify email sent
    assert_email_sent(subject: "Your PopStash login link")

    # Extract token and verify
    {token, _} = PopStash.Accounts.UserToken.build_email_token(user, "login")
    PopStash.Repo.insert!(%PopStash.Accounts.UserToken{
      user_id: user.id,
      token: :crypto.hash(:sha256, Base.url_decode64!(token, padding: false)),
      context: "login",
      sent_to: user.email
    })

    # Click magic link
    conn = get(build_conn(), ~p"/users/log-in/#{token}")

    # Should be logged in
    assert redirected_to(conn) in [~p"/", ~p"/orgs/select"]
  end
end
```

### 3. Performance Tests

**File**: `test/pop_stash/performance_test.exs`

```elixir
defmodule PopStash.PerformanceTest do
  use PopStash.DataCase

  alias PopStash.Projects
  alias PopStash.Repo
  alias PopStash.Scope

  @tag :performance
  test "queries use indexes (no N+1)" do
    org = insert(:organization)
    user = insert(:user, selected_org_id: org.id)
    insert(:org_member, org_id: org.id, user_id: user.id)
    scope = %Scope{org_id: org.id, user_id: user.id, role: :member}

    # Create 100 projects
    for i <- 1..100 do
      insert(:project, org_id: org.id, name: "Project #{i}")
    end

    Repo.put_org_id(org.id)

    # List should use single query with index
    result = ExUnit.CaptureLog.capture_log(fn ->
      Projects.list(scope)
    end)

    # Should be single SELECT query
    assert result =~ "SELECT"
    refute result =~ "SELECT.*SELECT" # No N+1
  end
end
```

### 4. Manual Verification Checklist

```bash
# Run all tests
mix test

# Start server
mix phx.server

# Manual verification:
# 1. Register new user
# 2. Receive magic link email
# 3. Click link, verify login
# 4. Create organization
# 5. Create project
# 6. Create insight
# 7. Create decision
# 8. View activity feed
# 9. Create second org
# 10. Switch between orgs
# 11. Verify different data shown
# 12. Verify MCP endpoint still works
# 13. Check dashboard performance (<500ms)
```

### 5. Security Audit

**File**: `test/pop_stash/security_audit_test.exs`

```elixir
defmodule PopStash.SecurityAuditTest do
  use PopStash.DataCase

  alias PopStash.Projects
  alias PopStash.Repo
  alias PopStash.Scope

  test "prepare_query enforces org isolation even on direct Repo queries" do
    org1 = insert(:organization)
    org2 = insert(:organization)
    user = insert(:user, selected_org_id: org1.id)
    insert(:org_member, org_id: org1.id, user_id: user.id)

    project = insert(:project, org_id: org2.id)

    scope = %Scope{org_id: org1.id, user_id: user.id, role: :member}

    # Context-level access blocked
    Repo.put_org_id(org1.id)
    assert {:error, :not_found} = Projects.get(scope, project.id)

    # Direct Repo access is ALSO scoped by prepare_query
    # prepare_query enforces this at the Repo level automatically
    direct_results = Repo.all(PopStash.Projects.Project)
    refute Enum.any?(direct_results, &(&1.id == project.id))
  end

  test "cannot query content tables without org_id" do
    Repo.put_org_id(nil)

    assert_raise RuntimeError, ~r/expected org_id or skip_org_id/, fn ->
      Repo.all(PopStash.Projects.Project)
    end

    assert_raise RuntimeError, ~r/expected org_id or skip_org_id/, fn ->
      Repo.all(PopStash.Memory.Insight)
    end
  end
end
```

### 6. Polish Items

- [ ] Add org switcher to navigation bar
- [ ] Add breadcrumbs showing current org
- [ ] Add "Invite members" UI
- [ ] Add org settings page
- [ ] Update error messages for better UX
- [ ] Add loading states to org selection
- [ ] Add empty states for new orgs
- [ ] Update documentation

## Verification

```bash
# Run full test suite
mix test

# Run specific test suites
mix test test/pop_stash/organizations_test.exs
mix test test/pop_stash/cross_org_isolation_test.exs
mix test --only performance

# Check test coverage
mix test --cover

# Run static analysis
mix credo --strict
mix sobelow

# Performance check
mix run -e "PopStash.Repo.query!(\"EXPLAIN ANALYZE SELECT * FROM projects WHERE org_id = 'some-uuid'\")"
```

## Dependencies
- Steps 0-7 completed

## Success Criteria
- [ ] All tests pass
- [ ] Cross-org isolation verified (both context-level and prepare_query-level)
- [ ] No N+1 queries
- [ ] Dashboard loads in <500ms
- [ ] Security audit passed (prepare_query raises on missing org_id)
- [ ] MCP endpoint still works
- [ ] User can complete full auth flow
- [ ] User can switch between orgs
- [ ] Static analysis passes (credo, sobelow)

## Completion
Multi-tenancy implementation is complete! Users can now:
- Register with passwordless auth
- Create multiple organizations
- Switch between organizations
- Access only their org's data (enforced at Repo level by prepare_query)
- Collaborate with team members
