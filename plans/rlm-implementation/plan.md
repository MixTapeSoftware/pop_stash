# RLM (Reinforcement Learning from Multi-step Feedback) Implementation Plan

## Overview

Implement RLM support in PopStash to allow Claude to execute multi-step plans iteratively, discovering and adding new steps as needed, with full access to PopStash's memory system (insights, decisions, plans) for context.

## Key Design Decisions

Based on user requirements:
- **No revisions/versioning**: Simplify plans - remove thread_id concept and revision tracking
- **Direct plan-to-steps relationship**: Steps reference a plan via `plan_id` (not thread_id)
- **Mutable steps**: Steps can be updated (status, result) during execution
- **No step versioning**: Steps don't have thread_ids
- **Linear execution**: No branching or rollback support (for now)

## Database Changes

### 1. Simplify Plans Schema

**Migration: Remove thread_id from plans**
- Remove `thread_id` field from `plans` table
- Remove thread-related code from `Plan` schema
- Plans become simpler: just id, title, body, tags, files, project_id

**Files to modify:**
- `priv/repo/migrations/[timestamp]_remove_thread_from_plans.exs` (new)
- `lib/pop_stash/memory/plan.ex`

### 2. Create PlanSteps Schema

**Migration: Create plan_steps table**

```elixir
create table(:plan_steps) do
  add :plan_id, references(:plans, on_delete: :delete_all), null: false
  add :step_number, :float, null: false  # Float allows insertion (2.5 between 2 and 3)
  add :description, :text, null: false
  add :status, :string, default: "pending"  # pending | in_progress | completed | failed
  add :result, :text  # Execution result/notes
  add :created_by, :string, default: "user"  # "user" | "agent" - tracks who created the step
  add :metadata, :map, default: %{}  # For extensibility
  add :project_id, references(:projects, on_delete: :delete_all), null: false
  
  timestamps()
end

create index(:plan_steps, [:plan_id])
create index(:plan_steps, [:project_id])
create index(:plan_steps, [:status])
create unique_index(:plan_steps, [:plan_id, :step_number])
```

**New schema file:**
- `lib/pop_stash/memory/plan_step.ex`

### 3. Update Plan Schema

Add association to steps:
```elixir
schema "plans" do
  # existing fields...
  has_many(:steps, PopStash.Memory.PlanStep)
end
```

## Core Logic Updates

### 1. Memory Context (`lib/pop_stash/memory.ex`)

Add functions for plan step management:

```elixir
# Create a step (appends to end or inserts after a specific step)
def add_plan_step(plan_id, description, opts \\ [])
# opts:
#   - after_step: float - insert after this step number (calculates midpoint)
#   - created_by: "user" | "agent" - defaults to "user"
#   - metadata: map

# Get next pending step for a plan (does not mutate status)
def get_next_plan_step(plan_id)

# Get next pending step and mark it as in_progress (atomic operation for HTTP API)
def get_next_step_and_mark_in_progress(plan_id)

# Update step status and result
def update_plan_step(step_id, attrs)

# List all steps for a plan (ordered by step_number)
def list_plan_steps(plan_id, opts \\ [])

# Get a specific step by step_number
def get_plan_step(plan_id, step_number)

# Get a step by its id
def get_plan_step_by_id(step_id)

# List all plans for a project (used by HTTP API)
def list_plans(project_id, opts \\ [])
# opts:
#   - title: filter by exact title match
```

Key implementation notes:
- `step_number` is a float to allow insertion (e.g., 2.5 between 2 and 3)
- `add_plan_step` with `after_step: N`:
  - Find step N and the next step's number
  - New step_number = midpoint (e.g., after 2, next is 3 → 2.5)
  - If no next step, add 1.0 to the after_step value
- `add_plan_step` without `after_step`: query `max(step_number)` and add 1.0
- Handle concurrent step additions properly
- Validate status transitions (pending → in_progress → completed/failed)
- `get_next_step_and_mark_in_progress` is an atomic operation used by the HTTP API to prevent race conditions
- `list_plan_steps` accepts optional filters (e.g., `status: "pending"`) and always orders by step_number

### 2. Simplify Plan Functions

Remove thread_id logic from:
- `create_plan/4` - no longer needs thread_id option
- `get_plan/2` - simpler lookup
- Remove `get_plan_by_thread/2`
- Remove `list_plan_revisions/2` 
- Remove `list_plan_thread/2`
- Simplify `list_plan_titles/1`

