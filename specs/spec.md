# Concerto Minimal Service Specification

Status: Draft v1 minimal usable foundation

Purpose: define the smallest useful Concerto that can continuously pull engineering work from
Postgres, materialize runnable workspaces, run Codex against that work inside isolated Linux
containers, and remain easy to understand, change, and operate.

This document intentionally replaces the earlier multi-layer, infrastructure-heavy draft with a
single normative v1 specification. The base system is one Elixir/OTP application, one host-side
workflow root containing `WORKFLOW.md`, one read-only Postgres work source, local durable
workspaces, code-defined workspace materialization, `../codex-indubitably` app-server execution
inside isolated Linux containers, structured runtime events, and evidence-driven validation.

## 1. Design Principles

### 1.1 Small Enough to Understand

Concerto is a single-node service, not a platform.

- One OTP application owns the full runtime.
- One orchestrator process owns dispatch decisions.
- One worker process exists per active `work_item_id`.
- Temporary agent containers are execution sandboxes, not microservices.
- The base design should fit in a small number of source files and avoid deep abstraction stacks.

If the implementation becomes hard to explain end to end, it has likely exceeded the intent of this
specification.

### 1.2 Secure by Isolation

Codex must never run directly on the host in base v1.

- Every run attempt executes inside a Linux container.
- The host orchestrator chooses the container image, Codex command, and mount list in code.
- The agent can access only paths explicitly mounted into the container.
- The per-work-item workspace is the only required host-side writable mount.

This specification does not define a single container runtime. Docker, Apple Container, and other
OCI-compatible Linux container runtimes are acceptable if they provide equivalent isolation.

### 1.3 Built for the Individual User

Concerto is designed to be forked and adapted by a small team or individual operator.

- The base specification avoids framework-style feature breadth.
- The service remains read-only against the work source in v1.
- Business-system writes are performed by the agent and/or external automation, not by Concerto
  itself.

### 1.4 Customization Equals Code Changes

The base specification keeps the workflow schema intentionally small.

- Codex runtime details, container image selection, materialization behavior, mount policy, timeout
  defaults, and deployment details are implementation constants.
- Advanced behavior should be added by changing code in a fork, not by growing a generic config
  surface.
- Supporting a second agent harness is an extension, not a base requirement. Codex is the only
  normative harness in v1.

### 1.5 AI-Native Operations

Base v1 does not require a dashboard, debugging API, or installation wizard.

- Structured logs are required.
- Structured runtime events are required.
- Inspectable workspaces, captured app-server transcripts, and stderr artifacts are sufficient for
  base debugging.
- Operator-facing HTTP endpoints are out of scope for base conformance.

### 1.6 Skills Over Features

Optional capabilities should arrive as targeted code changes or repo-local skills that transform a
fork.

The base specification should not absorb every optional behavior into always-on core functionality.

### 1.7 Repo-Owned Validation

Concerto keeps its operating contract in repo-owned documents.

- [spec.md](/Users/gp/src/concerto/specs/spec.md) is the normative runtime contract.
- [acceptance-matrix.md](/Users/gp/src/concerto/specs/acceptance-matrix.md) is the concrete
  completion gate.
- [harness-architecture.md](/Users/gp/src/concerto/specs/harness-architecture.md) is the system of
  record for validation layers, evidence bundles, and release-blocking smoke requirements.

