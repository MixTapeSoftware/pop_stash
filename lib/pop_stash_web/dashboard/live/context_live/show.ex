defmodule PopStashWeb.Dashboard.ContextLive.Show do
  @moduledoc """
  LiveView for viewing a single context.
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

    {:ok, assign(socket, :current_path, "/pop_stash/contexts")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    context = Repo.get!(Memory.Context, id)
    project = Projects.get!(context.project_id)

    socket =
      socket
      |> assign(:page_title, context.name)
      |> assign(:context, context)
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
    case Memory.delete_context(socket.assigns.context.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Context deleted successfully")
         |> push_navigate(to: ~p"/pop_stash/contexts")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete context")}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/pop_stash/contexts/#{socket.assigns.context.id}")}
  end

  @impl true
  def handle_info({:context_updated, context}, socket) do
    if context.id == socket.assigns.context.id do
      {:noreply, assign(socket, :context, context)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:context_deleted, id}, socket) do
    if id == socket.assigns.context.id do
      {:noreply,
       socket
       |> put_flash(:info, "This context was deleted")
       |> push_navigate(to: ~p"/pop_stash/contexts")}
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
      <.back_link navigate={~p"/pop_stash/contexts"} label="Back to contexts" />

      <div class="mt-4">
        <.page_header title={@context.name} subtitle={"Project: #{@project.name}"}>
          <:actions>
            <.link_button navigate={~p"/pop_stash/contexts/#{@context.id}/edit"} variant="secondary">
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.link_button>
            <.button
              variant="danger"
              phx-click="delete"
              data-confirm="Are you sure you want to delete this context? This action cannot be undone."
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </.button>
          </:actions>
        </.page_header>
      </div>

      <div class="max-w-5xl">
        <!-- Main Content -->
        <.card>
          <.section_header title="Summary" />
          <.markdown content={@context.summary} />
        </.card>

        <%= if @context.files && @context.files != [] do %>
          <.card class="mt-6">
            <.section_header title="Files" />
            <ul class="space-y-1">
              <li :for={file <- @context.files} class="flex items-center gap-2 py-1">
                <.icon name="hero-document" class="size-4 text-slate-400" />
                <span class="font-mono text-sm text-slate-700">{file}</span>
              </li>
            </ul>
          </.card>
        <% end %>
        
    <!-- Details -->
        <.card class="mt-6">
          <dl class="divide-y divide-slate-100">
            <.detail_row label="ID">
              <span class="font-mono text-xs">{@context.id}</span>
            </.detail_row>

            <.detail_row label="Project">
              {@project.name}
            </.detail_row>

            <.detail_row label="Tags">
              <%= if @context.tags && @context.tags != [] do %>
                <.tag_badges tags={@context.tags} />
              <% else %>
                <span class="text-slate-400 text-sm">No tags</span>
              <% end %>
            </.detail_row>

            <.detail_row label="Expires At">
              <%= if @context.expires_at do %>
                <.timestamp datetime={@context.expires_at} />
              <% else %>
                <span class="text-slate-400 text-sm">Never</span>
              <% end %>
            </.detail_row>

            <.detail_row label="Created">
              <.timestamp datetime={@context.inserted_at} />
            </.detail_row>

            <.detail_row label="Updated">
              <.timestamp datetime={@context.updated_at} />
            </.detail_row>
          </dl>
        </.card>
      </div>
      
    <!-- Edit Modal -->
      <.modal
        :if={@show_modal}
        id="context-edit-modal"
        show={@show_modal}
        on_cancel={JS.push("close_modal")}
        title="Edit Context"
      >
        <.live_component
          module={PopStashWeb.Dashboard.ContextLive.FormComponent}
          id={@context.id}
          context={@context}
          projects={@projects}
          action={:edit}
          return_to={~p"/pop_stash/contexts/#{@context.id}"}
        />
      </.modal>
    </div>
    """
  end
end