## MCP Tools

### 1. Update Existing Tools

**save_plan** (`lib/pop_stash/mcp/tools/save_plan.ex`):
- Remove `thread_id` parameter
- Simplify description (no mention of revisions/threads)
- Return `plan_id` in the tool response (standard MCP return value)

**get_plan** (`lib/pop_stash/mcp/tools/get_plan.ex`):
- Remove `all_revisions` parameter
- Remove thread-related logic
- Simplify to just title lookup

**search_plans** - no changes needed

### 2. New Step Management Tools

**add_step** (`lib/pop_stash/mcp/tools/add_step.ex`):
```elixir
Parameters:
  - plan_id (required): ID of the plan
  - description (required): What this step does
  - after_step (optional): Insert after this step number (float). If omitted, appends to end.
  - step_number (optional): Explicit step number (float). Use when ingesting from files with known ordering.
  - created_by (optional): "user" | "agent" - defaults to "agent" for MCP calls
  - metadata (optional): Additional context

Returns: Created step with step_number, id, and created_by

Notes:
  - When after_step is provided, calculates midpoint between that step and the next
  - e.g., after_step: 2, next is 3 → new step is 2.5
  - e.g., after_step: 2.5, next is 3 → new step is 2.75
  - When step_number is provided explicitly, uses that value directly (for file-based ingestion)
  - If neither after_step nor step_number is provided, appends to end (max + 1.0)
```

**update_step** (`lib/pop_stash/mcp/tools/update_step.ex`):
```elixir
Parameters:
  - step_id (required): ID of the step
  - status (optional): completed | failed (note: in_progress is set automatically by HTTP API)
  - result (optional): Execution result/notes
  - metadata (optional): Additional context

Returns: Updated step

Notes:
  - Status transitions: pending → in_progress (automatic via HTTP API) → completed/failed (via this tool)
  - The MCP tool should only be used to mark steps completed or failed, not to set in_progress
```

**peek_next_step** (`lib/pop_stash/mcp/tools/peek_next_step.ex`):
```elixir
Parameters:
  - plan_id (required): ID of the plan

Returns: Next pending step (without changing status), or message if none left

Note: This is a read-only tool for manual inspection/debugging. It does NOT mark 
the step as in_progress. The ps-execute script uses the HTTP API endpoint 
`GET /plans/:id/next-step` instead, which atomically marks the step in_progress.
Useful for checking plan status after failures or when resuming work manually.
```

**get_plan_steps** (`lib/pop_stash/mcp/tools/get_plan_steps.ex`):
```elixir
Parameters:
  - plan_id (required): ID of the plan
  - status (optional): Filter by status

Returns: Compact list showing step_number, status, created_by, step_id for each step
         (minimal output for quick overview, agent uses this to figure out next steps)

Example output:
  Steps for plan "Feature Implementation":
  1.   [pending]     user   step_abc123 - Setup database schema
  2.   [completed]   user   step_def456 - Create migrations
  2.5  [pending]     agent  step_xyz789 - Add missing index (inserted by agent)
  3.   [in_progress] user   step_ghi789 - Add business logic
  4.   [pending]     user   step_jkl012 - Write tests
```

**get_step** (`lib/pop_stash/mcp/tools/get_step.ex`):
```elixir
Parameters:
  - step_id (required): ID of the step

Returns: Step details including plan_id, step_number, description, status, result, metadata
```

## Tool Registration

Update `lib/pop_stash/mcp/server.ex` (or wherever tools are registered) to include new step tools.

## Planning Phase

**Key Principle: Separate Planning from Execution**

Planning is an interactive, iterative process where the user works with a **planner agent** to refine the plan and break it into well-scoped steps. Only after the user is satisfied with the plan do they submit it for execution.

### File-Based Plan Structure

Plans live in the project repository under `plans/`:

```
plans/
└── feature-auth/
    ├── plan.md          # Overall plan with ## Steps section
    ├── step-0.md        # Step 0: Setup database schema
    ├── step-1.md        # Step 1: Create migrations
    ├── step-2.md        # Step 2: Add business logic (refs step-1)
    └── step-3.md        # Step 3: Write tests
```

### plan.md Format