This follows the
[Harness Engineering](https://openai.com/index/harness-engineering/) principle that the harness and
its documentation should stay legible, repo-owned, and directly executable.

## 2. Goals and Non-Goals

### 2.1 Goals

- Poll a read-only Postgres work source on a fixed cadence.
- Select dispatchable work with bounded concurrency.
- Create and reuse deterministic local workspaces.
- Materialize the code and artifacts needed for real engineering work through a code-defined,
  idempotent workspace materializer.
- Run Codex in isolated Linux containers, never on the host.
- Allow bounded in-process continuation on the same app-server thread, capped at five turns per run
  attempt.
- Stop active work when the source lifecycle becomes ineligible.
- Emit enough events, logs, and evidence to understand what the service is doing.
- Keep the implementation single-node, single-process, and easy to modify.

### 2.2 Non-Goals

- Distributed orchestration, leader election, or multi-node coordination.
- Generic workflow-engine behavior.
- Built-in retry queues or backoff schedulers.
- Cross-run Codex thread resume or fork behavior.
- Prompt templating engines.
- Workflow-defined hooks for workspace setup or cleanup.
- A plugin framework for multiple agent harnesses.
- Required dashboards, REST APIs, health endpoints, token accounting, or cloud-specific
  observability.
- Cloud-specific deployment lock-in.

## 3. Minimal Architecture

### 3.1 Runtime Shape

The normative v1 implementation is an Elixir/OTP application with this shape:

1. One top-level OTP application.
2. One authoritative `Orchestrator` `GenServer`.
3. One `DynamicSupervisor` for active workers.
4. One worker process per active `work_item_id`.
5. One Postgres adapter used only for reads.
6. One workspace manager used only for deterministic workspace paths and directory creation.
7. One workspace materializer used only for ensuring a workspace contains the code and artifacts
   needed for the agent to do useful work.
8. One container runner that launches Codex inside isolated Linux containers.

The orchestrator is the only component that mutates scheduling state.

### 3.2 Required Components

#### Orchestrator

- Owns the poll timer.
- Tracks current effective config and active runs.
- Reconciles running work items against source lifecycle.
- Dispatches new work when slots are available.

#### Work Source Adapter

- Reads dispatch candidates from Postgres.
- Reads current lifecycle state for active work items.
- Normalizes rows into the `WorkItem` model in Section 4.

#### Workspace Manager

- Maps `workspace_key` to a deterministic local path.
- Creates the workspace directory if it does not exist.
- Reuses the same path for later runs of the same `workspace_key`.

#### Workspace Materializer

- Ensures a workspace contains the code and artifacts needed by the agent.
- Is chosen entirely in code, not by `WORKFLOW.md`.
- Must be idempotent on an already materialized workspace.

#### Worker

- Ensures the workspace exists.
- Ensures the workspace is materialized.
- Assembles the final prompt from `WORKFLOW.md` plus the normalized work item.
- Launches a short-lived Linux container with the workspace mounted writable.
- Makes `WORKFLOW.md` available read-only inside the container when the implementation exposes it.
- Starts Codex app-server inside the container.
- Runs one app-server session for up to five turns on a single thread.
- Captures structured events, logs, app-server transcript, and stderr artifacts.
- Reports the terminal outcome to the orchestrator.

#### Runtime Events and Logging

- Emit typed runtime events for startup, dispatch, materialization, session lifecycle, completion,
  failure, reconciliation, and Postgres read failures.
- Emit structured logs for operator visibility and postmortem debugging.

### 3.3 External Dependencies

- Postgres reachable with read-only credentials.
- Local durable storage for workspaces, state, and evidence artifacts.
- A Linux container runtime capable of launching isolated containers.
- A container image that includes Codex and can run `codex app-server`.
- A compatible `../codex-indubitably` build for integration and smoke validation.

## 4. Core Data Contracts

### 4.1 WorkItem

`WorkItem` is the normalized unit of dispatch.

Required fields:

- `work_item_id` (string)
- `workspace_key` (string)
- `dispatch_revision` (string)
- `lifecycle_state` (`dispatchable` | `inactive` | `terminal`)
- `prompt_context` (map)

Optional fields:

- `priority` (integer or null)

Normalization rules:

- `work_item_id` must be non-empty text.
- `workspace_key` must match `[A-Za-z0-9._-]+`.
- `dispatch_revision` must be non-empty text.
- `lifecycle_state` must be exactly one of `dispatchable`, `inactive`, or `terminal`.
- `prompt_context` must normalize to a JSON object. Missing values normalize to `{}`.
- `priority` must normalize to an integer or `null`.

### 4.2 WorkflowConfig

`WorkflowConfig` is the typed view of the minimal `WORKFLOW.md` front matter.

Fields:

- `work_source.dsn` (string)
- `work_source.schema` (string)
- `workspace.root` (path string)
- `polling.interval_ms` (integer, default `30000`)
- `agent.max_concurrent_agents` (integer, default `1`)

Required validations:

- `work_source.dsn` must be non-empty.
- `work_source.schema` must be non-empty.
- `workspace.root` must be non-empty.
- `polling.interval_ms` must be a positive integer.
- `agent.max_concurrent_agents` must be a positive integer.

No additional workflow keys are defined for materialization, provider selection, model selection,
approval behavior, auth behavior, or turn limits.

### 4.3 Workspace

A `Workspace` is the durable directory assigned to one `workspace_key`.

Fields:

- `workspace_key`
- `path`
- `created_now` (boolean)
- `materialized_now` (boolean)

The required path rule is:

- `workspace.path = join(workspace.root, workspace_key)`

### 4.4 WorkspaceMaterialization

`WorkspaceMaterialization` is the result of the code-defined workspace materializer.

Fields:

- `workspace_key`
- `workspace_path`
- `materialized_now` (boolean)
- `ready` (boolean)

Rules:

- `ready = true` means the workspace contains the code and artifacts the agent needs for the run.
- The materializer may clone, checkout, sync, copy, or generate artifacts in code-defined ways.
- The materializer must be idempotent. Reuse of an already prepared workspace must not corrupt it.
- The materializer is not configured by `WORKFLOW.md` or the Postgres row.

### 4.5 RunAttempt

A `RunAttempt` is one worker lifecycle for one `work_item_id`.

Fields:

- `work_item_id`
- `workspace_key`
- `dispatch_revision`
- `workspace_path`
- `thread_id` (string or null)
- `last_turn_id` (string or null)
- `turn_count` (integer)
- `trace` (`TraceContext`)
- `started_at`
- `stop_reason`
- `status`

Allowed `status` values:

- `completed`
- `failed`
- `canceled_by_reconciliation`

Required `stop_reason` values:

- `turn_completed`
- `turn_cap_reached`
- `timeout`
- `codex_failed`
- `startup_failed`
- `reconciliation`

Important boundary:

- `completed` means the Codex attempt ended normally or hit the defined turn cap without protocol or
  timeout failure.
- `completed` does not mean the business task is permanently finished.
- A later poll may dispatch the same work item again only when the source still reports
  `lifecycle_state = dispatchable` and `dispatch_revision` has changed since the last terminal
  attempt for that `work_item_id`.

### 4.6 TraceContext

`TraceContext` is the causal metadata propagated across orchestrator, worker, session, and turn
boundaries.

Fields:

- `trace_id` (string)
- `span_id` (string)
- `parent_span_id` (string or null)
- `causation_id` (string or null)

These fields are observability metadata only and must not be used to decide work-item eligibility.

### 4.7 RuntimeEvent

`RuntimeEvent` is the typed runtime observability contract for Concerto.

Fields:

- `name` (stable event name)
- `timestamp` (UTC timestamp)
- `metadata` (map)
- `measurements` (map)

Required metadata keys for all work-item-scoped events:

- `work_item_id`
- `workspace_key`
- `dispatch_revision`
- `trace_id`
- `span_id`

Required metadata keys for session-scoped events:

- `thread_id`
- `turn_id` when a turn exists

Required event names:

- `startup_succeeded`
- `startup_failed`
- `dispatch_started`
- `workspace_created`
- `workspace_reused`
- `workspace_materialized`
- `workspace_materialization_skipped`
- `container_launched`
- `session_started`
- `turn_started`
- `turn_completed`
- `turn_failed`
- `turn_interrupted`
- `attempt_completed`
- `attempt_failed`
- `reconciliation_stop`
- `orphan_cleanup`
- `postgres_read_failed`
- `event_contract_violation`

### 4.8 EvidenceBundle

`EvidenceBundle` is the retained artifact set for one validation scenario.

Fields:

- `scenario_id`
- `layer`
- `command`
- `exit_status`
- `started_at`
- `finished_at`
- `redacted_env` (map)
- `artifacts` (map of logical artifact name to relative path)

Required artifact names:

- `test_output`
- `structured_log`
- `app_server_transcript` when the scenario starts Codex
- `stderr` when the scenario starts Codex

The canonical storage layout is defined in
[harness-architecture.md](/Users/gp/src/concerto/specs/harness-architecture.md).

### 4.9 Runtime State

The orchestrator keeps only the minimum in-memory state required for base behavior:

- the current `WorkflowConfig`
- `running`, a map of `work_item_id -> worker metadata`

Base v1 also requires a durable local state directory for:

- the last terminal `dispatch_revision` seen for each `work_item_id`
- active run ownership manifests used for precise orphan cleanup

Base v1 does not require retry queues, token totals, rate-limit state, run journals, or recent
event buffers.

## 5. `WORKFLOW.md` Contract

### 5.1 File Location and Loading

- Concerto reads exactly one `WORKFLOW.md`.
- The file lives under one host-side workflow root chosen outside `WORKFLOW.md`.
- The workflow root is distinct from per-work-item workspace directories.
- Per-work-item workspaces do not need to be repository roots and do not own the authoritative
  `WORKFLOW.md`.
- The file is loaded and validated at startup.
- If the file is missing or invalid, the service must fail fast and refuse to dispatch work.
- Changes require a service restart in base v1.

If the implementation mounts `WORKFLOW.md` into the container for agent inspection, it must mount
the file read-only.

There is no file-discovery precedence across workspaces and no hot reload in base conformance.

### 5.2 File Format

`WORKFLOW.md` uses YAML front matter followed by a Markdown body.

Example:

```md
---
work_source:
  dsn: postgres://concerto:secret@db.example.internal/app
  schema: concerto
workspace:
  root: /var/lib/concerto/workspaces
polling:
  interval_ms: 30000
agent:
  max_concurrent_agents: 2
---
# Concerto Workflow

Review the work item, make the required changes in the workspace, and leave the workspace in a
state that a later run can continue from if needed.
```

### 5.3 Front Matter Schema

Only these keys are defined by the base specification:

- `work_source`
  - `dsn`
  - `schema`
- `workspace`
  - `root`
- `polling`
  - `interval_ms`
- `agent`
  - `max_concurrent_agents`

Rules:

- Unknown keys must be ignored by the base parser.
- The base specification does not define extension keys.
- Codex runtime details are not part of `WORKFLOW.md` in v1.

### 5.4 Prompt Assembly

The Markdown body of `WORKFLOW.md` is static instructions. Concerto does not evaluate template
syntax in base v1.

For the first turn of each run attempt, Concerto assembles the final prompt as:

1. The raw Markdown body of `WORKFLOW.md`
2. A blank line
3. A fixed heading: `## Work Item`
4. A fenced `json` block containing the normalized `WorkItem`

Required format:

````md
<workflow body>

## Work Item
```json
{"work_item_id":"...","workspace_key":"...","dispatch_revision":"...","lifecycle_state":"dispatchable","prompt_context":{...},"priority":1}
```
````

Rules:

- The JSON payload must reflect the normalized `WorkItem` fields from Section 4.1.
- No variable interpolation is performed.
- No template filters or conditionals exist in base v1.
- The full assembled prompt is sent only for the first turn of the run attempt.
- Continuation turns must send fixed continuation guidance and must not re-send the full prompt.

## 6. Postgres Work Source Contract

### 6.1 Operations

The base Postgres adapter exposes exactly two operations:

1. `fetch_dispatch_candidates(limit)`
2. `fetch_work_item_states(work_item_ids)`

Concerto remains read-only against Postgres in v1.

### 6.2 Fixed Views

The base specification requires two views under `work_source.schema`:

- `dispatch_candidates_view`
- `work_item_states_view`

There is no workflow-configured view renaming in base v1.

### 6.3 `dispatch_candidates_view`

Required columns:

- `work_item_id text`
- `workspace_key text`
- `dispatch_revision text`
- `lifecycle_state text`
- `prompt_context jsonb`

Optional columns:

- `priority bigint`

### 6.4 `work_item_states_view`

Required columns:

- `work_item_id text`
- `workspace_key text`
- `dispatch_revision text`
- `lifecycle_state text`

### 6.5 Adapter Behavior

- `fetch_dispatch_candidates(limit)` returns normalized `WorkItem` rows from
  `schema.dispatch_candidates_view`.
- `fetch_work_item_states(work_item_ids)` returns the current lifecycle rows for the supplied IDs
  from `schema.work_item_states_view`.
- `fetch_dispatch_candidates(limit)` must normalize values according to Section 4.1.
- `fetch_work_item_states(work_item_ids)` must normalize `work_item_id`, `workspace_key`,
  `dispatch_revision`, and `lifecycle_state` using the same rules as Section 4.1.
- Invalid rows must be skipped with an operator-visible log entry rather than crashing the service.

## 7. Workspace, Materialization, and Container Isolation

### 7.1 Workspace Rules

- Each `workspace_key` maps to one durable directory under `workspace.root`.
- The worker must create the directory if it does not exist.
- Later runs for the same `workspace_key` must reuse the same path.
- Base v1 does not require automatic workspace cleanup.

### 7.2 Workspace Materializer

The base specification requires a code-defined workspace materializer.

Rules:

- The materializer runs before the first dispatch for a workspace and may be called again on reuse.
- The materializer must be idempotent. Re-running it on an already prepared workspace must preserve
  a usable workspace.
- The materializer is responsible for ensuring the workspace contains the code and artifacts needed
  for real engineering work.
- The materializer is not configured by `WORKFLOW.md`.
- Materializer failures are fatal to the current run attempt and must emit operator-visible logs and
  runtime events.

### 7.3 Isolation Rules

- The agent must run only inside a Linux container.
- The per-work-item workspace is the only required host-side writable mount.
- `WORKFLOW.md` may be mounted read-only when the implementation exposes it to the container.
- The container must also have a writable ephemeral internal directory used as `CODEX_HOME`.
- Auth material, when file-based, must be mounted read-only.
- Additional mounts are extension-only and must be explicitly chosen in code.
- The host orchestrator must not expose the full host filesystem by default.
- The host process remains the authority for container lifecycle and mount selection.

### 7.4 Ownership Markers and Orphan Cleanup

Each run attempt must have a stable `run_id`.

Required ownership markers:

- Every launched container must carry labels:
  - `concerto.owner=concerto`
  - `concerto.run_id=<run_id>`
  - `concerto.work_item_id=<work_item_id>`
  - `concerto.workspace_key=<workspace_key>`
  - `concerto.workflow_root=<absolute workflow root>`
- Every active run must also write a host-side ownership manifest under the durable local state
  directory with the same identifiers and any tracked process/container handles.

Cleanup rules:

- Startup orphan cleanup may target only resources that match Concerto ownership labels or manifests.
- Cleanup must not rely on process-name matching alone.
- Cleanup must stay within the current service namespace, defined by the current workflow root and
  state directory.

### 7.5 Container Boundary

The container is an execution boundary, not a long-lived service boundary.

- Workers may launch short-lived containers for each run attempt.
- Containers do not coordinate with one another.
- Concerto remains one host-side process plus temporary containers.

## 8. Orchestration Lifecycle

### 8.1 Startup

At startup, Concerto must:

1. Load and validate `WORKFLOW.md`.
2. Load the durable local state directory.
3. Clean up any leftover Concerto-owned containers or app-server processes from a prior crash or
   unclean shutdown using the ownership markers from Section 7.4.
4. Start the orchestrator and worker supervisor.
5. Schedule an immediate poll tick.

If startup validation or orphan cleanup fails, the service must not dispatch work.

### 8.2 Poll Tick

Each poll tick runs in this order:

1. Reconcile currently running work items.
2. Compute available slots from `agent.max_concurrent_agents - running_count`.
3. If slots remain, fetch dispatch candidates.
4. Sort eligible candidates.
5. Dispatch up to the available slot count.

### 8.3 Candidate Eligibility

A candidate is eligible only if all are true:

- `lifecycle_state == "dispatchable"`
- `work_item_id` is present
- `workspace_key` is present and valid
- `dispatch_revision` is present and valid
- `prompt_context` normalizes successfully
- the work item is not already in `running`
- the durable local record does not already show the same `dispatch_revision` for that
  `work_item_id`

### 8.4 Candidate Ordering

Dispatch ordering is:

1. `priority` ascending, with `null` sorted last
2. `work_item_id` ascending

### 8.5 Dispatch

Dispatch for one work item is:

1. Create or reuse the workspace.
2. Ensure the workspace is materialized.
3. Assemble the first-turn prompt from `WORKFLOW.md` plus the normalized `WorkItem`.
4. Start a worker process under the `DynamicSupervisor`.
5. Add the work item to `running`.
6. Launch the isolated container and run one Codex attempt.

### 8.6 Reconciliation

On each poll tick, the orchestrator must refresh lifecycle state for all running work items.

Required behavior:

- If the refreshed lifecycle is `dispatchable` and `dispatch_revision` is unchanged, keep the run
  active.
- If the refreshed lifecycle is `dispatchable` and `dispatch_revision` has changed, terminate the
  run and mark it `canceled_by_reconciliation`.
- If the refreshed lifecycle is `inactive`, terminate the run and mark it
  `canceled_by_reconciliation`.
- If the refreshed lifecycle is `terminal`, terminate the run and mark it
  `canceled_by_reconciliation`.
- If the lifecycle row is missing, terminate the run and mark it `canceled_by_reconciliation`.

### 8.7 Worker Execution and Continuation

Within a single run attempt, the worker may execute up to five turns on the same app-server thread.

Rules:

- Turn `1` uses the full assembled prompt from Section 5.4.
- Turns `2` through `5`, when needed, must reuse the same `thread_id` and send only continuation
  guidance.
- After each normally completed turn, the worker must refresh the current lifecycle row for its own
  `work_item_id`.
- A continuation turn is allowed only when:
  - the app-server has not already indicated task completion for the current turn
  - the refreshed lifecycle is still `dispatchable`
  - the refreshed `dispatch_revision` is unchanged
  - the worker has not already reached the turn cap of five turns
- If the turn cap is reached while the run remains otherwise healthy, the attempt ends with
  `status = completed` and `stop_reason = turn_cap_reached`.

Required continuation guidance:

- resume from the current workspace state instead of restarting from scratch
- treat the prior turn history as already present on the thread
- focus on the remaining work for the same `work_item_id`
- do not ask for human input because the session is unattended

### 8.8 Worker Exit Semantics

When a worker exits:

- remove the item from `running`
- log and emit the attempt outcome
- persist the terminal `dispatch_revision` for that `work_item_id`
- persist the terminal `RunAttempt` metadata needed for evidence and debugging
- do not create retry state
- do not resume the same Codex thread automatically in a later run

If a later poll still sees the same work item as `dispatchable`, Concerto may start a fresh run in
the same workspace only after `dispatch_revision` changes.

### 8.9 Restart Behavior

After process restart:

- the last terminal `dispatch_revision` record must still be honored
- orphan cleanup must run before the first dispatch
- no in-memory worker state, retry state, or live app-server session is restored

## 9. Codex Execution Contract

### 9.1 Normative Harness Choice

Codex is the only normative agent harness in base v1.

The specification does not define a harness abstraction layer for multiple agent runtimes.

### 9.2 Code-Defined Runtime Details

The following are implementation constants, not `WORKFLOW.md` fields:

- container image
- container runtime selection
- `codex app-server` command line
- the fixed turn cap of `5`
- session startup parameters
- unattended approval policy and related non-interactive settings
- auth or token injection path used for compatible Codex builds
- timeout defaults
- stdout, stderr, and transcript capture policy
- the workspace materializer implementation

Changing these values is a code change.

### 9.3 App-Server Compatibility Profile

Concerto v1 targets the current stdio JSON-RPC app-server behavior described by the official
[Codex app-server documentation](https://developers.openai.com/codex/app-server/) and validated
against `../codex-indubitably`.

Required protocol behaviors:

- stdio transport only
- `initialize`
- `initialized`
- `thread/start`
- `turn/start`
- `turn/interrupt`

Required client identity:

- `clientInfo.name = "concerto_orchestrator"`
- `clientInfo.version` must be set

Base v1 does not require:

- websocket transport
- `thread/resume`
- `thread/fork`
- `turn/steer`
- dynamic tools
- public event streaming
- provider- or model-selection config in `WORKFLOW.md`

### 9.4 Session Startup Handshake

For each run attempt, the worker must:

1. Launch the container.
2. Set `CODEX_HOME` to a writable ephemeral path inside the container.
3. Start `codex app-server` inside the container using stdio transport.
4. Send `initialize`.
5. Send `initialized`.
6. Send `thread/start` to create a fresh thread for the attempt.
7. Send `turn/start` with the first-turn prompt.
8. Observe the session until normal completion, failure, timeout, or external cancellation.
9. Terminate the app-server process and container when the attempt ends.

Additional rules:

- `thread/start` and `turn/start` must use the workspace path as `cwd`.
- The `turn/start` title may be the `work_item_id` or a code-defined title derived from
  `prompt_context`.
- `thread_id` comes from the `thread/start` result.
- `last_turn_id` comes from each `turn/start` result.
- Because the Linux container is the primary execution sandbox in Concerto v1, `turn/start` should
  use the app-server's external-sandbox mode rather than an inner filesystem sandbox. Network
  access remains code-defined.

### 9.5 Continuation Turns

If turn `N` completes normally and the continuation conditions from Section 8.7 are still true, the
worker must:

1. keep the same app-server session alive
2. reuse the same `thread_id`
3. send another `turn/start` with continuation guidance only
4. increment `turn_count`

No run may exceed five turns.

### 9.6 Unattended Execution

- The container boundary remains the primary security boundary.
- The worker must use code-defined non-interactive settings so a run does not block on approval
  prompts.
- Concerto must not depend on a human answering app-server approval requests.
- No extra runtime config surface is added to `WORKFLOW.md` for approval, provider, model, or auth
  behavior.

If the app-server still produces interaction requests:

- approval requests may be auto-resolved only according to the documented code-defined policy
- user-input-required requests must fail the run promptly
- unknown server requests must fail the run promptly

### 9.7 Timeout and Cancellation

- The implementation must apply a code-defined timeout to each run attempt.
- The implementation must apply a code-defined read timeout to app-server requests.
- On reconciliation stop or timeout, the worker must send `turn/interrupt` when there is an active
  turn and the app-server is still responsive, then terminate the app-server process and container
  promptly.
- Timeout is treated as `failed`.

### 9.8 Transcript and Stderr Capture

Every run attempt that starts Codex must capture:

- an app-server transcript artifact
- a stderr artifact

Transcript rules:

- the transcript must preserve request, response, notification, and interrupt ordering
- each transcript row must include timestamp, direction, and raw message payload
- malformed protocol lines must be retained as malformed transcript rows, not discarded silently

stderr rules:

- stderr must not be parsed as protocol
- stderr may be truncated only by a documented size cap
- stderr must remain available in the `EvidenceBundle`

### 9.9 `codex-indubitably` Compatibility

Concerto v1 requires compatibility with `../codex-indubitably` as a narrow runtime path, not as a
second architecture.

Supported compatibility profiles:

- OpenAI baseline through `codex-indubitably`
- Bedrock or Indubitably proxy mode with bearer-token auth supplied by code-defined environment or
  read-only mounted auth material

Required runtime pieces for both profiles:

- writable ephemeral `CODEX_HOME` inside the container
- redacted auth injection path
- stderr capture
- release-blocking provider smoke evidence

Unsupported in base v1:

- direct AWS credential-chain Bedrock auth
- direct AWS Bedrock runtime endpoints
- websocket app-server transport
- cross-run resumed or forked Codex thread behavior

Unsupported behavior must appear only as an explicit expected failure, not as unspecified behavior.

## 10. Runtime Events, Logging, and Failure Semantics

### 10.1 Required Runtime Event Contract

Base v1 requires typed runtime events that conform to Section 4.7.

Rules:

- event names must be stable
- required metadata keys must be present
- validation failures must emit `event_contract_violation`
- validation failures must not crash the service

### 10.2 Trace Propagation

Trace metadata must preserve at least this causal chain:

poll tick -> dispatch decision -> workspace materialization -> app-server session -> turn ->
interrupt/completion

Every child event must keep the same `trace_id` and create a new `span_id`.

### 10.3 Required Structured Logs

Base v1 requires structured logs for at least these events:

- startup success
- startup configuration failure
- dispatch start
- workspace created
- workspace reused
- workspace materialized
- container launch
- Codex completed
- Codex failed
- reconciliation stop
- orphan cleanup
- Postgres read failure

Recommended common fields:

- `event`
- `work_item_id` when applicable
- `workspace_key` when applicable
- `dispatch_revision` when applicable
- `status` when applicable
- `error` when applicable
- `trace_id` when applicable
- `timestamp`

### 10.4 Output and Evidence Capture

The implementation must preserve enough output to inspect failures and validate acceptance
scenarios.

This may be done through structured logs, workspace-local files, evidence bundle directories, or a
combination of those mechanisms.

### 10.5 Failure Handling

- Invalid `WORKFLOW.md`: fail fast at startup.
- Candidate fetch failure: log the error, emit `postgres_read_failed`, and skip dispatch for that
  tick.
- Running-state refresh failure: log the error and keep current runs active until the next tick.
- Workspace creation failure: mark the attempt `failed` and release the slot.
- Materializer failure: mark the attempt `failed` and release the slot.
- Container launch failure: mark the attempt `failed` and release the slot.
- Approval or user-input policy violation: mark the attempt `failed` and release the slot.
- Codex timeout or protocol failure: mark the attempt `failed` and release the slot.

Base v1 does not require retries or backoff after failure.

## 11. Extension Policy

The base specification is intentionally narrow.

These items are outside base conformance and belong in future extensions, repo-local skills, or
fork-specific code changes:

- retries and backoff
- cross-run thread resume or fork
- prompt templating
- workflow hooks
- extra writable mounts driven by workflow config
- dashboards, REST APIs, and health endpoints
- token accounting and rate-limit reporting
- dynamic workflow reload
- dynamic tools or experimental app-server methods
- run journals or recent-event debug buffers
- multi-node coordination
- cloud-specific deployment profiles
- support for additional agent harnesses

Extensions should be explicit additions, not hidden assumptions in the base design.

## 12. Conformance and Validation

A conforming base-v1 implementation is complete only when it satisfies:

- [spec.md](/Users/gp/src/concerto/specs/spec.md)
- [acceptance-matrix.md](/Users/gp/src/concerto/specs/acceptance-matrix.md)
- [harness-architecture.md](/Users/gp/src/concerto/specs/harness-architecture.md)

The required validation layers are:

- unit tests
- component tests
- app-server integration tests against `../codex-indubitably`
- smoke tests on a target environment

The required evidence type is the `EvidenceBundle` defined in Section 4.8.

At minimum, the acceptance scenarios must demonstrate:

- `WORKFLOW.md` parsing and fail-fast validation
- fixed prompt assembly with the `## Work Item` JSON block
- one host-side workflow root distinct from per-item workspaces
- candidate eligibility and ordering by `priority` then `work_item_id`
- `dispatch_revision` dedupe behavior for unchanged dispatchable work
- bounded concurrency from `agent.max_concurrent_agents`
- deterministic workspace creation and reuse
- required workspace materialization and idempotent materializer behavior
- container-only agent execution with explicit mounts
- minimal Codex app-server lifecycle for one run attempt using stdio, `initialize`,
  `initialized`, `thread/start`, `turn/start`, and `turn/interrupt`
- bounded continuation turns that reuse the same `thread_id` and stop at five turns
- slot release on both `completed` and `failed`
- redispatch as a fresh run only after `dispatch_revision` changes
- reconciliation stop for changed `dispatch_revision`, `inactive`, `terminal`, and missing
  lifecycle rows
- startup orphan cleanup before dispatch, using precise ownership markers
- required runtime events and trace propagation
- required structured logs for startup, dispatch, completion, failure, reconciliation, and Postgres
  read failures
- `../codex-indubitably` OpenAI baseline compatibility
- `../codex-indubitably` Bedrock or Indubitably proxy compatibility with bearer-token auth
- direct AWS Bedrock endpoint behavior captured as an expected failure in base v1
- evidence bundle retention and redaction
- no dependency on dashboards, APIs, health endpoints, retry queues, token metrics, or cloud
  services

Real smoke evidence for OpenAI and Bedrock proxy profiles is release-blocking when claiming the
specification is complete for a target environment.

## 13. Normative Assumptions

- Elixir/OTP is required for v1.
- Codex is the required agent harness for v1.
- Linux container isolation is required for v1.
- The service remains single-node and hosting-agnostic.
- The base specification optimizes for the smallest understandable foundation, not for feature
  completeness.
- Jido-inspired adoption is contract-first: typed runtime events and trace correlation are required,
  while run journals and recent-event buffers remain optional extensions.
- The workflow surface stays intentionally small. Materialization, provider, model, auth, and turn
  cap behavior remain code-defined, not workflow-defined.
