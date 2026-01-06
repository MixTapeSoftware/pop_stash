# PopStash Project Plan

**Project Status: EXPERIMENTAL**

## Overview

Agents can be briliant wrecking balls if the lack the appropriate context. We can throw a markdown file
into the project root and hope for the best or we can build systems that help agents coordinate, pick
up where they left off, and record insights for future use as they work. 

*That's PopStash*

It's the missing infrastructure layer between your AI agents and sanity: memory, coordination (via tasks and locks), observability.

### PopStash's Focus

| What PopStash Does | What It Doesn't Do |
|-------------------|-------------------|
| Remembers context across sessions | Call LLMs (agents do that) |
| Prevents agents from colliding | Execute code or write files |
| Tracks what happened and what it cost | Orchestrate workflows |
| Works with Claude Code, Cursor, Cline | Replace your agents |
---

## Quick Start (< 5 Minutes)

Five minutes from now, your AI agents will have memory, coordination, and (some) accountability.

Here's how:

```bash
# 1. Clone and start (30 seconds)
git clone https://github.com/MixTapeSoftware/pop_stash.git
cd pop_stash
docker compose up -d

# 2. Add to your MCP config (60 seconds)
# ~/.config/claude/claude_desktop_config.json
{
  "mcpServers": {
    "pop_stash": {
      "command": "mix",
      "args": ["run", "--no-halt"],
      "cwd": "/path/to/pop_stash"
    }
  }
}

# 3. Restart Claude Code. That's it.
```

**What just changed:**

| Before | After |
|--------|-------|
| Every session starts from zero | Agent remembers everything |
| Multiple agents = file conflicts | Automatic coordination |
| "What did it do?" 🤷 | Full timeline at localhost:3301 |
| Context dies when window fills | `stash` and `pop` — nothing lost |

**Try it now:** Ask Claude to "start a task on the auth module." Watch it automatically check for conflicts, load relevant context, and acquire locks.

---

### Where we are headed

