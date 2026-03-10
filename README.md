# Concerto

Concerto is a minimal Elixir/OTP orchestration service that pulls work from Postgres, materializes
durable workspaces, and runs `codex app-server` inside isolated Linux containers.

## Run

Create a `WORKFLOW.md` that matches [specs/spec.md](/Users/gp/src/concerto/specs/spec.md), then run:

```bash
mix concerto.run --workflow-root /abs/path/to/workflow-root
```

## Validation

The canonical layer commands are:

```bash
mix test test/unit
mix test test/component
mix test test/integration
mix test test/smoke --include smoke
```

Each acceptance scenario writes an evidence bundle under `evidence/<scenario-id>/<timestamp>/`.

## Repo-Owned Docker Workflow

Use the helper script when host `elixir`/`mix` are unavailable:

```bash
scripts/mix-in-docker test test/unit
```

Build the runner image from the parent workspace, which also contains `../codex-indubitably`:

```bash
scripts/build-runner-image
```
