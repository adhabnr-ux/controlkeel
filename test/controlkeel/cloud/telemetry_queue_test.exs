defmodule ControlKeel.Cloud.TelemetryQueueTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.TelemetryConfig
  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Cloud.TelemetryQueue
  alias ControlKeel.Cloud.WorkspaceIdentity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-queue-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    {:ok, _identity, :created} = WorkspaceIdentity.ensure()
    {:ok, _state} = TelemetryConfig.enable(:governance)

    {:ok, envelope} =
      TelemetryEnvelope.build("finding.created", %{"severity" => "high"})

    {:ok, envelope: envelope}
  end

  describe "enqueue/1" do
    test "persists a new envelope as a pending event", %{envelope: envelope} do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)

      assert event.event_id == envelope["event_id"]
      assert event.workspace_id == envelope["workspace_id"]
      assert event.kind == "finding.created"
      assert event.sent_at == nil
      assert event.send_attempts == 0
      assert event.schema_version == "1"
      assert is_binary(event.body)
    end

    test "enqueueing the same event_id twice is a no-op (idempotent)", %{envelope: envelope} do
      {:ok, :enqueued, first} = TelemetryQueue.enqueue(envelope)
      {:ok, :duplicate, second} = TelemetryQueue.enqueue(envelope)

      assert first.id == second.id
      assert TelemetryQueue.pending_count() == 1
    end

    test "envelope body is stored as JSON and round-trips", %{envelope: envelope} do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)
      assert Jason.decode!(event.body) == envelope
    end

    test "envelope missing required keys raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        TelemetryQueue.enqueue(%{"event_id" => "x"})
      end
    end
  end

  describe "pending/1 and pending_count/0" do
    test "returns events oldest-first" do
      {:ok, e1} = build_unique_envelope("finding.created")
      {:ok, e2} = build_unique_envelope("review.submitted")

      {:ok, :enqueued, _} = TelemetryQueue.enqueue(e1)
      Process.sleep(1100)
      {:ok, :enqueued, _} = TelemetryQueue.enqueue(e2)

      [first, second] = TelemetryQueue.pending()
      assert first.event_id == e1["event_id"]
      assert second.event_id == e2["event_id"]
    end

    test "limit caps the batch size" do
      for _ <- 1..5 do
        {:ok, env} = build_unique_envelope("heartbeat")
        TelemetryQueue.enqueue(env)
      end

      assert length(TelemetryQueue.pending(limit: 3)) == 3
      assert TelemetryQueue.pending_count() == 5
    end

    test "pending_count excludes sent events", %{envelope: envelope} do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)
      assert TelemetryQueue.pending_count() == 1

      {:ok, _} = TelemetryQueue.mark_sent(event)
      assert TelemetryQueue.pending_count() == 0
    end
  end

  describe "mark_sent/1" do
    test "transitions a pending event to sent", %{envelope: envelope} do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)
      {:ok, updated} = TelemetryQueue.mark_sent(event)

      assert %DateTime{} = updated.sent_at
      assert updated.send_attempts == 1
      assert updated.last_error == nil
    end

    test "returns :already_sent on double-ack", %{envelope: envelope} do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)
      {:ok, _} = TelemetryQueue.mark_sent(event)
      assert {:error, :already_sent} = TelemetryQueue.mark_sent(event.id)
    end

    test "returns :not_found for an unknown ID" do
      assert {:error, :not_found} = TelemetryQueue.mark_sent(999_999)
    end
  end

  describe "mark_failed/2" do
    test "records last_error and bumps send_attempts without setting sent_at", %{
      envelope: envelope
    } do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)
      {:ok, updated} = TelemetryQueue.mark_failed(event, "timeout after 5s")

      assert updated.sent_at == nil
      assert updated.send_attempts == 1
      assert updated.last_error == "timeout after 5s"
      assert TelemetryQueue.pending_count() == 1
    end
  end

  describe "prune/1" do
    test "deletes sent events older than the retention window", %{envelope: envelope} do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)
      {:ok, _} = TelemetryQueue.mark_sent(event)

      # Backdate sent_at past the retention window
      from =
        Ecto.Adapters.SQL.query!(
          ControlKeel.Repo,
          "UPDATE cloud_telemetry_events SET sent_at = $1 WHERE id = $2",
          [
            ~N[2026-01-01 00:00:00],
            event.id
          ]
        )

      _ = from

      assert {1, nil} = TelemetryQueue.prune(retention_days: 7)
    end

    test "never deletes unsent events", %{envelope: envelope} do
      {:ok, :enqueued, _event} = TelemetryQueue.enqueue(envelope)
      assert {0, nil} = TelemetryQueue.prune(retention_days: 0)
      assert TelemetryQueue.pending_count() == 1
    end
  end

  describe "discard/1" do
    test "removes an event by id", %{envelope: envelope} do
      {:ok, :enqueued, event} = TelemetryQueue.enqueue(envelope)
      assert {1, nil} = TelemetryQueue.discard(event)
      assert TelemetryQueue.pending_count() == 0
    end
  end

  defp build_unique_envelope(kind) do
    TelemetryEnvelope.build(kind, %{"n" => System.unique_integer([:positive])})
  end
end