> "The programming is done by accumulating, massaging and cleaning datasets." — [Andrej Karpathy](https://karpathy.medium.com/software-2-0-a64152b37c35)

PopStash is infrastructure:

- **Decisions are code** — Every `decide` call is like a commit to the project's decision history
- **Context is the program** — Stashes and notes ARE the state that makes agents effective
- **Semantic search over explicit lookup** — `recall` finds relevant context even with fuzzy queries
- **Observable by default** — Every operation emits telemetry; you can always see what happened

### Developer Experience Requirements

These are non-negotiable for project success:

| Requirement | Target |
|-------------|--------|
| **Time to "Hello World"** | < 5 minutes from `git clone` to first `start_task` |
| **Zero configuration** | `docker compose up` and it works |
| **Docs with examples** | Every tool shows input AND expected output |
| **Helpful error messages** | Errors explain what went wrong AND how to fix it |
| **Graceful degradation** | Works with partial setup (DB only, no SigNoz) |

### Fault Tolerance (OTP Philosophy)

> "Let it crash." — Erlang/OTP

- Agent disconnects → locks auto-release, session marked abandoned
- Database unavailable → clear error, no silent failures
- Embedding model slow → operations proceed, embeddings computed async
- SigNoz down → telemetry buffered or dropped, core features unaffected

---

## The Problems We're Solving

### 1. Context Amnesia
Claude Code hits 200k tokens, you start a new session, and it has no idea you spent 3 hours debugging that race condition. All context is lost.

### 2. Session Death
Close your terminal, come back tomorrow — everything's gone. You have to re-explain the entire problem.

### 3. Multi-Agent Chaos
Run three Claude instances on a monorepo and they'll edit the same files, make conflicting decisions, and have no idea what the others are doing.

### 4. Zero Observability
How much did that session cost? What files did it touch? What decisions were made? No idea.

---

## Architecture

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Claude Code  │  │    Cursor    │  │    Cline     │
│  (Agent A)   │  │  (Agent B)   │  │  (Agent C)   │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                 │
       └─────────────────┼─────────────────┘
                         │ MCP Protocol (stdio)
                         ▼
         ┌───────────────────────────────────┐
         │              PopStash              │
         │                                   │
         │  ┌─────────┐ ┌──────────────────┐ │
         │  │ Memory  │ │   Coordination   │ │
         │  │         │ │                  │ │
         │  │ stash   │ │ acquire/release  │ │
         │  │ pop     │ │ announce         │ │
         │  │ note    │ │ decide           │ │
         │  │ recall  │ │ who_is_working   │ │
         │  └─────────┘ └──────────────────┘ │
         │                                   │
         │  ┌────────────────────────────┐   │
         │  │      Observability         │   │
         │  │                            │   │
         │  │  sessions, costs, timeline │   │
         │  │  OpenTelemetry → SigNoz    │   │
         │  └────────────────────────────┘   │
         │                                   │
         │  ┌────────────────────────────┐   │
         │  │   Nx/Bumblebee Embeddings  │   │
         │  │   (all-MiniLM-L6-v2)       │   │
         │  └────────────────────────────┘   │
         └───────────────────────────────────┘
                         │
                         ▼
                    PostgreSQL
                   (+ pgvector)
```

**No LLM calls.** PopStash is a smart database with MCP tools and local embeddings.

---

## Key Decisions

| Question | Decision |
|----------|----------|
| **Embeddings** | Nx/Bumblebee local (all-MiniLM-L6-v2, 384 dimensions) |
| **Lock expiry** | 15 minutes default, configurable |
| **Multi-project** | One PopStash instance per project |
| **MCP transport** | stdio for V1 |
| **Stash retention** | Forever by default, optional TTL |
| **Agent IDs** | PopStash assigns them on connect |
| **Telemetry** | OpenTelemetry → SigNoz for distributed tracing |
| **Developer UX** | Pit of success design — make the right thing easy |

---

## The Three Pillars

### Pillar 1: Memory

Persistent storage that survives session death.

| Tool | Purpose |
|------|---------|
| `stash` | Save current context with a name ("auth-debugging") |
| `pop` | Restore a stash (by name or semantic search) |
| `insight` | Save a persistent insight ("The auth module uses JWT") |
| `recall` | Search insights semantically ("how does auth work?") |
| `decide` | Record a decision ("Using Guardian for auth tokens") |
| `get_decisions` | Get decisions on a topic |

### Pillar 2: Coordination

Multi-agent awareness and conflict prevention.

| Tool | Purpose |
|------|---------|
| `acquire` | Get exclusive lock on file(s) before editing |
| `release` | Release lock when done |
| `announce` | Broadcast what you're working on ("Refactoring auth module") |
| `decide` | Record a decision for all agents ("Using Guardian for auth") |
| `who_is_working` | See all active agents and what they're doing |
| `get_decisions` | Get recent decisions on a topic |

### Pillar 3: Observability

Visibility into what agents are doing, what it costs, and distributed tracing via **SigNoz**.

| Tool | Purpose |
|------|---------|
| `report_cost` | Agent reports token usage for a task |
| `timeline` | Get recent activity across all agents |
| `session_summary` | Summary of current session (files touched, decisions, cost) |

**Telemetry Stack:**
- **OpenTelemetry** — Instrumentation standard for traces, metrics, and logs
- **SigNoz** — Self-hosted observability platform (APM + logs + traces)
- All storage events are emitted as OpenTelemetry spans for full visibility

---

## Telemetry Architecture

PopStash emits OpenTelemetry spans for all storage operations, enabling full observability in SigNoz.

### Storage Events

All database operations emit telemetry events with the following pattern:

| Event | Span Name | Attributes |
|-------|-----------|------------|
| **Stash created** | `pop_stash.stash.create` | `stash.id`, `stash.name`, `agent.id` |
| **Stash popped** | `pop_stash.stash.pop` | `stash.id`, `stash.name`, `agent.id` |
| **Stash deleted** | `pop_stash.stash.delete` | `stash.id`, `agent.id` |
| **Insight created** | `pop_stash.insight.create` | `insight.id`, `insight.key`, `agent.id` |
| **Insight recalled** | `pop_stash.insight.recall` | `insight.id`, `query`, `agent.id` |
| **Insight updated** | `pop_stash.insight.update` | `insight.id`, `insight.key`, `agent.id` |
| **Insight deleted** | `pop_stash.insight.delete` | `insight.id`, `agent.id` |
| **Decision created** | `pop_stash.decision.create` | `decision.id`, `decision.topic`, `agent.id` |
| **Decision queried** | `pop_stash.decision.query` | `topic`, `count`, `agent.id` |
| **Lock acquired** | `pop_stash.lock.acquire` | `lock.id`, `lock.pattern`, `agent.id` |
| **Lock released** | `pop_stash.lock.release` | `lock.id`, `lock.pattern`, `agent.id` |
| **Lock expired** | `pop_stash.lock.expire` | `lock.id`, `lock.pattern`, `agent.id` |
| **Session started** | `pop_stash.session.start` | `session.id`, `task`, `agent.id` |
| **Session ended** | `pop_stash.session.end` | `session.id`, `status`, `cost_usd`, `agent.id` |
| **Agent connected** | `pop_stash.agent.connect` | `agent.id`, `agent.name` |
| **Agent disconnected** | `pop_stash.agent.disconnect` | `agent.id`, `reason` |
| **Activity logged** | `pop_stash.activity.log` | `activity.type`, `agent.id`, `session.id` |

### Telemetry Module

```elixir
defmodule PopStash.Telemetry do
  @moduledoc """
  OpenTelemetry instrumentation for all PopStash storage operations.
  """
  
  require OpenTelemetry.Tracer, as: Tracer
  
  @doc "Emit a storage event span"
  def emit_storage_event(event_name, attributes, fun) do
    Tracer.with_span event_name, %{attributes: build_attributes(attributes)} do
      try do
        result = fun.()
        Tracer.set_status(:ok, "")
        result
      rescue
        e ->
          Tracer.set_status(:error, Exception.message(e))
          Tracer.record_exception(e, __STACKTRACE__)
          reraise e, __STACKTRACE__
      end
    end
  end
  
  @doc "Emit a simple event (no wrapping)"
  def emit(event_name, attributes) do
    Tracer.add_event(event_name, build_attributes(attributes))
  end
  
  defp build_attributes(attrs) when is_map(attrs) do
    Enum.map(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
```

### Usage in Storage Modules

```elixir
# Example: PopStash.Memory.create_stash/3
def create_stash(agent_id, name, summary, opts \\ []) do
  PopStash.Telemetry.emit_storage_event(
    "pop_stash.stash.create",
    %{agent_id: agent_id, stash_name: name},
    fn ->
      # ... actual database operation
      %Stash{}
      |> Stash.changeset(%{name: name, summary: summary, created_by: agent_id})
      |> Repo.insert()
    end
  )
end
```

### Ecto Telemetry

Database queries are automatically instrumented via `opentelemetry_ecto`:

```elixir
# In application.ex
:ok = OpentelemetryEcto.setup([:pop_stash, :repo])
```

---

## The Preflight Pattern

Every agent task follows this pattern:

```
┌─────────────────────────────────────────────────────────────┐
│                      START TASK                             │
│                                                             │
│  1. Call start_task("Implement user auth", ["lib/auth.ex"]) │
│  2. PopStash returns:                                        │
│     - Your agent_id                                         │
│     - Lock status (acquired or conflict)                    │
│     - Relevant stashes/notes/decisions                      │
│     - What other agents are doing                           │
│  3. If conflict → STOP, report to user                      │
│  4. Otherwise → proceed with full context                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      DO THE WORK                            │
│                                                             │
│  - Edit files (you have locks)                              │
│  - Call note() if you learn something important             │
│  - Call decide() if you make an architectural choice        │
│  - Call stash() if context is getting long                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       END TASK                              │
│                                                             │
│  1. Call end_task("Implemented JWT auth with Guardian")     │
│  2. PopStash:                                                │
│     - Releases your locks                                   │
│     - Logs the activity                                     │
│     - Records cost if provided                              │
└─────────────────────────────────────────────────────────────┘
```

---

## MCP Tools (Complete Specification)

> **Documentation Principle**: Every tool shows realistic input AND expected output.
> Error cases show how to recover. — *José Valim's "docs as feature" philosophy*

### start_task

Called at the beginning of every task. Returns context and acquires locks.

```json
{
  "name": "start_task",
  "description": "Start a new task. Returns context and acquires locks on specified files.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "task": { "type": "string", "description": "What you're about to do" },
      "files": { "type": "array", "items": { "type": "string" }, "description": "Files you'll edit" }
    },
    "required": ["task"]
  }
}
```

**Example — Success:**
```json
// Input
{ "task": "Add JWT authentication to the API", "files": ["lib/auth.ex", "lib/router.ex"] }

