defmodule ControlKeel.ExecutionSandbox do
  @moduledoc false

  @default_adapter "local"

  @callback run(command :: String.t(), args :: [String.t()], opts :: keyword()) ::
              {:ok, %{output: String.t(), exit_status: integer()}}
              | {:error, term()}

  @callback available?() :: boolean()

  @callback adapter_name() :: String.t()

  def adapter_name(opts \\ []) do
    Keyword.get(opts, :sandbox, config_sandbox_adapter())
  end

  def run(command, args, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    requested_capabilities = Keyword.get(opts, :requested_capabilities, [])
    force = Keyword.get(opts, :force, false)

    case ControlKeel.ExecutionSandbox.Preflight.check(
           session_id,
           requested_capabilities,
           force: force
         ) do
      {:ok, :proceed} ->
        dispatch_run(command, args, opts)

      {:warn, _message, _findings} ->
        dispatch_run(command, args, opts)

      {:error, {:blocked, reason, _findings}} ->
        {:error, {:blocked_by_policy, reason}}
    end
  end

  defp dispatch_run(command, args, opts) do
    adapter = resolve_adapter(opts)
    adapter.run(command, args, opts)
  end

  def resolve_adapter(opts) do
    name = adapter_name(opts)
    adapter = adapter_module(name)

    if function_exported?(adapter, :available?, 0) and not adapter.available?() do
      if name == @default_adapter do
        adapter
      else
        ControlKeel.ExecutionSandbox.Local
      end
    else
      adapter
    end
  end

  def adapter_module("local"), do: ControlKeel.ExecutionSandbox.Local
  def adapter_module("docker"), do: ControlKeel.ExecutionSandbox.Docker
  def adapter_module("e2b"), do: ControlKeel.ExecutionSandbox.E2B
  def adapter_module("nono"), do: ControlKeel.ExecutionSandbox.Nono
  def adapter_module(_), do: ControlKeel.ExecutionSandbox.Local

  def supported_adapters do
    [
      %{
        id: "local",
        name: "Local process",
        description: "Run commands directly on the host (default, zero config).",
        available: ControlKeel.ExecutionSandbox.Local.available?()
      },
      %{
        id: "docker",
        name: "Docker container",
        description: "Run commands inside an isolated Docker container.",
        available: ControlKeel.ExecutionSandbox.Docker.available?()
      },
      %{
        id: "e2b",
        name: "E2B sandbox",
        description: "Run commands inside an E2B Firecracker microVM.",
        available: ControlKeel.ExecutionSandbox.E2B.available?()
      },
      %{
        id: "nono",
        name: "nono sandbox",
        description:
          "Wrap agent execution with nono kernel sandboxing, rollback, and built-in client profiles.",
        available: ControlKeel.ExecutionSandbox.Nono.available?()
      }
    ]
  end

  defp config_sandbox_adapter do
    case read_config() do
      %{"execution_sandbox" => adapter} when is_binary(adapter) -> adapter
      _ -> @default_adapter
    end
  end

  defp read_config do
    path = ControlKeel.RuntimePaths.config_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{} = config} -> config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end
end
