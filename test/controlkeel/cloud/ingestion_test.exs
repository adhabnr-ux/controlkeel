defmodule ControlKeel.Cloud.IngestionTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.Ingestion
  alias ControlKeel.Cloud.ReceivedTelemetryEvent
  alias ControlKeel.Cloud.Telemetry.Config
  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Cloud.Workspace.Identity
  alias ControlKeel.Repo

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-ingestion-test-#{System.unique_integer([:positive])}"
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

    {:ok, identity, :created} = Identity.ensure()
    {:ok, _state} = Config.enable(:governance)

    {:ok, envelope} = Envelope.build("finding.created", %{"severity" => "high"})

    {:ok, identity: identity, envelope: envelope}
  end

  describe "ingest/2 validation" do
    test "rejects missing keys", %{identity: identity} do
      assert {:error, :malformed_batch} = Ingestion.ingest(%{}, identity.workspace_id)
    end

    test "rejects unsupported schema_version", %{identity: identity, envelope: envelope} do
      batch = %{
        "schema_version" => "999",
        "workspace_id" => identity.workspace_id,
        "events" => [envelope]
      }

      assert {:error, :unsupported_schema_version} =
               Ingestion.ingest(batch, identity.workspace_id)
    end

    test "rejects workspace mismatch in batch header", %{identity: identity, envelope: envelope} do
      batch = %{
        "schema_version" => "1",
        "workspace_id" => "ws_someone_else",
        "events" => [envelope]
      }

      assert {:error, :workspace_mismatch} =
               Ingestion.ingest(batch, identity.workspace_id)
    end

    test "rejects empty batch", %{identity: identity} do
      batch = %{
        "schema_version" => "1",
        "workspace_id" => identity.workspace_id,
        "events" => []
      }

      assert {:error, :empty_batch} = Ingestion.ingest(batch, identity.workspace_id)
    end

    test "rejects batch above max size", %{identity: identity, envelope: envelope} do
      batch = %{
        "schema_version" => "1",
        "workspace_id" => identity.workspace_id,
        "events" => List.duplicate(envelope, 501)
      }

      assert {:error, :batch_too_large} =
               Ingestion.ingest(batch, identity.workspace_id)
    end
  end

  describe "ingest/2 happy path" do
    test "persists a fresh envelope as accepted", %{identity: identity, envelope: envelope} do
      batch = batch_for(identity, [envelope])

      assert {:ok, summary} = Ingestion.ingest(batch, identity.workspace_id)
      assert summary.accepted == 1
      assert summary.duplicates == 0
      assert summary.rejected == 0
      assert [%{event_id: id, status: :accepted}] = summary.outcomes
      assert id == envelope["event_id"]

      stored = Repo.get_by!(ReceivedTelemetryEvent, event_id: id)
      assert stored.source_workspace_id == identity.workspace_id
      assert Jason.decode!(stored.body)["payload"]["severity"] == "high"
    end

    test "marks a re-sent envelope as duplicate", %{identity: identity, envelope: envelope} do
      batch = batch_for(identity, [envelope])

      {:ok, _} = Ingestion.ingest(batch, identity.workspace_id)
      assert {:ok, summary} = Ingestion.ingest(batch, identity.workspace_id)
      assert summary.duplicates == 1
      assert summary.accepted == 0
    end

    test "rejects envelopes with workspace_id different from authenticated workspace", %{
      identity: identity,
      envelope: envelope
    } do
      forged =
        envelope
        |> Map.put("workspace_id", "ws_attacker")
        |> Map.put("event_id", Envelope.ulid())
        |> Map.put("idempotency_key", Envelope.ulid())

      batch = batch_for(identity, [forged])

      # Batch-header workspace matches the auth header, but inner envelope's
      # workspace_id does not — the envelope is individually rejected.
      assert {:ok, summary} = Ingestion.ingest(batch, identity.workspace_id)
      assert summary.rejected == 1
      assert [%{status: :rejected, reason: reason}] = summary.outcomes
      assert reason =~ "workspace_id mismatch"
    end

    test "rejects envelopes with unknown kind", %{identity: identity, envelope: envelope} do
      bad = Map.put(envelope, "kind", "totally.unknown")
      batch = batch_for(identity, [bad])

      assert {:ok, summary} = Ingestion.ingest(batch, identity.workspace_id)
      assert summary.rejected == 1
      assert [%{reason: reason}] = summary.outcomes
      assert reason =~ "unknown kind"
    end

    test "accepts mixed batches and records per-envelope outcomes", %{
      identity: identity,
      envelope: envelope
    } do
      {:ok, second} = Envelope.build("review.approved", %{"id" => 2})
      bad = Map.put(envelope, "kind", "nope.nope")
      bad = Map.put(bad, "event_id", Envelope.ulid())
      bad = Map.put(bad, "idempotency_key", Envelope.ulid())

      batch = batch_for(identity, [envelope, second, bad])

      assert {:ok, summary} = Ingestion.ingest(batch, identity.workspace_id)
      assert summary.accepted == 2
      assert summary.rejected == 1
    end
  end

  describe "count/0 and recent/1" do
    test "track persisted events", %{identity: identity, envelope: envelope} do
      assert Ingestion.count() == 0

      batch = batch_for(identity, [envelope])
      {:ok, _} = Ingestion.ingest(batch, identity.workspace_id)

      assert Ingestion.count() == 1
      assert [%ReceivedTelemetryEvent{}] = Ingestion.global_recent(limit: 10)
    end
  end

  defp batch_for(identity, events) do
    %{
      "schema_version" => "1",
      "workspace_id" => identity.workspace_id,
      "events" => events
    }
  end
end
