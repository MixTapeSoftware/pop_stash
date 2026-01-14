defmodule PopStashWeb.Dashboard.DecisionLive.Index do
  @moduledoc """
  LiveView for listing and managing decisions.
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
      |> assign(:page_title, "Decisions")
      |> assign(:current_path, "/pop_stash/decisions")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:search_query, "")
      |> assign(:filter_topic, nil)
      |> load_decisions()
      |> load_topics()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:show_modal, false)
    |> assign(:decision, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:show_modal, true)
    |> assign(:decision, %Memory.Decision{})
  end

  @impl true
  def handle_event("select_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> assign(:filter_topic, nil)
      |> load_decisions()
      |> load_topics()

    {:noreply, socket}
  end

  def handle_event("filter_topic", %{"topic" => topic}, socket) do
    topic = if topic == "", do: nil, else: topic

    socket =
      socket
      |> assign(:filter_topic, topic)
      |> load_decisions()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_decisions()

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Memory.delete_decision(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Decision deleted successfully")
         |> load_decisions()
         |> load_topics()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete decision")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/decisions")}
  end

  @impl true
  def handle_info({:decision_created, _decision}, socket) do
    {:noreply, socket |> load_decisions() |> load_topics()}
  end

  def handle_info({:decision_updated, _decision}, socket) do
    {:noreply, load_decisions(socket)}
  end

  def handle_info({:decision_deleted, _id}, socket) do
    {:noreply, socket |> load_decisions() |> load_topics()}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_decisions(socket) do
    decisions =
      socket
      |> fetch_decisions()
      |> filter_decisions_by_search(socket.assigns.search_query)

    assign(socket, :decisions, decisions)
  end

  defp fetch_decisions(socket) do
    opts = build_topic_filter_opts(socket.assigns.filter_topic)

    case socket.assigns.selected_project_id do
      nil ->
        socket.assigns.projects
        |> Enum.flat_map(&Memory.list_decisions(&1.id, opts))
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

      project_id ->
        Memory.list_decisions(project_id, opts)
    end
  end

  defp build_topic_filter_opts(nil), do: []
  defp build_topic_filter_opts(title), do: [title: title]

  defp filter_decisions_by_search(decisions, ""), do: decisions

  defp filter_decisions_by_search(decisions, query) do
    query = String.downcase(query)
    Enum.filter(decisions, &decision_matches_query?(&1, query))
  end

  defp decision_matches_query?(decision, query) do
    matches_field?(decision.title, query) ||
      matches_field?(decision.body, query) ||
      matches_field?(decision.reasoning, query) ||
      matches_tags?(decision.tags, query)
  end

  defp matches_field?(nil, _query), do: false
  defp matches_field?(value, query), do: String.contains?(String.downcase(value), query)

  defp matches_tags?(nil, _query), do: false
  defp matches_tags?(tags, query), do: Enum.any?(tags, &matches_field?(&1, query))

  defp load_topics(socket) do
    titles =
      case socket.assigns.selected_project_id do
        nil ->
          socket.assigns.projects
          |> Enum.flat_map(fn project -> Memory.list_decision_titles(project.id) end)
          |> Enum.uniq()
          |> Enum.sort()

        project_id ->
          Memory.list_decision_titles(project_id)
      end

    assign(socket, :titles, titles)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Decisions" subtitle="Immutable decision records">
        <:actions>
          <.link_button navigate={~p"/pop_stash/decisions/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Decision
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

        <form :if={@titles != []} phx-change="filter_topic" class="flex-shrink-0">
          <select
            name="topic"
            class="px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
          >
            <option value="">All Titles</option>
            <option
              :for={title <- @titles}
              value={title}
              selected={@filter_topic == title}
            >
              {title}
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
              placeholder="Search decisions..."
              class="w-full pl-10 pr-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>
      
    <!-- Decision List -->
      <%= if @decisions == [] do %>
        <.empty_state
          title="No decisions found"
          description={
            if @search_query != "" || @filter_topic,
              do: "Try adjusting your filters",
              else: "Record your first decision to get started"
          }
        >
          <:action>
            <.link_button
              :if={@search_query == "" && !@filter_topic}
              navigate={~p"/pop_stash/decisions/new"}
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4" /> New Decision
            </.link_button>
          </:action>
        </.empty_state>
      <% else %>
        <.data_table id="decisions-table" rows={@decisions} row_id={&"decision-#{&1.id}"}>
          <:col :let={decision} label="Title" class="font-medium">
            <.link navigate={~p"/pop_stash/decisions/#{decision.id}"} class="hover:text-violet-600">
              <span class="font-mono">{decision.title}</span>
            </.link>
          </:col>
          <:col :let={decision} label="Body">
            <.markdown_preview content={decision.body} max_length={100} />
          </:col>
          <:col :let={decision} label="Tags">
            <.tag_badges tags={decision.tags || []} />
          </:col>
          <:col :let={decision} label="Thread" mono>
            <span class="text-xs text-slate-500 font-mono">{decision.thread_id}</span>
          </:col>
          <:col :let={decision} label="Created" mono>
            <.timestamp datetime={decision.inserted_at} />
          </:col>
          <:col :let={decision} label="Actions" class="text-right">
            <div class="flex items-center justify-end gap-2">
              <.link_button
                navigate={~p"/pop_stash/decisions/#{decision.id}"}
                variant="ghost"
                size="sm"
              >
                View
              </.link_button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="delete"
                phx-value-id={decision.id}
                data-confirm="Are you sure you want to delete this decision? Decisions are meant to be immutable records."
              >
                <.icon name="hero-trash" class="size-4 text-red-500" />
              </.button>
            </div>
          </:col>
        </.data_table>
      <% end %>
      
    <!-- New Decision Modal -->
      <.modal
        :if={@show_modal}
        id="decision-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="New Decision"
      >
        <.live_component
          module={PopStashWeb.Dashboard.DecisionLive.FormComponent}
          id={:new}
          decision={@decision}
          projects={@projects}
          titles={@titles}
          action={:new}
          return_to={~p"/pop_stash/decisions"}
        />
      </.modal>
    </div>
    """
  end
end
