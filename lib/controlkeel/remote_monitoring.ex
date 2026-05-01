defmodule ControlKeel.RemoteMonitoring do
  @moduledoc """
  Remote monitoring hooks system for session event streaming.
  Provides webhook/subscription capabilities for read-only monitoring.
  """

  use GenServer
  require Logger

  @table_name :remote_monitoring_subscriptions
  @max_subscriptions_per_session 10

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe(session_id, subscriber_url, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe, session_id, subscriber_url, opts})
  end

  def unsubscribe(subscription_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscription_id})
  end

  def list_subscriptions(session_id) do
    GenServer.call(__MODULE__, {:list_subscriptions, session_id})
  end

  def publish_event(session_id, event_type, event_data) do
    GenServer.cast(__MODULE__, {:publish_event, session_id, event_type, event_data})
  end

  # Server Callbacks

  @impl true
  def init(_) do
    # Create ETS table for subscriptions
    :ets.new(@table_name, [:named_table, :set, :protected])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:subscribe, session_id, subscriber_url, opts}, _from, state) do
    # Validate subscription limit
    session_subscriptions =
      :ets.select(@table_name, [{{:"$1", :"$2", :"$3"}, [{:==, :"$2", session_id}], [:"$1"]}])

    if length(session_subscriptions) >= @max_subscriptions_per_session do
      {:reply, {:error, :max_subscriptions_reached}, state}
    else
      # Validate URL format
      case validate_url(subscriber_url) do
        :ok ->
          subscription_id = generate_subscription_id()
          event_types = Keyword.get(opts, :event_types, :all)

          subscription = %{
            id: subscription_id,
            session_id: session_id,
            subscriber_url: subscriber_url,
            event_types: event_types,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            last_activated_at: nil,
            error_count: 0
          }

          :ets.insert(@table_name, {subscription_id, session_id, subscription})

          {:reply, {:ok, subscription}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    case :ets.lookup(@table_name, subscription_id) do
      [{^subscription_id, _session_id, _subscription}] ->
        :ets.delete(@table_name, subscription_id)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_subscriptions, session_id}, _from, state) do
    subscriptions =
      :ets.select(@table_name, [
        {{:"$1", :"$2", :"$3"}, [{:==, :"$2", session_id}], [:"$3"]}
      ])

    {:reply, {:ok, subscriptions}, state}
  end

  @impl true
  def handle_cast({:publish_event, session_id, event_type, event_data}, state) do
    # Find all subscriptions for this session
    subscriptions =
      :ets.select(@table_name, [
        {{:"$1", :"$2", :"$3"}, [{:==, :"$2", session_id}], [:"$3"]}
      ])

    # Send event to each matching subscription
    Enum.each(subscriptions, fn subscription ->
      if should_receive_event?(subscription, event_type) do
        send_webhook(subscription, event_type, event_data)
      end
    end)

    {:noreply, state}
  end

  # Private functions

  defp generate_subscription_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 32)
  end

  defp validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        :ok

      _ ->
        {:error, :invalid_url}
    end
  end

  defp validate_url(_), do: {:error, :invalid_url}

  defp should_receive_event?(subscription, event_type) do
    case subscription.event_types do
      :all -> true
      types when is_list(types) -> event_type in types
      _ -> true
    end
  end

  defp send_webhook(subscription, event_type, event_data) do
    payload = %{
      "subscription_id" => subscription.id,
      "session_id" => subscription.session_id,
      "event_type" => event_type,
      "event_data" => event_data,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Req.post(subscription.subscriber_url, json: payload) do
      {:ok, _response} ->
        # Update last_activated_at
        :ets.update_element(
          @table_name,
          subscription.id,
          {3,
           Map.put(subscription, :last_activated_at, DateTime.utc_now() |> DateTime.to_iso8601())}
        )

      {:error, _reason} ->
        # Increment error count
        updated_subscription = Map.update!(subscription, :error_count, &(&1 + 1))
        :ets.update_element(@table_name, subscription.id, {3, updated_subscription})
    end
  end
end
