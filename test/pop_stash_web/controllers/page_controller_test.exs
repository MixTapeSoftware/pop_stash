defmodule PopStashWeb.PageControllerTest do
  use PopStashWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Searchable insights, decisions, context for AI agents"
  end

  test "sets Content-Security-Policy header", %{conn: conn} do
    conn = get(conn, ~p"/")
    csp = get_resp_header(conn, "content-security-policy")
    assert csp != []
    assert List.first(csp) =~ "default-src 'self'"
  end
end
