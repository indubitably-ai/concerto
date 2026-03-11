# Docs Map

This directory is the repository-level map for durable documentation.

## Core Docs

- [`../AGENTS.md`](../AGENTS.md): top-level agent entry point.
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
- Mechanically validate cross-references when practical so repo maps and README links stay current.

## Elixir Reference Implementation

- [`../elixir/README.md`](../elixir/README.md): setup and runtime model.
- [`../elixir/AGENTS.md`](../elixir/AGENTS.md): concise implementation-scoped entry point.
- [`../elixir/WORKFLOW.md`](../elixir/WORKFLOW.md): issue execution contract.
- [`../elixir/docs/agent-guide.md`](../elixir/docs/agent-guide.md): canonical Elixir agent guide.
- [`../elixir/docs/logging.md`](../elixir/docs/logging.md): logging conventions.
- [`../elixir/docs/token_accounting.md`](../elixir/docs/token_accounting.md): token accounting
  reference.

## Still Worth Adding

- Add a workflow-alignment note or follow-up when the documented state machine diverges from the
  active Linear workflow used by the project.
- Add an unattended-workspace prerequisites note when a workflow depends on writable Git metadata,
  network reachability, or external auth that an agent cannot infer from the repo alone.
- Add `decisions/` when durable architecture choices start recurring across issues, PRs, or review
  threads.
- Add `quality.md`, `reliability.md`, and `security.md` once those practices harden enough to need
  stable cross-cutting references.
- Add `generated/` or another generated-reference entry point when schemas, workflow contracts, or
  other drift-prone material needs a canonical home.
- Add lightweight doc validation in CI when the doc surface is broad enough that broken links,
  missing entry points, or stale routing docs are likely to slip through review.
