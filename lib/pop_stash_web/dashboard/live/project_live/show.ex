defmodule PopStashWeb.Dashboard.ProjectLive.Show do
  @moduledoc """
  LiveView for showing a single project with its details and activity.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Activity
  alias PopStash.Memory
  alias PopStash.Projects

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    case Projects.get(id) do
      {:ok, project} ->
        socket =
          socket
          |> assign(:page_title, project.name)
          |> assign(:current_path, "/pop_stash/projects/#{id}")
          |> assign(:project, project)
          |> load_stats()
          |> load_activity()

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found")
         |> push_navigate(to: ~p"/pop_stash/projects")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Projects.delete(socket.assigns.project.id) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project deleted successfully")
         |> push_navigate(to: ~p"/pop_stash/projects")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete project")}
    end
  end

  # Real-time event handlers
  @impl true
  def handle_info({:stash_created, stash}, socket) do
    if stash.project_id == socket.assigns.project.id do
      item = Activity.to_item(stash)
      {:noreply, prepend_activity_item(socket, item) |> load_stats()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stash_updated, _stash}, socket) do
    {:noreply, socket}
  end

  def handle_info({:decision_created, decision}, socket) do
    if decision.project_id == socket.assigns.project.id do
      item = Activity.to_item(decision)
      {:noreply, prepend_activity_item(socket, item) |> load_stats()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:insight_created, insight}, socket) do
    if insight.project_id == socket.assigns.project.id do
      item = Activity.to_item(insight)
      {:noreply, prepend_activity_item(socket, item) |> load_stats()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:insight_updated, _insight}, socket) do
    {:noreply, socket}
  end

  def handle_info({:stash_deleted, id}, socket) do
    {:noreply, remove_activity_item(socket, id) |> load_stats()}
  end

  def handle_info({:decision_deleted, id}, socket) do
    {:noreply, remove_activity_item(socket, id) |> load_stats()}
  end

  def handle_info({:insight_deleted, id}, socket) do
    {:noreply, remove_activity_item(socket, id) |> load_stats()}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_stats(socket) do
    project_id = socket.assigns.project.id
    insights = Memory.list_insights(project_id)
    decisions = Memory.list_decisions(project_id)

    # Calculate recent activity (last 7 days)
    now = DateTime.utc_now()
    week_ago = DateTime.add(now, -7, :day)

    recent_insights = Enum.filter(insights, &(DateTime.compare(&1.inserted_at, week_ago) == :gt))

    recent_decisions =
      Enum.filter(decisions, &(DateTime.compare(&1.inserted_at, week_ago) == :gt))

    # Get the most recent item for each category
    latest_insight = List.first(Enum.sort_by(insights, & &1.inserted_at, {:desc, DateTime}))
    latest_decision = List.first(Enum.sort_by(decisions, & &1.inserted_at, {:desc, DateTime}))

    stats = [
      %{
        title: "Insights",
        value: length(insights),
        desc: build_stat_description(length(recent_insights), latest_insight, "insight", "week"),
        link: ~p"/pop_stash/insights?project_id=#{project_id}"
      },
      %{
        title: "Decisions",
        value: length(decisions),
        desc:
          build_stat_description(length(recent_decisions), latest_decision, "decision", "week"),
        link: ~p"/pop_stash/decisions?project_id=#{project_id}"
      }
    ]

    assign(socket, :stats, stats)
  end

  defp build_stat_description(recent_count, latest_item, _item_type, period) do
    recent_text = format_recent_count(recent_count, period)
    latest_text = format_latest_time(latest_item)
    recent_text <> latest_text
  end

  defp format_recent_count(0, period), do: "None this #{period}"
  defp format_recent_count(count, period), do: "#{count} this #{period}"

  defp format_latest_time(nil), do: ""

  defp format_latest_time(latest_item) do
    days_ago = div(DateTime.diff(DateTime.utc_now(), latest_item.inserted_at), 86_400)
    ", last added #{format_time_ago(days_ago)}"
  end

  defp format_time_ago(0), do: "today"
  defp format_time_ago(1), do: "yesterday"
  defp format_time_ago(days) when days < 7, do: "#{days} days ago"

  defp format_time_ago(days) when days < 30 do
    weeks = div(days, 7)
    "#{weeks} #{pluralize("week", weeks)} ago"
  end

  defp format_time_ago(days) do
    months = div(days, 30)
    "#{months} #{pluralize("month", months)} ago"
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"

  defp load_activity(socket) do
    items = Activity.list_recent(limit: 20, project_id: socket.assigns.project.id)
    assign(socket, :activity_items, items)
  end

  defp prepend_activity_item(socket, item) do
    items = [item | socket.assigns.activity_items]
    items = Enum.take(items, 20)
    assign(socket, :activity_items, items)
  end

  defp remove_activity_item(socket, item_id) do
    items = Enum.reject(socket.assigns.activity_items, &(&1.id == item_id))
    assign(socket, :activity_items, items)
  end

  defp get_stat_value(stats, title) do
    case Enum.find(stats, &(&1.title == title)) do
      nil -> 0
      stat -> stat.value
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/pop_stash/projects"} label="Back to projects" />

      <.page_header title={@project.name} subtitle="Project Details">
        <:actions>
          <.button
            variant="danger"
            phx-click="delete"
            data-confirm="Are you sure you want to delete this project? This will delete all associated stashes, insights, and decisions."
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </.button>
        </:actions>
      </.page_header>
      
    <!-- Project Info -->
      <.card>
        <div class="space-y-4">
          <.detail_row label="ID">
            <.id_badge id={@project.id} />
          </.detail_row>

          <.detail_row label="Description">
            <div class="text-sm text-slate-600">
              {if @project.description, do: @project.description, else: "—"}
            </div>
          </.detail_row>

          <.detail_row label="Tags">
            <.tag_badges tags={@project.tags || []} />
          </.detail_row>

          <.detail_row label="Created">
            <.timestamp datetime={@project.inserted_at} />
          </.detail_row>

          <.detail_row label="Updated">
            <.timestamp datetime={@project.updated_at} />
          </.detail_row>
        </div>
      </.card>
      
    <!-- Stats -->
      <div class="mt-6">
        <.stats_row stats={@stats} />
      </div>
      
    <!-- Recent Activity -->
      <div class="mt-8">
        <.card>
          <.section_header title="Recent Activity">
            <:actions>
              <span class="text-xs text-slate-400">Live updates enabled</span>
              <span class="relative flex h-2 w-2 ml-2">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75">
                </span>
                <span class="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
              </span>
            </:actions>
          </.section_header>

          <.live_component
            module={PopStashWeb.Dashboard.ActivityFeedComponent}
            id="activity-feed"
            items={@activity_items}
            limit={20}
            project_id={@project.id}
            show_project={false}
          />
        </.card>
      </div>
      
    <!-- Quick Navigation -->
      <div class="mt-6">
        <.card>
          <.section_header title="Browse Project Contents" />
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <.link
              navigate={~p"/pop_stash/insights?project_id=#{@project.id}"}
              class="flex items-center gap-3 p-4 rounded border border-slate-200 hover:bg-slate-50 hover:border-violet-300 transition-colors"
            >
              <.icon name="hero-light-bulb" class="size-6 text-slate-400" />
              <div>
                <div class="text-sm font-medium text-slate-900">View Insights</div>
                <div class="text-xs text-slate-500">
                  {get_stat_value(@stats, "Insights")} insights
                </div>
              </div>
            </.link>

            <.link
              navigate={~p"/pop_stash/decisions?project_id=#{@project.id}"}
              class="flex items-center gap-3 p-4 rounded border border-slate-200 hover:bg-slate-50 hover:border-violet-300 transition-colors"
            >
              <.icon name="hero-check-badge" class="size-6 text-slate-400" />
              <div>
                <div class="text-sm font-medium text-slate-900">View Decisions</div>
                <div class="text-xs text-slate-500">
                  {get_stat_value(@stats, "Decisions")} decisions
                </div>
              </div>
            </.link>
          </div>
        </.card>
      </div>
    </div>
    """
  end
end
