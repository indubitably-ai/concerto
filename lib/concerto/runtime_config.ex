defmodule Concerto.RuntimeConfig do
  @moduledoc false

  alias Concerto.WorkflowDefinition

  @enforce_keys [
    :workflow,
    :paths,
    :work_source,
    :workspace_materializer,
    :container_runtime,
    :app_server_client
  ]
  defstruct [
    :workflow,
    :paths,
    :work_source,
    :workspace_materializer,
    :container_runtime,
    :app_server_client,
    :runner_image,
    :runner_env,
    :runner_auth_mounts
  ]

  @type t :: %__MODULE__{
          workflow: WorkflowDefinition.t(),
          paths: map(),
          work_source: module() | {module(), map()},
          workspace_materializer: module() | {module(), map()},
          container_runtime: module() | {module(), map()},
          app_server_client: module() | {module(), map()},
          runner_image: String.t(),
          runner_env: map(),
          runner_auth_mounts: [map()]
        }
end