// Output
{
  "agent_id": "agent_abc123",
  "session_id": "sess_xyz789",
  "locks": { 
    "acquired": ["lib/auth.ex", "lib/router.ex"], 
    "conflicts": [] 
  },
  "context": {
    "relevant_stashes": [
      { "name": "auth-research", "summary": "Evaluated Guardian vs Pow for auth...", "age": "2 days" }
    ],
    "relevant_insights": [
      { "key": "api-patterns", "content": "All API responses use {:ok, data} | {:error, reason}" }
    ],
    "recent_decisions": [
      { "topic": "auth", "decision": "Use Guardian for JWT tokens", "reasoning": "Better Plug integration" }
    ],
    "other_agents": [
      { "id": "agent_xyz", "task": "Writing tests for user model", "files": ["test/user_test.exs"] }
    ]
  }
}
```

**Example — Conflict:**
```json
// Input
{ "task": "Refactor auth module", "files": ["lib/auth.ex"] }

// Output — STOP and report to user!
{
  "agent_id": "agent_abc123",
  "locks": {
    "acquired": [],
    "conflicts": [
      {
        "file": "lib/auth.ex",
        "held_by": "agent_xyz",
        "task": "Add JWT authentication to the API",
        "held_for": "5 minutes",
        "expires_in": "10 minutes"
      }
    ]
  },
  "suggestion": "Wait for agent_xyz to finish, or ask user to coordinate"
}
```

### end_task

Called at the end of every task. Releases locks and logs activity.

```json
{
  "name": "end_task",
  "description": "End the current task. Releases locks and logs what was accomplished.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "summary": { "type": "string", "description": "What you accomplished" },
      "tokens_in": { "type": "integer" },
      "tokens_out": { "type": "integer" }
    },
    "required": ["summary"]
  }
}
```

**Example:**
```json
// Input
{ 
  "summary": "Added JWT auth with Guardian. Created Auth.Token module, updated router with :api pipeline.", 
  "tokens_in": 15000, 
  "tokens_out": 8000 
}

// Output
{
  "status": "completed",
  "session_id": "sess_xyz789",
  "duration": "12 minutes",
  "locks_released": ["lib/auth.ex", "lib/router.ex"],
  "cost_usd": 0.12
}
```

### stash

Save context for later retrieval. Use when context is getting long or switching tasks.

```json
{
  "name": "stash",
  "description": "Save current context with a name for later retrieval.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "name": { "type": "string", "description": "Short name for this stash" },
      "summary": { "type": "string", "description": "What you were working on and current state" },
      "files": { "type": "array", "items": { "type": "string" } }
    },
    "required": ["name", "summary"]
  }
}
```

**Example:**
```json
// Input
{ 
  "name": "auth-jwt-wip",
  "summary": "Implementing JWT auth. DONE: Auth.Token module, generate/verify functions. TODO: Add to router, write tests. BLOCKER: Need to decide on token expiry time.",
  "files": ["lib/auth/token.ex", "lib/router.ex"]
}

// Output
{
  "stash_id": "stash_abc123",
  "name": "auth-jwt-wip",
  "created_at": "2025-01-15T10:30:00Z",
  "tip": "Use `pop` with name 'auth-jwt-wip' or search 'JWT authentication' to restore"
}
```

### pop

Retrieve a stash by name or semantic search. Works even with fuzzy queries!

```json
{
  "name": "pop",
  "description": "Retrieve a stash by name or semantic search.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Name or description to search for" }
    },
    "required": ["query"]
  }
}
```

**Example — By Name:**
```json
// Input
{ "query": "auth-jwt-wip" }

// Output
{
  "stash_id": "stash_abc123",
  "name": "auth-jwt-wip",
  "summary": "Implementing JWT auth. DONE: Auth.Token module, generate/verify functions. TODO: Add to router, write tests. BLOCKER: Need to decide on token expiry time.",
  "files": ["lib/auth/token.ex", "lib/router.ex"],
  "created_at": "2025-01-15T10:30:00Z",
  "created_by": "agent_abc123"
}
```

**Example — Semantic Search:**
```json
// Input (fuzzy query — still works!)
{ "query": "that JWT thing I was working on" }

// Output — finds the right stash via embeddings
{
  "stash_id": "stash_abc123",
  "name": "auth-jwt-wip",
  "summary": "Implementing JWT auth...",
  "match_score": 0.89
}
```

### insight

Save a persistent insight. Insights never expire and are searchable by meaning.

```json
{
  "name": "insight",
  "description": "Save a persistent insight about the codebase.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "key": { "type": "string", "description": "Optional key for direct retrieval" },
      "content": { "type": "string", "description": "The insight content" }
    },
    "required": ["content"]
  }
}
```

**Example:**
```json
// Input
{ 
  "key": "auth-patterns",
  "content": "This codebase uses Guardian for JWT auth. Tokens expire in 24h. Refresh tokens stored in Redis. All auth errors return 401 with {error: 'unauthorized'}."
}

