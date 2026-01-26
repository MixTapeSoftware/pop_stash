defmodule PopStashWeb.Plugs.BasicAuthTest do
  use PopStashWeb.ConnCase, async: true

  alias PopStashWeb.Plugs.BasicAuth

  describe "BasicAuth plug" do
    setup do
      # Store original config
      original_skip = Application.get_env(:pop_stash, :skip_basic_auth)
      original_auth = Application.get_env(:pop_stash, :basic_auth)

      on_exit(fn ->
        # Restore original config
        if original_skip do
          Application.put_env(:pop_stash, :skip_basic_auth, original_skip)
        else
          Application.delete_env(:pop_stash, :skip_basic_auth)
        end

        if original_auth do
          Application.put_env(:pop_stash, :basic_auth, original_auth)
        else
          Application.delete_env(:pop_stash, :basic_auth)
        end
      end)

      :ok
    end

    test "auth bypassed when skip_basic_auth is true", %{conn: conn} do
      Application.put_env(:pop_stash, :skip_basic_auth, true)

      conn = BasicAuth.call(conn, BasicAuth.init([]))

      refute conn.halted
      assert conn.status == nil
    end

    test "returns 401 when no credentials provided", %{conn: conn} do
      Application.put_env(:pop_stash, :skip_basic_auth, false)
      Application.put_env(:pop_stash, :basic_auth, username: "admin", password: "secret")

      conn = BasicAuth.call(conn, BasicAuth.init([]))

      assert conn.halted
      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Basic realm=\"PopStash Dashboard\""]
    end

    test "returns 401 with wrong credentials", %{conn: conn} do
      Application.put_env(:pop_stash, :skip_basic_auth, false)
      Application.put_env(:pop_stash, :basic_auth, username: "admin", password: "secret")

      credentials = Base.encode64("admin:wrong")

      conn =
        conn
        |> put_req_header("authorization", "Basic #{credentials}")
        |> BasicAuth.call(BasicAuth.init([]))

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 200 with correct credentials", %{conn: conn} do
      Application.put_env(:pop_stash, :skip_basic_auth, false)
      Application.put_env(:pop_stash, :basic_auth, username: "admin", password: "secret")

      credentials = Base.encode64("admin:secret")

      conn =
        conn
        |> put_req_header("authorization", "Basic #{credentials}")
        |> BasicAuth.call(BasicAuth.init([]))

      refute conn.halted
      assert conn.status == nil
    end

    test "returns 503 when credentials not configured", %{conn: conn} do
      Application.put_env(:pop_stash, :skip_basic_auth, false)
      Application.delete_env(:pop_stash, :basic_auth)

      conn = BasicAuth.call(conn, BasicAuth.init([]))

      assert conn.halted
      assert conn.status == 503
      assert conn.resp_body == "Service unavailable - authentication not configured"
    end

    test "realm is set correctly in WWW-Authenticate header", %{conn: conn} do
      Application.put_env(:pop_stash, :skip_basic_auth, false)
      Application.put_env(:pop_stash, :basic_auth, username: "admin", password: "secret")

      conn = BasicAuth.call(conn, BasicAuth.init(realm: "Custom Realm"))

      assert conn.halted
      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Basic realm=\"Custom Realm\""]
    end
  end
end
