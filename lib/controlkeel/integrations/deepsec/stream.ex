defmodule ControlKeel.Integrations.Deepsec.Stream do
  @moduledoc """
  Streaming support for deepsec findings.

  This module provides streaming capabilities to process findings
  as they are discovered, rather than waiting for the complete scan.
  """

  use GenServer

  require Logger

  @doc """
  Starts a streaming session for deepsec findings.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes to finding streams for a session.
  """
  def subscribe(session_id, callback_pid \\ nil) do
    callback_pid = callback_pid || self()
    GenServer.call(__MODULE__, {:subscribe, session_id, callback_pid})
  end

  @doc """
  Unsubscribes from finding streams.
  """
  def unsubscribe(session_id, callback_pid \\ nil) do
    callback_pid = callback_pid || self()
    GenServer.call(__MODULE__, {:unsubscribe, session_id, callback_pid})
  end

  @doc """
  Streams a finding to subscribers.
  """
  def stream_finding(session_id, finding) do
    GenServer.cast(__MODULE__, {:stream_finding, session_id, finding})
  end

  @doc """
  Streams multiple findings to subscribers.
  """
  def stream_findings(session_id, findings) when is_list(findings) do
    Enum.each(findings, fn finding ->
      stream_finding(session_id, finding)
    end)
  end

  @doc """
  Gets the count of findings streamed for a session.
  """
  def get_count(session_id) do
    GenServer.call(__MODULE__, {:get_count, session_id})
  end

  @doc """
  Resets the stream for a session.
  """
  def reset_stream(session_id) do
    GenServer.call(__MODULE__, {:reset_stream, session_id})
  end

  @doc """
  Streams findings from a deepsec scan with a callback.
  """
  def stream_scan(callback, workspace_path, opts \\ []) do
    # Start a temporary stream session
    session_id = generate_session_id()
    subscribe(session_id)

    # Start the scan in a separate process
    task =
      Task.async(fn ->
        case do_stream_scan(session_id, workspace_path, opts) do
          {:ok, _result} ->
            :ok

          {:error, reason} ->
            Logger.error("Stream scan failed: #{reason}")
            {:error, reason}
        end
      end)

    # Process findings as they arrive
    Stream.resource(
      fn -> {session_id, task, [], :streaming} end,
      fn
        {session_id, task, _buffer, :done} ->
          {:halt, {session_id, task, [], :done}}

        {session_id, task, buffer, :streaming} ->
          # Check if task is complete
          case Task.yield(task, 100) do
            {:ok, _result} ->
              # Task complete; drain any messages emitted before the task exited
              # that have not yet been consumed by this stream.
              emit_final_findings(session_id, task, drain_stream_messages(buffer))

            nil ->
              # Task still running, check for new findings
              receive do
                {:finding, finding} ->
                  {[finding], {session_id, task, [finding | buffer], :streaming}}

                :stream_complete ->
                  emit_final_findings(session_id, task, buffer)
              after
                100 ->
                  {[], {session_id, task, buffer, :streaming}}
              end
          end
      end,
      fn _ -> unsubscribe(session_id) end
    )
    |> Enum.each(callback)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Deepsec stream server started")
    {:ok, %{subscribers: %{}, counts: %{}}}
  end

  @impl true
  def handle_call({:subscribe, session_id, callback_pid}, _from, state) do
    subscribers =
      Map.update(state.subscribers, session_id, [callback_pid], fn subs ->
        if callback_pid in subs, do: subs, else: [callback_pid | subs]
      end)

    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_call({:unsubscribe, session_id, callback_pid}, _from, state) do
    subscribers =
      Map.update(state.subscribers, session_id, [], fn subs ->
        List.delete(subs, callback_pid)
      end)

    # Clean up empty subscription lists
    subscribers = Enum.reject(subscribers, fn {_sid, subs} -> Enum.empty?(subs) end)
    subscribers = Map.new(subscribers)

    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_call({:get_count, session_id}, _from, state) do
    count = Map.get(state.counts, session_id, 0)
    {:reply, count, state}
  end

  @impl true
  def handle_call({:reset_stream, session_id}, _from, state) do
    {:reply, :ok, %{state | counts: Map.delete(state.counts, session_id)}}
  end

  @impl true
  def handle_call({:get_subscribers, session_id}, _from, state) do
    subscribers = Map.get(state.subscribers, session_id, [])
    {:reply, subscribers, state}
  end

  @impl true
  def handle_cast({:stream_finding, session_id, finding}, state) do
    # Update count
    counts = Map.update(state.counts, session_id, 1, &(&1 + 1))

    # Send to subscribers
    subscribers = Map.get(state.subscribers, session_id, [])

    Enum.each(subscribers, fn pid ->
      if Process.alive?(pid) do
        send(pid, {:finding, finding})
      end
    end)

    {:noreply, %{state | counts: counts}}
  end

  ## Private Functions

  defp do_stream_scan(session_id, workspace_path, opts) do
    alias ControlKeel.Integrations.Deepsec.CLI

    scan_fun = Keyword.get(opts, :scan_fun, &CLI.scan/1)

    case scan_fun.(workspace_path: workspace_path) do
      {:ok, output} ->
        # Parse findings from output
        case CLI.extract_findings(output) do
          {:ok, findings} ->
            # Stream each finding
            Enum.each(findings, fn finding ->
              stream_finding(session_id, finding)
            end)

            # Notify subscribers that stream is complete
            notify_complete(session_id)
            {:ok, findings}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp notify_complete(session_id) do
    # Get subscribers for this session
    subscribers =
      GenServer.call(__MODULE__, {:get_subscribers, session_id}, 5000)

    Enum.each(subscribers, fn pid ->
      if Process.alive?(pid) do
        send(pid, :stream_complete)
      end
    end)
  end

  defp drain_stream_messages(buffer) do
    receive do
      {:finding, finding} -> drain_stream_messages([finding | buffer])
      :stream_complete -> drain_stream_messages(buffer)
    after
      0 -> buffer
    end
  end

  defp emit_final_findings(session_id, task, buffer) do
    findings = Enum.reverse(buffer)

    if Enum.empty?(findings) do
      {:halt, {session_id, task, [], :done}}
    else
      {findings, {session_id, task, [], :done}}
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
