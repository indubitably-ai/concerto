defmodule Concerto.WorkflowDefinition do
  @moduledoc false

  alias Concerto.WorkflowConfig

  @enforce_keys [:workflow_root, :workflow_path, :config, :body]
  defstruct [:workflow_root, :workflow_path, :config, :body]

  @type t :: %__MODULE__{
          workflow_root: String.t(),
          workflow_path: String.t(),
          config: WorkflowConfig.t(),
          body: String.t()
        }
end
