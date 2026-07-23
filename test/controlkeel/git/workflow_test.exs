defmodule ControlKeel.Git.WorkflowTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Git.Workflow
  alias ControlKeel.MCP.Tools.CkGitDiff
  alias ControlKeel.Repo

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
      assert {:ok, result} = Workflow.status(tmp_dir)
      assert is_binary(result["branch"])
      assert is_binary(result["head_sha"])
      assert result["status"]["total"] == 0
    end

    test "detects untracked files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "new_file.txt"), "hello")
      assert {:ok, result} = Workflow.status(tmp_dir)
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

      assert {:ok, result} = Workflow.status(tmp_dir, session_id: session.id)
      assert result["findings_correlation"]["available"] == true
      assert result["findings_correlation"]["blocked_count"] >= 1
    end
  end

  describe "diff/4" do
    test "returns diff between two refs", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "feature.txt"), "new feature\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      assert {_, 0} = System.cmd("git", ["commit", "-m", "add feature"], cd: tmp_dir)

      assert {:ok, result} = Workflow.diff(tmp_dir, "HEAD~1", "HEAD")
      assert is_binary(result["diff"])
      assert result["files_changed"] >= 1
      assert is_map(result["validation"])
    end

    test "ck_git_diff treats empty refs as omitted working tree diff", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "README.md"), "# Initial\nchanged\n")

      assert {:ok, result} =
               CkGitDiff.call(%{
                 "project_root" => tmp_dir,
                 "base_ref" => "",
                 "head_ref" => ""
               })

      assert result["base_ref"] == nil
      assert result["head_ref"] == nil
      assert result["diff"] =~ "changed"
      assert result["files_changed"] >= 1
    end
  end

  describe "commit/3" do
    test "commits when there are staged changes and no blocked findings", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "commit_test.txt"), "content\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)

      assert {:ok, result} = Workflow.commit(tmp_dir, "test commit")
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
               Workflow.commit(tmp_dir, "should fail", session_id: session.id)

      # The error is self-describing: it surfaces the actual blocking finding so
      # the operator can see what to dismiss, not just a bare count.
      assert message =~ "blocked"
      assert message =~ "security.critical_block"
      assert message =~ "Critical blocked finding"
      assert message =~ "controlkeel approve"
    end

    test "commit-gate error lists each blocking finding with id, rule, severity, and age",
         %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "x.txt"), "x\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)

      session = session_fixture()

      f1 =
        finding_fixture(%{
          session: session,
          status: "blocked",
          severity: "high",
          rule_id: "secret.high_entropy_token",
          title: "High entropy token"
        })

      f2 =
        finding_fixture(%{
          session: session,
          status: "blocked",
          severity: "high",
          rule_id: "secret.high_entropy_token",
          title: "High entropy token"
        })

      assert {:error, {:blocked_findings, message}} =
               Workflow.commit(tmp_dir, "blocked by two", session_id: session.id)

      assert message =~ "##{f1.id} "
      assert message =~ "##{f2.id} "
      # An age label is appended (today / N days old / >N months old).
      assert message =~ ~r/\((today|\d+ days? old|>\d+ months old)\)/
    end

    test "rejects empty commit messages", %{tmp_dir: tmp_dir} do
      assert {:error, _} = Workflow.commit(tmp_dir, "")
    end
  end

  describe "commit/3 stale-finding dormancy" do
    setup do
      prev = Application.get_env(:controlkeel, :commit_gate, [])
      on_exit(fn -> Application.put_env(:controlkeel, :commit_gate, prev) end)
      :ok
    end

    setup context do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-gate-dormancy-#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)
      assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
      assert {_, 0} = System.cmd("git", ["config", "user.email", "t@e.com"], cd: tmp_dir)
      assert {_, 0} = System.cmd("git", ["config", "user.name", "T"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "a.txt"), "a\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      assert {_, 0} = System.cmd("git", ["commit", "-m", "init"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "b.txt"), "b\n")
      assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      Map.merge(context, %{tmp_dir: tmp_dir})
    end

    @tag stale_days: 30
    test "a stale blocked finding does NOT gate the commit", %{tmp_dir: tmp_dir} do
      Application.put_env(:controlkeel, :commit_gate, stale_block_days: 30)

      session = session_fixture()

      finding =
        finding_fixture(%{
          session: session,
          status: "blocked",
          severity: "high",
          rule_id: "secret.old_token",
          title: "Old token"
        })

      # Backdate the finding so it is older than the 30-day threshold.
      backdate(finding, 45)

      assert {:ok, _result} =
               Workflow.commit(tmp_dir, "stale does not block", session_id: session.id)
    end

    @tag stale_days: 30
    test "a fresh blocked finding still gates the commit under a dormancy threshold", %{
      tmp_dir: tmp_dir
    } do
      Application.put_env(:controlkeel, :commit_gate, stale_block_days: 30)

      session = session_fixture()

      finding_fixture(%{
        session: session,
        status: "blocked",
        severity: "high",
        rule_id: "secret.fresh_token",
        title: "Fresh token"
      })

      # Leave inserted_at as today (fresh).
      assert {:error, {:blocked_findings, message}} =
               Workflow.commit(tmp_dir, "fresh blocks", session_id: session.id)

      assert message =~ "secret.fresh_token"
    end

    test "stale_block_days 0 disables dormancy — stale findings still block", %{tmp_dir: tmp_dir} do
      Application.put_env(:controlkeel, :commit_gate, stale_block_days: 0)

      session = session_fixture()

      finding =
        finding_fixture(%{
          session: session,
          status: "blocked",
          severity: "high",
          rule_id: "secret.disabled_dormancy",
          title: "Old but blocking"
        })

      backdate(finding, 200)

      assert {:error, {:blocked_findings, message}} =
               Workflow.commit(tmp_dir, "0 disables dormancy", session_id: session.id)

      assert message =~ "secret.disabled_dormancy"
    end

    test "when fresh blockers exist, stale findings appear as dormant in the error", %{
      tmp_dir: tmp_dir
    } do
      Application.put_env(:controlkeel, :commit_gate, stale_block_days: 30)

      session = session_fixture()

      fresh =
        finding_fixture(%{
          session: session,
          status: "blocked",
          severity: "high",
          rule_id: "secret.fresh",
          title: "Fresh"
        })

      stale =
        finding_fixture(%{
          session: session,
          status: "blocked",
          severity: "high",
          rule_id: "secret.stale",
          title: "Stale"
        })

      backdate(stale, 60)

      assert {:error, {:blocked_findings, message}} =
               Workflow.commit(tmp_dir, "mixed", session_id: session.id)

      # Fresh finding is the blocker; stale is listed as dormant (not blocking).
      assert message =~ "##{fresh.id} "
      assert message =~ "Dormant"
      assert message =~ "##{stale.id} "
    end
  end

  defp backdate(finding, days_ago) do
    ago = DateTime.utc_now() |> DateTime.add(-days_ago * 24 * 3600, :second)

    Repo.update_all(
      from(f in ControlKeel.Mission.Finding, where: f.id == ^finding.id),
      set: [inserted_at: ago, updated_at: ago]
    )
  end
end
