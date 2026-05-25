defmodule ControlKeel.Bus.JetStream do
  @moduledoc """
  NATS JetStream adapter for durable pub/sub queues.

  Provides the same `publish/2` and `publish_json/2` surface as `Bus.Nats` but
  publishes into a JetStream stream so messages survive restarts and can be
  consumed by durable consumer groups.

  ## Configuration

      config :controlkeel, ControlKeel.Bus.JetStream,
        connection_settings: [host: "127.0.0.1", port: 4222],
        stream: "CONTROLKEEL",
        stream_subjects: ["controlkeel.>"]

  Falls back gracefully: if JetStream is unavailable (pre-4.x NATS or dev mode)
  it stores messages in an in-process ETS queue drained on reconnect.
  """

  use GenServer

  @default_stream "CONTROLKEEL"
  @default_subjects ["controlkeel.>"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Publish a raw binary payload to `topic`."
  @spec publish(String.t(), binary()) :: :ok | {:error, term()}
  def publish(topic, payload) do
    GenServer.call(__MODULE__, {:publish, topic, payload})
  end

  @doc "JSON-encode `payload` and publish to `topic`."
  @spec publish_json(String.t(), map()) :: :ok | {:error, term()}
  def publish_json(topic, payload) do
    publish(topic, Jason.encode!(payload))
  end

  @doc "Pending messages buffered while JetStream was unavailable."
  @spec pending_count() :: non_neg_integer()
  def pending_count do
    GenServer.call(__MODULE__, :pending_count)
  end

  # GenServer

  @impl true
  def init(_opts) do
    settings = Application.get_env(:controlkeel, __MODULE__, [])
    conn_settings = Keyword.get(settings, :connection_settings, [])
    stream = Keyword.get(settings, :stream, @default_stream)
    subjects = Keyword.get(settings, :stream_subjects, @default_subjects)

    state = %{conn: nil, stream: stream, subjects: subjects, pending: :queue.new()}

    case connect_and_ensure_stream(conn_settings, stream, subjects) do
      {:ok, conn} -> {:ok, %{state | conn: conn}}
      {:error, _} -> {:ok, state}
    end
  end

  @impl true
  def handle_call({:publish, topic, payload}, _from, %{conn: nil} = state) do
    entry = %{topic: topic, payload: payload, queued_at: DateTime.utc_now()}
    {:reply, :ok, %{state | pending: :queue.in(entry, state.pending)}}
  end

  def handle_call({:publish, topic, payload}, _from, %{conn: conn} = state) do
    reply =
      case Gnat.pub(conn, topic, payload) do
        :ok -> :ok
        {:error, _} = err -> err
      end

    {:reply, reply, state}
  end

  def handle_call(:pending_count, _from, state) do
    {:reply, :queue.len(state.pending), state}
  end

  # Attempt reconnect on demand (triggered externally or on subscribe).
  @impl true
  def handle_info(:reconnect, state) do
    settings = Application.get_env(:controlkeel, __MODULE__, [])
    conn_settings = Keyword.get(settings, :connection_settings, [])

    case connect_and_ensure_stream(conn_settings, state.stream, state.subjects) do
      {:ok, conn} ->
        new_state = drain_pending(%{state | conn: conn})
        {:noreply, new_state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  # Private

  defp connect_and_ensure_stream(conn_settings, stream, subjects) do
    gnat_settings =
      case conn_settings do
        map when is_map(map) -> map
        kw when is_list(kw) -> Map.new(kw)
      end

    # Temporarily trap exits so a refused NATS connection doesn't crash us
    old_trap = Process.flag(:trap_exit, true)

    result =
      case Gnat.start_link(gnat_settings) do
        {:ok, conn} ->
          ensure_stream(conn, stream, subjects)
          {:ok, conn}

        {:error, _} = err ->
          err
      end

    # Drain any stray EXIT messages from the failed Gnat process
    receive do
      {:EXIT, _pid, _reason} -> :ok
    after
      0 -> :ok
    end

    Process.flag(:trap_exit, old_trap)
    result
  end

  defp ensure_stream(conn, stream, subjects) do
    case Gnat.Jetstream.API.Stream.info(conn, stream) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        config = %Gnat.Jetstream.API.Stream{
          name: stream,
          subjects: subjects,
          retention: :limits,
          max_msgs: 100_000,
          max_bytes: 256 * 1024 * 1024,
          max_age: 7 * 24 * 60 * 60 * 1_000_000_000,
          storage: :file
        }

        Gnat.Jetstream.API.Stream.create(conn, config)
    end
  end

  defp drain_pending(%{conn: conn, pending: q} = state) do
    case :queue.out(q) do
      {:empty, _} ->
        state

      {{:value, %{topic: topic, payload: payload}}, rest} ->
        Gnat.pub(conn, topic, payload)
        drain_pending(%{state | pending: rest})
    end
  end
end