```markdown
# Feature: User Authentication

## Overview
Add JWT-based authentication with refresh tokens...

## Steps
- step-0: Setup database schema for users and tokens
- step-1: Create Ecto migrations (depends: step-0)
- step-2: Add authentication business logic
- step-3: Write tests (depends: step-2)
```

### step-N.md Format

```markdown
# Step 0: Setup database schema

## Context
This step creates the foundational schema for auth...

## Tasks
- Define User schema with email, password_hash
- Define Token schema with refresh token fields
- Add indexes for email lookup

## Dependencies
None (or: Requires step-1 to be completed first)

## Acceptance
- Schemas compile without errors
- Fields match the auth design doc
```

### Planner Agent

The planner agent helps users:
1. **Create the overall plan** - Draft the plan.md with overview and goals
2. **Break down into steps** - Identify discrete, orthogonal units of work
3. **Ensure proper scoping** - Each step should have minimal context requirements
4. **Identify dependencies** - Mark which steps depend on others
5. **Write step files** - Generate step-N.md files with clear context, tasks, and acceptance criteria

The planner agent is invoked via `/ps-plan` and operates interactively until the user is satisfied.

### Slash Commands

- `/ps-plan [plan-name]` - Start or continue planning with the planner agent
  - If plan-name exists, opens that plan for editing
  - If new, creates `plans/<plan-name>/` directory structure
  - Interactive session to refine plan and steps
  
- `/ps-plans` - Browse all plans and their execution status
  - Lists plans from both local `plans/` directory and PopStash API
  - Shows which plans have been submitted, step completion status
  - Example output:
    ```
    Local Plans:
      feature-auth/     [not submitted]
      bug-fix-123/      [submitted] 3/5 steps complete
      
    Submitted Plans (PopStash):
      refactor-api      [completed] 4/4 steps
      add-caching       [in_progress] 2/6 steps (step 3 failed)
    ```

- `/ps-execute <plan-name>` - Submit a plan to PopStash and start execution
  - Reads `plans/<plan-name>/plan.md` and all `step-N.md` files
  - Saves plan to PopStash via `save_plan`
  - Creates steps via `add_step` for each step file
  - Begins execution loop

## Execution Model

**Key Principle: Fresh Context Per Step**

Each step executes in a **separate Claude session** with only that step's file content in context. The full plan is never loaded during step execution. This:
- Minimizes token usage
- Keeps the agent focused on the immediate task
- Prevents context window bloat on large plans

**On-demand context**: During step execution, Claude can pull additional context if needed:
- `get_plan_steps` - Quick overview of all steps (step_number, status, step_id)
- `recall` - Query insights about the codebase
- `get_decisions` - Check architectural decisions
- `search_plans` - Find related plans
- `get_plan` - Load the full plan body (use sparingly)

**Execution is orchestrated by the script, not by Claude:**

1. **User runs**: `/ps-execute feature-auth`
2. **Submission phase**:
   - Script reads `plans/feature-auth/plan.md`
   - Script reads all `plans/feature-auth/step-N.md` files
   - Script calls `save_plan` with plan.md content → gets `plan_id`
   - Script calls `add_step` for each step file
3. **Execution loop** (one step per session):
   - Script calls HTTP API: `GET /api/plans/:id/next-step`
   - If step found: script spawns Claude with step file content as prompt
   - Claude executes the step
   - Claude marks complete: `update_step(step_id, status: "completed", result: "...")`
   - Session ends, script loops back
4. **Completion**: When API returns no pending steps, script exits with success message

**Error handling**: If a step fails, Claude calls `update_step(step_id, status: "failed", result: "...")`. Script detects this and halts, allowing user to fix and resume.

## Claude Plugin for RLM Planning and Execution

**Goal**: Package the RLM planning and execution system as an installable Claude plugin.

### Plugin Structure

```
popstash-plugin/
├── plugin.json           # Plugin metadata
├── scripts/
│   ├── ps-plan.sh        # Planning session orchestration
│   ├── ps-plans.sh       # Browse plans and status
│   └── ps-execute.sh     # Submit and execute plans
├── agents/
│   └── planner.md        # Planner agent prompt/instructions
├── README.md             # Plugin documentation
└── .claude/
    └── rules.md          # PopStash rules for Claude
```

### plugin.json

