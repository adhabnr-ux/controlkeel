defmodule ControlKeel.GitWorkflowTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.GitWorkflow

  import ControlKeel.MissionFixtures

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-git-workflow-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)

    File.write!(Path.join(tmp_dir, "README.md"), "# Initial\n")
    assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  describe "status/2" do
    test "returns branch, head_sha, and status for a clean repo", %{tmp_dir: tmp_dir} do
      assert {:ok, result} = GitWorkflow.status(tmp_dir)
      assert is_binary(result["branch"])
      assert is_binary(result["head_sha"])
      assert result["status"]["total"] == 0
    end

    test "detects untracked files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "new_file.txt"), "hello")
      assert {:ok, result} = GitWorkflow.status(tmp_dir)
      assert result["status"]["untracked"] >= 1
    end

    test "correlates findings when session_id is provided", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})

      _finding =
        finding_fixture(%{
          session: session,
          status: "blocked",
          rule_id: "security.test_issue",
          title: "Test finding",
          plain_message: "Blocked finding for test",
          metadata: %{"task_id" => task.id}
        })

      assert {:ok, result} = GitWorkflow.status(tmp_dir, session_id: session.id)
      assert result["findings_correlation"]["available"] == true
      assert result["findings_correlation"]["blocked_count"] >= 1
    end
  end

  describe "diff/4" do
    test "returns diff between two refs", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "feature.txt"), "new feature\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      assert {_, 0} = System.cmd("git", ["commit", "-m", "add feature"], cd: tmp_dir)

      assert {:ok, result} = GitWorkflow.diff(tmp_dir, "HEAD~1", "HEAD")
      assert is_binary(result["diff"])
      assert result["files_changed"] >= 1
      assert is_map(result["validation"])
    end
  end

  describe "commit/3" do
    test "commits when there are staged changes and no blocked findings", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "commit_test.txt"), "content\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)

      assert {:ok, result} = GitWorkflow.commit(tmp_dir, "test commit")
      assert result["message"] == "Commit successful"
      assert is_binary(result["head_sha"])
    end

    test "blocks commit when session has blocked findings", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "blocked_test.txt"), "content\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)

      session = session_fixture()
      task = task_fixture(%{session: session, status: "in_progress"})

      _finding =
        finding_fixture(%{
          session: session,
          status: "blocked",
          severity: "critical",
          rule_id: "security.critical_block",
          title: "Critical blocked finding",
          plain_message: "Must not commit",
          metadata: %{"task_id" => task.id}
        })

      assert {:error, {:blocked_findings, message}} =
               GitWorkflow.commit(tmp_dir, "should fail", session_id: session.id)

      assert message =~ "blocked"
    end

    test "rejects empty commit messages", %{tmp_dir: tmp_dir} do
      assert {:error, _} = GitWorkflow.commit(tmp_dir, "")
    end
  end
end
