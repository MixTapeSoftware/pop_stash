defmodule PopStashWeb.Dashboard.ActivityFeedComponent do
  @moduledoc """
  LiveComponent for displaying real-time activity feed.
  """

  use PopStashWeb.Dashboard, :live_component

  alias PopStash.Activity

  @impl true
  def mount(socket) do
    {:ok, assign(socket, items: [], loading: true)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:limit, fn -> 20 end)
      |> assign_new(:project_id, fn -> nil end)
      |> assign_new(:show_project, fn -> true end)

    # Only load items if not already provided
    socket =
      if Map.has_key?(assigns, :items) do
        assign(socket, loading: false)
      else
        load_items(socket)
      end

    {:ok, socket}
  end

  defp load_items(socket) do
    items =
      Activity.list_recent(
        limit: socket.assigns.limit,
        project_id: socket.assigns.project_id
      )

    assign(socket, items: items, loading: false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-1" id={@id}>
      <div :if={@loading} class="py-8 text-center text-slate-400 text-sm">
        Loading activity...
      </div>

      <div :if={!@loading && @items == []} class="py-8 text-center text-slate-400 text-sm">
        No recent activity
      </div>

      <div
        :for={item <- @items}
        id={"activity-#{item.id}"}
        class="group flex items-start gap-3 p-3 rounded hover:bg-slate-50 transition-colors"
      >
        <!-- Type Icon -->
        <div class={[
          "flex-shrink-0 w-8 h-8 rounded flex items-center justify-center",
          type_bg_class(item.type)
        ]}>
          <.icon name={type_icon(item.type)} class={"size-4 #{type_icon_class(item.type)}"} />
        </div>
        
    <!-- Content -->
        <div class="flex-1 min-w-0">
          <%= if item_path(item) do %>
            <.link
              navigate={item_path(item)}
              class="block text-sm font-medium text-slate-900 hover:text-violet-600 truncate"
            >
              {item.title}
            </.link>
          <% else %>
            <div class="block text-sm font-medium text-slate-900 truncate">
              {item.title}
            </div>
          <% end %>

          <p :if={item.preview} class="text-xs text-slate-500 truncate mt-0.5">
            {item.preview}
          </p>

          <div class="flex items-center gap-2 mt-1">
            <span
              :if={@show_project && item.project_name}
              class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-slate-50 text-slate-600"
            >
              {item.project_name}
            </span>
            <span class="text-xs text-slate-400 font-mono">
              {relative_time_string(item.inserted_at)}
            </span>
          </div>
        </div>
        
    <!-- Type Badge -->
        <span class={[
          "flex-shrink-0 inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded",
          type_badge_class(item.type)
        ]}>
          {type_label(item.type)}
        </span>
      </div>
    </div>
    """
  end

  # Helper functions

  defp type_icon(:context), do: "hero-archive-box"
  defp type_icon(:decision), do: "hero-check-badge"
  defp type_icon(:insight), do: "hero-light-bulb"
  defp type_icon(:search), do: "hero-magnifying-glass"
  defp type_icon(:plan), do: "hero-map"

  defp type_bg_class(:context), do: "bg-blue-50"
  defp type_bg_class(:decision), do: "bg-green-50"
  defp type_bg_class(:insight), do: "bg-amber-50"
  defp type_bg_class(:search), do: "bg-purple-50"
  defp type_bg_class(:plan), do: "bg-indigo-50"

  defp type_icon_class(:context), do: "text-blue-500"
  defp type_icon_class(:decision), do: "text-green-500"
  defp type_icon_class(:insight), do: "text-amber-500"
  defp type_icon_class(:search), do: "text-purple-500"
  defp type_icon_class(:plan), do: "text-indigo-500"

  defp type_badge_class(:context), do: "bg-blue-100 text-blue-800"
  defp type_badge_class(:decision), do: "bg-green-100 text-green-800"
  defp type_badge_class(:insight), do: "bg-amber-100 text-amber-800"
  defp type_badge_class(:search), do: "bg-purple-100 text-purple-800"
  defp type_badge_class(:plan), do: "bg-indigo-100 text-indigo-800"

  defp type_label(:context), do: "Context"
  defp type_label(:decision), do: "Decision"
  defp type_label(:insight), do: "Insight"
  defp type_label(:search), do: "Search"
  defp type_label(:plan), do: "Plan"

  defp item_path(%{type: :context, id: id}), do: ~p"/pop_stash/contexts/#{id}"
  defp item_path(%{type: :decision, id: id}), do: ~p"/pop_stash/decisions/#{id}"
  defp item_path(%{type: :insight, id: id}), do: ~p"/pop_stash/insights/#{id}"
  defp item_path(%{type: :search}), do: nil
  defp item_path(%{type: :plan, id: id}), do: ~p"/pop_stash/plans/#{id}"

  defp relative_time_string(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
