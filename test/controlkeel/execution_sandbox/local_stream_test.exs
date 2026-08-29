defmodule ControlKeel.ExecutionSandbox.LocalStreamTest do
  # Port-based streaming, timeout, kill-on-result, and heartbeat — the
  # liveness disciplines headless agent-CLI sub-workers need (Antigravity
  # Bridge-style idle-wait protection).
  use ExUnit.Case, async: true

  alias ControlKeel.ExecutionSandbox.Local

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "ck-local-stream-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp sh_script(body) do
    dir = tmp_dir()
    script = Path.join(dir, "run.sh")
    File.write!(script, "#!/bin/sh\n" <> body)
    File.chmod!(script, 0o755)
    script
  end

  test "runs to natural completion and captures output" do
    script = sh_script("echo hello-from-child")

    assert {:ok, run} = Local.run(script, [], timeout_ms: 5_000)
    assert run.exit_status == 0
    assert run.output =~ "hello-from-child"
    refute run[:timed_out]
    refute run[:killed_on_result]
  end

  test "captures non-zero exit status" do
    script = sh_script("echo boom >&2; exit 3")

    assert {:ok, run} = Local.run(script, [], timeout_ms: 5_000)
    assert run.exit_status == 3
    assert run.output =~ "boom"
  end

  test "kill-on-result: terminates an idle child once the result file appears" do
    dir = tmp_dir()
    result_path = Path.join(dir, "result.json")

    script =
      sh_script(
        "echo working; sleep 1; echo '{\"done\":true}' > " <> result_path <> "; sleep 300"
      )

    started = System.monotonic_time(:millisecond)

    assert {:ok, run} =
             Local.run(script, [], timeout_ms: 30_000, result_path: result_path)

    elapsed = System.monotonic_time(:millisecond) - started

    # Result delivered then child idled: killed within the grace window, well
    # before the 300s sleep (and the 30s deadline).
    assert run[:killed_on_result] == true
    assert run.exit_status == 0
    assert run.output =~ "idle-wait guard"
    assert File.exists?(result_path)
    assert elapsed < 15_000
    refute run[:timed_out]
  end

  test "hard deadline: reports exit 124 when no result is ever delivered" do
    script = sh_script("echo spinning; sleep 60")

    assert {:ok, run} = Local.run(script, [], timeout_ms: 1_500)

    assert run[:timed_out] == true
    assert run.exit_status == 124
    assert run.output =~ "spinning"
    assert run.output =~ "terminated on deadline"
  end

  test "heartbeat file is written and kept fresh during execution" do
    dir = tmp_dir()
    heartbeat = Path.join(dir, "progress.json")
    # Emit output for a while so the heartbeat gets touched repeatedly.
    script = sh_script("for i in 1 2 3 4 5; do echo tick-$i; sleep 0.15; done")

    assert {:ok, run} = Local.run(script, [], timeout_ms: 10_000, heartbeat_path: heartbeat)
    assert run.exit_status == 0

    assert File.exists?(heartbeat)
    {:ok, payload} = Jason.decode(File.read!(heartbeat))
    assert is_binary(payload["ts"])
  end

  test "returns command_not_found for a missing executable" do
    assert {:error, {:command_not_found, "definitely-not-a-real-cmd-xyz"}} =
             Local.run("definitely-not-a-real-cmd-xyz", [], timeout_ms: 1_000)
  end

  test "cwd option is honored" do
    dir = tmp_dir()
    script = sh_script("pwd")

    assert {:ok, run} = Local.run(script, [], cwd: dir, timeout_ms: 5_000)
    assert run.exit_status == 0
    assert run.output =~ Path.basename(dir)
  end
end