```json
{
  "name": "popstash",
  "version": "0.1.0",
  "description": "PopStash integration for Claude - planning, memory management, and RLM execution",
  "author": "PopStash",
  "hooks": {
    "SessionStart": [
      {
        "type": "prompt",
        "prompt": "Before starting work, search for previous decisions and insights that might apply to this task."
      }
    ],
    "Stop": [
      {
        "type": "prompt",
        "prompt": "If meaningful work occurred: record insights and document decisions."
      }
    ]
  },
  "requirements": {
    "mcp_servers": ["pop_stash"]
  },
  "skills": {
    "ps-plan": {
      "description": "Start or continue planning with the planner agent",
      "prompt_file": "{{PLUGIN_DIR}}/agents/planner.md"
    },
    "ps-plans": {
      "description": "Browse all plans and their execution status",
      "script": "{{PLUGIN_DIR}}/scripts/ps-plans.sh"
    },
    "ps-execute": {
      "description": "Submit a plan to PopStash and start execution",
      "script": "{{PLUGIN_DIR}}/scripts/ps-execute.sh"
    }
  }
}
```

### Planner Agent (agents/planner.md)

```markdown
# PopStash Planner Agent

You are a planning assistant that helps users create well-structured, executable plans.

## Your Role

Help the user:
1. Define the overall goal and scope of their plan
2. Break the work into discrete, orthogonal steps
3. Ensure each step has minimal context requirements
4. Identify dependencies between steps
5. Write clear step files with context, tasks, and acceptance criteria

## File Structure

Plans are stored in `plans/<plan-name>/`:
- `plan.md` - Overall plan with overview and step list
- `step-0.md`, `step-1.md`, etc. - Individual step files

## Guidelines for Good Steps

- **Orthogonal context**: Each step should be executable with minimal knowledge of other steps
- **Clear acceptance criteria**: Define what "done" looks like
- **Right-sized**: Not too big (overwhelming) or too small (trivial)
- **Self-contained instructions**: Include enough context that a fresh Claude session can execute it

## Workflow

1. Ask the user what they want to accomplish
2. Help draft the plan.md with overview and step list
3. For each step, create a step-N.md file with:
   - Context: What this step is about
   - Tasks: Specific things to do
   - Dependencies: What must be done first
   - Acceptance: How to know it's done
4. Review the full plan with the user
5. Iterate until they're satisfied

## Commands

- "show plan" - Display current plan.md
- "show step N" - Display step-N.md
- "add step" - Add a new step
- "edit step N" - Modify an existing step
- "done" - Finalize planning session

When the user says "done", summarize the plan and remind them to run `/ps-execute <plan-name>` to begin execution.
```

### ps-execute.sh (Execution orchestration script)

