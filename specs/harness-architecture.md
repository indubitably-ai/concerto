# Concerto Harness Architecture

Status: Normative companion to
[spec.md](/Users/gp/src/concerto/specs/spec.md) and
[acceptance-matrix.md](/Users/gp/src/concerto/specs/acceptance-matrix.md)

Purpose: define the validation layers, evidence bundle layout, release gates, and operator-facing
debugging workflow required to declare Concerto v1 complete.

## 1. Principles

### 1.1 Repo-Owned System of Record

Concerto keeps its validation contract in repo-owned documents:

- [spec.md](/Users/gp/src/concerto/specs/spec.md) defines runtime behavior.
- [acceptance-matrix.md](/Users/gp/src/concerto/specs/acceptance-matrix.md) defines the scenarios
  and hard completion gate.
- [harness-architecture.md](/Users/gp/src/concerto/specs/harness-architecture.md) defines how the
  scenarios are validated and what evidence must be retained.

### 1.2 Small Harness, Real Proof

The harness should be no larger than necessary to prove the runtime contract.

- Prefer simple fixture-backed doubles for unit and component tests.
- Use the real `../codex-indubitably` app-server path for integration tests.
- Use real provider smoke tests only where mocked tests cannot prove the requirement.

### 1.3 Evidence First

Every scenario must leave behind enough artifacts that an operator can answer:

- what command ran
- what environment class it ran under
- what Codex and Concerto exchanged
- why it passed or failed

## 2. Required Validation Layers

### 2.1 Unit

Unit coverage must validate pure or nearly pure logic:

- `WORKFLOW.md` parsing and validation
- Postgres row normalization
- candidate ordering
- `dispatch_revision` dedupe rules
- runtime event schema validation
- evidence bundle manifest generation

Allowed doubles:

- in-memory workflow content
- fake rows
- fake clock
- fake filesystem paths

### 2.2 Component

Component coverage must validate service behavior without requiring live providers:

- orchestrator dispatch and slot accounting
- workspace creation and reuse
- workspace materialization and idempotence
- reconciliation stop behavior
- timeout handling
- restart persistence of last terminal `dispatch_revision`
- ownership marker creation and orphan cleanup

Allowed doubles:

- fake Postgres adapter
- fake container runner
- fake app-server process

Required real dependencies:

- local filesystem
- durable state directory

### 2.3 Integration

Integration coverage must drive the real app-server protocol against `../codex-indubitably`.

Required proof:

- stdio JSON-RPC handshake
- `initialize`, `initialized`, `thread/start`, `turn/start`, `turn/interrupt`
- transcript capture
- non-interactive approval behavior
- bounded continuation turns on one thread

Allowed setup:

- use a locally built `codex-app-server` binary from `../codex-indubitably`
- use a fixture-backed or mock upstream model endpoint
- inject auth/config through ephemeral files or environment variables

### 2.4 Smoke

Smoke coverage must validate the real supported provider paths on the target environment.

Required smoke scenarios:

- OpenAI baseline
- Bedrock or Indubitably proxy path with bearer-token auth
- direct AWS Bedrock expected failure

Smoke rules:

- these scenarios are release-blocking when claiming Concerto v1 is complete
- a skipped smoke scenario means the target environment is not yet spec-complete

## 3. Canonical Commands

Implementations must expose one stable command per validation layer and record the exact command in
the evidence manifest.

Recommended Elixir shape:

```text
mix test test/unit
mix test test/component
mix test test/integration
mix test test/smoke
```

If the implementation chooses different commands, the evidence manifest must still record the exact
invocation used.

## 4. Evidence Bundle Contract

### 4.1 Layout

Each scenario run must write one bundle under:

```text
evidence/<scenario-id>/<timestamp>/
```

Required files:

- `manifest.json`
- `test-output.txt`
- `structured.log`
- `app-server-transcript.jsonl` when the scenario starts Codex
- `stderr.txt` when the scenario starts Codex

### 4.2 `manifest.json`

`manifest.json` must include:

- `scenario_id`
- `layer`
- `command`
- `exit_status`
- `started_at`
- `finished_at`
- `redacted_env`
- `artifacts`

Recommended optional fields:

- `git_rev`
- `codex_binary`
- `container_runtime`
- `notes`

### 4.3 Transcript Format

`app-server-transcript.jsonl` must use one JSON object per line.

Required fields per line:

- `at`
- `direction` (`client_to_server` or `server_to_client`)
- `stream` (`stdout`, `stdin`, or `stderr_bridge`)
- `kind` (`request`, `response`, `notification`, `malformed`)
- `payload`

Malformed protocol lines must still be written with `kind = "malformed"`.

### 4.4 Redaction Rules

Evidence must never retain raw secrets or bearer tokens.

Required redactions:

- auth tokens in environment variables
- bearer tokens in mounted config or auth files
- authorization headers if they appear in logs or transcripts

Allowed retained values:

- env var names
- masked values such as `abcd...wxyz`
- filesystem paths that do not themselves encode secrets

## 5. Harness Inputs and Doubles

### 5.1 Fake Postgres Adapter

Component tests may replace the live Postgres adapter with a fixture-backed adapter that returns:

- dispatch candidates
- lifecycle refresh rows
- invalid rows for normalization tests

The fake adapter must preserve the same normalization and ordering rules as the real adapter.

### 5.2 Fake Container Runner

Component tests may replace the real container runner with a deterministic fake that records:

- selected image
- mount list
- ownership markers
- timeout handling
- interrupt requests

### 5.3 Real App-Server Client Path

Integration tests must exercise the real stdio app-server protocol path from `../codex-indubitably`
rather than a mocked protocol implementation.

The harness may still mock upstream model responses, but it must not bypass the app-server process
or its JSON-RPC transport.

## 6. Release Gates

A target environment may be called Concerto v1 complete only when:

- all applicable unit, component, and integration scenarios pass
- real OpenAI smoke evidence exists
- real Bedrock/Indubitably proxy smoke evidence exists
- direct AWS expected-failure evidence exists
- all evidence bundles satisfy the retention and redaction rules

No silent skips are allowed for smoke scenarios in a completion claim.

## 7. Operator Debugging Workflow

The retained artifacts must support a simple debugging path:

1. Read `manifest.json` to see what scenario ran, when, and with what command.
2. Read `structured.log` to locate the failure phase.
3. Read `app-server-transcript.jsonl` to inspect protocol order and interrupt behavior.
4. Read `stderr.txt` for app-server or container diagnostics.

If those artifacts are insufficient to explain a failure, the harness is incomplete and the related
scenario is not yet proven.
