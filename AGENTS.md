# Concerto

Use this file as the repository-level entrypoint for agents. Keep it short and route to the
canonical docs instead of duplicating long guidance here.

## Start Here

- [`README.md`](README.md): project overview and repository map.
- [`docs/README.md`](docs/README.md): system-of-record docs index.
- [`SPEC.md`](SPEC.md): portable product and runtime contract.
- [`docs/agent-guidance-assessment.md`](docs/agent-guidance-assessment.md): assessment of the
  current repo guidance against the harness-engineering recommendations.

## Local Instructions

- [`elixir/README.md`](elixir/README.md): Elixir reference implementation overview.
- [`elixir/AGENTS.md`](elixir/AGENTS.md): Elixir-specific rules, invariants, and validation
  entrypoint.
- [`elixir/WORKFLOW.md`](elixir/WORKFLOW.md): issue execution contract for the reference
  implementation.

## Repo-wide Rules

- Keep durable guidance in versioned docs beside the code.
- Treat `AGENTS.md` files as routing documents with the highest-value guardrails.
- Prefer progressive disclosure: expand the linked canonical docs instead of growing this file.
- When you add a durable guide, register it in [`docs/README.md`](docs/README.md).
- Promote conclusions that outlive a single ticket or PR into versioned docs instead of leaving
  them only in Linear, chat, or review threads.
- Prefer mechanically checked or generated references for drift-prone material when practical.
- Keep implementation behavior aligned with [`SPEC.md`](SPEC.md) when practical.
- Update the matching docs in the same change when behavior or operating instructions change.
