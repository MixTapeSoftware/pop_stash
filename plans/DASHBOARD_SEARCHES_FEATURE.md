# Dashboard Searches Feature

## Overview

Added comprehensive search tracking and display to the PopStash dashboard. Searches are now logged, displayed in the activity feed, shown in quick access sidebar, and counted in the stats.

## Changes Made

### 1. Memory Context (`lib/pop_stash/memory.ex`)

Added functions to list and count search logs:

- `list_search_logs/2` - Lists recent search logs for a project with configurable limit
- `count_searches/1` - Counts total searches for a project
- Updated `log_search/4` - Now broadcasts `:search_logged` events via PubSub for real-time updates

### 2. Activity Context (`lib/pop_stash/activity.ex`)

Extended to support search logs as activity items:

- Added `:search` to `Item.type` type spec
- Added `SearchLog` to imports
- Added search fetching to `list_recent/1` (searches now appear in activity feed)
- Implemented `to_item/1` for `SearchLog` structs
- Added `fetch_searches/2` private function to retrieve search logs from database

### 3. Activity Feed Component (`lib/pop_stash_web/dashboard/live/activity_feed_component.ex`)

Updated UI to display search items:

- Added search type icon (`hero-magnifying-glass`)
- Added purple color scheme for search items
- Made item paths optional (searches don't have detail pages)
- Added search badge styling (`bg-purple-100 text-purple-700`)

### 4. Home Dashboard Live View (`lib/pop_stash_web/dashboard/live/home_live.ex`)

Major enhancements:

#### Stats
- Added "Searches" stat card showing total queries across all projects or for selected project
- Displays search count alongside stashes, insights, and decisions



#### Real-Time Updates
- Added `handle_info/2` for `:search_logged` events
- Searches appear in activity feed immediately when logged
- Integrated with existing PubSub subscription

#### State Management
- Searches integrated into unified activity feed
- No separate state management needed for searches

## Features

### 1. Search Count Stats
Shows total number of searches:
- Aggregate count across all projects (when no project selected)
- Per-project count (when project selected)
- Displayed as stat card with "Total queries" description

### 2. Searches in Activity Feed
Search logs now appear in the unified activity feed:
- Shows alongside stashes, insights, and decisions
- Purple badge with "Search" label
- Displays query as title
- Shows collection, search type, and result count as preview
- Real-time updates via PubSub
- Sortable by timestamp with other activities

## Real-Time Behavior

When a search is logged via `Memory.log_search/4`:

1. Search log is inserted into database (async)
2. `:search_logged` event is broadcast via PubSub
3. Dashboard receives event and:
   3. **Real-time feed update:**
      - Converts search log to activity item
      - Prepends to activity feed (if matches project filter)
   4. Updates appear instantly without page refresh

## UI Design

### Colors
- **Purple theme** for searches (`purple-50`, `purple-100`, `purple-400`, `purple-500`)
- Consistent with other activity types (blue for stashes, green for decisions, amber for insights)

### Layout
- Searches appear in unified activity feed
- Purple theme distinguishes them from other activity types
- Compact display with icon + text layout
- Hover states for better interactivity

### Typography
- Query text: `text-sm text-slate-900` (truncated)
- Metadata: `text-xs text-slate-500`
- Empty states: `text-sm text-slate-400`

## Database Schema

Uses existing `search_logs` table (no migrations needed):
- `id` - UUID primary key
- `project_id` - References projects
- `query` - Search query text
- `collection` - Type of collection searched
- `search_type` - Search strategy used
- `tool` - MCP tool that initiated search
- `result_count` - Number of results returned
- `found` - Boolean indicating if results were found
- `duration_ms` - Search duration in milliseconds
- `inserted_at` - Timestamp (no updated_at)

## Testing

To test the feature:

1. Start the server: `mix phx.server`
2. Navigate to dashboard: `http://localhost:4001/pop_stash`
3. Select a project from dropdown
4. Perform searches via MCP tools (recall, search, etc.)
5. Observe:
   - Search count increments in stats
   - Searches show in activity feed with real-time updates

## Integration Points

### MCP Tools
Search logs are created when MCP tools perform searches:
- `recall` tool - Semantic and keyword searches
- `search` tool - Typesense searches
- `pop` tool - Context retrieval

### PubSub Events
Subscribes to `"memory:events"` topic for:
- `:search_logged` - New search logged
- `:stash_created`, `:decision_created`, `:insight_created` - Also tracked
- All activity types unified in single feed

## Performance Considerations

- Activity feed limited to 20 items total (includes searches)
- Database queries use indexes on `project_id` and `inserted_at`
- No N+1 queries (uses `preload(:project)`)

## Future Enhancements

Potential additions:
- Search analytics page with charts and trends
- Search query auto-complete based on history
- Search result quality metrics
- Filter activity feed by type (show only searches)
- Export search logs to CSV
- Search log retention policies