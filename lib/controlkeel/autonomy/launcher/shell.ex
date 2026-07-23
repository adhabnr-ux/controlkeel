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
  * **Process-tree timeout.** Unix launches use a Python `os.setsid()+execv()`
    wrapper so the tracked PID remains the dedicated process-group leader;
    Windows uses `taskkill /T`. Timeout termination targets the managed process
    group/tree, not only the BEAM port owner. Launcher commands are trusted
    configuration and must not deliberately escape that boundary by daemonizing,
    double-forking, or creating another session. A timeout is reported only after
    managed shutdown is confirmed; otherwise the launcher returns an explicit
    termination failure. Launching fails closed when isolation is unavailable.

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
  @termination_grace_ms 100
  @termination_confirm_ms 500
  @termination_poll_ms 10

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
        case terminate_tree(port, os_pid, isolation) do
          :ok -> {:error, {:launch_timeout, timeout_ms}}
          {:error, reason} -> {:error, {:launch_termination_failed, timeout_ms, reason}}
        end
    end
  end

  # On Unix, run each launcher in a new session/process group so timeout signals
  # target the whole tree. A Python os.setsid()+execv wrapper keeps the tracked
  # port PID as the process-group leader (unlike the setsid utility, which may
  # fork). Fail closed when the isolation helper is unavailable.
  defp isolated_command(command_path, args) do
    case :os.type() do
      {:win32, _} ->
        {:ok, command_path, args, :windows_tree}

      {:unix, _} ->
        case System.find_executable("python3") do
          nil ->
            {:error, :process_group_unavailable}

          python ->
            script =
              "import os,sys\n" <>
                "try:\n os.setsid()\n" <>
                "except PermissionError:\n" <>
                " assert os.getpgrp() == os.getpid()\n" <>
                "os.execv(sys.argv[1], sys.argv[1:])"

            {:ok, python, ["-c", script, command_path | args], {:unix_process_group, python}}
        end
    end
  end

  defp terminate_tree(port, os_pid, {:unix_process_group, python}) do
    result =
      with {:ok, kill} <- executable("kill"),
           :ok <- signal_process_group(kill, python, os_pid, "TERM") do
        safe_port_close(port)
        wait(@termination_grace_ms)

        case portable_process_group_alive?(python, os_pid) do
          {:ok, false} ->
            :ok

          {:ok, true} ->
            with :ok <- signal_process_group(kill, python, os_pid, "KILL"),
                 :ok <- await_process_group_exit(python, os_pid, @termination_confirm_ms) do
              :ok
            end

          {:error, _reason} = error ->
            error
        end
      end

    safe_port_close(port)
    result
  end

  defp terminate_tree(port, os_pid, :windows_tree) do
    result =
      with {:ok, taskkill} <- executable("taskkill"),
           {_output, 0} <-
             System.cmd(taskkill, ["/PID", to_string(os_pid), "/T", "/F"], stderr_to_stdout: true) do
        safe_port_close(port)
        await_windows_process_exit(os_pid, @termination_confirm_ms)
      else
        {output, status} when is_integer(status) ->
          {:error, command_failure(:taskkill_failed, status, output)}

        {:error, _reason} = error ->
          error
      end

    safe_port_close(port)
    result
  rescue
    error ->
      safe_port_close(port)
      {:error, {:taskkill_exception, Exception.message(error)}}
  end

  defp executable(name) do
    case System.find_executable(name) do
      nil -> {:error, {:executable_unavailable, name}}
      path -> {:ok, path}
    end
  end

  defp signal_process_group(kill, python, os_pid, signal) do
    case System.cmd(kill, ["-#{signal}", "--", "-#{os_pid}"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        case portable_process_group_alive?(python, os_pid) do
          {:ok, false} -> :ok
          {:ok, true} -> {:error, command_failure(:signal_failed, status, output)}
          {:error, _reason} = error -> error
        end
    end
  rescue
    error -> {:error, {:signal_exception, signal, Exception.message(error)}}
  end

  defp await_process_group_exit(python, os_pid, timeout_ms) do
    deadline = monotonic_ms() + timeout_ms
    do_await_process_group_exit(python, os_pid, deadline)
  end

  defp do_await_process_group_exit(python, os_pid, deadline) do
    case process_group_alive?(python, os_pid) do
      {:ok, false} ->
        :ok

      {:ok, true} ->
        if monotonic_ms() >= deadline do
          {:error, :still_running}
        else
          receive do
          after
            @termination_poll_ms ->
              do_await_process_group_exit(python, os_pid, deadline)
          end
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp process_group_alive?(python, os_pid) do
    if :os.type() == {:unix, :linux} do
      linux_process_group_alive?(os_pid)
    else
      portable_process_group_alive?(python, os_pid)
    end
  end

  defp portable_process_group_alive?(python, os_pid) do
    script =
      "import os,sys\n" <>
        "try:\n os.killpg(int(sys.argv[1]), 0)\n" <>
        "except ProcessLookupError:\n sys.exit(1)\n" <>
        "except PermissionError:\n sys.exit(2)"

    case System.cmd(python, ["-c", script, to_string(os_pid)], stderr_to_stdout: true) do
      {_output, 0} -> {:ok, true}
      {_output, 1} -> {:ok, false}
      {output, status} -> {:error, command_failure(:liveness_check_failed, status, output)}
    end
  rescue
    error -> {:error, {:liveness_check_failed, Exception.message(error)}}
  end

  defp linux_process_group_alive?(os_pid) do
    case File.ls("/proc") do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, false}, fn entry, _acc ->
          result =
            case Integer.parse(entry) do
              {_pid, ""} -> runnable_process_group_member?(entry, os_pid)
              _ -> {:ok, false}
            end

          case result do
            {:ok, true} -> {:halt, {:ok, true}}
            {:ok, false} -> {:cont, {:ok, false}}
            {:error, _reason} = error -> {:halt, error}
          end
        end)

      {:error, reason} ->
        {:error, {:proc_unavailable, reason}}
    end
  end

  defp runnable_process_group_member?(pid, os_pid) do
    with {:ok, stat} <- File.read("/proc/#{pid}/stat"),
         {:ok, state, process_group} <- parse_proc_stat(stat),
         {process_group, ""} <- Integer.parse(process_group) do
      {:ok, process_group == os_pid and state not in ["Z", "X", "x"]}
    else
      {:error, :enoent} -> {:ok, false}
      {:error, reason} -> {:error, {:proc_stat_unavailable, pid, reason}}
      _ -> {:error, {:invalid_proc_stat, pid}}
    end
  end

  defp parse_proc_stat(stat) do
    case :binary.matches(stat, ") ") do
      [] ->
        {:error, :missing_comm_delimiter}

      matches ->
        {position, delimiter_size} = List.last(matches)
        offset = position + delimiter_size
        remainder = binary_part(stat, offset, byte_size(stat) - offset)

        case remainder |> :binary.split(" ", [:global]) |> Enum.reject(&(&1 == "")) do
          [state, _parent_pid, process_group | _rest] ->
            {:ok, state, process_group}

          _ ->
            {:error, :missing_process_fields}
        end
    end
  end

  defp await_windows_process_exit(os_pid, timeout_ms) do
    with {:ok, tasklist} <- executable("tasklist") do
      deadline = monotonic_ms() + timeout_ms
      do_await_windows_process_exit(tasklist, os_pid, deadline)
    end
  end

  defp do_await_windows_process_exit(tasklist, os_pid, deadline) do
    case System.cmd(
           tasklist,
           ["/FI", "PID eq #{os_pid}", "/FO", "CSV", "/NH"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        if Regex.match?(~r/"#{os_pid}"/, output) do
          if monotonic_ms() >= deadline do
            {:error, :still_running}
          else
            receive do
            after
              @termination_poll_ms ->
                do_await_windows_process_exit(tasklist, os_pid, deadline)
            end
          end
        else
          :ok
        end

      {output, status} ->
        {:error, command_failure(:tasklist_failed, status, output)}
    end
  rescue
    error -> {:error, {:liveness_check_failed, Exception.message(error)}}
  end

  defp command_failure(kind, status, output) do
    {kind, status, output |> then(&append_output(<<>>, &1)) |> finalize_output()}
  end

  defp wait(timeout_ms) do
    receive do
    after
      timeout_ms -> :ok
    end
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
