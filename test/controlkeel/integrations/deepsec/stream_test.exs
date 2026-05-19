defmodule ControlKeel.Integrations.Deepsec.StreamTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Integrations.Deepsec.Stream

  test "stream_scan emits findings produced by a fast completing scan" do
    start_supervised!(Stream)

    parent = self()

    scan_fun = fn [workspace_path: _workspace_path] ->
      {:ok, Jason.encode!(%{"findings" => [%{"id" => "finding-1", "severity" => "HIGH"}]})}
    end

    Stream.stream_scan(
      fn finding -> send(parent, {:streamed_finding, finding}) end,
      System.tmp_dir!(),
      scan_fun: scan_fun
    )

    assert_receive {:streamed_finding, %{"id" => "finding-1", "severity" => "HIGH"}}
  end
end
