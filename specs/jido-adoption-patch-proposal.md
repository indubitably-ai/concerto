# Jido-Inspired Patch Proposal for `spec.md`

Status: Proposal

Purpose: Capture specific, reviewable improvements to [spec.md](/Users/gp/src/concerto/specs/spec.md) based on patterns observed in the Jido Elixir runtime at `/Users/gp/src/jido`.

This proposal does not recommend adopting Jido wholesale. It recommends importing a small number of runtime and observability patterns that fit Symphony's problem shape:

- append-only per-issue run journals
- typed observability event contracts
- causal trace propagation
- recent-event debug buffers
- optional keyed worker ownership as an implementation pattern

## Summary

Jido is a general OTP agent runtime. Symphony is a specialized scheduler/runner for issue-driven Codex sessions. The useful overlap is operational discipline, not the full signal/directive/plugin abstraction.

The strongest adoptable ideas from Jido are:

- Separate current state from append-only history.
- Enforce persistence invariants in one place.
- Treat observability schemas as contracts, not conventions.
- Carry causal trace metadata through runtime events.
- Offer a lightweight recent-events surface for debugging.

The parts that should not be copied into Symphony's spec are:

- state-based completion as the primary execution model
- generic multi-agent orchestration abstractions
- pooled reusable agents as a default runtime shape

## Proposed Changes

### 1. Add `Run Journal` as an Optional First-Class Entity

Insert after Section 4.1.6 in [spec.md](/Users/gp/src/concerto/specs/spec.md).

```md
#### 4.1.6A Run Journal (Optional but Recommended)

Append-only per-issue event log used for debugging, replay, and operational forensics.

Design goals:

- Preserve "what happened" independently of the current in-memory worker state.
- Support incremental persistence without serializing large live session structs repeatedly.
- Enable future restart recovery and postmortem debugging.

Fields:

- `issue_id`
- `issue_identifier`
- `journal_id` (string)
- `rev` (integer, monotonic append revision)
- `entries` (ordered list of journal entries)

Each journal entry should include:

- `seq` (integer, monotonic per journal)
- `timestamp` (UTC timestamp)
- `kind` (enum/string)
- `payload` (map)

Recommended entry kinds:

- `dispatch_started`
- `workspace_prepared`
- `hook_started`
- `hook_finished`
- `session_started`
- `turn_started`
- `codex_event`
- `turn_finished`
- `worker_finished`
- `retry_scheduled`
- `reconciliation_stop`
- `workspace_cleaned`
- `error`

Persistence and retention are implementation-defined.

If persistence is implemented:

- The journal should be append-only.
- Checkpoints/snapshots must not embed the full journal body.
- A snapshot may store only a journal pointer such as `{journal_id, rev}`.
```

Why:

- The current spec keeps only current live-session fields and aggregate logs. That is enough to operate the system, but not enough to reconstruct behavior cleanly after failures or for deep debugging.
- Jido's `Thread` plus `Persist` split is a strong model here: append-only journal as history, snapshot as current state pointer.

Pros:

- Stronger debugging and forensic value.
- Cleaner future path to partial restart recovery.
- Better base for issue-specific debug endpoints.

Cons:

- Adds storage and retention design decisions.
- Risks over-logging if event kinds are not scoped carefully.
- Can become a second observability system if not positioned clearly.

### 2. Add an Explicit Observability Event Contract

Insert after Section 13.1 in [spec.md](/Users/gp/src/concerto/specs/spec.md).

```md
### 13.1A Runtime Event Contract

Implementations should define a typed runtime event contract for structured observability.

Each emitted event should have:

- `name` (stable event name)
- `timestamp` (UTC timestamp)
- `metadata` (map)
- `measurements` (map)

Required metadata keys for all issue-scoped events:

- `issue_id`
- `issue_identifier`

Required metadata keys for session-scoped events:

- `session_id`

Recommended additional metadata keys:

- `worker_id`
- `attempt`
- `trace_id`
- `span_id`
- `parent_span_id`
- `event_source`

Recommended event families:

- `orchestrator.tick.*`
- `orchestrator.dispatch.*`
- `orchestrator.retry.*`
- `orchestrator.reconcile.*`
- `workspace.hook.*`
- `workspace.cleanup.*`
- `agent.session.*`
- `agent.turn.*`
- `tracker.request.*`
- `tracker.response.*`

If an implementation validates event metadata/measurements before emission, validation failures
should not crash the service; they should be surfaced through operator-visible diagnostics.
```

Why:

- Section 13 currently requires structured logs but does not define a stable event schema.
- Jido's event contract helpers and telemetry event families reduce drift between implementations and tests.

Pros:

- Makes observability testable and portable.
- Reduces schema drift across runtime components.
- Improves compatibility with metrics/tracing/reporting backends.

Cons:

- Slightly increases implementation ceremony.
- Some teams may treat this as heavier than necessary for a single-node daemon.

### 3. Add Causal Trace Propagation

Insert into Section 4.1.6 and Section 13.

```md
Additional recommended live-session fields:

- `trace_id` (string or null)
- `span_id` (string or null)
- `parent_span_id` (string or null)
- `causation_id` (string or null)
```

```md
### 13.1B Trace Correlation

Implementations should propagate causal trace metadata across orchestrator and worker boundaries.

Recommended fields:

- `trace_id`
- `span_id`
- `parent_span_id`
- `causation_id`

Trace propagation should preserve at least this causal chain:

poll tick -> dispatch decision -> worker start -> app-server session -> turn -> tool call/result

These fields are observability metadata only and must not be required for orchestrator correctness.
```

