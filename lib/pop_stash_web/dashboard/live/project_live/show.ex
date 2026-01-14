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
    contexts = Memory.list_contexts(project_id)
    insights = Memory.list_insights(project_id)
    decisions = Memory.list_decisions(project_id)

    stats = [
      %{title: "Contexts", value: length(contexts)},
      %{title: "Insights", value: length(insights)},
      %{title: "Decisions", value: length(decisions)}
    ]

    assign(socket, :stats, stats)
  end

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
          <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
            <.link
              navigate={~p"/pop_stash/contexts?project_id=#{@project.id}"}
              class="flex items-center gap-3 p-4 rounded border border-slate-200 hover:bg-slate-50 hover:border-violet-300 transition-colors"
            >
              <.icon name="hero-archive-box" class="size-6 text-slate-400" />
              <div>
                <div class="text-sm font-medium text-slate-900">View Stashes</div>
                <div class="text-xs text-slate-500">
                  {Enum.find(@stats, &(&1.title == "Stashes")).value} stashes
                </div>
              </div>
            </.link>

            <.link
              navigate={~p"/pop_stash/insights?project_id=#{@project.id}"}
              class="flex items-center gap-3 p-4 rounded border border-slate-200 hover:bg-slate-50 hover:border-violet-300 transition-colors"
            >
              <.icon name="hero-light-bulb" class="size-6 text-slate-400" />
              <div>
                <div class="text-sm font-medium text-slate-900">View Insights</div>
                <div class="text-xs text-slate-500">
                  {Enum.find(@stats, &(&1.title == "Insights")).value} insights
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
                  {Enum.find(@stats, &(&1.title == "Decisions")).value} decisions
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
