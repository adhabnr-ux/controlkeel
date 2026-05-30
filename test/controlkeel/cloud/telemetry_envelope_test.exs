defmodule ControlKeel.Cloud.TelemetryEnvelopeTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.Redactor
  alias ControlKeel.Cloud.TelemetryConfig
  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Cloud.WorkspaceIdentity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-envelope-test-#{System.unique_integer([:positive])}"
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

    :ok
  end

  describe "build/2 gating" do
    test "fails when telemetry is disabled" do
      assert {:error, :telemetry_disabled} =
               TelemetryEnvelope.build("finding.created", %{"severity" => "high"})
    end

    test "fails with unknown_kind for unrecognised event kinds" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _state} = TelemetryConfig.enable(:governance)

      assert {:error, {:unknown_kind, "made.up.event"}} =
               TelemetryEnvelope.build("made.up.event", %{})
    end

    test "fails with redaction_failed when payload contains unsupported types" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _state} = TelemetryConfig.enable(:governance)

      assert {:error, {:redaction_failed, _}} =
               TelemetryEnvelope.build("finding.created", %{"data" => self()})
    end
  end

  describe "build/2 success" do
    setup do
      {:ok, identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _state} = TelemetryConfig.enable(:governance)
      {:ok, identity: identity}
    end

    test "produces an envelope with the documented D3 shape", %{identity: identity} do
      assert {:ok, env} =
               TelemetryEnvelope.build("finding.created", %{
                 "severity" => "high",
                 "category" => "security"
               })

      assert env["schema_version"] == "1"
      assert env["workspace_id"] == identity.workspace_id
      assert env["kind"] == "finding.created"
      assert env["redaction_policy_version"] == Redactor.policy_version()
      assert is_binary(env["event_id"])
      assert is_binary(env["emitted_at"])
      assert env["payload"]["severity"] == "high"
      assert env["payload"]["category"] == "security"
    end

    test "idempotency_key defaults to event_id" do
      {:ok, env} = TelemetryEnvelope.build("heartbeat", %{})
      assert env["idempotency_key"] == env["event_id"]
    end

    test "idempotency_key can be overridden" do
      {:ok, env} =
        TelemetryEnvelope.build("heartbeat", %{}, idempotency_key: "explicit-key-123")

      assert env["idempotency_key"] == "explicit-key-123"
      refute env["idempotency_key"] == env["event_id"]
    end

    test "emitted_at can be overridden" do
      fixed = ~U[2026-05-23 20:00:00Z]
      {:ok, env} = TelemetryEnvelope.build("heartbeat", %{}, emitted_at: fixed)
      assert env["emitted_at"] == DateTime.to_iso8601(fixed)
    end

    test "atom payload keys are coerced to strings" do
      {:ok, env} =
        TelemetryEnvelope.build("finding.created", %{severity: "high", count: 3})

      assert env["payload"]["severity"] == "high"
      assert env["payload"]["count"] == 3
    end

    test "nested maps and lists are normalised" do
      payload = %{
        "tags" => ["security", "high"],
        "metadata" => %{"source" => "ck_validate"}
      }

      {:ok, env} = TelemetryEnvelope.build("finding.created", payload)
      assert env["payload"]["tags"] == ["security", "high"]
      assert env["payload"]["metadata"]["source"] == "ck_validate"
    end
  end

  describe "ulid/0" do
    test "produces a 26-character string" do
      assert String.length(TelemetryEnvelope.ulid()) == 26
    end

    test "is lexicographically monotonic over time" do
      first = TelemetryEnvelope.ulid()
      Process.sleep(5)
      second = TelemetryEnvelope.ulid()

      assert second > first
    end

    test "is unique across many calls" do
      ulids = for _ <- 1..1000, do: TelemetryEnvelope.ulid()
      assert length(Enum.uniq(ulids)) == 1000
    end

    test "uses only Crockford base32 characters" do
      alphabet = MapSet.new(~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ")

      Enum.each(1..50, fn _ ->
        ulid = TelemetryEnvelope.ulid()

        Enum.each(String.to_charlist(ulid), fn char ->
          assert char in alphabet, "ULID contains non-Crockford char: #{<<char>>}"
        end)
      end)
    end
  end

  describe "recognised_kinds/0" do
    test "includes the core governance events" do
      kinds = TelemetryEnvelope.recognised_kinds()

      for kind <- ~w(finding.created review.submitted budget.exceeded heartbeat) do
        assert kind in kinds, "missing kind: #{kind}"
      end
    end
  end
end
