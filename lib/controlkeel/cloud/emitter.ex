defmodule ControlKeel.Cloud.Emitter.Supervisor do
  @moduledoc false
  use GenServer

  alias ControlKeel.Cloud.Emitter

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    _ = Emitter.attach()
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    Emitter.detach()
    :ok
  end
end

defmodule ControlKeel.Cloud.Emitter do
  @moduledoc """
  Bridge from local governance events to the cloud telemetry queue.

  When cloud telemetry is opted in (`Config.enabled?/1`), governance
  events flow through here:

      governance event → translate to envelope kind → Envelope.build →
      Redactor.redact → Queue.enqueue

  When telemetry is disabled the emitter is a no-op. This module is
  fail-soft: any unexpected error during emit is swallowed and the original
  event flow continues. We never crash a finding/review/budget path because
  the cloud pipeline misbehaved.

  ## Wiring

  Attach the `:telemetry` handler at app start:

      ControlKeel.Cloud.Emitter.attach()

  Detach for tests that want to assert on the queue contents directly without
  the live handler running.
  """

  require Logger

  alias ControlKeel.Cloud.Telemetry.Config
  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Cloud.Telemetry.Queue

  @handler_id "controlkeel-cloud-emitter"

  @event_map %{
    [:controlkeel, :finding, :created] => "finding.created",
    [:controlkeel, :finding, :approved] => "finding.approved",
    [:controlkeel, :finding, :rejected] => "finding.rejected",
    [:controlkeel, :review, :submitted] => "review.submitted",
    [:controlkeel, :review, :approved] => "review.approved",
    [:controlkeel, :review, :denied] => "review.denied",
    [:controlkeel, :proof, :generated] => "proof.generated",
    [:controlkeel, :task, :completed] => "task.completed",
    [:controlkeel, :task, :failed] => "task.failed",
    [:controlkeel, :budget, :exceeded] => "budget.exceeded"
  }

  @doc "Telemetry events the emitter listens for."
  @spec events() :: [list(atom())]
  def events, do: Map.keys(@event_map)

  @doc "Attach the `:telemetry` handler that routes governance events to the queue."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach_many(@handler_id, events(), &__MODULE__.handle_event/4, %{})
  end

  @doc "Detach the handler. Idempotent."
  @spec detach() :: :ok
  def detach do
    :telemetry.detach(@handler_id)
    :ok
  end

  @doc """
  Emit one governance event directly without going through the `:telemetry`
  bus. Returns:

    - `:ok` when the envelope was enqueued
    - `{:ok, :duplicate}` when an event with the same `event_id` already exists
    - `{:skipped, reason}` when telemetry is disabled or the kind is unknown
    - `{:error, reason}` for unexpected failures (never raised)
  """
  @spec emit(String.t(), map()) ::
          :ok
          | {:ok, :duplicate}
          | {:skipped, atom() | tuple()}
          | {:error, term()}
  def emit(kind, payload) when is_binary(kind) and is_map(payload) do
    state = Config.load()

    if Config.enabled?(state) do
      do_emit(kind, payload, state)
    else
      {:skipped, :telemetry_disabled}
    end
  rescue
    error ->
      Logger.warning("Cloud.Emitter unexpected failure: #{inspect(error)}")
      {:error, error}
  catch
    kind_caught, value ->
      Logger.warning("Cloud.Emitter caught #{inspect(kind_caught)} #{inspect(value)}")
      {:error, {kind_caught, value}}
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    case Map.get(@event_map, event) do
      nil -> :ok
      kind -> emit_event(kind, measurements, metadata)
    end
  end

  defp emit_event(kind, measurements, metadata) do
    payload = build_payload(measurements, metadata)

    case emit(kind, payload) do
      :ok -> :ok
      {:ok, :duplicate} -> :ok
      {:skipped, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp build_payload(measurements, metadata) do
    metadata
    |> normalize()
    |> Map.put("measurements", normalize(measurements))
  end

  defp normalize(value) when is_map(value) do
    Enum.into(value, %{}, fn
      {k, v} when is_map(v) -> {to_string(k), normalize(v)}
      {k, v} when is_list(v) -> {to_string(k), Enum.map(v, &normalize_value/1)}
      {k, v} -> {to_string(k), normalize_value(v)}
    end)
  end

  defp normalize(_), do: %{}

  defp normalize_value(v) when is_binary(v), do: v
  defp normalize_value(v) when is_integer(v), do: v
  defp normalize_value(v) when is_float(v), do: v
  defp normalize_value(v) when is_boolean(v), do: v
  defp normalize_value(nil), do: nil
  defp normalize_value(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_value(v) when is_map(v), do: normalize(v)
  defp normalize_value(v) when is_list(v), do: Enum.map(v, &normalize_value/1)
  defp normalize_value(other), do: inspect(other)

  defp do_emit(kind, payload, state) do
    with {:ok, envelope} <- Envelope.build(kind, payload, state: state),
         {:ok, outcome, _event} <- Queue.enqueue(envelope) do
      case outcome do
        :enqueued -> :ok
        :duplicate -> {:ok, :duplicate}
      end
    else
      {:error, {:unknown_kind, _} = reason} -> {:skipped, reason}
      {:error, :telemetry_disabled} -> {:skipped, :telemetry_disabled}
      {:error, :workspace_not_set} -> {:skipped, :workspace_not_set}
      {:error, reason} -> {:error, reason}
    end
  end
end
