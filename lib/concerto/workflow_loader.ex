defmodule Concerto.WorkflowLoader do
  @moduledoc false

  alias Concerto.{WorkItem, WorkflowConfig, WorkflowDefinition}

  @front_matter_regex ~r/\A---\s*\n(?<front>.*?)\n---\s*\n?(?<body>.*)\z/s

  def load(workflow_root) do
    workflow_root = Path.expand(workflow_root)
    workflow_path = Path.join(workflow_root, "WORKFLOW.md")

    with {:ok, contents} <- File.read(workflow_path),
         {:ok, front_matter, body} <- split(contents),
         {:ok, parsed_front_matter} <- parse_yaml(front_matter),
         {:ok, config} <- WorkflowConfig.new(parsed_front_matter) do
      {:ok,
       %WorkflowDefinition{
         workflow_root: workflow_root,
         workflow_path: workflow_path,
         config: config,
         body: String.trim_trailing(body)
       }}
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end

  def assemble_prompt(workflow_body, %WorkItem{} = work_item) do
    json = Jason.encode!(WorkItem.to_prompt_json(work_item))

    [
      String.trim_trailing(workflow_body),
      "",
      "## Work Item",
      "```json",
      json,
      "```"
    ]
    |> Enum.join("\n")
  end

  defp split(contents) do
    case Regex.named_captures(@front_matter_regex, contents) do
      %{"front" => front, "body" => body} -> {:ok, front, body}
      _ -> {:error, :invalid_workflow_format}
    end
  end

  defp parse_yaml(front_matter) do
    case YamlElixir.read_from_string(front_matter) do
      {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
      {:ok, _} -> {:error, :invalid_workflow_front_matter}
      {:error, reason} -> {:error, {:invalid_workflow_front_matter, reason}}
    end
  end
end
