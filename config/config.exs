import Config

config :logger, level: :info

config :concerto,
  runner_image: "concerto-codex-runner:latest",
  runtime_version: Mix.Project.config()[:version]
