# Refactor Plan: Convert "Stashes" to "Contexts"

## Overview
This document outlines the systematic approach to rename "stashes" to "contexts" throughout the PopStash codebase. The term "context" better represents the semantic purpose of saving and restoring working state.

## Scope of Changes

### 1. Database Layer
- **Migration files**
- **Table names**
- **Column references**
- **Indexes and constraints**

### 2. Elixir Application Code
- **Schema modules**
- **Context modules**
- **MCP tools**
- **LiveView components**
- **Router definitions**

### 3. Documentation & Configuration
- **README.md**
- **API documentation**
- **Code comments**
- **Configuration files**

### 4. Search & Indexing
- **TypeSense collections**
- **Search functions**
- **Embedding operations**

## Phase 1: Database Migration (Breaking Change)

### Step 1.1: Create Rename Migration
Create new migration: `priv/repo/migrations/TIMESTAMP_rename_stashes_to_contexts.exs`

```elixir
defmodule PopStash.Repo.Migrations.RenameStashesToContexts do
  use Ecto.Migration

  def change do
    # Rename the table
    rename table(:stashes), to: table(:contexts)
    
    # Update indexes
    drop index(:stashes, [:project_id])
    drop index(:stashes, [:project_id, :name])
    drop index(:stashes, [:expires_at])
    
    create index(:contexts, [:project_id])
    create index(:contexts, [:project_id, :name])
    create index(:contexts, [:expires_at])
  end
  
  def down do
    rename table(:contexts), to: table(:stashes)
    
    drop index(:contexts, [:project_id])
    drop index(:contexts, [:project_id, :name])
    drop index(:contexts, [:expires_at])
    
    create index(:stashes, [:project_id])
    create index(:stashes, [:project_id, :name])
    create index(:stashes, [:expires_at])
  end
end
```

### Step 1.2: Update Original Migration
Update `priv/repo/migrations/20260106210924_create_stashes.exs` to:
`priv/repo/migrations/20260106210924_create_contexts.exs`

Change table name from `:stashes` to `:contexts` in the migration.

## Phase 2: Schema & Model Updates

### Step 2.1: Rename Schema Module
**From:** `lib/pop_stash/memory/stash.ex`
**To:** `lib/pop_stash/memory/context.ex`

```elixir
defmodule PopStash.Memory.Context do
  @moduledoc """
  Schema for contexts (saved working state).

  A context is like `git stash` - saves current work state for later retrieval.
  """

  use PopStash.Schema

  schema "contexts" do
    field(:name, :string)
    field(:summary, :string)
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:expires_at, :utc_datetime_usec)
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
```

### Step 2.2: Update Memory Context Module
Update `lib/pop_stash/memory.ex`:

Replace all instances of:
- `Stash` → `Context`
- `stash` → `context`
- `stashes` → `contexts`
- `create_stash` → `create_context`
- `update_stash` → `update_context`
- `get_stash_by_name` → `get_context_by_name`
- `list_stashes` → `list_contexts`
- `delete_stash` → `delete_context`
- `search_stashes` → `search_contexts`

Update broadcast events:
- `:stash_created` → `:context_created`
- `:stash_updated` → `:context_updated`
- `:stash_deleted` → `:context_deleted`

## Phase 3: MCP Tools Updates

### Step 3.1: Rename Tool Module
**From:** `lib/pop_stash/mcp/tools/stash.ex`
**To:** `lib/pop_stash/mcp/tools/save_context.ex`

```elixir
defmodule PopStash.MCP.Tools.SaveContext do
  @moduledoc """
  MCP tool for creating contexts.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "save_context",
        description: "Save context for later. Use when switching tasks or context is long.",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Short name (e.g., 'auth-wip')"},
            summary: %{type: "string", description: "What you're working on"},
            files: %{type: "array", items: %{type: "string"}},
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Optional tags for categorization"
            }
          },
          required: ["name", "summary"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id}) do
    case Memory.create_context(
           project_id,
           args["name"],
           args["summary"],
           files: Map.get(args, "files", []),
           tags: Map.get(args, "tags", [])
         ) do
      {:ok, context} ->
        {:ok, "Saved context '#{context.name}'. Use `restore_context` with name '#{context.name}' to restore."}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end
  
  # ... rest of module
end
```

### Step 3.2: Update Pop Tool
Rename `lib/pop_stash/mcp/tools/pop.ex` to `lib/pop_stash/mcp/tools/restore_context.ex`

Update tool name from `"pop"` to `"restore_context"` and update all references to contexts.

### Step 3.3: Update MCP Server
In `lib/pop_stash/mcp/server.ex`, update the tool module list:
```elixir
@tool_modules [
  PopStash.MCP.Tools.SaveContext,      # was Stash
  PopStash.MCP.Tools.RestoreContext,   # was Pop
  PopStash.MCP.Tools.Insight,
  PopStash.MCP.Tools.Recall,
  PopStash.MCP.Tools.Decide,
  PopStash.MCP.Tools.GetDecisions
]
```

## Phase 4: LiveView Components

### Step 4.1: Rename LiveView Modules
**Directory:** `lib/pop_stash_web/dashboard/live/stash_live/`
**To:** `lib/pop_stash_web/dashboard/live/context_live/`