```bash
#!/bin/bash
# ps-execute.sh - Submit a plan to PopStash and execute it
# Usage:
#   ps-execute <plan-name>           # Submit and execute a plan from plans/<plan-name>/
#   ps-execute --resume <plan_id>    # Resume an existing plan
#
# Environment:
#   POPSTASH_API - API base URL (default: http://localhost:4001/api)
#   PLANS_DIR    - Local plans directory (default: plans)
#
# Dependencies: jq, curl, claude
set -e

POPSTASH_API="${POPSTASH_API:-http://localhost:4001/api}"
PLANS_DIR="${PLANS_DIR:-plans}"

# Parse arguments
if [[ "$1" == "--resume" ]]; then
  if [[ -z "$2" ]]; then
    echo "Usage: ps-execute --resume <plan_id>"
    exit 1
  fi
  PLAN_ID="$2"
  echo "Resuming plan: $PLAN_ID"
else
  PLAN_NAME="$1"
  
  if [[ -z "$PLAN_NAME" ]]; then
    echo "Usage:"
    echo "  ps-execute <plan-name>           # Submit and execute"
    echo "  ps-execute --resume <plan_id>    # Resume existing plan"
    exit 1
  fi
  
  PLAN_DIR="$PLANS_DIR/$PLAN_NAME"
  PLAN_FILE="$PLAN_DIR/plan.md"
  
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo "Error: Plan not found at $PLAN_FILE"
    echo "Run /ps-plan $PLAN_NAME to create it first."
    exit 1
  fi
  
  # Read plan.md content
  PLAN_CONTENT=$(cat "$PLAN_FILE")
  
  # Submit plan to PopStash
  echo "Submitting plan to PopStash..."
  PLAN_RESPONSE=$(curl -sf -X POST "$POPSTASH_API/plans" \
    -H "Content-Type: application/json" \
    -d "{\"title\": \"$PLAN_NAME\", \"body\": $(echo "$PLAN_CONTENT" | jq -Rs .)}")
  
  PLAN_ID=$(echo "$PLAN_RESPONSE" | jq -r '.id')
  
  if [[ -z "$PLAN_ID" || "$PLAN_ID" == "null" ]]; then
    echo "Error: Failed to create plan in PopStash"
    exit 1
  fi
  
  echo "Plan created: $PLAN_ID"
  
  # Find and submit all step files (preserving step numbers from filenames)
  echo "Ingesting steps into PopStash..."
  STEP_COUNT=0
  for STEP_FILE in "$PLAN_DIR"/step-*.md; do
    if [[ -f "$STEP_FILE" ]]; then
      STEP_NUM=$(basename "$STEP_FILE" | sed 's/step-\([0-9]*\)\.md/\1/')
      STEP_CONTENT=$(cat "$STEP_FILE")
      
      # Pass step_number explicitly to preserve file-based ordering
      curl -sf -X POST "$POPSTASH_API/plans/$PLAN_ID/steps" \
        -H "Content-Type: application/json" \
        -d "{\"description\": $(echo "$STEP_CONTENT" | jq -Rs .), \"step_number\": $STEP_NUM, \"created_by\": \"user\"}" > /dev/null
      
      echo "  Added step $STEP_NUM"
      STEP_COUNT=$((STEP_COUNT + 1))
    fi
  done
  
  echo ""
  echo "NOTE: Your $STEP_COUNT steps have been ingested as a starting point."
  echo "      During execution, agents may discover and insert additional steps."
  echo "      Use '/ps-plans' to see the final step count after execution."
  echo ""
  echo "Starting execution..."
fi

# Step execution loop
while true; do
  # Get next pending step via HTTP API (marks it as in_progress)
  RESPONSE=$(curl -sf "$POPSTASH_API/plans/$PLAN_ID/next-step")
  STATUS=$(echo "$RESPONSE" | jq -r '.status')
  
  if [[ "$STATUS" == "complete" ]]; then
    echo ""
    echo "All steps complete!"
    exit 0
  fi
  
  STEP_ID=$(echo "$RESPONSE" | jq -r '.step_id')
  STEP_DESC=$(echo "$RESPONSE" | jq -r '.description')
  STEP_NUM=$(echo "$RESPONSE" | jq -r '.step_number')
  
  echo ""
  echo "Executing step $STEP_NUM..."
  echo "(Plan ID: $PLAN_ID - use '/ps-execute --resume $PLAN_ID' to resume if interrupted)"
  echo ""
  
  # Spawn fresh Claude session with step content as prompt
  claude -p "Execute this task:

$STEP_DESC

Instructions:
- When complete, call update_step with step_id='$STEP_ID', status='completed', and a brief result summary.
- If you cannot complete the task, call update_step with status='failed' and explain why in the result.
- If you discover additional work is needed, you can insert a new step using add_step with after_step=$STEP_NUM.
  The new step will execute after this one completes. Only add steps for truly necessary work."

  # Check step status after execution
  STEP_STATUS=$(curl -sf "$POPSTASH_API/steps/$STEP_ID" | jq -r '.status')
  
  if [[ "$STEP_STATUS" == "failed" ]]; then
    echo ""
    echo "Step $STEP_NUM failed."
    echo "Fix the issue and run '/ps-execute --resume $PLAN_ID' to continue."
    exit 1
  fi

  echo "Step $STEP_NUM complete"
done
```

### ps-plans.sh (Plan browser script)

