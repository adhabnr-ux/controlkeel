defmodule ControlKeel.Governance.CopilotChannel do
  @moduledoc """
  Real-time collaborative channel where human actions (reviews, edits, approvals)
  stream to the agent without polling.

  Events:
    - human.viewing    — human opened a file or review
    - human.editing    — human made an edit
    - human.approving  — human approved a review
    - human.commenting — human left a comment

  Uses Phoenix PubSub for fan-out and stores recent events in an ETS-backed
  GenServer for history queries.
  """

  use GenServer

  @max_history 100
  @prune_interval_ms 60_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Publish an event to a session's copilot channel."
  def publish(session_id, event_type, payload \\ %{}, opts \\ []) do
    GenServer.cast(__MODULE__, {:publish, session_id, event_type, payload, opts})
  end

  @doc "Subscribe the current process to a session's copilot events."
  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(ControlKeel.PubSub, topic(session_id))
  end

  @doc "Get recent events for a session."
  def history(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    GenServer.call(__MODULE__, {:history, session_id, limit})
  end

  @doc "Get presence info for a session (who is connected)."
  def presence(session_id) do
    GenServer.call(__MODULE__, {:presence, session_id})
  end

  defp topic(session_id), do: "ck_copilot:#{session_id}"

  @impl true
  def init(_opts) do
    table = :ets.new(:ck_copilot_history, [:set, :public, read_concurrency: true])
    schedule_prune()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:publish, session_id, event_type, payload, opts}, state) do
    actor = Keyword.get(opts, :actor, "unknown")
    task_id = Keyword.get(opts, :task_id)

    event = %{
      id: System.unique_integer([:positive]),
      session_id: session_id,
      event_type: event_type,
      actor: actor,
      task_id: task_id,
      payload: payload,
      timestamp: DateTime.utc_now()
    }

    events =
      case :ets.lookup(state.table, session_id) do
        [{^session_id, stored}] -> stored
        [] -> []
      end

    trimmed = [event | events] |> Enum.take(@max_history)
    :ets.insert(state.table, {session_id, trimmed})

    Phoenix.PubSub.broadcast(ControlKeel.PubSub, topic(session_id), {:copilot_event, event})

    {:noreply, state}
  end

  @impl true
  def handle_call({:history, session_id, limit}, _from, state) do
    events =
      case :ets.lookup(state.table, session_id) do
        [{^session_id, stored}] -> Enum.take(stored, limit)
        [] -> []
      end

    {:reply, {:ok, events}, state}
  end

  @impl true
  def handle_call({:presence, session_id}, _from, state) do
    {:reply, {:ok, %{"session_id" => session_id, "topic" => topic(session_id)}}, state}
  end

  @impl true
  def handle_info(:prune, state) do
    schedule_prune()
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    :ets.tab2list(state.table)
    |> Enum.each(fn {session_id, events} ->
      filtered =
        Enum.filter(events, fn e ->
          DateTime.compare(e.timestamp, cutoff) in [:gt, :eq]
        end)

      if filtered == [] do
        :ets.delete(state.table, session_id)
      else
        :ets.insert(state.table, {session_id, filtered})
      end
    end)

    {:noreply, state}
  end

  defp schedule_prune do
    Process.send_after(self(), :prune, @prune_interval_ms)
  end
end
