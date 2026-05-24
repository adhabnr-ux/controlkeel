defmodule ControlKeel.Cloud.SenderTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.Sender
  alias ControlKeel.Cloud.TelemetryConfig
  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Cloud.TelemetryQueue
  alias ControlKeel.Cloud.WorkspaceIdentity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-sender-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    previous_endpoint = Application.get_env(:controlkeel, :cloud_telemetry_endpoint)
    Application.delete_env(:controlkeel, :cloud_telemetry_endpoint)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      if previous_endpoint do
        Application.put_env(:controlkeel, :cloud_telemetry_endpoint, previous_endpoint)
      else
        Application.delete_env(:controlkeel, :cloud_telemetry_endpoint)
      end

      Application.delete_env(:controlkeel, :cloud_sender_http_module)

      File.rm_rf!(tmp_home)
    end)

    :ok
  end

  describe "endpoint/0" do
    test "returns nil by default" do
      assert Sender.endpoint() == nil
    end

    test "returns the configured URL" do
      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "https://cloud.example/v1")
      assert Sender.endpoint() == "https://cloud.example/v1"
    end

    test "treats empty string as nil" do
      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "")
      assert Sender.endpoint() == nil
    end
  end

  describe "flush/0 no-op behaviour" do
    test "returns :no_endpoint when no endpoint configured" do
      assert {:ok, :no_endpoint, 0} = Sender.flush()
    end

    test "does not call HTTP module when endpoint is nil" do
      install_failing_http()
      assert {:ok, :no_endpoint, 0} = Sender.flush()
    end

    test "returns :not_connected when endpoint set but no workspace identity" do
      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "https://cloud.example/v1")
      assert {:error, :not_connected, 0} = Sender.flush()
    end
  end

  describe "flush/0 with endpoint + identity" do
    setup do
      {:ok, identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _state} = TelemetryConfig.enable(:governance)
      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "https://cloud.example/v1")
      {:ok, identity: identity}
    end

    test "returns :no_pending when queue is empty" do
      install_recording_http(fn _url, _opts -> {:ok, %{status: 200, body: ""}} end)
      assert {:ok, :no_pending, 0} = Sender.flush()
    end

    test "sends a batch and marks events sent on 2xx" do
      enqueue_envelope("finding.created", %{"severity" => "high"})
      enqueue_envelope("review.approved", %{"id" => "1"})

      Process.put(:captured_requests, [])

      install_recording_http(fn url, opts ->
        Process.put(:captured_requests, [{url, opts} | Process.get(:captured_requests, [])])
        {:ok, %{status: 202}}
      end)

      assert {:ok, :sent, 2} = Sender.flush()
      assert TelemetryQueue.pending_count() == 0

      [{url, opts}] = Process.get(:captured_requests)
      assert url == "https://cloud.example/v1"

      body = Keyword.fetch!(opts, :json)
      assert body["schema_version"] == "1"
      assert is_binary(body["workspace_id"])
      assert length(body["events"]) == 2

      headers = Keyword.fetch!(opts, :headers)
      {"authorization", "Bearer " <> token} = List.keyfind(headers, "authorization", 0)
      # Signed token: payload.signature, both base64url
      assert [_payload_b64, _sig_b64] = String.split(token, ".", parts: 2)
      assert {"content-type", "application/json"} = List.keyfind(headers, "content-type", 0)
      assert {"idempotency-key", batch_id} = List.keyfind(headers, "idempotency-key", 0)
      assert String.length(batch_id) == 26
    end

    test "marks events failed on 5xx and keeps them pending" do
      enqueue_envelope("finding.created", %{"severity" => "high"})
      install_recording_http(fn _url, _opts -> {:ok, %{status: 503}} end)

      assert {:error, {:server, 503}, 1} = Sender.flush()
      assert TelemetryQueue.pending_count() == 1

      [event] = TelemetryQueue.pending()
      assert event.send_attempts == 1
      assert event.last_error =~ "503"
    end

    test "marks events failed on network error" do
      enqueue_envelope("finding.created", %{"severity" => "high"})

      install_recording_http(fn _url, _opts -> {:error, :timeout} end)

      assert {:error, :network, 1} = Sender.flush()
      assert TelemetryQueue.pending_count() == 1

      [event] = TelemetryQueue.pending()
      assert event.last_error =~ "network error"
    end

    test "respects limit option" do
      for _ <- 1..5, do: enqueue_envelope("heartbeat", %{"x" => System.unique_integer([:positive])})

      install_recording_http(fn _url, _opts -> {:ok, %{status: 200}} end)

      assert {:ok, :sent, 2} = Sender.flush(limit: 2)
      assert TelemetryQueue.pending_count() == 3
    end

    test "does not double-send: a re-flush after success is :no_pending" do
      enqueue_envelope("heartbeat", %{})

      install_recording_http(fn _url, _opts -> {:ok, %{status: 200}} end)

      assert {:ok, :sent, 1} = Sender.flush()
      assert {:ok, :no_pending, 0} = Sender.flush()
    end
  end

  defp enqueue_envelope(kind, payload) do
    {:ok, envelope} = TelemetryEnvelope.build(kind, payload)
    {:ok, :enqueued, _event} = TelemetryQueue.enqueue(envelope)
  end

  defp install_recording_http(handler) do
    Application.put_env(:controlkeel, :cloud_sender_http_module, ControlKeel.Cloud.SenderTest.FakeHTTP)
    Process.put(:fake_http_handler, handler)
  end

  defp install_failing_http do
    Application.put_env(:controlkeel, :cloud_sender_http_module, ControlKeel.Cloud.SenderTest.ForbiddenHTTP)
  end

  defmodule FakeHTTP do
    def post(url, opts) do
      handler = Process.get(:fake_http_handler)
      handler.(url, opts)
    end
  end

  defmodule ForbiddenHTTP do
    def post(_url, _opts) do
      raise "HTTP must not be called when endpoint is nil"
    end
  end
end
