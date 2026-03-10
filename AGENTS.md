# Concerto Agent Guide

This repository is the implementation setup for Concerto: a minimal usable Elixir/OTP orchestration
service that pulls work from Postgres, materializes runnable workspaces, and runs Codex in isolated
Linux containers.

This file is intentionally short. It is the table of contents for repository knowledge, not the
encyclopedia. Follow the deeper docs in `specs/` for the actual runtime contract and completion
gates.

The guidance here follows the Harness Engineering principle of keeping repository knowledge
discoverable, repo-owned, and easy for an agent to navigate.
Reference: [Harness Engineering](https://openai.com/index/harness-engineering/)

## Current State

- This repo is spec-first today. It does not yet contain the production Elixir implementation.
- Treat the spec set as the current source of truth.
- Keep docs and code aligned. Do not let code drift ahead of the spec.
- Keep this file thin. Put detail into the existing `specs/` documents.

## Source Of Truth

Read these in order before starting implementation work:

- `specs/spec.md`: normative runtime contract
- `specs/acceptance-matrix.md`: definition of done
- `specs/harness-architecture.md`: validation and evidence contract
- `specs/jido-adoption-patch-proposal.md`: optional design influence only, not normative

If these docs disagree, stop and reconcile them instead of guessing in code.

## Implementation Order

Build Concerto in the same order the spec implies:

1. Elixir/OTP application scaffold: application module, supervision tree, minimal `WORKFLOW.md`
   loading
2. Orchestrator and worker supervision: single authoritative orchestrator, one worker per active
   `work_item_id`
3. Postgres read adapter: candidate fetch, lifecycle refresh, `WorkItem` normalization
4. Workspace manager and workspace materializer: deterministic paths, durable reuse, code-defined
   idempotent materialization
5. Container runner and app-server client: Linux container boundary, writable workspace, ephemeral
   `CODEX_HOME`, `initialize`, `initialized`, `thread/start`, `turn/start`, `turn/interrupt`,
   bounded continuation on one thread
6. Validation harness and evidence plumbing: unit/component/integration/smoke layers and evidence
   bundles

Do not skip ahead to dashboards, retries, or generic abstractions before the core path works.

## Hard Invariants

Do not "improve" these away:

- Single-node Elixir/OTP runtime.
- Linux container isolation only for agent execution; no host-side Codex execution.
- Codex is the only base harness in v1.
- No workflow hooks, retries/backoff, dashboards, REST APIs, or config sprawl in v1.
- `WORKFLOW.md` stays intentionally small.
- Workspace materialization is code-defined, not workflow-defined.
- Runtime details such as container image, auth injection, timeouts, and turn cap are code-defined.
- Each run attempt is bounded to five turns on one app-server thread.
- No cross-run `thread/resume` or `thread/fork`.
- Unsupported direct AWS Bedrock behavior must remain an explicit expected failure, not undefined
  behavior.

## Change Discipline

For any implementation change:

- Update code, tests, and the relevant source-of-truth doc together.
- Keep behavior aligned with `specs/spec.md`.
- Keep completion criteria aligned with `specs/acceptance-matrix.md`.
- Keep validation and artifact behavior aligned with `specs/harness-architecture.md`.

If you need to change a contract:

- Change the spec first or in the same change.
- Update the acceptance matrix if definition of done changes.
- Update the harness doc if evidence, validation layers, or smoke gates change.

## Validation Expectations

Every meaningful behavior change should come with:

- unit or component coverage for the local behavior
- integration coverage when app-server behavior changes
- evidence bundle updates when validation output changes

Do not claim Concerto v1 is complete unless:

- the acceptance matrix scenarios pass
- the required evidence bundles are retained
- OpenAI smoke evidence exists
- Bedrock or Indubitably proxy smoke evidence exists
- direct AWS expected-failure coverage exists

## Documentation Rule

Keep this file short and map-like.

- Put deep runtime detail in `specs/spec.md`.
- Put definition-of-done changes in `specs/acceptance-matrix.md`.
- Put testing and evidence detail in `specs/harness-architecture.md`.
- Do not turn `AGENTS.md` into a long manual.

## Default Working Style

When implementing:

- start from the smallest end-to-end slice
- preserve legibility over abstraction
- prefer code-defined behavior over new configuration
- make validation artifacts first-class
- leave the repository easier for the next agent run to navigate
