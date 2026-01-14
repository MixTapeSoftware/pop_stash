# Remove Recent Searches Sidebar

## Summary

Removed the separate "Recent Searches" sidebar widget from the dashboard. Search logs now appear exclusively in the unified "Recent Activity" feed alongside contexts, insights, decisions, and plans.

## Motivation

- **Reduce UI clutter**: The separate searches sidebar was redundant since searches were already appearing in the activity feed
- **Unified experience**: All activity types (contexts, decisions, insights, plans, searches) now live in one place
- **Simplified state management**: No need to maintain separate `recent_searches` state
- **Consistency**: Searches are treated the same as other memory types

## Changes Made

### Files Modified

#### 1. `lib/pop_stash_web/dashboard/live/home_live.ex`

**Removed:**
- `:recent_searches` socket assign
- `load_recent_searches/1` private function
- Call to `load_recent_searches/1` in `mount/3`
- Call to `load_recent_searches/1` in `handle_event("select_project")`
- Call to `load_recent_searches/1` in `handle_info({:search_logged, ...})`

**Simplified:**
- `handle_info({:search_logged, search_log}, socket)` now just calls `prepend_activity_item/2` (no reload of searches sidebar)

**Removed HTML:**
- Entire "Recent Searches" card section (~40 lines)
  - Search list with query text
  - Collection and result count metadata
  - Empty state messages

**Before:**
```elixir
socket
|> assign(:recent_searches, [])
|> load_recent_searches()

defp load_recent_searches(socket) do
  searches = case socket.assigns.selected_project_id do
    nil -> []
    project_id -> Memory.list_search_logs(project_id, limit: 5)
  end
  assign(socket, :recent_searches, searches)
end
```

**After:**
```elixir
# No recent_searches assign or function needed
# Searches appear automatically in activity feed
```

#### 2. `docs/DASHBOARD_SEARCHES_FEATURE.md`

Updated documentation to reflect:
- Removed "Recent Searches Sidebar" section
- Updated feature descriptions
- Removed sidebar layout references
- Updated testing instructions
- Simplified state management description

**Key documentation changes:**
- "Recent Searches Quick Access" section removed
- "Recent searches sidebar updates" removed from real-time updates
- Layout section updated to reference unified feed
- Testing steps simplified

## Current Behavior

### How Searches Appear Now

1. **Activity Feed Only**: Searches appear in the unified activity feed at `/pop_stash`
2. **Real-time Updates**: When a search is logged via MCP tools:
   - `:search_logged` event is broadcast
   - Dashboard receives event
   - Search is converted to activity item
   - Prepended to activity feed (if project filter matches)
3. **Display Format**:
   - **Icon**: Purple magnifying glass in rounded square
   - **Badge**: Purple "Search" label
   - **Title**: Search query text
   - **Preview**: Collection type, search type, and result count
   - **Timestamp**: Relative time ("2m ago", "1h ago", etc.)

### Activity Feed Integration

Searches are fully integrated in `PopStash.Activity`:

```elixir
def to_item(%SearchLog{} = search) do
  preview = "#{search.collection} • #{search.search_type}"
  preview = if search.result_count, 
    do: "#{preview} • #{search.result_count} results", 
    else: preview

  %Item{
    id: search.id,
    type: :search,
    title: search.query,
    preview: preview,
    project_id: search.project_id,
    # ...
  }
end
```

## Benefits

1. **Cleaner UI**: One less sidebar widget to maintain
2. **Better context**: Searches shown in chronological order with other activities
3. **Simpler code**: ~60 lines removed from home_live.ex
4. **Consistent UX**: All memory types use the same interface
5. **Better discoverability**: Users see searches in context with related activities

## Migration Notes

### For Users

- **No action required**: Searches still visible in activity feed
- **Same information**: Query, collection, results still displayed
- **Better integration**: Searches shown chronologically with other work

### For Developers

- **No database changes**: Uses existing search logging
- **No API changes**: MCP tools work exactly the same
- **No breaking changes**: Activity feed already supported searches

## Related Components

### Still Functional

- **Search Statistics**: Stats card still shows total search count
- **Activity Feed Component**: `activity_feed_component.ex` has full search support
- **Search Logging**: `Memory.log_search/4` continues to work
- **Real-time Updates**: PubSub events still broadcast and update feed
- **Activity Module**: `PopStash.Activity.to_item/1` handles SearchLog conversion

### Files Unchanged

- `lib/pop_stash/activity.ex` - Still includes searches in activity feed
- `lib/pop_stash/memory.ex` - `log_search/4` and `list_search_logs/2` still exist
- `lib/pop_stash_web/dashboard/live/activity_feed_component.ex` - Fully supports searches
- Database schema - No changes to `search_logs` table

## Testing

To verify searches still work correctly:

1. Start server: `mix phx.server`
2. Navigate to: `http://localhost:4001/pop_stash`
3. Select a project
4. Use MCP tools to perform searches:
   - `recall` with query
   - `get_decisions` with topic
   - `get_plan` with title search
   - `search_plans` with query
5. Verify:
   - ✅ Searches appear in activity feed in real-time
   - ✅ Purple icon and badge displayed
   - ✅ Query text, collection, and result count shown
   - ✅ Searches count increments in stats
   - ✅ Filtering by project works
   - ✅ Relative timestamps display correctly

## Code Metrics

**Lines removed**: ~60
**Lines added**: 0
**Net change**: -60 lines

**Files modified**: 2
- `home_live.ex`: -57 lines
- `DASHBOARD_SEARCHES_FEATURE.md`: -3 sections

## Conclusion

The Recent Searches sidebar has been successfully removed. Searches remain fully functional and visible in the unified activity feed, providing a cleaner and more consistent user experience.