defmodule ControlKeel.MCP.Tools.CkTaskTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkTask
  alias ControlKeel.Platform

  import ControlKeel.MissionFixtures

  describe "status mode" do
    test "returns task details for a valid task in the session" do
      session = session_fixture()
      task = task_fixture(%{session: session})

      assert {:ok, result} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "status"
               })

      assert result["task_id"] == task.id
      assert result["title"] == task.title
      assert result["status"] == "queued"
      assert result["session_id"] == session.id
      assert result["position"]
    end

    test "returns error when task_id is missing" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "mode" => "status"})

      assert message =~ "task_id"
    end

    test "returns error when task does not exist" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => 999_999,
                 "mode" => "status"
               })

      assert message =~ "not found"
    end

    test "returns error when task belongs to a different session" do
      session_a = session_fixture()
      session_b = session_fixture()
      task = task_fixture(%{session: session_a})

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{
                 "session_id" => session_b.id,
                 "task_id" => task.id,
                 "mode" => "status"
               })

      assert message =~ "current session"
    end
  end

  describe "claim mode" do
    test "claims an available task" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "ready"})

      assert {:ok, result} =
               CkTask.call(%{"session_id" => session.id, "task_id" => task.id, "mode" => "claim"})

      assert result["claimed"] == true
      assert result["task_id"] == task.id
      assert result["status"] == "in_progress"
      assert result["run_id"]
    end

    test "returns error for already completed task" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "done"})

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "task_id" => task.id, "mode" => "claim"})

      assert message =~ "claimable"
    end

    test "returns error when task_id is missing" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "mode" => "claim"})

      assert message =~ "task_id"
    end
  end

  describe "complete mode" do
    test "completes a task" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})

      assert {:ok, result} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "complete"
               })

      assert result["completed"] == true
      assert result["task_id"] == task.id
      assert result["status"] == "done"
    end

    test "returns error when task has unresolved findings" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})
      finding_fixture(%{session: session, task_id: task.id, status: "blocked"})

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "complete"
               })

      assert message =~ "unresolved findings"
    end

    test "returns error when task_id is missing" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "mode" => "complete"})

      assert message =~ "task_id"
    end
  end

  describe "heartbeat mode" do
    test "records a heartbeat for a claimed task" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})
      assert {:ok, _run} = Platform.claim_task(task.id)

      assert {:ok, result} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "heartbeat",
                 "progress" => "50%",
                 "note" => "working on it"
               })

      assert result["recorded"] == true
      assert result["task_id"] == task.id
      assert result["run_id"]
    end

    test "returns error when task has not been claimed" do
      session = session_fixture()
      task = task_fixture(%{session: session})

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "heartbeat"
               })

      assert message =~ "not found"
    end

    test "returns error when task_id is missing" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "mode" => "heartbeat"})

      assert message =~ "task_id"
    end
  end

  describe "checks mode" do
    test "records check results for a claimed task" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})
      assert {:ok, _run} = Platform.claim_task(task.id)

      checks = [
        %{
          "check_type" => "validation",
          "status" => "passed",
          "summary" => "All good",
          "payload" => %{"stdout" => "validation passed"},
          "metadata" => %{"command" => "mix test test/example_test.exs", "exit_code" => 0}
        }
      ]

      assert {:ok, result} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "checks",
                 "checks" => checks
               })

      assert result["recorded"] == true
      assert result["count"] == 1
      [check] = result["results"]
      assert check["proof_strength"] == "command_output"
      assert check["proof"]["command"] == "mix test test/example_test.exs"
      assert check["proof"]["exit_code"] == 0
      assert is_binary(check["proof"]["output_sha256"])
    end

    test "records git head sha and dirty state when project_root provided" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})
      assert {:ok, _run} = Platform.claim_task(task.id)

      project_root = File.cwd!()

      checks = [
        %{
          "check_type" => "validation",
          "status" => "passed",
          "summary" => "All good",
          "payload" => %{"stdout" => "validation passed"},
          "metadata" => %{"command" => "mix test", "exit_code" => 0}
        }
      ]

      assert {:ok, result} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "checks",
                 "checks" => checks,
                 "project_root" => project_root
               })

      assert result["recorded"] == true
      [check] = result["results"]
      assert is_binary(check["proof"]["git_head_sha"])
      assert check["proof"]["git_head_sha"] =~ ~r/^[0-9a-f]{40}$/
      assert is_boolean(check["proof"]["working_tree_dirty"])
    end

    test "returns error when checks is missing" do
      session = session_fixture()
      task = task_fixture(%{session: session})

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "checks"
               })

      assert message =~ "checks"
    end

    test "returns error when checks is not an array" do
      session = session_fixture()
      task = task_fixture(%{session: session})

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "checks",
                 "checks" => "not an array"
               })

      assert message =~ "array"
    end

    test "returns error when task_id is missing" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "mode" => "checks", "checks" => []})

      assert message =~ "task_id"
    end
  end

  describe "report mode" do
    test "submits a task report" do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})
      assert {:ok, _run} = Platform.claim_task(task.id)

      assert {:ok, result} =
               CkTask.call(%{
                 "session_id" => session.id,
                 "task_id" => task.id,
                 "mode" => "report",
                 "status" => "done",
                 "output" => %{"files_changed" => 3},
                 "metadata" => %{"agent" => "test"}
               })

      assert result["reported"] == true
      assert result["task_id"] == task.id
      assert result["status"] == "done"
    end

    test "returns error when task_id is missing" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "mode" => "report"})

      assert message =~ "task_id"
    end
  end

  describe "validation" do
    test "returns error for invalid mode" do
      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkTask.call(%{"session_id" => session.id, "mode" => "invalid"})

      assert message =~ "mode"
    end

    test "returns error when arguments are not a map" do
      assert {:error, {:invalid_arguments, _message}} = CkTask.call("not a map")
    end
  end
end
