# Plan: Add Search Logging for Agent Tools

## Overview
Add comprehensive logging for each time an agent runs a search (both exact match and semantic search) across all search tools (pop, recall, get_decisions).

## Critical Files
- `lib/pop_stash/memory.ex` - Add logging to search functions
- `lib/pop_stash/mcp/tools/pop.ex` - Log stash searches
- `lib/pop_stash/mcp/tools/recall.ex` - Log insight searches  
- `lib/pop_stash/mcp/tools/get_decisions.ex` - Log decision searches
- `lib/pop_stash/search/typesense.ex` - Log Typesense semantic searches
- `lib/pop_stash_web/telemetry.ex` - Add telemetry event handlers for search metrics

## Implementation Steps

### 1. Add Telemetry Events to Search Functions
**Files:** `lib/pop_stash/search/typesense.ex`

Add `:telemetry.execute/3` calls to the three semantic search functions:
- `search_stashes/3` - emit `[:pop_stash, :search, :stashes]`
- `search_insights/3` - emit `[:pop_stash, :search, :insights]`
- `search_decisions/3` - emit `[:pop_stash, :search, :decisions]`

**Measurements:**
- `duration` - search execution time
- `result_count` - number of results returned

**Metadata:**
- `project_id` - for filtering/grouping
- `query` - the search query text
- `search_type` - `:semantic` for Typesense searches
- `limit` - max results requested

### 2. Add Telemetry Events to Exact Match Functions
**Files:** `lib/pop_stash/memory.ex`

Add telemetry events to exact match functions:
- `get_stash_by_name/2` - emit `[:pop_stash, :search, :stashes]`
- `get_insight_by_key/2` - emit `[:pop_stash, :search, :insights]`
- `list_decisions/2` (with topic filter) - emit `[:pop_stash, :search, :decisions]`

**Metadata:**
- `search_type` - `:exact` for database exact matches
- `found` - boolean indicating if result was found

### 3. Add Application Logging in Tool Modules
**Files:** 
- `lib/pop_stash/mcp/tools/pop.ex`
- `lib/pop_stash/mcp/tools/recall.ex`
- `lib/pop_stash/mcp/tools/get_decisions.ex`

Add `Logger.info/2` calls in each tool's execute function to log:
- Tool name
- Search query/key
- Search strategy used (exact → semantic fallback, or semantic only)
- Results found/returned

Use structured logging format:
```elixir
Logger.info("Agent search executed",
  tool: "pop",
  project_id: project_id,
  query: name,
  strategy: "exact_then_semantic",
  found: true,
  result_count: 1
)
```

### 4. Register Telemetry Handlers
**Files:** `lib/pop_stash_web/telemetry.ex`

Add new metrics to the `metrics/0` function:
- `Telemetry.Metrics.counter("pop_stash.search.stashes.count")` - total stash searches
- `Telemetry.Metrics.counter("pop_stash.search.insights.count")` - total insight searches
- `Telemetry.Metrics.counter("pop_stash.search.decisions.count")` - total decision searches
- `Telemetry.Metrics.summary("pop_stash.search.stashes.duration")` - stash search latency
- `Telemetry.Metrics.summary("pop_stash.search.insights.duration")` - insight search latency
- `Telemetry.Metrics.summary("pop_stash.search.decisions.duration")` - decision search latency

Tag metrics with `search_type` (exact/semantic) for filtering.

### 5. Update MCP Server Tool Execution
**Files:** `lib/pop_stash/mcp/server.ex`

The existing `execute_tool/5` function already emits telemetry with the tool name. Ensure search-related tools are clearly identified in the telemetry metadata so we can correlate tool execution with search events.

## Technical Considerations

### Telemetry Event Naming
Use consistent event naming:
- `[:pop_stash, :search, :stashes]` - for stash searches
- `[:pop_stash, :search, :insights]` - for insight searches
- `[:pop_stash, :search, :decisions]` - for decision searches

### Performance Impact
- Telemetry events have minimal overhead (~microseconds)
- Logger calls are async by default in production
- No database writes for logging to avoid slowing down searches

### Metadata Consistency
All search events should include:
- `project_id` - for multi-tenant filtering
- `search_type` - `:exact` or `:semantic`
- `query` - the search text
- `duration` - execution time (semantic searches only)
- `result_count` - number of results

### Graceful Degradation
If embeddings are disabled or Typesense is unavailable, ensure logging still captures:
- Failed semantic search attempts
- Fallback to exact-only matching
- Degraded service indicators

## Verification

### Manual Testing
1. Start the application with `mix phx.server`
2. Make MCP tool calls for each search tool:
   - Call `pop` tool with name parameter
   - Call `recall` tool with key parameter
   - Call `get_decisions` tool with topic parameter
3. Check logs for search events with all expected metadata
4. Verify telemetry metrics increment correctly

### Log Output Validation
Look for log entries like:
```
[info] Agent search executed tool=pop project_id=123 query="user_auth" strategy=exact_then_semantic found=true result_count=1
[info] Agent search executed tool=recall project_id=123 query="api_endpoint" strategy=semantic found=true result_count=3
```

### Telemetry Verification
Uncomment the ConsoleReporter in telemetry.ex temporarily to see metrics:
```
[Telemetry.Metrics.ConsoleReporter, metrics: metrics()]
```

Then verify counter increments and latency summaries are captured.

### Integration Testing
Run existing tests to ensure logging doesn't break functionality:
```bash
mix test
```

No test changes should be required as logging is non-invasive.

## Notes

- Logging is intentionally lightweight to avoid performance impact
- All timestamps use monotonic time for duration measurements
- Structured logging enables easy parsing by log aggregation tools
- Telemetry events can be consumed by external monitoring systems (DataDog, Prometheus, etc.)
- No database schema changes required