// Output
{
  "insight_id": "insight_xyz789",
  "key": "auth-patterns",
  "created_at": "2025-01-15T10:35:00Z",
  "tip": "Other agents can find this via `recall` with queries like 'how does auth work'"
}
```

### recall

Search insights semantically. Finds relevant info even with vague queries.

```json
{
  "name": "recall",
  "description": "Search insights by semantic similarity.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "What you want to know about" },
      "limit": { "type": "integer", "default": 5 }
    },
    "required": ["query"]
  }
}
```

**Example:**
```json
// Input (natural language query)
{ "query": "how do we handle authentication in this project", "limit": 3 }

// Output — semantic search finds relevant insights
{
  "results": [
    {
      "insight_id": "insight_xyz789",
      "key": "auth-patterns",
      "content": "This codebase uses Guardian for JWT auth. Tokens expire in 24h...",
      "match_score": 0.92
    },
    {
      "insight_id": "insight_abc456",
      "key": "api-security",
      "content": "All API endpoints require authentication except /health and /metrics...",
      "match_score": 0.78
    }
  ]
}
```

### acquire / release

Manual lock management. Usually you don't need these — `start_task`/`end_task` handle locks automatically.

```json
{
  "name": "acquire",
  "description": "Acquire exclusive lock on files.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "patterns": { "type": "array", "items": { "type": "string" } },
      "ttl_minutes": { "type": "integer", "default": 15 }
    },
    "required": ["patterns"]
  }
}
```

```json
{
  "name": "release",
  "description": "Release locks on files.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "patterns": { "type": "array", "items": { "type": "string" } }
    },
    "required": ["patterns"]
  }
}
```

**When to use manually:** Only when you need locks outside the normal task flow (rare).

### decide

Record an architectural decision. Other agents will see this and can query it.

```json
{
  "name": "decide",
  "description": "Record an architectural decision for all agents.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "topic": { "type": "string", "description": "What area this decision affects" },
      "decision": { "type": "string", "description": "The decision made" },
      "reasoning": { "type": "string", "description": "Why this decision was made" }
    },
    "required": ["topic", "decision"]
  }
}
```

**Example:**
```json
// Input
{
  "topic": "authentication",
  "decision": "Use Guardian library for JWT tokens",
  "reasoning": "Better Plug integration than alternatives. Active maintenance. Team has prior experience."
}

// Output
{
  "decision_id": "dec_abc123",
  "topic": "authentication",
  "created_at": "2025-01-15T10:40:00Z",
  "visibility": "all_agents",
  "tip": "Other agents starting auth-related tasks will see this decision automatically"
}
```

### who_is_working

See all active agents. Useful for understanding what's happening across the project.

```json
{
  "name": "who_is_working",
  "description": "See all active agents and what they're working on.",
  "inputSchema": { "type": "object", "properties": {} }
}
```

**Example:**
```json
// Input
{}

// Output
{
  "active_agents": [
    {
      "agent_id": "agent_abc123",
      "task": "Add JWT authentication to the API",
      "files_locked": ["lib/auth.ex", "lib/router.ex"],
      "started": "12 minutes ago"
    },
    {
      "agent_id": "agent_xyz789",
      "task": "Writing tests for user model",
      "files_locked": ["test/user_test.exs"],
      "started": "5 minutes ago"
    }
  ],
  "idle_agents": [
    { "agent_id": "agent_def456", "last_active": "2 hours ago" }
  ]
}
```

### report_cost

Report token usage for current session. Enables cost tracking and budgeting.

```json
{
  "name": "report_cost",
  "description": "Report token usage for the current session.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "tokens_in": { "type": "integer" },
      "tokens_out": { "type": "integer" },
      "model": { "type": "string", "default": "claude-3-sonnet" }
    },
    "required": ["tokens_in", "tokens_out"]
  }
}
```

**Example:**
```json
// Input
{ "tokens_in": 25000, "tokens_out": 12000, "model": "claude-3-5-sonnet" }

// Output
{
  "session_total": { "tokens_in": 40000, "tokens_out": 20000, "cost_usd": 0.24 },
  "today_total": { "tokens_in": 150000, "tokens_out": 75000, "cost_usd": 0.90 },
  "this_week": { "cost_usd": 4.50 }
}
```

### timeline

Get recent activity across all agents. Great for understanding what happened.

```json
{
  "name": "timeline",
  "description": "Get recent activity across all agents.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "limit": { "type": "integer", "default": 20 },
      "agent_id": { "type": "string", "description": "Filter to specific agent" }
    }
  }
}
```

**Example:**
```json
// Input
{ "limit": 5 }

// Output
{
  "activities": [
    { "time": "2 min ago", "agent": "agent_abc123", "type": "task_ended", "description": "Completed: Add JWT authentication" },
    { "time": "5 min ago", "agent": "agent_xyz789", "type": "decision", "description": "Decided: Use Guardian for JWT" },
    { "time": "14 min ago", "agent": "agent_abc123", "type": "task_started", "description": "Started: Add JWT authentication" },
    { "time": "20 min ago", "agent": "agent_abc123", "type": "stash", "description": "Stashed: auth-research" },
    { "time": "1 hour ago", "agent": "agent_def456", "type": "insight", "description": "Added insight: api-patterns" }
  ]
}
```

---

## PostgreSQL Schema

```sql
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS vector;

-- Agents (connected MCP clients)
CREATE TABLE agents (
  id TEXT PRIMARY KEY,
  name TEXT,
  current_task TEXT,
  status TEXT DEFAULT 'active',  -- active, idle, disconnected
  connected_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}'
);

CREATE INDEX agents_status_idx ON agents (status);

-- Stashes (like git stash)
CREATE TABLE stashes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  summary_embedding vector(384),  -- for semantic search
  files TEXT[],
  metadata JSONB DEFAULT '{}',
  created_by TEXT REFERENCES agents(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ  -- NULL = never expires
);

