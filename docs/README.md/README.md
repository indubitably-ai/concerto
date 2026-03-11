# Docs Map

This directory is the repository-level map for durable documentation.

## Core Docs

- [`../AGENTS.md`](../AGENTS.md): top-level agent entrypoint.
- [`../README.md`](../README.md): project overview and high-level repository map.
- [`../SPEC.md`](../SPEC.md): portable service specification used by Concerto.

## Assessments and Guidance

- [`agent-guidance-assessment.md`](agent-guidance-assessment.md): compares the current repo
  guidance with the harness-engineering recommendations and calls out remaining gaps.

## Maintenance Rules

- Keep `AGENTS.md` files short; add durable guidance here or beside the relevant code instead.
- When a decision or operating rule should outlive one ticket, promote it into a versioned doc.
- Register new durable docs in this index so agents have a reliable map.
- Prefer mechanically checked or generated references for material that is likely to drift.

## Elixir Reference Implementation

- [`../elixir/README.md`](../elixir/README.md): setup and runtime model.
- [`../elixir/AGENTS.md`](../elixir/AGENTS.md): concise implementation-scoped entrypoint.
- [`../elixir/WORKFLOW.md`](../elixir/WORKFLOW.md): issue execution contract.
- [`../elixir/docs/agent-guide.md`](../elixir/docs/agent-guide.md): canonical Elixir agent guide.
- [`../elixir/docs/logging.md`](../elixir/docs/logging.md): logging conventions.
- [`../elixir/docs/token_accounting.md`](../elixir/docs/token_accounting.md): token accounting
  reference.

## Still Worth Adding

- A small workflow-alignment note or follow-up that keeps [`../elixir/WORKFLOW.md`](../elixir/WORKFLOW.md)
  in sync with the actual Linear state model used by active projects.
- A short operational note describing the minimum unattended-workspace prerequisites, including
  writable Git metadata and reachability to required external systems.
- `decisions/`: design history or ADR-style notes for choices that should not live only in issues,
  PRs, or people's heads.
- `quality.md`, `reliability.md`, and `security.md`: cross-cutting operational references once the
  project's practices harden enough to justify stable docs.
- `generated/` or another generated-reference entrypoint for schemas, workflow contracts, or other
  drift-prone reference material.
- A lightweight doc validation check in CI so broken local links, missing entrypoints, or stale
  routing docs are caught automatically.