```bash
#!/bin/bash
# ps-plans.sh - Browse local and submitted plans with their status
#
# Environment:
#   POPSTASH_API - API base URL (default: http://localhost:4001/api)
#   PLANS_DIR    - Local plans directory (default: plans)
#
# Dependencies: jq, curl
set -e

POPSTASH_API="${POPSTASH_API:-http://localhost:4001/api}"
PLANS_DIR="${PLANS_DIR:-plans}"

echo "=== Local Plans ==="
echo ""

if [[ -d "$PLANS_DIR" ]]; then
  for PLAN_DIR in "$PLANS_DIR"/*/; do
    if [[ -d "$PLAN_DIR" ]]; then
      PLAN_NAME=$(basename "$PLAN_DIR")
      STEP_COUNT=$(ls -1 "$PLAN_DIR"step-*.md 2>/dev/null | wc -l | tr -d ' ')
      
      # Check if this plan has been submitted (by title match)
      # API returns an array, so we extract the first match's id
      SUBMITTED=$(curl -sf "$POPSTASH_API/plans?title=$PLAN_NAME" | jq -r '.[0].id // empty')
      
      if [[ -n "$SUBMITTED" ]]; then
        # Get step status from API
        STEPS_INFO=$(curl -sf "$POPSTASH_API/plans/$SUBMITTED/steps")
        TOTAL=$(echo "$STEPS_INFO" | jq 'length')
        COMPLETED=$(echo "$STEPS_INFO" | jq '[.[] | select(.status == "completed")] | length')
        FAILED=$(echo "$STEPS_INFO" | jq '[.[] | select(.status == "failed")] | length')
        
        if [[ "$FAILED" -gt 0 ]]; then
          echo "  $PLAN_NAME/  [submitted] $COMPLETED/$TOTAL steps (has failures)"
        elif [[ "$COMPLETED" -eq "$TOTAL" ]]; then
          echo "  $PLAN_NAME/  [completed] $TOTAL/$TOTAL steps"
        else
          echo "  $PLAN_NAME/  [in_progress] $COMPLETED/$TOTAL steps"
        fi
      else
        echo "  $PLAN_NAME/  [not submitted] $STEP_COUNT steps"
      fi
    fi
  done
else
  echo "  No plans/ directory found"
fi

echo ""
echo "=== Submitted Plans (PopStash) ==="
echo ""

# Get all plans from PopStash
PLANS=$(curl -sf "$POPSTASH_API/plans" 2>/dev/null || echo "[]")

if [[ "$PLANS" == "[]" ]]; then
  echo "  No plans in PopStash"
else
  echo "$PLANS" | jq -r '.[] | "\(.id) \(.title)"' | while read -r PLAN_ID PLAN_TITLE; do
    STEPS_INFO=$(curl -sf "$POPSTASH_API/plans/$PLAN_ID/steps")
    TOTAL=$(echo "$STEPS_INFO" | jq 'length')
    COMPLETED=$(echo "$STEPS_INFO" | jq '[.[] | select(.status == "completed")] | length')
    FAILED=$(echo "$STEPS_INFO" | jq '[.[] | select(.status == "failed")] | length')
    
    if [[ "$FAILED" -gt 0 ]]; then
      echo "  $PLAN_TITLE  [has failures] $COMPLETED/$TOTAL steps  (id: $PLAN_ID)"
    elif [[ "$COMPLETED" -eq "$TOTAL" ]]; then
      echo "  $PLAN_TITLE  [completed] $TOTAL/$TOTAL steps"
    else
      echo "  $PLAN_TITLE  [in_progress] $COMPLETED/$TOTAL steps  (id: $PLAN_ID)"
    fi
  done
fi
```

**Key design points**:
- **Two modes for ps-execute**: Start fresh with a plan name OR resume with `--resume <plan_id>`
- **File-based submission**: Reads plan.md and step-*.md files, submits to PopStash API
- **Resumable**: If execution fails or is interrupted, use `--resume` to continue
- **Fresh context per step** - each `claude -p` invocation is a new session
- **ps-plans browser**: Shows both local and submitted plans with completion status
- **HTTP API for coordination** - scripts query PopStash for state

### HTTP API Routes

**New router** (`lib/pop_stash_web/router.ex`):

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

**Controller** (`lib/pop_stash_web/controllers/api/plan_controller.ex`):

- `index/2`:
  - Calls `Memory.list_plans(project_id, opts)`
  - Returns list of plans with id, title, inserted_at
  - Supports optional `?title=` query param for exact title match (returns filtered list, not single object)

- `create/2`:
  - Accepts `%{"title" => ..., "body" => ...}`
  - Calls `Memory.create_plan(project_id, title, body)`
  - Returns created plan with id

- `show/2`:
  - Calls `Memory.get_plan(project_id, id)`
  - Returns plan details
  - Returns 404 if not found

