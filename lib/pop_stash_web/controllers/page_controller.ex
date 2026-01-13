defmodule PopStashWeb.PageController do
  use PopStashWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
