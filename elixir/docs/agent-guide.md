# Agent Guide

This document is the canonical map for agent-facing guidance in the Elixir reference implementation.
Keep `AGENTS.md` short and use this file for durable details that should stay discoverable in-repo.

## Start Here

- [`README.md`](../README.md): setup, runtime model, and `WORKFLOW.md` usage.
- [`WORKFLOW.md`](../WORKFLOW.md): operational workflow contract rendered into Codex sessions.
- [`../SPEC.md`](../../SPEC.md): product and runtime contract for Symphony as a whole.

## Canonical References

- [`docs/logging.md`](logging.md): logging conventions and required issue/session fields.
- [`docs/token_accounting.md`](token_accounting.md): token accounting terminology and implementation notes.

## Core Invariants

- Load runtime config through `SymphonyElixir.Workflow` and `SymphonyElixir.Config` rather than
  adding ad-hoc environment reads.
- Workspace safety is mandatory:
  - never run a Codex turn with cwd set to the source repo;
  - keep workspaces under the configured workspace root.
- Preserve retry, reconciliation, cleanup, and other concurrency-sensitive orchestrator semantics.
- Keep the implementation aligned with [`../SPEC.md`](../../SPEC.md) when practical:
  - the Elixir implementation may be a superset of the spec;
  - it must not conflict with the spec;
  - when behavior changes materially, update the spec in the same change where practical.
- Public functions (`def`) in `lib/` need an adjacent `@spec` unless the function is an `@impl`
  callback.
- Keep changes narrowly scoped and follow existing patterns in `lib/symphony_elixir/*`.

## Validation Expectations

- Run focused checks while iterating.
- Use `mix specs.check` after modifying public function signatures or adjacent specs in `lib/`.
- Run the full quality gate before handoff or review:

```bash
make all
```

- When touching public functions in `lib/`, verify the spec requirement explicitly:

```bash
mix specs.check
```

## Handoff and Docs Expectations

- If you are working in a downstream repo with a PR template, follow that repo's template and local
  validation rules.
- If behavior, config, or operating instructions change, update the matching docs in the same PR:
  - [`../README.md`](../../README.md) for project concept and high-level goals;
  - [`README.md`](../README.md) for Elixir runtime and setup instructions;
  - [`WORKFLOW.md`](../WORKFLOW.md) for workflow or config contract changes;
  - this guide when the agent-facing doc map or core invariants change.
