defmodule PopStashWeb.Dashboard do
  @moduledoc """
  The entrypoint for defining your dashboard interface.

  This module provides helpers for LiveViews and components
  within the PopStash Dashboard.
  """

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: PopStashWeb.Gettext

      import Phoenix.HTML
      import PopStashWeb.Dashboard.Components
      import PopStashWeb.CoreComponents, only: [icon: 1]

      alias Phoenix.LiveView.JS
      alias PopStashWeb.Dashboard.Layouts

      use Phoenix.VerifiedRoutes,
        endpoint: PopStashWeb.Endpoint,
        router: PopStashWeb.Router,
        statics: PopStashWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