- `next_step/2`:
  - Calls `Memory.get_next_step_and_mark_in_progress(plan_id)` to atomically fetch and mark
  - If step found: return `%{status: "next", step_id: ..., step_number: ..., description: ...}`
  - If no pending steps: return `%{status: "complete"}`
  - If plan not found: return 404

- `steps/2`:
  - Calls `Memory.list_plan_steps(plan_id)`
  - Returns list of steps with id, step_number, status, description

- `add_step/2`:
  - Accepts `%{"description" => ..., "step_number" => ..., "created_by" => ..., "after_step" => ..., "metadata" => ...}`
  - Only `description` is required; others are optional
  - Calls `Memory.add_plan_step(plan_id, description, opts)`
  - Returns created step with id and step_number

**Controller** (`lib/pop_stash_web/controllers/api/step_controller.ex`):

- `show/2`:
  - Calls `Memory.get_plan_step_by_id(step_id)`
  - Returns step details including status
  - Returns 404 if not found

- `update/2`:
  - Accepts `%{"status" => ..., "result" => ..., "metadata" => ...}` (all optional)
  - Calls `Memory.update_plan_step(step_id, attrs)`
  - Returns updated step
  - Returns 404 if not found
  - Note: This is used by Claude (via MCP) to mark steps completed/failed

### User Flow

```bash
# 1. Start planning (interactive session with planner agent)
$ /ps-plan feature-auth

# Planner helps you:
# - Define the goal and scope
# - Break into discrete steps
# - Write plan.md and step-0.md, step-1.md, etc.
# - Review and iterate until satisfied
# - End with "done" to finalize

# 2. Review your plan (optional)
$ cat plans/feature-auth/plan.md
$ cat plans/feature-auth/step-0.md

# 3. Browse all plans and their status
$ /ps-plans

# Output:
# === Local Plans ===
#   feature-auth/     [not submitted] 4 steps
#   bug-fix-123/      [submitted] 3/5 steps complete
#
# === Submitted Plans (PopStash) ===
#   refactor-api      [completed] 4/4 steps

# 4. Submit and execute
$ /ps-execute feature-auth

# Submitting plan to PopStash...
# Plan created: plan_abc123
# Ingesting steps into PopStash...
#   Added step 0
#   Added step 1
#   Added step 2
#   Added step 3
#
# NOTE: Your 4 steps have been ingested as a starting point.
#       During execution, agents may discover and insert additional steps.
#       Use '/ps-plans' to see the final step count after execution.
#
# Starting execution...
#
# Executing step 0...
# (Plan ID: plan_abc123 - use '/ps-execute --resume plan_abc123' to resume)
# [Claude executes step 0 in fresh session]
# Step 0 complete
#
# Executing step 1...
# [Claude executes step 1 in fresh session]
# Step 1 complete
#
# ... continues until all steps done ...
#
# All steps complete!

# 5. If interrupted or failed, resume
$ /ps-execute --resume plan_abc123
```

## Migration Strategy

1. Create migration to remove `thread_id` from plans
2. Create migration for `plan_steps` table
3. Update `Plan` schema and remove `thread_prefix/0`
4. Update `Memory` context functions
5. Create `PlanStep` schema
6. Update existing MCP tools (`save_plan`, `get_plan`)
7. Create new MCP step tools
8. Update PopStash documentation in `.claude/rules/popstash.md`

## Testing Strategy

1. **Unit tests** for Memory context functions:
   - `test/pop_stash/memory_test.exs` - add tests for step CRUD operations
   - Test step_number auto-increment
   - Test status transitions
   - Test concurrent step additions

2. **Integration tests** for MCP tools:
   - Test full execution flow: create plan → add steps → get next → update → repeat
   - Test error cases: invalid status, missing plan_id
   - Test step discovery: adding steps mid-execution

3. **Manual testing** via MCP client:
   - Create a simple multi-step plan
   - Execute steps one by one
   - Add steps dynamically
   - Query context during execution

## Critical Files

**Core Logic**:
- `lib/pop_stash/memory.ex` - Add step CRUD functions: `add_plan_step`, `get_next_plan_step`, `get_next_step_and_mark_in_progress`, `update_plan_step`, `list_plan_steps`, `get_plan_step`, `get_plan_step_by_id`, `list_plans`
- `lib/pop_stash/memory/plan.ex` - Schema update (remove thread_id, add has_many :steps)
- `lib/pop_stash/memory/plan_step.ex` - New schema

