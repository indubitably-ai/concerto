# Concerto

![Concerto](docs/assets/concerto-hero.png)

Concerto turns project work into isolated, autonomous implementation runs, allowing teams to manage
work instead of supervising coding agents.

Concerto monitors project work, spawns isolated agent runs, and expects those runs to return proof of
work such as validation results, review feedback, and walkthrough artifacts so humans can manage the
work at a higher level.

> [!WARNING]
> Concerto is a low-key engineering preview for testing in trusted environments.
> Expect rough edges around publish automation, external-service reachability, and other
> operator-focused workflows that are still being hardened.

## Running Concerto

### Requirements

Concerto works best in codebases that have adopted
[harness engineering](https://openai.com/index/harness-engineering/). Concerto is the next step --
moving from managing coding agents to managing work that needs to get done.

One practical lesson from that style of repo is to keep `AGENTS.md` lean and let it point to
canonical in-repo docs instead of growing into a single giant instruction file.

Another is to promote durable context into the repository itself. If a decision, operating rule, or
quality expectation matters beyond a single ticket, it should graduate from issue comments or PR
threads into a versioned doc.

The loop also needs a publish-ready workspace. Agents can only complete the end-to-end flow when the
repository copy can write normal Git metadata and the runtime can reach the external systems the
workflow depends on.

### Option 1. Make your own

Tell your favorite coding agent to build Concerto in a programming language of your choice:

> Implement Concerto according to the spec in `SPEC.md`.

### Option 2. Use our experimental reference implementation

Check out [elixir/README.md](elixir/README.md) for instructions on how to set up your environment
and run the Elixir-based Concerto implementation. You can also ask your favorite coding agent to
help with the setup:

> Set up Concerto for my repository based on `elixir/README.md`.

---

## Repository map

- [`AGENTS.md`](AGENTS.md) is the repository-level entry point for agents.
- [`docs/README.md`](docs/README.md) is the system-of-record index for durable documentation.
- [`SPEC.md`](SPEC.md) is the portable service specification used by Concerto.
- [`docs/agent-guidance-assessment.md`](docs/agent-guidance-assessment.md) reviews the current
  repository guidance against the harness engineering guide and lists recommended improvements.
- [`elixir/README.md`](elixir/README.md) explains how to run the Elixir reference implementation.
- [`elixir/WORKFLOW.md`](elixir/WORKFLOW.md) defines the issue-execution contract used in agent
  sessions.
- [`elixir/AGENTS.md`](elixir/AGENTS.md) contains implementation-scoped instructions for agents
  working inside the Elixir service.
- [`elixir/docs/agent-guide.md`](elixir/docs/agent-guide.md) carries the durable Elixir-specific
  agent guidance behind that entry point.

---

## License

This project is licensed under the [MIT License](LICENSE).
