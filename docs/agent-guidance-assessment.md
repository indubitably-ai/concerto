# Agent Guidance Assessment

This assessment reviews the current repository guidance against the practices described in OpenAI's
"Harness engineering: leveraging Codex in an agent-first world" post.

## Assessment summary

The current direction is good: the repo is moving toward the harness-guide pattern of a short root
`AGENTS.md`, a repository map in `README.md`, and a `docs/` index that acts as the system of
record. The highest-value remaining improvements are to make that structure more durable by
promoting long-lived decisions into versioned docs and by adding mechanical checks that keep the map
accurate.

## Scope reviewed

- `AGENTS.md`
- `README.md`
- `docs/README.md`
- `docs/agent-guidance-assessment.md`
- `elixir/AGENTS.md`
- `elixir/README.md`
- `elixir/docs/agent-guide.md`
- `SPEC.md`
- `elixir/docs/logging.md`
- `elixir/WORKFLOW.md`

## Improvements landed in this change

1. The repository now has a short root [`AGENTS.md`](../AGENTS.md) that routes agents to canonical
   docs instead of relying on a single large instruction surface.
2. [`docs/README.md`](README.md) now acts as a repository-level docs index, making progressive
   disclosure explicit.
3. [`elixir/AGENTS.md`](../elixir/AGENTS.md) was trimmed into a concise entrypoint, while
   [`elixir/docs/agent-guide.md`](../elixir/docs/agent-guide.md) now carries the durable Elixir-
   specific guidance.
4. The root [`README.md`](../README.md) now includes a clearer repository map so agents and humans
   can discover the right canonical artifact faster.
5. The root guidance now makes an explicit distinction between transient ticket discussion and
   durable in-repo documentation.

## What is working well now

1. The repo has clear canonical anchors for different layers of knowledge.
   - [`SPEC.md`](../SPEC.md) is the portable product and runtime contract.
   - [`README.md`](../README.md) explains the project and points to the main entrypoints.
   - [`docs/README.md`](README.md) acts as the top-level docs map.
   - [`elixir/README.md`](../elixir/README.md), [`elixir/WORKFLOW.md`](../elixir/WORKFLOW.md), and
     [`elixir/docs/agent-guide.md`](../elixir/docs/agent-guide.md) split implementation guidance by
     purpose.
2. The Elixir agent instructions now match the harness-guide preference for a short AGENTS file
   backed by deeper linked docs.
3. Supporting docs already exist for specialized topics such as logging, token accounting, and the
   Elixir workflow contract.
4. The root README now behaves more like a repository map than a mixed overview/manual, which is
   closer to the harness-guide recommendation.

## Remaining gaps relative to the harness guide

### 1. Doc legibility is not mechanically enforced yet

The harness guide recommends CI checks or recurring maintenance tasks that validate structure,
cross-links, and freshness. This repository still relies on manual review for those checks.

### 2. The docs tree is still light on decision-history and quality-reference material

The guide emphasizes keeping more reasoning in-repo over time and adding stable reference docs as
operational practices mature. Concerto already has strong runtime and implementation docs, but it
would still benefit from versioned decision records, architecture notes, or focused quality
references once those areas harden.

### 3. Durable conclusions can still get stranded outside the repo

The current workflow uses Linear workpads and PR discussion effectively, but the harness guide is
explicit that agent-visible context needs to live in-repo to compound over time. When a decision or
operating rule matters beyond one issue, there is not yet an obvious canonical home for it.

### 4. Recurring doc-gardening is still a manual habit

The guide recommends cleanup as a continuous background task. There is not yet a documented
mechanism for small periodic doc-fix PRs or issue generation.

### 5. The workflow contract is ahead of the live Linear state model

The repo's execution contract in [`elixir/WORKFLOW.md`](../elixir/WORKFLOW.md) expects dedicated
review and merge states such as `Human Review`, `Rework`, and `Merging`, but the current IND Linear
team only exposes `Backlog`, `Todo`, `In Progress`, `Done`, `Canceled`, and `Duplicate`. That makes
the handoff path less executable than the harness guide recommends because agents have to improvise
around a missing state machine in the tool itself.

### 6. Workspace prerequisites are not documented as a hard requirement yet

The harness guide assumes agents can use ordinary development tools directly. In practice, that means
the workspace needs writable Git metadata and network reachability to the systems the loop depends
on. This repo now exposes the docs map clearly, but it does not yet state those operational
prerequisites as part of the executable environment contract.

## Recommended improvements

### Priority 1: Add mechanical doc checks

Once the navigation structure exists, add a lightweight CI check that validates:

- required docs are present,
- linked local paths resolve,
- root `AGENTS.md` and `docs/README.md` both reference the canonical files.

This does not need to be fancy; even a small script or test would prevent silent documentation
drift.

### Priority 2: Create explicit homes for durable decisions and references

Add a lightweight destination for durable context that currently risks living only in Linear, PRs,
or reviewer memory. The smallest useful version would be:

- `docs/decisions/` for ADR-style notes or decision logs,
- `docs/generated/` for generated or drift-prone reference artifacts,
- optional focused docs such as `docs/quality.md`, `docs/reliability.md`, or `docs/security.md`
  when those practices stabilize.

This keeps the root `AGENTS.md` and `README.md` short while giving the repo a place to accumulate
high-value context.

### Priority 3: Add recurring doc-gardening

The harness guide explicitly recommends cleanup as a continuous practice. Once the repo has a root
doc map, a recurring maintenance task can keep it current by opening small doc-fix PRs.

### Priority 4: Add design-history and quality docs when they are truly needed

The next layer of value is not more generic guidance; it is versioned design context and focused
operational references for the parts of Concerto that are easy to forget or re-litigate. Add
decision, architecture, or quality docs only when the team has concrete practices worth preserving.

### Priority 5: Align workflow docs and Linear states

Make the documented issue flow executable in the actual project tool:

- either add the expected Linear states (`Human Review`, `Rework`, `Merging`), or
- simplify [`elixir/WORKFLOW.md`](../elixir/WORKFLOW.md) so it matches the states that really exist.

The harness guide emphasizes executable loops and legible tooling. If the repo contract and the live
tracker disagree, agents lose that legibility at the exact point where review and merge handoffs
matter most.

### Priority 6: Document unattended workspace prerequisites

Add a short operational note that makes the publish path explicit for autonomous runs:

- workspaces need writable `.git` metadata,
- the shell environment needs network/auth reachability to required external systems,
- and those assumptions should live in repo docs instead of only surfacing when a run fails.

This is a small change, but it turns an implicit environment assumption into a visible contract that
agents and humans can both verify.

## Recommended end state

```text
AGENTS.md
README.md
SPEC.md
docs/
  README.md
  agent-guidance-assessment.md
  generated/                # future
  architecture.md            # future
  security.md                # future
  quality.md                 # future
  reliability.md             # future
  decisions/                 # future
elixir/
  AGENTS.md
  README.md
  WORKFLOW.md
  docs/
    agent-guide.md
```

## Suggested follow-up order

1. Add a small doc-structure validation check.
2. Add explicit homes for decision logs and generated references.
3. Align the documented workflow with the actual Linear state model.
4. Document unattended workspace prerequisites.
5. Add a recurring doc-gardening loop.
6. Add decision-history or quality-reference docs when the project has concrete practices worth preserving.

That sequence builds on the new agent-facing map without forcing a large documentation rewrite all
at once.