**MCP Tools** (updated):
- `lib/pop_stash/mcp/tools/save_plan.ex` - Remove thread_id parameter
- `lib/pop_stash/mcp/tools/get_plan.ex` - Remove thread_id logic

**MCP Tools** (new):
- `lib/pop_stash/mcp/tools/add_step.ex`
- `lib/pop_stash/mcp/tools/update_step.ex`
- `lib/pop_stash/mcp/tools/peek_next_step.ex`
- `lib/pop_stash/mcp/tools/get_plan_steps.ex`
- `lib/pop_stash/mcp/tools/get_step.ex`

**HTTP API** (new):
- `lib/pop_stash_web/controllers/api/plan_controller.ex` - Plan CRUD and step management endpoints
- `lib/pop_stash_web/controllers/api/step_controller.ex` - Step lookup endpoint
- `lib/pop_stash_web/router.ex` - Add `/api/plans` and `/api/steps` routes

**Migrations**:
- `priv/repo/migrations/[timestamp]_remove_thread_from_plans.exs`
- `priv/repo/migrations/[timestamp]_create_plan_steps.exs`

**Plugin Package** (new repo: popstash-plugin):
- `plugin.json` - Plugin metadata with skills and hooks
- `scripts/ps-plan.sh` - Planning session orchestration (optional, may just use prompt_file)
- `scripts/ps-plans.sh` - Browse plans and execution status
- `scripts/ps-execute.sh` - Submit and execute plans
- `agents/planner.md` - Planner agent prompt/instructions
- `.claude/rules.md` - PopStash rules for Claude
- `README.md` - Plugin installation and usage documentation

**Note on Plugin Hooks**: 
- The SessionStart and Stop hooks fire during **all** Claude sessions, including RLM step execution sessions
- **During RLM execution**: The Stop hook will prompt Claude to record insights/decisions after each step, which is desirable - each step may discover useful information worth preserving
- **SessionStart hook**: Reminds Claude to check for relevant context before starting each step, encouraging use of `recall`, `get_decisions`, etc.
- The hooks and scripts are complementary: hooks provide gentle reminders, scripts orchestrate workflows

**User-facing** (main PopStash repo):
- `README.md` - Add tools table, plugin installation section, RLM workflow documentation
- `.claude/rules/popstash.md` - Update with step tools and RLM pattern

## Verification

### Core Functionality

1. Run migrations: `mix ecto.migrate`
2. Run tests: `mix test`
3. Manual verification via MCP:
   - Create a plan: `save_plan(title: "Test", body: "...")`
   - Add steps: `add_step(plan_id: "...", description: "Step 1")`
   - Execute loop: `get_next_step → update_step → get_next_step...`
4. Verify context queries work during execution: `recall`, `get_decisions`, `search_plans`
5. Test HTTP API endpoint:
   - `GET /api/plans/:id/next-step` - verify it returns next step and marks it in_progress
   - Verify concurrent requests to same plan don't return duplicate steps
   - Verify it returns `{status: "complete"}` when no steps remain
6. Run precommit: `mix precommit`

### Plugin Testing

1. Create plugin repository structure
2. Test ps-execute script manually:
   - Create a test plan directory (e.g., `plans/test-plan/` with `plan.md` and `step-*.md` files)
   - Run `./scripts/ps-execute.sh test-plan`
   - Verify plan is saved to PopStash and steps are ingested with correct step numbers
   - Verify each step executes in fresh session
3. Test full plugin workflow:
   - Install plugin in test project
   - Run `/ps-execute test-plan`
   - Verify steps execute sequentially with fresh context
   - Verify completion message when all steps done
4. Test resume functionality:
   - Interrupt execution mid-plan (Ctrl+C)
   - Run `/ps-execute --resume <plan_id>`
   - Verify execution continues from next pending step
## Steps

- step-0: Remove thread_id from plans schema and update Plan module
- step-1: Create plan_steps table and PlanStep schema
- step-2: Add step management functions to Memory context
- step-3: Update existing MCP tools (save_plan, get_plan)
- step-4: Create new MCP step tools (add_step, update_step, peek_next_step, get_plan_steps, get_step)
- step-5: Add HTTP API routes and controllers for plans and steps
- step-6: Write tests for step CRUD operations
- step-7: Update documentation (.claude/rules/popstash.md)
