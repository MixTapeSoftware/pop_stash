# Schema Field Standardization: Thread-Based History

## Overview

All PopStash memory records (insights, contexts, decisions, plans) use a **thread-based immutable history model**. Records are never edited—instead, you create new versions that share the same `thread_id`.

### Core Concept: Thread Identity

The `thread_id` field connects related records across revisions:

- **Same `thread_id`** = same logical entity, different versions (use timestamps to determine latest)
- **No `thread_id`** = standalone record, or first in a new thread (one will be auto-generated)
- **When revising**: Always reuse the original `thread_id` so history stays connected
- **When creating new**: Omit `thread_id` to auto-generate, or provide one if you anticipate revisions

Think of `thread_id` as "which thread does this belong to?"—a plan might evolve through draft → v1 → v2, but they all share the same `thread_id`.

## Thread ID Format

Thread IDs use Nanoid (12 characters) with type-specific prefixes:

```elixir
def generate_thread_id(type) do
  prefix = case type do
    :decision -> "dthr"
    :plan -> "pthr"
    :insight -> "ithr"
    :context -> "cthr"
  end
  "#{prefix}_#{Nanoid.generate(12)}"
end
```

Examples:
- `dthr_k8f2m9x1p4qz` (decision thread)
- `pthr_m3k9n7x2p4qz` (plan thread)
- `ithr_x7g3n2k9m1pq` (insight thread)
- `cthr_p4k8m2n6x9qz` (context thread)

## Current Schema State

All memory types now include:

### Insights
- `key` (string, optional) - Optional semantic key for exact retrieval
- `content` (text) - The insight content
- `tags` (array) - Metadata tags
- `thread_id` (string, required) - Auto-generated or passed for revisions

### Contexts
- `name` (string) - Short identifier
- `summary` (text) - Working context summary
- `files` (array) - Associated file paths
- `tags` (array) - Metadata tags
- `thread_id` (string, required) - Auto-generated or passed for revisions
- `expires_at` (datetime) - Optional expiration

### Decisions
- `topic` (string) - Decision area (normalized: lowercased, trimmed)
- `decision` (text) - What was decided
- `reasoning` (text) - Why (optional)
- `tags` (array) - Metadata tags
- `thread_id` (string, required) - Auto-generated or passed for revisions

### Plans
- `title` (string) - Plan title
- `version` (string) - Version identifier
- `body` (text) - Plan content
- `tags` (array) - Metadata tags
- `thread_id` (string, required) - Auto-generated or passed for revisions

## Implementation Details

### Database Schema

Migration added:
- `thread_id` column (string) to all memory tables
- Index on `thread_id` for efficient querying

```elixir
alter table(:insights) do
  add :thread_id, :string
end
create index(:insights, [:thread_id])

# Same for contexts, decisions, and plans
```

### Context Module (lib/pop_stash/memory.ex)

All `create_*` functions support optional `thread_id`:

```elixir
def create_insight(project_id, content, opts \\ []) do
  thread_id = Keyword.get(opts, :thread_id) || ThreadId.generate(:insight)
  # ... creates record with thread_id
end
```

When `thread_id` is:
- **Omitted**: Auto-generates a new thread ID
- **Provided**: Uses the provided thread ID (for revisions)

### MCP Tools

All MCP tools accept and return `thread_id`:

**Creating records:**
- `insight` - Returns: `"Insight saved... (thread_id: ithr_xxx)"`
- `save_context` - Returns: `"Saved context... (thread_id: cthr_xxx)"`
- `decide` - Returns: `"Decision recorded... (thread_id: dthr_xxx)"`
- `save_plan` - Returns: `"Saved plan... (thread_id: pthr_xxx)"`

**Retrieving records:**
- `recall` - Returns `thread_id` in result metadata
- `restore_context` - Returns `thread_id` in result metadata
- `get_decisions` - Shows `thread_id` in formatted output
- `get_plan` - Shows `thread_id` in formatted output

## Usage Pattern

### Creating a New Record

```elixir
# MCP tool call - omit thread_id
insight(content: "Rate limits reset at UTC midnight", key: "api/rate-limits")

# Returns: thread_id: ithr_x7g3n2k9m1pq
```

### Revising an Existing Record

```elixir
# MCP tool call - pass back the thread_id
insight(
  content: "Rate limits reset at UTC midnight per-key, not globally",
  key: "api/rate-limits",
  thread_id: "ithr_x7g3n2k9m1pq"
)

# Both records now share thread_id: ithr_x7g3n2k9m1pq
# Use timestamps to determine which is current
```

## Benefits

1. **Immutable History**: All versions preserved, never lost
2. **Clear Provenance**: Easy to trace evolution of decisions/plans
3. **Flexible Versioning**: No need to manage version numbers explicitly
4. **Time-Travel**: Query any point in history via timestamps
5. **Audit Trail**: Full history of all changes and revisions

## Querying by Thread

All queries by `thread_id` return records in reverse chronological order (most recent first):

```elixir
# Get all versions of a thread
Insight
|> where([i], i.thread_id == ^thread_id)
|> order_by(desc: :inserted_at)
|> Repo.all()

# Get latest version
Insight
|> where([i], i.thread_id == ^thread_id)
|> order_by(desc: :inserted_at)
|> limit(1)
|> Repo.one()
```

## Migration from Version-Based to Thread-Based

The previous plan proposed adding `version` fields (like "v1.0", "v2.0"). The thread-based approach is superior because:

1. **No version management**: Don't need to track version strings
2. **Simpler API**: Just "omit thread_id (new) or pass it back (revision)"
3. **Timestamp-driven**: Natural ordering via `inserted_at`
4. **Consistent with immutability**: Aligns with the append-only philosophy

Plans still have `version` fields for human-readable versioning, but `thread_id` provides the underlying connection between versions.

## Testing Checklist

- [x] Migration runs successfully
- [x] Thread IDs auto-generate when omitted
- [x] Thread IDs can be explicitly provided
- [x] MCP tools accept thread_id parameter
- [x] MCP tools return thread_id in responses
- [ ] Can query records by thread_id
- [ ] Multiple records with same thread_id maintain history
- [ ] All tests pass (`mix test`)
- [ ] Precommit checks pass (`mix precommit`)
