defmodule ControlKeel.ObservabilityWorkshopTest do
  use ControlKeel.DataCase

  import ExUnit.CaptureIO

  alias ControlKeel.CLI
  alias ControlKeel.Observability.Workshop

  defp tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-workshop-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  @snapshot %{
    "runs" => [
      %{
        "id" => "run-1",
        "event_id" => "evt-1",
        "event_name" => "triage-agent",
        "name" => "agent run",
        "metadata" => %{"tenant" => "acme"}
      }
    ],
    "spans" => [
      %{
        "id" => "span-1",
        "run_id" => "run-1",
        "name" => "call model",
        "span_type" => "LLM",
        "status" => "OK",
        "input_payload" => "secret prompt",
        "output_payload" => "answer",
        "attributes" => %{"tool" => "search"}
      },
      %{
        "id" => "span-2",
        "run_id" => "run-1",
        "name" => "tool search",
        "span_type" => "tool",
        "status" => "ERROR",
        "output_payload" => "failure details"
      }
    ],
    "live_events" => [%{"trace_id" => "run-1", "content" => "streamed token"}],
    "saved_events" => [%{"id" => "saved-1", "user_input" => "raw user input"}]
  }

  test "preview redacts raw Workshop payloads while preserving counts and metadata" do
    assert {:ok, preview} = Workshop.preview(@snapshot)

    assert preview.schema_version == "controlkeel.workshop.preview.v1"
    assert preview.dry_run == true
    assert preview.mutation == "none"
    assert preview.counts.runs == 1
    assert preview.counts.spans == 2
    assert preview.counts.tool_spans == 1
    assert preview.counts.error_spans == 1
    assert preview.counts.live_events == 1
    assert preview.counts.saved_events == 1
    assert preview.counts.payload_chars_redacted > 0
    assert preview.redaction.raw_span_payloads == false

    encoded = Jason.encode!(preview)
    refute encoded =~ "secret prompt"
    refute encoded =~ "streamed token"
    refute encoded =~ "raw user input"

    assert [%{event_name: "triage-agent", metadata_keys: ["tenant"]}] = preview.runs
    assert Enum.any?(preview.recommendations, &String.contains?(&1, "Error spans"))
  end

  test "preview rejects invalid Workshop snapshot shapes" do
    assert {:error, :invalid_workshop_snapshot} = Workshop.preview(%{"spans" => []})

    assert {:error, {:invalid_field, "spans"}} =
             Workshop.preview(%{"runs" => [], "spans" => "bad"})
  end

  test "CLI parses and renders Workshop dry-run preview" do
    tmp_path = tmp_dir()
    file = Path.join(tmp_path, "workshop.json")
    File.write!(file, Jason.encode!(@snapshot))

    assert {:ok, parsed} = CLI.parse(["obs", "workshop", file, "--dry-run"])
    assert parsed.command == :obs_workshop
    assert parsed.args == [file]

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(parsed, project_root: tmp_path)
      end)

    assert output =~ "Workshop observability dry-run:"
    assert output =~ "Runs: 1"
    assert output =~ "Spans: 2"
    assert output =~ "Mutation: none"
  end

  test "CLI requires dry-run for Workshop snapshots" do
    tmp_path = tmp_dir()
    file = Path.join(tmp_path, "workshop.json")
    File.write!(file, Jason.encode!(@snapshot))

    assert {:ok, parsed} = CLI.parse(["obs", "workshop", file])

    output =
      capture_io(:stderr, fn ->
        assert 1 == CLI.execute(parsed, project_root: tmp_path)
      end)

    assert output =~ "Workshop observability preview requires --dry-run"
  end
end
