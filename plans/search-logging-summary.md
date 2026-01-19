# Search Logging - Final Implementation

## Overview
Database persistence for agent semantic searches to analyze search patterns and trends over time.

## What Gets Logged

### ✅ Logged
- **Semantic searches** performed by agents when exact matches fail
- Both successful searches (with results) and unsuccessful searches (no results)
- Includes: query text, collection type, tool name, result count, timestamp

### ❌ NOT Logged
- **Exact name/key lookups** - these are getters, not searches
- List operations (e.g., `get_decisions` with `list_topics: true`)
- Searches when embeddings are disabled (no search actually performed)

## Database Schema

**Table:** `search_logs`

```sql
CREATE TABLE search_logs (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  collection VARCHAR NOT NULL,  -- 'stashes', 'insights', or 'decisions'
  search_type VARCHAR NOT NULL, -- 'semantic'
  tool VARCHAR,                 -- 'pop', 'recall', or 'get_decisions'
  result_count INTEGER DEFAULT 0,
  found BOOLEAN DEFAULT FALSE,
  duration_ms INTEGER,          -- future enhancement
  inserted_at TIMESTAMP NOT NULL
);

-- Indexes for efficient querying
CREATE INDEX ON search_logs (project_id);
CREATE INDEX ON search_logs (project_id, collection);
CREATE INDEX ON search_logs (project_id, inserted_at);
CREATE INDEX ON search_logs (tool);
```

## Implementation Details

### 1. Log Function (lib/pop_stash/memory.ex:344)
```elixir
@doc false
def log_search(project_id, query, collection, search_type, opts \\ [])
```
- Marked with `@doc false` - internal use only
- Runs asynchronously via `Task.start/1` to avoid blocking
- Validates required fields before insert

### 2. Tool Integration

**pop tool** - Logs when semantic search executes:
```elixir
Memory.search_stashes(project_id, query, limit: limit)
# -> logs search with result count
```

**recall tool** - Logs when semantic search executes:
```elixir
Memory.search_insights(project_id, query, limit: limit)
# -> logs search with result count
```

**get_decisions tool** - Logs when semantic search executes:
```elixir
Memory.search_decisions(project_id, topic, limit: limit)
# -> logs search with result count
```

## Example Analytics Queries

### Most frequent searches
```sql
SELECT query, collection, COUNT(*) as frequency
FROM search_logs
WHERE project_id = $1
GROUP BY query, collection
ORDER BY frequency DESC
LIMIT 20;
```

### Failed searches (improvement opportunities)
```sql
SELECT query, collection, tool, COUNT(*) as attempts
FROM search_logs
WHERE project_id = $1 AND found = false
GROUP BY query, collection, tool
ORDER BY attempts DESC
LIMIT 20;
```

### Search success rate by tool
```sql
SELECT 
  tool,
  COUNT(*) as total_searches,
  SUM(CASE WHEN found THEN 1 ELSE 0 END) as successful,
  ROUND(100.0 * SUM(CASE WHEN found THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate
FROM search_logs
WHERE project_id = $1
GROUP BY tool;
```

### Search volume over time
```sql
SELECT 
  DATE(inserted_at) as date,
  collection,
  COUNT(*) as searches
FROM search_logs
WHERE project_id = $1
  AND inserted_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(inserted_at), collection
ORDER BY date DESC;
```

### Unique queries vs total searches
```sql
SELECT 
  collection,
  COUNT(DISTINCT query) as unique_queries,
  COUNT(*) as total_searches,
  ROUND(COUNT(DISTINCT query)::numeric / COUNT(*) * 100, 2) as uniqueness_pct
FROM search_logs
WHERE project_id = $1
GROUP BY collection;
```

## Benefits

1. **Pattern Analysis** - See what agents search for most frequently
2. **Query Optimization** - Identify searches that consistently fail
3. **Content Gaps** - Understand what information agents need but can't find
4. **Tool Usage** - Track which tools are used most and their success rates
5. **Trend Analysis** - Monitor search behavior over time

## Testing

- ✅ Migration applied (20260113183445_create_search_logs.exs)
- ✅ All 57 memory and tool tests pass
- ✅ Clean compilation with no warnings
- ✅ Async logging doesn't block search operations
- ✅ Only semantic searches are logged (not getters)

## Future Enhancements

- Add `duration_ms` tracking for semantic searches
- Add dashboard for visualizing search trends
- Implement search query suggestions based on patterns
- Add alerts for high failure rates