Why:

- Today the spec requires `issue_id`, `issue_identifier`, and `session_id`, which is useful but shallow.
- Jido's tracing model makes it easier to follow cause-and-effect chains across async boundaries.

Pros:

- Better debugging of race conditions and retries.
- Easier to correlate tracker requests, hooks, and Codex events within one run.

Cons:

- More metadata plumbing.
- Some implementations will emit IDs without integrating a full tracing backend.

### 4. Add Optional Recent-Events Debug Surface

Insert after Section 13.6 in [spec.md](/Users/gp/src/concerto/specs/spec.md).

```md
### 13.6A Recent Events Buffer (Optional)

Implementations may keep a bounded in-memory ring buffer of recent runtime events for debugging.

Recommended properties:

- bounded capacity per running issue/session
- newest-first or oldest-first ordering, documented by the implementation
- not required to be durable
- safe to disable in production or reduce capacity

Recommended event row fields:

- `at`
- `event`
- `message`
- `metadata`

This buffer is a debugging aid and must not be treated as the system of record.
```

Add optional HTTP endpoint under Section 13.7.2:

```md
- `GET /api/v1/<issue_identifier>/events`
  - Returns recent in-memory events for the issue/session when supported.
  - Suggested response shape:

    ```json
    {
      "issue_identifier": "MT-649",
      "events": [
        {
          "at": "2026-02-24T20:14:59Z",
          "event": "turn_started",
          "message": "starting continuation turn",
          "metadata": {
            "session_id": "thread-1-turn-2"
          }
        }
      ]
    }
    ```
```

Why:

- Jido's debug ring buffer is a pragmatic middle ground between raw logs and full event persistence.
- Symphony's current optional dashboard/API would benefit from a focused per-issue event tail.

Pros:

- Very high debugging value for low implementation cost.
- No durability requirement.
- Useful even when log aggregation is weak.

Cons:

- Can be mistaken for an audit trail if not labeled clearly.
- Memory overhead scales with concurrent sessions.

### 5. Add Optional Implementation Guidance for Keyed Worker Ownership

Insert near Section 7 or Section 16 as non-normative implementation guidance.

```md
Implementation note:

An implementation may model per-issue worker ownership as a keyed singleton runtime:

- one live worker owner per `issue_id`
- registry lookup by `issue_id`
- supervised worker lifecycle under a dynamic supervisor
- optional idle shutdown or hibernation for issue-scoped runtime state

This is an implementation technique only. The normative behavior remains the orchestration state
machine defined in Sections 7 and 8.
```

Why:

- Jido's `InstanceManager` is a good Elixir pattern for "one logical owner per key".
- This fits Symphony's "claimed/running/retrying by issue ID" model well, without changing the spec's language-agnostic contract.

Pros:

- Good fit for Elixir implementation structure.
- Clarifies worker ownership and duplicate-prevention mechanics.

Cons:

- Too runtime-specific to make normative.
- Less useful outside actor/supervision-oriented implementations.

## Things Not Recommended For Adoption

### 1. Do Not Make Generic Signals/Directives the Public Symphony Model

Why:

- Jido is solving a broader problem than Symphony.
- Symphony already has the right public abstractions: issue tracker, workspace manager, agent runner, orchestrator.

Pros of not adopting:

- Keeps the spec concrete and portable.
- Avoids hiding core operational semantics behind a generic runtime DSL.

Cons:

- Elixir implementations lose some reuse if they already standardize on a Jido-style runtime.

### 2. Do Not Replace Worker Completion With State-Based Completion

Why:

- Jido treats completion as agent state while the server process can remain alive.
- Symphony's unit of work is an app-server subprocess/session with explicit completion, timeout, stall, and reconciliation behavior.

Pros of not adopting:

- Preserves the correct operational boundary around Codex sessions.
- Keeps retry semantics tied to real worker/session outcomes.

Cons:

- Less flexibility for very long-lived conversational workers.

### 3. Do Not Add Pooled Reusable Workers As a Default Pattern

Why:

- Symphony requires per-issue workspace isolation and often per-run freshness.
- Reusing warm workers is at odds with the spec's workspace and issue-ownership model.

Pros of not adopting:

- Fewer isolation hazards.
- Easier reasoning about workspace state and retries.

Cons:

- Misses some throughput optimization opportunities for specific subcomponents.

## Recommended Adoption Order

1. Add runtime event contract.
2. Add causal trace metadata.
3. Add recent-events debug buffer.
4. Add optional run journal.
5. Add non-normative keyed worker ownership note.

This order keeps the first changes small and operationally valuable before introducing any persistence-oriented design surface.

## Source Basis

The proposal is based primarily on these Jido components:

- [README.md](/Users/gp/src/jido/README.md:30)
- [agent_server.ex](/Users/gp/src/jido/lib/jido/agent_server.ex:1)
- [thread.ex](/Users/gp/src/jido/lib/jido/thread.ex:1)
- [persist.ex](/Users/gp/src/jido/lib/jido/persist.ex:1)
- [event_contract.ex](/Users/gp/src/jido/lib/jido/observe/event_contract.ex:1)
- [trace.ex](/Users/gp/src/jido/lib/jido/tracing/trace.ex:1)
- [telemetry.ex](/Users/gp/src/jido/lib/jido/telemetry.ex:1)
- [instance_manager.ex](/Users/gp/src/jido/lib/jido/agent/instance_manager.ex:1)
