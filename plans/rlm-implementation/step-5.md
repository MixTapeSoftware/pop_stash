# Step 5: Add HTTP API routes and controllers

## Context

The execution script (ps-execute.sh) needs HTTP endpoints to coordinate plan execution. These endpoints handle plan CRUD and the atomic "get next step and mark in_progress" operation.

## Tasks

1. **Add routes to `lib/pop_stash_web/router.ex`**:

```elixir
scope "/api", PopStashWeb.API do
  pipe_through :api

  # Plans
  get "/plans", PlanController, :index
  post "/plans", PlanController, :create
  get "/plans/:id", PlanController, :show
  get "/plans/:id/next-step", PlanController, :next_step
  get "/plans/:id/steps", PlanController, :steps
  post "/plans/:id/steps", PlanController, :add_step
  
  # Steps
  get "/steps/:id", StepController, :show
  patch "/steps/:id", StepController, :update
end
```

2. **Create `lib/pop_stash_web/controllers/api/plan_controller.ex`**:
   - `index/2`: List plans, optional `?title=` filter, returns array
   - `create/2`: Create plan from `{title, body}`, returns plan with id
   - `show/2`: Get plan by id, returns plan details or 404
   - `next_step/2`: Atomic get-and-mark using `Memory.get_next_step_and_mark_in_progress/1`
     - Returns `{status: "next", step_id, step_number, description}` or `{status: "complete"}`
   - `steps/2`: List steps for plan
   - `add_step/2`: Add step to plan, accepts description, step_number, created_by, after_step, metadata

3. **Create `lib/pop_stash_web/controllers/api/step_controller.ex`**:
   - `show/2`: Get step by id, returns step details or 404
   - `update/2`: Update step status/result/metadata, returns updated step or 404

4. **Create JSON views or use Jason encoding** for responses

5. **Handle project_id**: Determine how to get project_id for API requests (header, path param, or default project)

## Dependencies

Requires step-2 (Memory context step functions) to be completed first.

## Acceptance

- All routes are accessible
- Test with curl:
  - `POST /api/plans` - create a plan
  - `GET /api/plans` - list plans
  - `GET /api/plans?title=X` - filter by title
  - `POST /api/plans/:id/steps` - add a step
  - `GET /api/plans/:id/steps` - list steps
  - `GET /api/plans/:id/next-step` - get next pending step (marks it in_progress)
  - `GET /api/plans/:id/next-step` again - returns the NEXT step (not same one)
  - `PATCH /api/steps/:id` - update step status
  - `GET /api/steps/:id` - get step details
- Concurrent `next-step` requests don't return same step (test race condition handling)
