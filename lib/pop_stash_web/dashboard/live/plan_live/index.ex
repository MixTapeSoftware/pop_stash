defmodule PopStashWeb.Dashboard.PlanLive.Index do
  @moduledoc """
  LiveView for listing and managing plans.
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
      |> assign(:page_title, "Plans")
      |> assign(:current_path, "/pop_stash/plans")
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:search_query, "")
      |> assign(:filter_title, nil)
      |> assign(:show_all_versions, false)
      |> load_plans()
      |> load_titles()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:show_modal, false)
    |> assign(:plan, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:show_modal, true)
    |> assign(:plan, %Memory.Plan{})
  end

  @impl true
  def handle_event("select_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> assign(:filter_title, nil)
      |> load_plans()
      |> load_titles()

    {:noreply, socket}
  end

  def handle_event("filter_title", %{"title" => title}, socket) do
    title = if title == "", do: nil, else: title

    socket =
      socket
      |> assign(:filter_title, title)
      |> load_plans()

    {:noreply, socket}
  end

  def handle_event("toggle_versions", _params, socket) do
    socket =
      socket
      |> assign(:show_all_versions, !socket.assigns.show_all_versions)
      |> load_plans()

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_plans()

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Memory.delete_plan(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Plan deleted successfully")
         |> load_plans()
         |> load_titles()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete plan")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/plans")}
  end

  @impl true
  def handle_info({:plan_created, _plan}, socket) do
    {:noreply, socket |> load_plans() |> load_titles()}
  end

  def handle_info({:plan_updated, _plan}, socket) do
    {:noreply, load_plans(socket)}
  end

  def handle_info({:plan_deleted, _id}, socket) do
    {:noreply, socket |> load_plans() |> load_titles()}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_plans(socket) do
    plans =
      socket
      |> fetch_plans()
      |> maybe_filter_latest_versions(socket.assigns.show_all_versions)
      |> filter_plans_by_search(socket.assigns.search_query)

    assign(socket, :plans, plans)
  end

  defp fetch_plans(socket) do
    opts = build_title_filter_opts(socket.assigns.filter_title)

    case socket.assigns.selected_project_id do
      nil ->
        socket.assigns.projects
        |> Enum.flat_map(&Memory.list_plans(&1.id, opts))
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

      project_id ->
        Memory.list_plans(project_id, opts)
    end
  end

  defp build_title_filter_opts(nil), do: []
  defp build_title_filter_opts(title), do: [title: title]

  defp maybe_filter_latest_versions(plans, true), do: plans

  defp maybe_filter_latest_versions(plans, false) do
    plans
    |> Enum.group_by(& &1.title)
    |> Enum.map(fn {_title, versions} ->
      Enum.max_by(versions, & &1.inserted_at, DateTime)
    end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp filter_plans_by_search(plans, ""), do: plans

  defp filter_plans_by_search(plans, query) do
    query = String.downcase(query)
    Enum.filter(plans, &plan_matches_query?(&1, query))
  end

  defp plan_matches_query?(plan, query) do
    matches_field?(plan.title, query) ||
      matches_field?(plan.version, query) ||
      matches_field?(plan.body, query) ||
      matches_tags?(plan.tags, query)
  end

  defp matches_field?(nil, _query), do: false
  defp matches_field?(value, query), do: String.contains?(String.downcase(value), query)

  defp matches_tags?(nil, _query), do: false
  defp matches_tags?(tags, query), do: Enum.any?(tags, &matches_field?(&1, query))

  defp load_titles(socket) do
    titles =
      case socket.assigns.selected_project_id do
        nil ->
          socket.assigns.projects
          |> Enum.flat_map(fn project -> Memory.list_plan_titles(project.id) end)
          |> Enum.uniq()
          |> Enum.sort()

        project_id ->
          Memory.list_plan_titles(project_id)
      end

    assign(socket, :titles, titles)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.page_header title="Plans" subtitle="Versioned project documentation and roadmaps">
        <:actions>
          <.link_button navigate={~p"/pop_stash/plans/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> New Plan
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

        <form :if={@titles != []} phx-change="filter_title" class="flex-shrink-0">
          <select
            name="title"
            class="px-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
          >
            <option value="">All Plans</option>
            <option
              :for={title <- @titles}
              value={title}
              selected={@filter_title == title}
            >
              {title}
            </option>
          </select>
        </form>

        <button
          type="button"
          phx-click="toggle_versions"
          class={[
            "px-3 py-2 text-sm border rounded transition-colors flex-shrink-0",
            if(@show_all_versions,
              do: "bg-violet-50 border-violet-200 text-violet-700",
              else: "bg-white border-slate-200 text-slate-600 hover:bg-slate-50"
            )
          ]}
        >
          <%= if @show_all_versions do %>
            <.icon name="hero-eye" class="size-4 inline" /> All Versions
          <% else %>
            <.icon name="hero-eye-slash" class="size-4 inline" /> Latest Only
          <% end %>
        </button>

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
              placeholder="Search plans..."
              class="w-full pl-10 pr-3 py-2 text-sm bg-white border border-slate-200 rounded focus:outline-none focus:ring-2 focus:ring-violet-500/20 focus:border-violet-500"
              phx-debounce="300"
            />
          </div>
        </form>
      </div>
      
    <!-- Plan List -->
      <%= if @plans == [] do %>
        <.empty_state
          title="No plans found"
          description={
            if @search_query != "" || @filter_title,
              do: "Try adjusting your filters",
              else: "Create your first plan to get started"
          }
        >
          <:action>
            <.link_button
              :if={@search_query == "" && !@filter_title}
              navigate={~p"/pop_stash/plans/new"}
              variant="primary"
            >
              <.icon name="hero-plus" class="size-4" /> New Plan
            </.link_button>
          </:action>
        </.empty_state>
      <% else %>
        <.data_table id="plans-table" rows={@plans} row_id={&"plan-#{&1.id}"}>
          <:col :let={plan} label="Title" class="font-medium">
            <.link navigate={~p"/pop_stash/plans/#{plan.id}"} class="hover:text-violet-600">
              {plan.title}
            </.link>
          </:col>
          <:col :let={plan} label="Version">
            <span class="font-mono text-sm bg-slate-100 px-1.5 py-0.5 rounded">
              {plan.version}
            </span>
          </:col>
          <:col :let={plan} label="Preview">
            <.markdown_preview content={plan.body} max_length={150} />
          </:col>
          <:col :let={plan} label="Tags">
            <.tag_badges tags={plan.tags || []} />
          </:col>
          <:col :let={plan} label="Created" mono>
            <.timestamp datetime={plan.inserted_at} />
          </:col>
          <:col :let={plan} label="Actions" class="text-right">
            <div class="flex items-center justify-end gap-2">
              <.link_button
                navigate={~p"/pop_stash/plans/#{plan.id}"}
                variant="ghost"
                size="sm"
              >
                View
              </.link_button>
              <.link_button
                navigate={~p"/pop_stash/plans/#{plan.id}/edit"}
                variant="ghost"
                size="sm"
              >
                <.icon name="hero-pencil" class="size-4" />
              </.link_button>
              <.button
                variant="ghost"
                size="sm"
                phx-click="delete"
                phx-value-id={plan.id}
                data-confirm="Are you sure you want to delete this plan version?"
              >
                <.icon name="hero-trash" class="size-4 text-red-500" />
              </.button>
            </div>
          </:col>
        </.data_table>
      <% end %>
      
    <!-- New Plan Modal -->
      <.modal
        :if={@show_modal}
        id="plan-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="New Plan"
      >
        <.live_component
          module={PopStashWeb.Dashboard.PlanLive.FormComponent}
          id={:new}
          plan={@plan}
          projects={@projects}
          titles={@titles}
          action={:new}
          return_to={~p"/pop_stash/plans"}
        />
      </.modal>
    </div>
    """
  end
end
