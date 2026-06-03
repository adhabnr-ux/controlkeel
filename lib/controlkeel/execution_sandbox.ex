defmodule ControlKeel.ExecutionSandbox do
  @moduledoc false

  @default_adapter "local"

  @callback run(command :: String.t(), args :: [String.t()], opts :: keyword()) ::
              {:ok, %{output: String.t(), exit_status: integer()}}
              | {:error, term()}

  @callback available?() :: boolean()

  @callback adapter_name() :: String.t()

  def adapter_name(opts \\ []) do
    case Keyword.get(opts, :sandbox) do
      nil -> config_sandbox_adapter()
      name -> name
    end
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
        guarded_dispatch(command, args, opts)

      {:warn, _message, _findings} ->
        guarded_dispatch(command, args, opts)

      {:error, {:blocked, reason, _findings}} ->
        {:error, {:blocked_by_policy, reason}}
    end
  end

  defp guarded_dispatch(command, args, opts) do
    case resolve_adapter(opts, strict: true) do
      {:error, _reason} = error ->
        error

      adapter ->
        if host_adapter?(adapter) and enforce_sandbox?() and not Keyword.get(opts, :force, false) do
          {:error,
           {:blocked_by_policy,
            "Host (local) execution is forbidden because enforce_sandbox is enabled. " <>
              "Use an isolated adapter (sandbox: \"docker\"), set execution_sandbox=docker in config, " <>
              "or pass force: true for an explicit, audited override."}}
        else
          adapter.run(command, args, opts)
        end
    end
  end

  defp host_adapter?(ControlKeel.ExecutionSandbox.Local), do: true
  defp host_adapter?(_), do: false

  @doc """
  Whether host (local) execution is forbidden.

  Off by default to preserve the zero-config local path; opt in via config
  `enforce_sandbox: true` or env `CK_ENFORCE_SANDBOX=1` to require an isolated
  runtime for all sandboxed execution (host runs then return
  `{:error, {:blocked_by_policy, _}}` unless `force: true` is passed).
  """
  def enforce_sandbox? do
    case read_config() do
      %{"enforce_sandbox" => value} when is_boolean(value) ->
        value

      _ ->
        System.get_env("CK_ENFORCE_SANDBOX") in ~w(1 true TRUE yes YES)
    end
  end

  def resolve_adapter(opts, resolution_opts \\ []) do
    name = adapter_name(opts)
    adapter = adapter_module(name)
    strict? = Keyword.get(resolution_opts, :strict, false)

    if function_exported?(adapter, :available?, 0) and not adapter.available?() do
      cond do
        name == @default_adapter ->
          adapter

        strict? ->
          {:error,
           {:sandbox_unavailable,
            "Requested sandbox adapter #{name} is unavailable; refusing to fall back to host execution."}}

        true ->
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
