# Concerto v1 Acceptance Matrix

This file is the concrete definition of done for the Concerto v1 minimal usable specification. A
conforming implementation passes every applicable scenario below and retains the listed evidence
bundle.

## Required Evidence Bundle

Each scenario must retain one evidence bundle under:

```text
evidence/<scenario-id>/<timestamp>/
```

Required files:

- `manifest.json`
- `test-output.txt`
- `structured.log`
- `app-server-transcript.jsonl` when the scenario starts Codex
- `stderr.txt` when the scenario starts Codex

`manifest.json` must include:

- `scenario_id`
- `layer`
- `command`
- `exit_status`
- `started_at`
- `finished_at`
- `redacted_env`
- `artifacts`

## Scenarios

| ID | Layer | Scenario | Proves | Required Evidence |
| --- | --- | --- | --- | --- |
| ACC-1 | Unit | `WORKFLOW.md` parsing and startup validation | invalid or missing `WORKFLOW.md` fails fast before dispatch | manifest, test output |
| ACC-2 | Unit or Component | Workflow root boundary and prompt assembly | one host-side workflow root remains distinct from per-item workspaces, and the assembled prompt contains workflow body plus `## Work Item` JSON with `dispatch_revision` | manifest, test output, structured log |
| ACC-3 | Unit | Candidate ordering | eligible items are ordered by `priority`, then `work_item_id` | manifest, test output |
| ACC-4 | Unit or Component | `dispatch_revision` dedupe | unchanged dispatchable work does not rerun after a terminal attempt; changed revision becomes eligible again | manifest, test output, structured log |
| ACC-5 | Component | Bounded concurrency | active workers never exceed `agent.max_concurrent_agents` | manifest, test output, structured log |
| ACC-6 | Component | Workspace reuse | the same `workspace_key` reuses the same durable path across runs | manifest, test output, structured log |
| ACC-7 | Component | Reconciliation stop | active runs are interrupted when lifecycle becomes `inactive`, `terminal`, missing, or `dispatch_revision` changes | manifest, test output, structured log, transcript |
| ACC-8 | Component | Timeout handling | timed-out runs become `failed`, release their slot, and preserve stderr artifacts | manifest, test output, structured log, stderr |
| ACC-9 | Component | Startup orphan cleanup | leftover Concerto-owned containers or app-server processes are cleaned up before the first dispatch | manifest, test output, structured log |
| ACC-10 | Integration | Minimal app-server handshake and one-turn run | Concerto uses stdio plus `initialize`, `initialized`, `thread/start`, and `turn/start` successfully | manifest, test output, transcript, structured log, stderr |
| ACC-11 | Integration | Interrupt path | reconciliation stop or timeout sends `turn/interrupt` when an active turn exists | manifest, test output, transcript, structured log |
| ACC-12 | Smoke | `codex-indubitably` OpenAI baseline | a one-turn OpenAI-backed run succeeds through the supported Concerto path | manifest, test output, transcript, structured log, stderr |
| ACC-13 | Smoke | `codex-indubitably` Bedrock or Indubitably proxy path | a one-turn bearer-auth Bedrock proxy run succeeds through the supported Concerto path | manifest, test output, transcript, structured log, stderr |
| ACC-14 | Smoke | Direct AWS Bedrock path expected failure | direct AWS Bedrock configuration is explicitly unsupported and fails in the documented way | manifest, test output, structured log, stderr |
| ACC-15 | Component | Workspace materialization | the code-defined workspace materializer makes an empty workspace runnable, is idempotent on reuse, and logs/materializes deterministically | manifest, test output, structured log |
| ACC-16 | Integration | Bounded continuation turns | continuation turns reuse the same `thread_id`, send continuation guidance instead of the full prompt, and stop at the fixed turn cap of five | manifest, test output, transcript, structured log, stderr |
| ACC-17 | Integration | Non-interactive approval and user-input handling | approval or user-input-required paths do not stall indefinitely; they are auto-resolved according to policy or failed deterministically | manifest, test output, transcript, structured log, stderr |
| ACC-18 | Component | Restart persistence | the durable local `dispatch_revision` record survives restart and prevents duplicate reruns of the same revision | manifest, test output, structured log |
| ACC-19 | Component | Ownership markers and precise cleanup | container labels and host ownership manifests are sufficient for cleanup without broad process-name matching | manifest, test output, structured log |
| ACC-20 | Unit or Component | Runtime event and trace contract | required event names and trace fields appear on dispatch, session start, turn start, interrupt, completion, and failure | manifest, test output, structured log |
| ACC-21 | Component | Evidence bundle retention and redaction | every scenario writes the required bundle shape and omits raw secrets or bearer tokens from retained artifacts | manifest, test output |

## Completion Rule

Concerto v1 spec work is complete only when all are true:

- [spec.md](/Users/gp/src/concerto/specs/spec.md),
  [acceptance-matrix.md](/Users/gp/src/concerto/specs/acceptance-matrix.md), and
  [harness-architecture.md](/Users/gp/src/concerto/specs/harness-architecture.md) agree
- every applicable scenario passes
- every applicable scenario retains the required evidence bundle
- OpenAI and Bedrock proxy smoke evidence exists for the target environment
- direct AWS behavior appears only as an explicit expected failure
- no smoke scenario is skipped when claiming the specification is complete for a target environment
