defmodule ControlKeel.ExecutionSandbox.Docker do
  @moduledoc false

  @behaviour ControlKeel.ExecutionSandbox

  @default_image "ghcr.io/aryaminus/controlkeel-agent-runner:latest"

  @impl true
  def run(command, args, opts) do
    env = Keyword.get(opts, :env, [])
    allowed_env_vars = Keyword.get(opts, :allowed_env_vars, [])
    cwd = Keyword.get(opts, :cwd)
    image = Keyword.get(opts, :docker_image, config_image())
    timeout = Keyword.get(opts, :timeout, 600)

    with :ok <- ensure_image_available(image) do
      env_vars = merge_env_vars(env, allowed_env_vars)

      docker_args = build_docker_args(command, args, env_vars, cwd, image, timeout)

      try do
        {output, exit_status} = System.cmd("docker", docker_args, stderr_to_stdout: true)
        {:ok, %{output: output, exit_status: exit_status}}
      rescue
        e -> {:error, {:docker_execution_failed, Exception.message(e)}}
      end
    end
  end

  @doc """
  Fail fast with an actionable error when the sandbox image is missing, instead of
  surfacing an opaque `docker run` pull failure. Tries a local inspect, then a pull.
  """
  def ensure_image_available(image) do
    case System.cmd("docker", ["image", "inspect", image], stderr_to_stdout: true) do
      {_out, 0} ->
        :ok

      _ ->
        case System.cmd("docker", ["pull", image], stderr_to_stdout: true) do
          {_out, 0} ->
            :ok

          {out, _} ->
            {:error,
             {:image_unavailable,
              "Sandbox image #{image} is not present locally and could not be pulled. " <>
                "Build and publish it (see Dockerfile.agent-runner and " <>
                ".github/workflows/agent-runner-image.yml), or set " <>
                "execution_sandbox_docker.image in config. Detail: #{String.slice(out, 0, 200)}"}}
        end
    end
  rescue
    e -> {:error, {:image_unavailable, Exception.message(e)}}
  end

  @impl true
  def available? do
    case System.cmd("docker", ["version", "--format", "{{.Client.Version}}"],
           stderr_to_stdout: true
         ) do
      {output, 0} when is_binary(output) and byte_size(output) > 0 -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @impl true
  def adapter_name, do: "docker"

  defp build_docker_args(command, args, env, cwd, image, timeout) do
    base = ["run", "--rm"]

    env_flags =
      env
      |> Enum.flat_map(fn {k, v} -> ["-e", "#{k}=#{v}"] end)

    volume_flags =
      if cwd do
        ["-v", "#{Path.expand(cwd)}:/workspace:rw", "-w", "/workspace"]
      else
        []
      end

    resource_flags =
      ["--memory", config_memory_limit(), "--cpus", config_cpu_limit()] ++
        timeout_flag(timeout) ++
        network_flag()

    base ++ env_flags ++ volume_flags ++ resource_flags ++ [image, command] ++ args
  end

  defp timeout_flag(timeout) when is_integer(timeout) and timeout > 0,
    do: ["--stop-timeout", to_string(timeout)]

  defp timeout_flag(_), do: []

  defp network_flag do
    case config_network() do
      "none" -> ["--network", "none"]
      "host" -> ["--network", "host"]
      _ -> []
    end
  end

  defp config_image do
    case read_docker_config() do
      %{"image" => image} when is_binary(image) -> image
      _ -> @default_image
    end
  end

  defp config_memory_limit do
    case read_docker_config() do
      %{"memory_limit" => limit} when is_binary(limit) -> limit
      _ -> "512m"
    end
  end

  defp config_cpu_limit do
    case read_docker_config() do
      %{"cpu_limit" => limit} when is_binary(limit) -> limit
      _ -> "1"
    end
  end

  defp config_network do
    case read_docker_config() do
      %{"network" => network} when network in ["none", "host", "bridge"] -> network
      _ -> "none"
    end
  end

  defp read_docker_config do
    path = ControlKeel.RuntimePaths.config_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"execution_sandbox_docker" => %{} = docker_config}} -> docker_config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  # Well-known sensitive env var prefixes that must never be forwarded to sandboxes
  @sensitive_env_prefixes ~w(AWS_SECRET AWS_ACCESS DATABASE_URL MONGODB REDIS_URL SECRET_KEY PRIVATE_KEY TOKEN PASSWORD CREDENTIAL AUTH_TOKEN)

  # Well-known sensitive env var suffixes (e.g. GITHUB_TOKEN, OPENAI_API_KEY, STRIPE_SECRET_KEY)
  @sensitive_env_suffixes ~w(_TOKEN _SECRET _API_KEY _PRIVATE_KEY _PASSWORD _CREDENTIAL)

  defp merge_env_vars(explicit_env, allowed_env_vars)
       when is_list(allowed_env_vars) and
              length(allowed_env_vars) > 0 do
    # Filter out sensitive env var names before reading host values
    sanitized_vars =
      allowed_env_vars
      |> Enum.reject(&sensitive_env_var?/1)

    host_env_vars =
      sanitized_vars
      |> Enum.map(fn var_name ->
        case System.get_env(var_name) do
          nil -> nil
          value -> {var_name, value}
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Explicit env vars take precedence: merge host first, then explicit overwrites
    Map.new(host_env_vars)
    |> Map.merge(Enum.into(explicit_env, %{}))
    |> Map.to_list()
  end

  defp merge_env_vars(explicit_env, _allowed_env_vars), do: explicit_env

  defp sensitive_env_var?(var_name) do
    upper = String.upcase(var_name)

    Enum.any?(@sensitive_env_prefixes, &String.starts_with?(upper, &1)) or
      Enum.any?(@sensitive_env_suffixes, &String.ends_with?(upper, &1))
  end
end
