defmodule ControlKeel.Cloud.Telemetry.Emitter.Supervisor do
  @moduledoc false
  use GenServer

  alias ControlKeel.Cloud.Telemetry.Emitter

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
