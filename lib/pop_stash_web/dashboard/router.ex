defmodule PopStashWeb.Dashboard.Router do
  @moduledoc """
  Router helpers for mounting the PopStash Dashboard.

  ## Usage

  In your router.ex:

      import PopStashWeb.Dashboard.Router

      scope "/pop_stash" do
        pipe_through [:browser, :admin_auth]  # You provide auth!
        pop_stash_dashboard "/"
      end

  ## Security

  ⚠️ **The dashboard provides NO authentication by default.**

  You MUST secure the dashboard routes yourself using your own
  authentication pipeline. Anyone who can access these routes
  can view and modify all stored memory data.
  """

  @doc """
  Generates routes for the PopStash Dashboard.

  ## Options

    * `:as` - the alias for the generated routes (default: `:pop_stash_dashboard`)
  """
  defmacro pop_stash_dashboard(path, _opts \\ []) do
    alias Phoenix.LiveView.Router, as: LiveRouter

    quote do
      scope unquote(path), alias: false, as: false do
        LiveRouter.live_session :pop_stash_dashboard,
          root_layout: {PopStashWeb.Dashboard.Layouts, :root},
          layout: {PopStashWeb.Dashboard.Layouts, :dashboard} do
          # Home
          LiveRouter.live("/", PopStashWeb.Dashboard.HomeLive, :index)

          # Projects
          LiveRouter.live("/projects", PopStashWeb.Dashboard.ProjectLive.Index, :index)

          LiveRouter.live(
            "/projects/new",
            PopStashWeb.Dashboard.ProjectLive.Index,
            :new
          )

          LiveRouter.live(
            "/projects/:id",
            PopStashWeb.Dashboard.ProjectLive.Show,
            :show
          )

          # Contexts
          LiveRouter.live("/contexts", PopStashWeb.Dashboard.ContextLive.Index, :index)

          LiveRouter.live(
            "/contexts/new",
            PopStashWeb.Dashboard.ContextLive.Index,
            :new
          )

          LiveRouter.live(
            "/contexts/:id",
            PopStashWeb.Dashboard.ContextLive.Show,
            :show
          )

          LiveRouter.live(
            "/contexts/:id/edit",
            PopStashWeb.Dashboard.ContextLive.Show,
            :edit
          )

          # Insights
          LiveRouter.live(
            "/insights",
            PopStashWeb.Dashboard.InsightLive.Index,
            :index
          )

          LiveRouter.live(
            "/insights/new",
            PopStashWeb.Dashboard.InsightLive.Index,
            :new
          )

          LiveRouter.live(
            "/insights/:id",
            PopStashWeb.Dashboard.InsightLive.Show,
            :show
          )

          LiveRouter.live(
            "/insights/:id/edit",
            PopStashWeb.Dashboard.InsightLive.Show,
            :edit
          )

          # Decisions
          LiveRouter.live(
            "/decisions",
            PopStashWeb.Dashboard.DecisionLive.Index,
            :index
          )

          LiveRouter.live(
            "/decisions/new",
            PopStashWeb.Dashboard.DecisionLive.Index,
            :new
          )

          LiveRouter.live(
            "/decisions/:id",
            PopStashWeb.Dashboard.DecisionLive.Show,
            :show
          )

          LiveRouter.live(
            "/decisions/:id/edit",
            PopStashWeb.Dashboard.DecisionLive.Show,
            :edit
          )

          # Plans
          LiveRouter.live(
            "/plans",
            PopStashWeb.Dashboard.PlanLive.Index,
            :index
          )

          LiveRouter.live(
            "/plans/new",
            PopStashWeb.Dashboard.PlanLive.Index,
            :new
          )

          LiveRouter.live(
            "/plans/:id",
            PopStashWeb.Dashboard.PlanLive.Show,
            :show
          )

          LiveRouter.live(
            "/plans/:id/edit",
            PopStashWeb.Dashboard.PlanLive.Show,
            :edit
          )

          # Searches
          LiveRouter.live(
            "/searches",
            PopStashWeb.Dashboard.SearchLive.Index,
            :index
          )
        end
      end
    end
  end
end