Rename files and update module names:
- `StashLive.Index` → `ContextLive.Index`
- `StashLive.Show` → `ContextLive.Show`
- `StashLive.FormComponent` → `ContextLive.FormComponent`

### Step 4.2: Update Templates
Update all `.heex` templates to use "context" terminology:
- Page titles
- Form labels
- Button text
- Help text

## Phase 5: Router Updates

### Step 5.1: Update Dashboard Router
In `lib/pop_stash_web/dashboard/router.ex`:

```elixir
# Contexts (formerly Stashes)
LiveRouter.live("/contexts", PopStashWeb.Dashboard.ContextLive.Index, :index)
LiveRouter.live("/contexts/new", PopStashWeb.Dashboard.ContextLive.Index, :new)
LiveRouter.live("/contexts/:id", PopStashWeb.Dashboard.ContextLive.Show, :show)
LiveRouter.live("/contexts/:id/edit", PopStashWeb.Dashboard.ContextLive.Show, :edit)
```

## Phase 6: Search & TypeSense Updates

### Step 6.1: Update TypeSense Module
In `lib/pop_stash/search/typesense.ex`:
- Rename collection from `"stashes"` to `"contexts"`
- Update `search_stashes` → `search_contexts`
- Update `index_stash` → `index_context`
- Update `delete_stash` → `delete_context`

### Step 6.2: Update Indexer
In `lib/pop_stash/search/indexer.ex`:
- Update all references from stash to context
- Update collection names

## Phase 7: Documentation Updates

### Step 7.1: README.md
Update all references:
- "Stash/Pop" → "Save/Restore Context"
- Tool descriptions
- Example commands
- API documentation

### Step 7.2: AGENTS.md
Update the agents documentation:
```markdown
**`save_context` / `restore_context` - Working Context**
- SAVE when: switching tasks, context is getting long, before exploring tangents
- RESTORE when: resuming work, need previous context, starting a related task
```

### Step 7.3: Code Comments
Search and replace in all `.ex` and `.exs` files:
- "stash" → "context" (case-insensitive where appropriate)
- Update module documentation

## Phase 8: Test Updates

### Step 8.1: Update Test Files
Rename test files:
- `test/pop_stash/memory/stash_test.exs` → `test/pop_stash/memory/context_test.exs`
- `test/pop_stash_web/dashboard/live/stash_live_test.exs` → `test/pop_stash_web/dashboard/live/context_live_test.exs`

### Step 8.2: Update Test Content
- Update all test descriptions
- Update function names
- Update assertions

## Phase 9: Backward Compatibility (Optional)

### Step 9.1: Create Alias Tools
Create temporary alias tools for backward compatibility:

```elixir
defmodule PopStash.MCP.Tools.StashAlias do
  @moduledoc "Temporary alias for backward compatibility"
  
  def tools do
    [%{
      name: "stash",
      description: "DEPRECATED: Use 'save_context' instead",
      inputSchema: PopStash.MCP.Tools.SaveContext.tools() |> hd() |> Map.get(:inputSchema),
      callback: fn args, ctx -> 
        IO.warn("Tool 'stash' is deprecated. Use 'save_context' instead.")
        PopStash.MCP.Tools.SaveContext.execute(args, ctx)
      end
    }]
  end
end
```

### Step 9.2: Add Deprecation Notices
Add warnings in logs when old tool names are used.

## Implementation Order

1. **Create feature branch**: `refactor/stashes-to-contexts`
2. **Database migrations** (Phase 1)
3. **Core model updates** (Phase 2)
4. **Update Memory context** (Phase 2.2)
5. **Update MCP tools** (Phase 3)
6. **Update TypeSense** (Phase 6)
7. **Update LiveViews** (Phase 4)
8. **Update routers** (Phase 5)
9. **Update tests** (Phase 8)
10. **Update documentation** (Phase 7)
11. **Add backward compatibility** (Phase 9) - if needed
12. **Run full test suite**
13. **Test with existing MCP clients**
14. **Deploy with migration strategy**

## Migration Strategy for Production

### Option 1: Big Bang
1. Take system offline for maintenance
2. Run all migrations
3. Deploy new code
4. Restart services

### Option 2: Blue-Green Deployment
1. Deploy new version to parallel infrastructure
2. Run migrations on copy of database
3. Switch traffic to new version
4. Keep old version available for rollback

### Option 3: Gradual Migration with Compatibility Layer
1. Deploy backward-compatible version with aliases
2. Run database migrations
3. Update clients to use new tool names
4. Remove compatibility layer in next release

## Validation Checklist

- [ ] All database migrations run successfully
- [ ] All tests pass
- [ ] TypeSense search works with new collection names
- [ ] MCP tools respond correctly to new names
- [ ] Dashboard LiveViews display and function correctly
- [ ] No references to "stash" remain in user-facing text
- [ ] Documentation is updated and accurate
- [ ] Backward compatibility works (if implemented)
- [ ] Performance is not degraded

## Rollback Plan

If issues arise:
1. Revert code deployment
2. Run down migration to rename tables back
3. Restore TypeSense collections
4. Communicate changes to users

## Notes

- This is a breaking change for MCP clients using the old tool names
- Consider versioning the MCP API if backward compatibility is critical
- Update any external documentation or integrations
- Notify users of the change with clear migration instructions