defmodule PopStashWeb.Dashboard.InsightLive.Index do
  @moduledoc """
  LiveView for listing and managing insights.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Projects

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    projects = Projects.list()

    socket =
      socket
      |> assign(:page_title, "Insights")
      |> assign(:current_path, "/pop_stash/insights")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:search_query, "")
      |> load_insights()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:show_modal, false)
    |> assign(:insight, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:show_modal, true)
    |> assign(:insight, %Memory.Insight{})
  end

  @impl true
  def handle_event("select_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> load_insights()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_insights()

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Memory.delete_insight(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Insight deleted successfully")
         |> load_insights()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete insight")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/insights")}
  end

  @impl true
  def handle_info({:insight_created, _insight}, socket) do
    {:noreply, load_insights(socket)}
  end

  def handle_info({:insight_updated, _insight}, socket) do
    {:noreply, load_insights(socket)}
  end

  def handle_info({:insight_deleted, _id}, socket) do
    {:noreply, load_insights(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_insights(socket) do
    insights =
      socket
      |> fetch_insights()
      |> filter_insights_by_search(socket.assigns.search_query)

    assign(socket, :insights, insights)
  end

  defp fetch_insights(socket) do
    case socket.assigns.selected_project_id do
      nil ->
        socket.assigns.projects
        |> Enum.flat_map(&Memory.list_insights(&1.id))
        |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

      project_id ->
        Memory.list_insights(project_id)
    end
  end

  defp filter_insights_by_search(insights, ""), do: insights

  defp filter_insights_by_search(insights, query) do
    query = String.downcase(query)
    Enum.filter(insights, &insight_matches_query?(&1, query))
  end

  defp insight_matches_query?(insight, query) do
    matches_field?(insight.key, query) ||
      matches_field?(insight.content, query) ||
      matches_tags?(insight.tags, query)
  end

  defp matches_field?(nil, _query), do: false
  defp matches_field?(value, query), do: String.contains?(String.downcase(value), query)

  defp matches_tags?(nil, _query), do: false
  defp matches_tags?(tags, query), do: Enum.any?(tags, &matches_field?(&1, query))

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Insights" subtitle="Learned knowledge and patterns">
        <:actions>
          <.link_button navigate={~p"/pop_stash/insights/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Insight
          </.link_button>
        </:actions>
      </.page_header>
      
    <!-- Filters -->
      <div class="flex flex-col sm:flex-row gap-3 mb-6">
        <form phx-change="select_project" class="flex-shrink-0">
          <select
            name="project_id"
            class="px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
          >
            <option value="">All Projects</option>
            <option
              :for={project <- @projects}
              value={project.id}
              selected={@selected_project_id == project.id}
            >
              {project.name}
            </option>
          </select>
        </form>

        <form phx-change="search" class="flex-1">
          <div class="relative">
            <.icon
              name="hero-magnifying-glass"
              class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-slate-400"
            />
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search insights..."
              class="w-full pl-10 pr-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>
      
    <!-- Insight List -->
      <%= if @insights == [] do %>
        <.empty_state
          title="No insights found"
          description={
            if @search_query != "",
              do: "Try adjusting your search",
              else: "Create your first insight to get started"
          }
        >
          <:action>
            <.link_button
              :if={@search_query == ""}
              navigate={~p"/pop_stash/insights/new"}
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4" /> New Insight
            </.link_button>
          </:action>
        </.empty_state>
      <% else %>
        <.data_table id="insights-table" rows={@insights} row_id={&"insight-#{&1.id}"}>
          <:col :let={insight} label="Key" class="font-medium">
            <.link navigate={~p"/pop_stash/insights/#{insight.id}"} class="hover:text-violet-600">
              <%= if insight.key do %>
                <span class="font-mono">{insight.key}</span>
              <% else %>
                <span class="text-slate-400 italic">No key</span>
              <% end %>
            </.link>
          </:col>
          <:col :let={insight} label="Content">
            <.markdown_preview content={insight.content} max_length={100} />
          </:col>
          <:col :let={insight} label="Tags">
            <.tag_badges tags={insight.tags || []} />
          </:col>
          <:col :let={insight} label="Updated" mono>
            <.timestamp datetime={insight.updated_at} />
          </:col>
          <:col :let={insight} label="Actions" class="text-right">
            <div class="flex items-center justify-end gap-2">
              <.link_button navigate={~p"/pop_stash/insights/#{insight.id}"} variant="ghost" size="sm">
                View
              </.link_button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="delete"
                phx-value-id={insight.id}
                data-confirm="Are you sure you want to delete this insight?"
              >
                <.icon name="hero-trash" class="size-4 text-red-500" />
              </.button>
            </div>
          </:col>
        </.data_table>
      <% end %>
      
    <!-- New Insight Modal -->
      <.modal
        :if={@show_modal}
        id="insight-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="New Insight"
      >
        <.live_component
          module={PopStashWeb.Dashboard.InsightLive.FormComponent}
          id={:new}
          insight={@insight}
          projects={@projects}
          action={:new}
          return_to={~p"/pop_stash/insights"}
        />
      </.modal>
    </div>
    """
  end
end
