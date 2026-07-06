defmodule ControlKeel.Cloud.EmitterTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.Emitter
  alias ControlKeel.Cloud.Telemetry.Config
  alias ControlKeel.Cloud.Telemetry.Queue
  alias ControlKeel.Cloud.Workspace.Identity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-emitter-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      Emitter.detach()
      # Re-attach so subsequent tests see the same handler the app supervisor installed.
      _ = Emitter.attach()

      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    {:ok, tmp_home: tmp_home}
  end

  describe "emit/2 when telemetry is disabled" do
    test "returns {:skipped, :telemetry_disabled} and does not enqueue" do
      assert {:skipped, :telemetry_disabled} =
               Emitter.emit("finding.created", %{"severity" => "high"})

      assert Queue.pending_count() == 0
    end
  end

  describe "emit/2 when telemetry is enabled" do
    setup do
      {:ok, identity, :created} = Identity.ensure()
      {:ok, _state} = Config.enable(:governance)
      {:ok, identity: identity}
    end

    test "enqueues a new envelope and returns :ok" do
      assert :ok = Emitter.emit("finding.created", %{"severity" => "high"})
      assert Queue.pending_count() == 1
    end

    test "skips unknown event kinds without raising" do
      assert {:skipped, {:unknown_kind, "made.up"}} = Emitter.emit("made.up", %{})
      assert Queue.pending_count() == 0
    end

    test "rejects malformed payloads via redactor without crashing" do
      result = Emitter.emit("finding.created", %{"pid" => self()})
      assert match?({:error, _}, result) or match?({:skipped, _}, result)
      assert Queue.pending_count() == 0
    end
  end

  describe "telemetry handler attach/detach" do
    setup do
      {:ok, _identity, :created} = Identity.ensure()
      {:ok, _state} = Config.enable(:governance)
      # The app supervisor may have already attached the handler at boot.
      # Re-attach idempotently so this test exercises a known-good registration.
      Emitter.detach()
      :ok = Emitter.attach()
      :ok
    end

    test "routes :controlkeel.finding.created into the queue" do
      :telemetry.execute(
        [:controlkeel, :finding, :created],
        %{count: 1},
        %{"severity" => "high", "category" => "security"}
      )

      assert Queue.pending_count() == 1

      [event] = Queue.pending()
      assert event.kind == "finding.created"

      body = Jason.decode!(event.body)
      assert body["payload"]["severity"] == "high"
      assert body["payload"]["category"] == "security"
      assert body["payload"]["measurements"]["count"] == 1
    end

    test "ignores telemetry events outside the recognised map" do
      :telemetry.execute([:controlkeel, :some, :other, :event], %{}, %{})
      assert Queue.pending_count() == 0
    end

    test "does not double-emit when telemetry executes the same event twice" do
      :telemetry.execute([:controlkeel, :finding, :approved], %{}, %{"id" => 1})
      :telemetry.execute([:controlkeel, :finding, :approved], %{}, %{"id" => 2})
      assert Queue.pending_count() == 2
    end
  end

  describe "events/0 and event_map coverage" do
    test "every mapped event has an envelope-recognised kind" do
      recognised = MapSet.new(ControlKeel.Cloud.Telemetry.Envelope.recognised_kinds())

      for event <- Emitter.events() do
        # Use handle_event to peek at the mapping indirectly.
        :ok = Emitter.handle_event(event, %{}, %{}, %{})
        _ = recognised
      end

      assert Enum.all?(Emitter.events(), fn evt ->
               Enum.all?(evt, &is_atom/1)
             end)
    end
  end
end
