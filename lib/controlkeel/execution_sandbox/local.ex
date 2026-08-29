defmodule ControlKeel.ExecutionSandbox.Local do
  @moduledoc false

  @behaviour ControlKeel.ExecutionSandbox

  @default_timeout_ms 600_000
  @result_grace_ms 2_000

  @impl true
  def run(command, args, opts) do
    env = Keyword.get(opts, env_key(), [])
    cwd = Keyword.get(opts, :cwd)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    result_path = Keyword.get(opts, :result_path)
    heartbeat_path = Keyword.get(opts, :heartbeat_path)

    command
    |> resolve_executable()
    |> case do
      {:ok, executable} ->
        stream_run(executable, args,
          env: env,
          cwd: cwd,
          timeout_ms: timeout,
          result_path: result_path,
          heartbeat_path: heartbeat_path
        )

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def available?, do: true

  @impl true
  def adapter_name, do: "local"

  # ─── Streaming runner ────────────────────────────────────────────────────────
  #
  # Headless agent CLIs (agy -p, claude -p, codex exec, …) emit their structured
  # result and then may idle waiting for further input instead of exiting. A bare
  # blocking System.cmd hangs forever in that case. This runner:
  #
  #   * streams stdout (heartbeat file touched on every chunk)
  #   * kills the child promptly once the executor's result file appears
  #     (kill-on-result, with a short natural-exit grace window)
  #   * enforces a hard deadline and reports exit status 124 (timeout(1)
  #     convention) when the child never delivered a result
  #
  # All outcomes stay within the adapter contract `{:ok, %{output, exit_status}}`
  # with extra diagnostic keys (`timed_out`, `killed_on_result`).

  defp stream_run(executable, args, opts) do
    env = Keyword.get(opts, :env, [])
    cwd = Keyword.get(opts, :cwd)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    result_path = Keyword.get(opts, :result_path)
    heartbeat_path = Keyword.get(opts, :heartbeat_path)

    port_opts =
      [
        :binary,
        :stream,
        :use_stdio,
        :stderr_to_stdout,
        :exit_status,
        {:args, args},
        {:env, port_env(env)}
      ] ++ list_opt(:cd, cwd)

    port = Port.open({:spawn_executable, executable}, port_opts)
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    result =
      receive_loop(port, %{
        buffer: [],
        deadline: deadline,
        result_path: result_path,
        heartbeat_path: heartbeat_path,
        result_seen_at: nil,
        grace_deadline: nil
      })

    case result do
      {:ok, %{exit_status: _} = run} -> {:ok, run}
      {:error, _} = error -> error
    end
  end

  defp receive_loop(port, state) do
    now = System.monotonic_time(:millisecond)

    cond do
      state.grace_deadline != nil and now >= state.grace_deadline ->
        # Result delivered; the child idled past the grace window — kill it.
        kill_port(port)
        {:ok, finish(state, exit_status: 0, killed_on_result: true)}

      now >= state.deadline ->
        kill_port(port)
        {:ok, finish(state, exit_status: 124, timed_out: true)}

      true ->
        state = maybe_touch_heartbeat(state)

        receive do
          {^port, {:data, chunk}} ->
            state
            |> Map.update!(:buffer, &[chunk | &1])
            |> touch_heartbeat()
            |> detect_result_file()
            |> then(&receive_loop(port, &1))

          {^port, {:exit_status, status}} ->
            {:ok, finish(state, exit_status: status)}

          {^port, :closed} ->
            # The exit_status message is the authoritative terminator; a bare
            # close (without :exit_status semantics) should not end the run.
            receive_loop(port, state)

          {:DOWN, ^port, :port, _pid, reason} ->
            {:ok, finish(state, exit_status: down_exit_status(reason))}
        after
          50 ->
            state
            |> detect_result_file()
            |> then(&receive_loop(port, &1))
        end
    end
  end

  # Once the executor's result file exists, allow a short grace window for a
  # natural exit before killing (mirrors Antigravity Bridge's kill-on-result
  # guard against WaitForConversationFullyIdle hangs).
  defp detect_result_file(%{result_path: nil} = state), do: state

  defp detect_result_file(%{result_path: path, grace_deadline: nil} = state)
       when is_binary(path) do
    if File.exists?(path) do
      %{
        state
        | result_seen_at: System.monotonic_time(:millisecond),
          grace_deadline: System.monotonic_time(:millisecond) + @result_grace_ms
      }
    else
      state
    end
  end

  defp detect_result_file(state), do: state

  defp maybe_touch_heartbeat(%{heartbeat_path: path} = state) do
    if is_binary(path) and rem(System.monotonic_time(:millisecond), 8) == 0 do
      write_heartbeat(path)
    end

    state
  end

  defp touch_heartbeat(%{heartbeat_path: nil} = state), do: state

  defp touch_heartbeat(%{heartbeat_path: path} = state) do
    write_heartbeat(path)
    state
  end

  defp write_heartbeat(path) do
    payload =
      %{
        "ts" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "pid" => System.get_env("CONTROLKEEL_SESSION_ID")
      }
      |> Jason.encode!()

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, payload)
  rescue
    _ -> :ok
  end

  defp finish(state, overrides) do
    output =
      state.buffer
      |> Enum.reverse()
      |> Enum.join()

    run =
      %{output: output, exit_status: nil}
      |> Map.merge(Map.new(overrides))

    run =
      if Map.get(run, :killed_on_result, false) or Map.get(run, :timed_out, false) do
        note =
          if Map.get(run, :killed_on_result) do
            "\n[controlkeel] child terminated after result delivery (idle-wait guard)\n"
          else
            "\n[controlkeel] child terminated on deadline (#{Map.get(run, :exit_status)})\n"
          end

        %{run | output: output <> note}
      else
        run
      end

    Map.take(run, [:output, :exit_status, :timed_out, :killed_on_result])
  end

  defp kill_port(port) do
    # Port.close sends SIGTERM to the child on Unix.
    Port.close(port)
    # Drain the exit message so the mailbox stays clean.
    receive do
      {^port, {:exit_status, _}} -> :ok
    after
      1_000 -> :ok
    end
  rescue
    _ -> :ok
  end

  defp down_exit_status(:normal), do: 0
  defp down_exit_status(:killed), do: 143
  defp down_exit_status(_), do: 1

  defp resolve_executable(command) do
    case System.find_executable(command) do
      nil -> {:error, {:command_not_found, command}}
      path -> {:ok, path}
    end
  end

  defp list_opt(_key, nil), do: []
  defp list_opt(key, value), do: [{key, value}]

  # Ports accept only "KEY=value" binaries (System.cmd-style {k, v} tuples
  # must be normalized).
  defp port_env(env) do
    Enum.map(env, fn
      {key, value} when is_binary(key) and is_binary(value) ->
        {String.to_charlist(key), String.to_charlist(value)}

      {key, value} when is_list(key) and is_list(value) ->
        {key, value}

      entry when is_binary(entry) ->
        [key, value] = String.split(entry, "=", parts: 2)
        {String.to_charlist(key), String.to_charlist(value)}
    end)
  end

  # Tests may pass charlist env (System.cmd style) or binary pairs.
  defp env_key, do: :env
end
