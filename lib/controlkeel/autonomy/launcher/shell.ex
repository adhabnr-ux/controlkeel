defmodule ControlKeel.Autonomy.Launcher.Shell do
  @moduledoc """
  Capability-gated shell launcher: invokes a configured agent program on schedule.

  ## Security model

  This is the only module in the autonomy subsystem that executes an external
  process, so its trust boundary is intentionally narrow:

  * **argv, not an implicit shell string.** Execution uses `System.cmd/3` with an
    explicit argument list. The job's task text is substituted as a *single
    discrete argv element* via the `:task` placeholder. ControlKeel does not
    implicitly invoke a shell; an operator who explicitly configures `sh -c`,
    `bash -c`, or another interpreter can reintroduce shell parsing and owns that
    trust boundary.
  * **Explicit opt-in.** Gated on the `CK_AUTONOMY_ALLOW_SHELL` environment
    variable or `config :controlkeel, autonomy: [allow_shell: true]`. When neither
    is set, `run/1` returns `{:error, :shell_not_allowed}` and launches nothing.
  * **Trusted template.** The `command` and `args` template are operator-configured
    (trusted source). Only the `:task` placeholder receives job-supplied text, and
    only as an argv element.
  * **Captured, never streamed.** Output is captured and truncated; every launch
    result (exit status + truncated output) is returned to the dispatcher, which
    records it in a governed session event for audit.
  * **Process-tree timeout.** Unix launches run in a dedicated OS process group
    (`setsid`, with Python `os.setsid` fallback); Windows uses `taskkill /T`.
    Timeout termination targets the entire tree, not only the BEAM port owner.

  ## Example

      %ControlKeel.Autonomy.Job{
        launcher: %{adapter: :shell, command: "opencode", args: ["run", :task]}
      }

  resolves, for `task: "Triage open tickets"`, to:

      System.cmd("opencode", ["run", "Triage open tickets"], stderr_to_stdout: true)
  """

  alias ControlKeel.Autonomy.Job

  @max_output_bytes 8_192
  @default_timeout_ms 300_000

  @type launch_result ::
          {:ok, %{exit_status: non_neg_integer(), output: binary()}} | {:error, term()}

  @doc "Whether shell launching is explicitly enabled."
  def enabled? do
    env_enabled?() or config_enabled?()
  end

  @doc """
  Execute the launcher for `job`.

  Returns `{:ok, %{exit_status, output}}` on execution (including non-zero exits,
  which are captured, not raised) or `{:error, reason}` when launching is disabled
  or the program is missing.
  """
  @spec run(Job.t(), keyword()) :: launch_result()
  def run(job, opts \\ [])

  def run(%Job{launcher: %{adapter: :shell}} = job, opts) do
    unless enabled?(), do: throw(:shell_not_allowed)

    %{command: command, args: template} = job.launcher
    args = resolve_args(template, job)
    timeout_ms = launch_timeout_ms(job, opts)

    execute(command, args, timeout_ms)
  catch
    :shell_not_allowed ->
      {:error, :shell_not_allowed}

    :error, :enoent ->
      {:error, {:launch_failed, :enoent}}

    kind, reason ->
      {:error, {:launch_failed, {kind, reason}}}
  end

  def run(_job, _opts), do: {:error, :no_shell_launcher}

  defp execute(command, args, timeout_ms) do
    with command_path when is_binary(command_path) <- System.find_executable(command),
         {:ok, executable, isolated_args, isolation} <- isolated_command(command_path, args),
         {:ok, port, os_pid} <- open_port(executable, isolated_args) do
      collect(port, os_pid, isolation, <<>>, monotonic_ms() + timeout_ms, timeout_ms)
    else
      nil -> {:error, {:launch_failed, :enoent}}
      {:error, _reason} = error -> error
    end
  catch
    kind, reason -> {:error, {:launch_failed, {kind, inspect(reason)}}}
  end

  defp open_port(executable, args) do
    port =
      Port.open(
        {:spawn_executable, String.to_charlist(executable)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          :use_stdio,
          args: Enum.map(args, &String.to_charlist/1)
        ]
      )

    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        {:ok, port, pid}

      nil ->
        safe_port_close(port)
        {:error, {:launch_failed, :missing_os_pid}}
    end
  end

  defp collect(port, os_pid, isolation, output, deadline, timeout_ms) do
    remaining = max(deadline - monotonic_ms(), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, os_pid, isolation, append_output(output, data), deadline, timeout_ms)

      {^port, {:exit_status, status}} ->
        {:ok, %{exit_status: status, output: finalize_output(output)}}
    after
      remaining ->
        terminate_tree(os_pid, isolation)
        safe_port_close(port)
        {:error, {:launch_timeout, timeout_ms}}
    end
  end

  # On Unix, run each launcher in a new session/process group so timeout signals
  # target the whole tree. `setsid` is preferred; Python's os.setsid wrapper is a
  # portable fallback on macOS installations without the setsid utility. If
  # neither exists, fail closed rather than launch a process tree we cannot stop.
  defp isolated_command(command_path, args) do
    case :os.type() do
      {:win32, _} ->
        {:ok, command_path, args, :windows_tree}

      {:unix, _} ->
        cond do
          setsid = System.find_executable("setsid") ->
            {:ok, setsid, [command_path | args], :unix_process_group}

          python = System.find_executable("python3") ->
            script =
              "import os,sys\n" <>
                "try:\n os.setsid()\n" <>
                "except PermissionError:\n" <>
                " assert os.getpgrp() == os.getpid()\n" <>
                "os.execv(sys.argv[1], sys.argv[1:])"

            {:ok, python, ["-c", script, command_path | args], :unix_process_group}

          true ->
            {:error, :process_group_unavailable}
        end
    end
  end

  defp terminate_tree(os_pid, :unix_process_group) do
    signal_process_group(os_pid, "TERM")
    Process.sleep(100)
    signal_process_group(os_pid, "KILL")
  end

  defp terminate_tree(os_pid, :windows_tree) do
    _ = System.cmd("taskkill", ["/PID", to_string(os_pid), "/T", "/F"], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  defp signal_process_group(os_pid, signal) do
    case System.find_executable("kill") do
      nil ->
        :ok

      kill ->
        _ = System.cmd(kill, ["-#{signal}", "-#{os_pid}"], stderr_to_stdout: true)
        :ok
    end
  rescue
    _ -> :ok
  end

  defp safe_port_close(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  defp append_output(output, data) do
    remaining = @max_output_bytes - byte_size(output)

    cond do
      remaining <= 0 -> output
      byte_size(data) <= remaining -> output <> data
      true -> output <> binary_part(data, 0, remaining)
    end
  end

  defp finalize_output(output), do: String.replace_invalid(output)

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp resolve_args(template, %Job{task: task}) when is_list(template) do
    Enum.map(template, fn
      :task -> task
      other when is_binary(other) -> other
    end)
  end

  defp launch_timeout_ms(job, opts) do
    Keyword.get(opts, :timeout_ms) || job.launcher.timeout_ms ||
      Application.get_env(:controlkeel, :autonomy, [])
      |> Keyword.get(:launch_timeout_ms, @default_timeout_ms)
  end

  defp env_enabled? do
    System.get_env("CK_AUTONOMY_ALLOW_SHELL") in ~w(1 true TRUE yes YES)
  end

  defp config_enabled? do
    Application.get_env(:controlkeel, :autonomy, []) |> Keyword.get(:allow_shell, false)
  end
end
