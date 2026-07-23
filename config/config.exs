# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :controlkeel,
  namespace: ControlKeel,
  ecto_repos: [ControlKeel.Repo],
  cloud_ecto_repos: [ControlKeel.CloudRepo],
  runtime_mode: :local,
  pdf_renderer: :chromic,
  protocol_access_token_ttl_seconds: 3_600,
  acp_registry_url: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json",
  acp_registry_ttl_seconds: 86_400,
  generators: [timestamp_type: :utc_datetime],
  # Governed autonomy scheduler — off by default so existing installs see no
  # behavior change. Enable via CK_AUTONOMY_SCHEDULER env or `enabled: true`.
  # See docs/autonomy-scheduler.md and lib/controlkeel/autonomy/scheduler.ex.
  autonomy: [
    enabled: false,
    allow_shell: false,
    launch_timeout_ms: 300_000,
    workspace_id: nil,
    jobs: []
  ]

# Configure the endpoint
# Default `code_reloader` so releases match runtime MCP overrides (CK_MCP_MODE).
# `config/dev.exs` enables reloading for local `mix phx.server` workflows.
# `:url` is the advertised URL used for route generation, OAuth redirect URIs,
# and any external link emission. Scheme/port must match the dev/test serving
# ports so OAuth IdPs can call back to the right address. Production overrides
# this in `config/runtime.exs` via `Runtime.Defaults.endpoint_url_config/0`.
config :controlkeel, ControlKeelWeb.Endpoint,
  url: [host: "localhost", scheme: "http", port: 4000],
  adapter: Bandit.PhoenixAdapter,
  code_reloader: false,
  render_errors: [
    formats: [html: ControlKeelWeb.ErrorHTML, json: ControlKeelWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ControlKeel.PubSub,
  live_view: [signing_salt: "BK4dPDY1"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  controlkeel: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  controlkeel: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
