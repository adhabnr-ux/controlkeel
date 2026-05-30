defmodule ControlKeel.Mailer.TestInbox do
  @moduledoc """
  In-memory inbox used only when `:mailer_adapter == :test`.

  Tests assert on delivered messages via `all/0` or `find_by_email/1`.
  Each entry is a tuple `{kind, payload, timestamp}` ordered newest first.

  The Agent is only started by `ControlKeel.Application` when the test
  adapter is active, so production / dev runs don't pay the supervision cost.
  """

  use Agent

  @doc false
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc "Push a new delivery onto the inbox."
  @spec put(atom(), map()) :: :ok
  def put(kind, payload) when is_atom(kind) and is_map(payload) do
    entry = {kind, payload, DateTime.utc_now()}
    Agent.update(__MODULE__, fn list -> [entry | list] end)
    :ok
  end

  @doc "Return all deliveries, newest first."
  @spec all() :: [{atom(), map(), DateTime.t()}]
  def all, do: Agent.get(__MODULE__, & &1)

  @doc "Clear the inbox. Useful in test setup."
  @spec clear() :: :ok
  def clear, do: Agent.update(__MODULE__, fn _ -> [] end)

  @doc """
  Find the most recent delivery to `email`. Returns the entry tuple or `nil`.
  """
  @spec find_by_email(String.t()) :: {atom(), map(), DateTime.t()} | nil
  def find_by_email(email) when is_binary(email) do
    Enum.find(all(), fn
      {_kind, %{to: ^email}, _ts} -> true
      _ -> false
    end)
  end
end
