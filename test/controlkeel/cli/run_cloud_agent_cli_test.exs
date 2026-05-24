defmodule ControlKeel.CLI.RunCloudAgentTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.CLI
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.MissionFixtures

  setup do
    workspace = MissionFixtures.workspace_fixture()
    session = MissionFixtures.session_fixture(%{workspace: workspace})
    task = MissionFixtures.task_fixture(%{session: session, title: "Add cloud feature"})
    {:ok, workspace: workspace, session: session, task: task}
  end

  describe "controlkeel run cloud-agent <task-id>" do
    test "creates a run package, prints token and metadata", %{task: task, workspace: workspace} do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: %{
                     runtime: "devin",
                     budget_cents: 500,
                     scopes: "mcp:access,context:read",
                     note: "investigate flaky test"
                   },
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Cloud run package created"))
      assert Enum.any?(lines, &(&1 =~ "Runtime: devin"))
      assert Enum.any?(lines, &(&1 =~ "Budget allocated (cents): 500"))
      assert Enum.any?(lines, &(&1 =~ "Scopes: mcp:access,context:read"))
      assert Enum.any?(lines, &String.contains?(&1, "Callback token"))

      [package] = RuntimeContext.list_for_workspace(workspace.id)
      assert package.task_id == task.id
      assert package.runtime_target == "devin"
      assert package.status == "pending"
      assert package.payload["task_title"] == "Add cloud feature"
      assert package.payload["note"] == "investigate flaky test"
    end

    test "rejects unknown runtime with helpful message", %{task: task} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: %{runtime: "not-a-real-runtime", budget_cents: 0},
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert msg =~ "Unknown runtime"
      assert msg =~ "devin"
    end

    test "requires --runtime", %{task: task} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: %{budget_cents: 100},
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert msg =~ "runtime"
    end

    test "rejects negative budget", %{task: task} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: %{runtime: "open-swe", budget_cents: -10},
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert msg =~ "non-negative integer"
    end

    test "rejects non-numeric task id", %{} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: %{runtime: "devin", budget_cents: 0},
                   args: ["not-a-number"]
                 },
                 File.cwd!()
               )

      assert msg =~ "Invalid task-id"
    end

    test "returns 'Task not found' for unknown id", %{} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: %{runtime: "devin", budget_cents: 0},
                   args: ["999999"]
                 },
                 File.cwd!()
               )

      assert msg =~ "Task not found"
    end
  end

  describe "CLI.parse/1" do
    test "parses run cloud-agent invocation" do
      assert {:ok, parsed} =
               CLI.parse([
                 "run",
                 "cloud-agent",
                 "42",
                 "--runtime",
                 "devin",
                 "--budget-cents",
                 "200"
               ])

      assert parsed.command == :run_cloud_agent
      assert parsed.args == ["42"]
      assert parsed.options[:runtime] == "devin"
      assert parsed.options[:budget_cents] == 200
    end
  end
end
