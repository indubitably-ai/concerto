# Symphony Elixir

This directory contains the Elixir orchestration service that polls Linear, creates per-issue
workspaces, and runs Codex in app-server mode.

Use this file as a fast entrypoint. Keep durable details in the linked docs rather than expanding
this into a long policy blob.

## Start Here

- [`README.md`](README.md): setup, runtime model, and operational overview.
- [`docs/agent-guide.md`](docs/agent-guide.md): canonical agent-facing guide, invariants, and
  validation expectations.
- [`WORKFLOW.md`](WORKFLOW.md): issue execution contract and state-machine workflow.
- [`../SPEC.md`](../SPEC.md): product and runtime contract for Symphony.

## Critical Guardrails

- Load runtime config through `SymphonyElixir.Workflow` and `SymphonyElixir.Config`; avoid ad-hoc
  environment reads.
- Never run a Codex turn with cwd set to the source repo; workspaces must stay under the configured
  workspace root.
- Preserve retry, reconciliation, cleanup, and other concurrency-sensitive orchestrator behavior.
- Public functions (`def`) in `lib/` need an adjacent `@spec` unless they are `@impl` callbacks.
- Follow [`docs/logging.md`](docs/logging.md) for required issue/session logging fields.

## Validation

- Run targeted checks while iterating, then finish with `make all`.
- Run `mix specs.check` when touching public `lib/` APIs.

## Docs Policy

- If behavior, config, or operating instructions change, update the matching docs in the same PR.
- Update this file only when the entrypoint guidance or linked doc map changes.
