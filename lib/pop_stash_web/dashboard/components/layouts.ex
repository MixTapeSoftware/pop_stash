defmodule PopStashWeb.Dashboard.Layouts do
  @moduledoc """
  Layouts for the PopStash Dashboard.

  Design direction: Precision & Density (Linear/Raycast aesthetic)
  - Borders-only depth (no shadows)
  - Cool slate foundation
  - Violet accent color
  - 4px grid spacing
  """

  use PopStashWeb.Dashboard, :html

  embed_templates "layouts/*"

  @doc """
  Renders the dashboard flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" class="fixed top-4 right-4 z-50 space-y-2">
      <.flash :if={Phoenix.Flash.get(@flash, :info)} kind={:info}>
        {Phoenix.Flash.get(@flash, :info)}
      </.flash>
      <.flash :if={Phoenix.Flash.get(@flash, :error)} kind={:error}>
        {Phoenix.Flash.get(@flash, :error)}
      </.flash>
    </div>
    """
  end

  attr :kind, :atom, values: [:info, :error], required: true
  slot :inner_block, required: true

  defp flash(assigns) do
    ~H"""
    <div
      class={[
        "px-4 py-3 rounded text-sm border",
        @kind == :info && "bg-violet-50 border-violet-200 text-violet-800",
        @kind == :error && "bg-red-50 border-red-200 text-red-800"
      ]}
      role="alert"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Navigation link component with active state styling.
  """
  attr :navigate, :string, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def nav_link(assigns) do
    active =
      String.starts_with?(assigns.current_path, assigns.navigate) and
        (assigns.navigate != "/pop_stash" or assigns.current_path == "/pop_stash")

    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-2 px-3 py-2 text-sm rounded transition-colors duration-150",
        @active && "bg-violet-50 text-violet-700 font-medium",
        !@active && "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
