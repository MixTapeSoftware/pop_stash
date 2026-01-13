defmodule PopStashWeb.Dashboard.StashLive.Show do
  @moduledoc """
  LiveView for viewing a single stash.
  """

  use PopStashWeb.Dashboard, :live_view

  alias PopStash.Memory
  alias PopStash.Projects
  alias PopStash.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")
    end

    {:ok, assign(socket, :current_path, "/pop_stash/stashes")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    stash = Repo.get!(Memory.Stash, id)
    project = Projects.get!(stash.project_id)

    socket =
      socket
      |> assign(:page_title, stash.name)
      |> assign(:stash, stash)
      |> assign(:project, project)
      |> assign(:projects, Projects.list())
      |> apply_action(socket.assigns.live_action)

    {:noreply, socket}
  end

  defp apply_action(socket, :show) do
    assign(socket, :show_modal, false)
  end

  defp apply_action(socket, :edit) do
    assign(socket, :show_modal, true)
  end

  @impl true
  def handle_event("delete", _, socket) do
    case Memory.delete_stash(socket.assigns.stash.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Stash deleted successfully")
         |> push_navigate(to: ~p"/pop_stash/stashes")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete stash")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/stashes/#{socket.assigns.stash.id}")}
  end

  @impl true
  def handle_info({:stash_updated, stash}, socket) do
    if stash.id == socket.assigns.stash.id do
      {:noreply, assign(socket, :stash, stash)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stash_deleted, id}, socket) do
    if id == socket.assigns.stash.id do
      {:noreply,
       socket
       |> put_flash(:info, "This stash was deleted")
       |> push_navigate(to: ~p"/pop_stash/stashes")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/pop_stash/stashes"} label="Back to stashes" />

      <div class="mt-4">
        <.page_header title={@stash.name} subtitle={"Project: #{@project.name}"}>
          <:actions>
            <.link_button navigate={~p"/pop_stash/stashes/#{@stash.id}/edit"} variant="secondary">
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.link_button>
            <.button
              variant="danger"
              phx-click="delete"
              data-confirm="Are you sure you want to delete this stash? This action cannot be undone."
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </.button>
          </:actions>
        </.page_header>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Main Content -->
        <div class="lg:col-span-2">
          <.card>
            <.section_header title="Summary" />
            <.markdown content={@stash.summary} />
          </.card>

          <%= if @stash.files && @stash.files != [] do %>
            <.card class="mt-6">
              <.section_header title="Files" />
              <ul class="space-y-1">
                <li :for={file <- @stash.files} class="flex items-center gap-2 py-1">
                  <.icon name="hero-document" class="size-4 text-slate-400" />
                  <span class="font-mono text-sm text-slate-700">{file}</span>
                </li>
              </ul>
            </.card>
          <% end %>
        </div>
        
    <!-- Sidebar -->
        <div class="space-y-6">
          <.card>
            <.section_header title="Details" />
            <dl class="divide-y divide-slate-100">
              <.detail_row label="ID">
                <span class="font-mono text-xs">{@stash.id}</span>
              </.detail_row>

              <.detail_row label="Project">
                {@project.name}
              </.detail_row>

              <.detail_row label="Tags">
                <%= if @stash.tags && @stash.tags != [] do %>
                  <.tag_badges tags={@stash.tags} />
                <% else %>
                  <span class="text-slate-400 text-sm">No tags</span>
                <% end %>
              </.detail_row>

              <.detail_row label="Expires At">
                <%= if @stash.expires_at do %>
                  <.timestamp datetime={@stash.expires_at} />
                <% else %>
                  <span class="text-slate-400 text-sm">Never</span>
                <% end %>
              </.detail_row>

              <.detail_row label="Created">
                <.timestamp datetime={@stash.inserted_at} />
              </.detail_row>

              <.detail_row label="Updated">
                <.timestamp datetime={@stash.updated_at} />
              </.detail_row>
            </dl>
          </.card>
        </div>
      </div>
      
    <!-- Edit Modal -->
      <.modal
        :if={@show_modal}
        id="stash-edit-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="Edit Stash"
      >
        <.live_component
          module={PopStashWeb.Dashboard.StashLive.FormComponent}
          id={@stash.id}
          stash={@stash}
          projects={@projects}
          action={:edit}
          return_to={~p"/pop_stash/stashes/#{@stash.id}"}
        />
      </.modal>
    </div>
    """
  end
end