CREATE INDEX stashes_name_idx ON stashes (name);
CREATE INDEX stashes_embedding_idx ON stashes USING ivfflat (summary_embedding vector_cosine_ops);

-- Insights (persistent knowledge)
CREATE TABLE insights (
  id TEXT PRIMARY KEY,
  key TEXT,
  content TEXT NOT NULL,
  embedding vector(384),  -- for semantic search
  created_by TEXT REFERENCES agents(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX insights_key_idx ON insights (key);
CREATE INDEX insights_embedding_idx ON insights USING ivfflat (embedding vector_cosine_ops);

-- Decisions (shared across agents)
CREATE TABLE decisions (
  id TEXT PRIMARY KEY,
  topic TEXT NOT NULL,
  decision TEXT NOT NULL,
  reasoning TEXT,
  embedding vector(384),  -- for semantic search
  created_by TEXT REFERENCES agents(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX decisions_topic_idx ON decisions (topic, created_at DESC);
CREATE INDEX decisions_embedding_idx ON decisions USING ivfflat (embedding vector_cosine_ops);

-- Locks (file coordination)
CREATE TABLE locks (
  id TEXT PRIMARY KEY,
  pattern TEXT NOT NULL,  -- file path or glob
  agent_id TEXT REFERENCES agents(id),
  acquired_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ DEFAULT now() + interval '15 minutes'
);

CREATE INDEX locks_pattern_idx ON locks (pattern);
CREATE INDEX locks_expires_idx ON locks (expires_at);

-- Sessions (observability)
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  agent_id TEXT REFERENCES agents(id),
  task TEXT,
  status TEXT DEFAULT 'active',  -- active, completed, abandoned
  files_touched TEXT[],
  tokens_in INTEGER DEFAULT 0,
  tokens_out INTEGER DEFAULT 0,
  cost_usd DECIMAL(10,6) DEFAULT 0,
  started_at TIMESTAMPTZ DEFAULT now(),
  ended_at TIMESTAMPTZ
);

CREATE INDEX sessions_agent_idx ON sessions (agent_id, started_at DESC);
CREATE INDEX sessions_status_idx ON sessions (status);

-- Activity log (timeline)
CREATE TABLE activities (
  id BIGSERIAL PRIMARY KEY,
  agent_id TEXT REFERENCES agents(id),
  session_id TEXT REFERENCES sessions(id),
  type TEXT NOT NULL,  -- task_started, task_ended, decision, stash, lock_acquired, etc.
  description TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX activities_time_idx ON activities (created_at DESC);
CREATE INDEX activities_agent_idx ON activities (agent_id, created_at DESC);
CREATE INDEX activities_type_idx ON activities (type, created_at DESC);
```

---

## OTP Supervision Tree

```
PopStash.Supervisor (one_for_one)
├── PopStash.Repo (PostgreSQL + pgvector)
├── Phoenix.PubSub (real-time coordination)
│
├── PopStash.Memory.Embeddings (GenServer)
│   └── Loads Nx/Bumblebee model at startup
│
├── Registry (PopStash.Agents.Registry)
│   └── Tracks connected agents by ID
│
├── DynamicSupervisor (PopStash.Agents.Supervisor)
│   ├── PopStash.Agent.Connection (agent_A) ← GenServer per agent
│   ├── PopStash.Agent.Connection (agent_B)
│   └── PopStash.Agent.Connection (agent_C)
│
├── PopStash.Locks.Cleaner (GenServer)
│   └── Periodic cleanup of expired locks
│
└── PopStash.Telemetry
    └── OpenTelemetry span emission for all storage events
```

---

## Core Modules

### PopStash.Memory.Embeddings

```elixir
defmodule PopStash.Memory.Embeddings do
  @moduledoc """
  Local embeddings using Nx/Bumblebee.
  Loads all-MiniLM-L6-v2 at startup for 384-dimensional embeddings.
  """
  use GenServer
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end
  
  def embed(text) do
    GenServer.call(__MODULE__, {:embed, text})
  end
  
  @impl true
  def init(_opts) do
    {:ok, model} = Bumblebee.load_model({:hf, "sentence-transformers/all-MiniLM-L6-v2"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "sentence-transformers/all-MiniLM-L6-v2"})
    
    serving = Bumblebee.Text.TextEmbedding.text_embedding(model, tokenizer,
      compile: [batch_size: 1, sequence_length: 512],
      defn_options: [compiler: EXLA]
    )
    
    {:ok, %{serving: serving}}
  end
  
  @impl true
  def handle_call({:embed, text}, _from, %{serving: serving} = state) do
    %{embedding: embedding} = Nx.Serving.run(serving, text)
    {:reply, {:ok, Nx.to_flat_list(embedding)}, state}
  end
end
```

### PopStash.Agent.Connection

```elixir
defmodule PopStash.Agent.Connection do
  @moduledoc """
  GenServer representing a connected agent.
  Handles heartbeat, task tracking, and cleanup on disconnect.
  """
  use GenServer
  
  alias PopStash.{Repo, Coordination, Memory}
  alias PopStash.Coordination.{Agent, Lock, Session}
  
  @heartbeat_interval :timer.seconds(30)
  @heartbeat_timeout :timer.seconds(90)
  
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(agent_id))
  end
  
  def start_task(agent_id, task, files) do
    GenServer.call(via_tuple(agent_id), {:start_task, task, files})
  end
  
  def end_task(agent_id, summary) do
    GenServer.call(via_tuple(agent_id), {:end_task, summary})
  end
  
  def heartbeat(agent_id) do
    GenServer.cast(via_tuple(agent_id), :heartbeat)
  end
  
  @impl true
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    # Create or update agent record
    agent = %Agent{id: agent_id, status: "active", connected_at: DateTime.utc_now()}
    Repo.insert!(agent, on_conflict: :replace_all, conflict_target: :id)
    
    # Schedule heartbeat check
    Process.send_after(self(), :check_heartbeat, @heartbeat_interval)
    
    {:ok, %{
      agent_id: agent_id,
      current_session: nil,
      last_heartbeat: System.monotonic_time(:millisecond)
    }}
  end
  
  @impl true
  def handle_call({:start_task, task, files}, _from, state) do
    # Create session
    session = %Session{
      id: Nanoid.generate(),
      agent_id: state.agent_id,
      task: task,
      files_touched: files,
      started_at: DateTime.utc_now()
    }
    {:ok, session} = Repo.insert(session)
    
    # Acquire locks
    {acquired, conflicts} = Coordination.acquire_locks(state.agent_id, files)
    
    # Get relevant context
    context = %{
      relevant_stashes: Memory.search_stashes(task, limit: 3),
      relevant_insights: Memory.search_insights(task, limit: 5),
      recent_decisions: Coordination.recent_decisions(limit: 5),
      other_agents: Coordination.active_agents(exclude: state.agent_id)
    }
    
    response = %{
      agent_id: state.agent_id,
      session_id: session.id,
      locks: %{acquired: acquired, conflicts: conflicts},
      context: context
    }
    
    {:reply, {:ok, response}, %{state | current_session: session.id}}
  end
  
  @impl true
  def handle_call({:end_task, summary}, _from, state) do
    if state.current_session do
      # Update session
      Repo.get!(Session, state.current_session)
      |> Session.changeset(%{status: "completed", ended_at: DateTime.utc_now()})
      |> Repo.update!()
      
      # Release all locks
      Coordination.release_all_locks(state.agent_id)
      
      # Log activity
      Coordination.log_activity(state.agent_id, state.current_session, "task_ended", summary)
    end
    
    {:reply, :ok, %{state | current_session: nil}}
  end
  
  @impl true
  def handle_cast(:heartbeat, state) do
    {:noreply, %{state | last_heartbeat: System.monotonic_time(:millisecond)}}
  end
  
  @impl true
  def handle_info(:check_heartbeat, state) do
    now = System.monotonic_time(:millisecond)
    if now - state.last_heartbeat > @heartbeat_timeout do
      {:stop, :heartbeat_timeout, state}
    else
      Process.send_after(self(), :check_heartbeat, @heartbeat_interval)
      {:noreply, state}
    end
  end
  
  @impl true
  def terminate(_reason, state) do
    # Mark agent as disconnected
    Repo.get(Agent, state.agent_id)
    |> Agent.changeset(%{status: "disconnected"})
    |> Repo.update()
    
    # Release all locks
    Coordination.release_all_locks(state.agent_id)
  end
  
  defp via_tuple(agent_id) do
    {:via, Registry, {PopStash.Agents.Registry, agent_id}}
  end
end
```

### PopStash.Locks.Cleaner

```elixir
defmodule PopStash.Locks.Cleaner do
  @moduledoc """
  Periodic cleanup of expired locks.
  """
  use GenServer
  
  alias PopStash.Repo
  import Ecto.Query
  
  @cleanup_interval :timer.minutes(1)
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    Repo.delete_all(from l in "locks", where: l.expires_at < ^DateTime.utc_now())
    schedule_cleanup()
    {:noreply, state}
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
```

---

## Project Structure

```
pop_stash/
├── lib/
│   ├── pop_stash.ex                         # Public API facade
│   ├── pop_stash/
│   │   ├── application.ex              # OTP application, supervision tree
│   │   ├── repo.ex                     # Ecto repo
│   │   │
│   ├── memory.ex                   # Memory context (stash, insight, recall)
│   ├── memory/
│   │   ├── stash.ex                # Schema
│   │   ├── insight.ex              # Schema
│   │   └── embeddings.ex           # Nx/Bumblebee GenServer
│   │   │
│   │   ├── coordination.ex             # Coordination context
│   │   ├── coordination/
│   │   │   ├── agent.ex                # Schema
│   │   │   ├── lock.ex                 # Schema
│   │   │   ├── decision.ex             # Schema
│   │   │   └── session.ex              # Schema
│   │   │
│   │   ├── agent/
│   │   │   └── connection.ex           # GenServer per connected agent
│   │   │
│   │   ├── observability.ex            # Observability context
│   │   ├── observability/
│   │   │   ├── activity.ex             # Schema
│   │   │   └── cost_tracker.ex         # Token/cost calculations
│   │   │
│   │   ├── locks/
│   │   │   └── cleaner.ex              # Expired lock cleanup
│   │   │
│   │   ├── mcp/
│   │   │   ├── server.ex               # MCP protocol handler
│   │   │   ├── transport/
│   │   │   │   └── stdio.ex            # stdio transport
│   │   │   └── tools.ex                # Tool definitions
│   │   │
│   │   ├── pubsub.ex                   # PubSub wrapper
│   │   ├── telemetry.ex                # OpenTelemetry instrumentation
│   │   └── telemetry/
│   │       ├── storage_handler.ex      # Storage event handlers
│   │       └── ecto_handler.ex         # Ecto query instrumentation
│   │
├── priv/
│   └── repo/
│       └── migrations/
│           ├── 20250101000001_create_agents.exs
│           ├── 20250101000002_create_stashes.exs
│           ├── 20250101000003_create_insights.exs
│           ├── 20250101000004_create_decisions.exs
│           ├── 20250101000005_create_locks.exs
│           ├── 20250101000006_create_sessions.exs
│           └── 20250101000007_create_activities.exs
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
│
├── test/
│   ├── pop_stash/
│   │   ├── memory_test.exs
│   │   ├── coordination_test.exs
│   │   ├── observability_test.exs
│   │   └── mcp/
│   │       └── server_test.exs
│   ├── support/
│   │   └── fixtures.ex
│   └── test_helper.exs
│
├── mix.exs
├── docker-compose.yml
├── otel-collector-config.yaml
└── README.md
```

---

## Configuration

```elixir
# config/config.exs
import Config

config :pop_stash,
  ecto_repos: [PopStash.Repo]

config :pop_stash, PopStash.Repo,
  migration_primary_key: [type: :text]

# config/runtime.exs
import Config

config :pop_stash,
  project_name: System.get_env("DOSSIER_PROJECT_NAME", "default"),
  project_path: System.get_env("DOSSIER_PROJECT_PATH", "."),
  lock_expiry_minutes: System.get_env("DOSSIER_LOCK_EXPIRY", "15") |> String.to_integer()

config :pop_stash, PopStash.Repo,
  url: System.get_env("DATABASE_URL", "postgres://localhost/pop_stash_dev"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

config :nx, default_backend: EXLA.Backend

# OpenTelemetry Configuration
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

config :opentelemetry, :resource,
  service: [
    name: "pop_stash",
    namespace: System.get_env("DOSSIER_PROJECT_NAME", "default")
  ]
```

---

## Dependencies

```elixir
# mix.exs
defp deps do
  [
    # Database
    {:ecto_sql, "~> 3.11"},
    {:postgrex, "~> 0.18"},
    {:pgvector, "~> 0.2"},
    
    # Embeddings (local)
    {:nx, "~> 0.7"},
    {:bumblebee, "~> 0.5"},
    {:exla, "~> 0.7"},
    
    # JSON
    {:jason, "~> 1.4"},
    
    # PubSub
    {:phoenix_pubsub, "~> 2.1"},
    
    # IDs
    {:nanoid, "~> 2.1"},
    
    # Telemetry & OpenTelemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 1.0"},
    {:opentelemetry, "~> 1.4"},
    {:opentelemetry_api, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.7"},
    {:opentelemetry_ecto, "~> 1.2"},
    
    # Dev/Test
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

---

## Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: pop_stash_dev
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  # SigNoz OpenTelemetry Collector
  signoz-otel-collector:
    image: signoz/signoz-otel-collector:0.88.11
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
    depends_on:
      clickhouse:
        condition: service_healthy

  # ClickHouse for SigNoz storage
  clickhouse:
    image: clickhouse/clickhouse-server:24.1.2-alpine
    volumes:
      - signoz-clickhouse:/var/lib/clickhouse
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 5s
      timeout: 5s
      retries: 10

  # SigNoz Query Service
  signoz-query-service:
    image: signoz/query-service:0.45.0
    environment:
      ClickHouseUrl: tcp://clickhouse:9000
      STORAGE: clickhouse
    depends_on:
      clickhouse:
        condition: service_healthy
      signoz-otel-collector:
        condition: service_started

  # SigNoz Frontend
  signoz-frontend:
    image: signoz/frontend:0.45.0
    ports:
      - "3301:3301"
    depends_on:
      - signoz-query-service
    environment:
      FRONTEND_API_ENDPOINT: http://signoz-query-service:8080

volumes:
  pgdata:
  signoz-clickhouse:
```

### OpenTelemetry Collector Config

Create `otel-collector-config.yaml` in the project root:

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024

exporters:
  clickhousetraces:
    datasource: tcp://clickhouse:9000/?database=signoz_traces
  clickhousemetricswrite:
    endpoint: tcp://clickhouse:9000/?database=signoz_metrics
  clickhouselogs:
    dsn: tcp://clickhouse:9000/signoz_logs

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [clickhousetraces]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [clickhousemetricswrite]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [clickhouselogs]
```

---

## CLAUDE.md Integration

For agents to actually use PopStash, add to your project's CLAUDE.md:

```markdown
# Coordination Rules (REQUIRED)

This project uses PopStash for multi-agent coordination. You MUST follow these rules:

## At the start of every task:
Call `start_task` with what you're about to do and which files you'll edit.
If there are conflicts, STOP and report to the user.

## At the end of every task:
Call `end_task` with a summary of what you accomplished.

## When making architectural decisions:
Call `decide` to record the decision so other agents know.

## When you learn something important about the codebase:
Call `insight` to save it for future sessions.

## When context is getting long or you're switching tasks:
Call `stash` to save your current state.
```

---

## Build Phases

### Phase 1: MCP Foundation
- [ ] Project setup, dependencies, basic config
- [ ] **MCP protocol implementation (stdio transport)**
- [ ] **Basic supervision tree (MCP server + stdio handler)**
- [ ] **Implement `list_tools` and `call_tool` handlers**
- [ ] **First tool: `ping` (returns "pong" - validates end-to-end)**
- [ ] Manual testing with MCP inspector/Claude Code
- [ ] Tests for MCP protocol layer

### Phase 2: Memory Foundation + Tools
- [ ] PostgreSQL setup (docker-compose, basic tables only)
- [ ] Ecto schemas: stashes, insights (no embeddings yet)
- [ ] Simple in-memory storage (GenServer) as placeholder
- [ ] **MCP tools: `stash`, `pop` (by name only), `insight`, `recall` (exact key match)**
- [ ] Test with real MCP client
- [ ] Upgrade to Ecto persistence when working

### Phase 3: Coordination + Tools
- [ ] Ecto schemas: agents, locks, sessions, decisions
- [ ] Agent.Connection GenServer
- [ ] Lock manager (acquire/release, basic expiry)
- [ ] **MCP tools: `start_task`, `end_task`, `acquire`, `release`, `decide`, `who_is_working`**
- [ ] Test multi-agent scenarios with Claude Code
- [ ] PubSub for real-time updates

### Phase 4: Semantic Search
- [ ] pgvector setup
- [ ] Nx/Bumblebee embeddings GenServer
- [ ] Upgrade `pop` to semantic search
- [ ] Upgrade `recall` to semantic search
- [ ] Upgrade `decide` queries to semantic search
- [ ] Performance testing

### Phase 5: Observability + Tools
- [ ] Activity logging schema + context
- [ ] Cost tracking calculations
- [ ] **MCP tools: `report_cost`, `timeline`, `session_summary`**
- [ ] OpenTelemetry instrumentation
- [ ] SigNoz integration (optional, graceful degradation)

### Phase 6: Developer Experience
- [ ] "5-minute quickstart" validation
- [ ] Error messages with remediation
- [ ] All MCP tools documented with examples
- [ ] `pop_stash doctor` health check
- [ ] Lock cleanup background job

### Phase 7: Polish
- [ ] CLI (`pop_stash status`)
- [ ] Edge case handling
- [ ] End-to-end integration tests
- [ ] Production hardening
- [ ] Documentation

---

## Success Metrics

### Functional Metrics
- [ ] Agent can call `start_task` and get relevant context
- [ ] Two agents can't edit the same file simultaneously (locks work)
- [ ] Agent can stash context, disconnect, reconnect, and pop it
- [ ] Semantic search returns relevant insights/decisions
- [ ] Decisions are visible to all agents
- [ ] Timeline shows all activity across agents
- [ ] Cost tracking shows token usage per session
- [ ] GenServer crashes don't lose state (DB persistence)
- [ ] Disconnected agents release their locks
- [ ] All storage events visible in SigNoz traces

### Developer Experience Metrics (Non-Negotiable)
- [ ] Time from `git clone` to first `start_task`: **< 5 minutes**
- [ ] Zero configuration required for basic usage
- [ ] Every error message includes remediation steps
- [ ] Documentation coverage: 100% of public tools
- [ ] Works in "degraded mode" without SigNoz/embeddings

---

## What This Is NOT

- **Not an LLM orchestrator** — we don't call LLMs, agents do
- **Not a workflow engine** — no chain-of-thought, map-reduce, etc.
- **Not a code execution environment** — no shell access, no file writes
- **Not competing with Claude Code** — we augment it

---

## The Pitch

### The Problem No One's Talking About

You wouldn't hire a developer with amnesia.

You wouldn't put three engineers on the same file without telling them.

You wouldn't pay someone to relearn your codebase every single morning.

**But that's exactly what you're doing with AI agents.**

Every session starts from zero. Every context window eventually fills up and dies. Every dollar you spend on tokens? A chunk of it is just re-explaining what you explained yesterday.

And if you're running multiple agents? Chaos. They'll edit the same file. Make contradictory decisions. Step on each other's work. You won't know until something breaks.

This isn't an AI problem. It's an infrastructure problem.

### The Insight

Human development teams figured this out decades ago:
- **Git** so we don't lose work
- **Project management** so we don't collide  
- **Monitoring** so we know what happened

AI agents have none of this. They're incredibly capable individuals with zero organizational infrastructure.

**PopStash is that infrastructure.**

### What Changes

| Before PopStash | After PopStash |
|----------------|---------------|
| "Where were we?" | Agent picks up exactly where it left off |
| "Did you already try that?" | Decisions are recorded, searchable, shared |
| "Who broke this file?" | You know who touched what, when, why |
| "This is costing HOW much?" | Cost per task, per session, per agent |
| Hope agents don't conflict | *They can't.* Locks prevent it. |

### Who This Is For

PopStash is for developers who:
- Use AI agents for real work, not demos
- Have felt the pain of re-explaining context
- Run (or want to run) multiple agents on one codebase
- Care about cost, accountability, and control

It's not for everyone. It's for the people building the future of software development.

### The Technical Truth

For the engineers who want to know how:

- **Elixir/OTP** — Fault-tolerant by design. Agents crash? State persists. 
- **PostgreSQL + pgvector** — Your context stored forever, searchable by meaning
- **Local embeddings** — Nx/Bumblebee, no API calls, no data leaving your machine
- **OpenTelemetry → SigNoz** — Every operation traced. Full observability.
- **MCP Protocol** — Works with Claude Code, Cursor, Cline. Any MCP client.

### The One-Liner

**PopStash: Memory, coordination, and accountability for AI agents.**

Because the bottleneck isn't AI capability anymore. It's AI infrastructure.

---

## Why Now?

A year ago, AI agents were toys. Demos. Impressive but impractical.

Today, developers are shipping real code with Claude Code, Cursor, and Cline. Multiple agents. Real projects. Real money.

But the infrastructure hasn't caught up.

We're in the "before Git" era of AI development. Everyone's copying files around, hoping nothing breaks, praying agents don't collide. It works until it doesn't.

**The shift is happening.** The developers who figure out AI agent infrastructure first will have a massive advantage. Not because their agents are smarter — everyone has access to the same models — but because their agents are *organized*.

PopStash is a bet on that shift.

The question isn't whether AI agents need memory and coordination. They obviously do. The question is whether you'll have it when your competitors don't.

---

## Appendix

### Why PostgreSQL, Not Git

The pitch says "Git for AI agent state." The architecture uses PostgreSQL. Why?

**Git is the metaphor.** It communicates the role: persistent, versioned, essential infrastructure that every serious project needs.

**PostgreSQL is the implementation.** Because you need things Git simply cannot do:

| Requirement | Git | PostgreSQL + pgvector |
|-------------|-----|----------------------|
| "Find insights about authentication" | Grep through files | `ORDER BY embedding <=> $query LIMIT 5` |
| "Who's working right now?" | Parse file timestamps | `SELECT * FROM agents WHERE status = 'active'` |
| "Total cost this week" | Script it yourself | `SELECT SUM(cost_usd) FROM sessions` |
| Lock expiry after 15 minutes | Manual cleanup | `WHERE expires_at < now()` |
| Multiple agents writing concurrently | Merge conflicts | Transactions just work |

The metaphor helps people understand what PopStash *is*. The database lets you actually *build* it.

---

### The Bottom Line

AI agents are good enough now. The models aren't the bottleneck.

**Infrastructure is the bottleneck.**

Memory. Coordination. Accountability. The boring stuff that makes the brilliant stuff actually work.

That's PopStash.
