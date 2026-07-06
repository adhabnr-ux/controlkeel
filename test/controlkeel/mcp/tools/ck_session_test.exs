defmodule ControlKeel.MCP.Tools.CkSessionTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkSession
  alias ControlKeel.Mission
  alias ControlKeel.Project.Binding

  import ControlKeel.MissionFixtures

  describe "list mode" do
    test "returns sessions" do
      _session_a = session_fixture(%{title: "Session A"})
      _session_b = session_fixture(%{title: "Session B"})

      assert {:ok, result} = CkSession.call(%{"mode" => "list"})

      assert result["total"] >= 2
      assert length(result["sessions"]) >= 2
    end

    test "respects limit" do
      for _i <- 1..5, do: session_fixture()

      assert {:ok, result} = CkSession.call(%{"mode" => "list", "limit" => 2})
      assert length(result["sessions"]) == 2
      assert result["total"] == 2
    end

    test "returns session fields" do
      session = session_fixture(%{title: "Detailed Session"})

      assert {:ok, result} = CkSession.call(%{"mode" => "list"})
      found = Enum.find(result["sessions"], &(&1["id"] == session.id))
      assert found["title"] == "Detailed Session"
      assert found["risk_tier"]
      assert found["workspace_id"]
    end
  end

  describe "status mode" do
    test "returns session details by session_id" do
      session = session_fixture(%{title: "Status Session"})

      assert {:ok, result} =
               CkSession.call(%{"session_id" => session.id, "mode" => "status"})

      assert result["id"] == session.id
      assert result["title"] == "Status Session"
      assert result["risk_tier"]
    end

    test "resolves session from project binding when session_id omitted" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "ck-session-status-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session = session_fixture()

      assert {:ok, _updated} =
               Mission.attach_session_runtime_context(session.id, %{"project_root" => tmp_dir})

      assert {:ok, _binding} =
               Binding.write(
                 %{
                   "workspace_id" => session.workspace_id,
                   "session_id" => session.id,
                   "agent" => "opencode"
                 },
                 tmp_dir
               )

      assert {:ok, result} = CkSession.call(%{"mode" => "status", "project_root" => tmp_dir})
      assert result["id"] == session.id
    end

    test "returns error for non-existent session" do
      assert {:error, {:invalid_arguments, message}} =
               CkSession.call(%{"session_id" => 999_999, "mode" => "status"})

      assert message =~ "not found"
    end

    test "returns error when no binding and no session_id" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "ck-session-status-nobinding-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      assert {:error, {:invalid_arguments, message}} =
               CkSession.call(%{"mode" => "status", "project_root" => tmp_dir})

      assert message =~ "session_id" or message =~ "active session"
    end
  end

  describe "switch mode" do
    test "returns error when confirm is not true" do
      assert {:error, {:invalid_arguments, message}} =
               CkSession.call(%{
                 "session_id" => 1,
                 "mode" => "switch",
                 "confirm" => false
               })

      assert message =~ "confirm"
    end

    test "returns error when confirm is omitted" do
      assert {:error, {:invalid_arguments, message}} =
               CkSession.call(%{"session_id" => 1, "mode" => "switch"})

      assert message =~ "confirm"
    end

    test "switches active session when confirm is true" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "ck-session-switch-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session_a = session_fixture(%{title: "Original Session"})
      session_b = session_fixture(%{title: "Target Session"})

      assert {:ok, _updated} =
               Mission.attach_session_runtime_context(session_a.id, %{"project_root" => tmp_dir})

      assert {:ok, _binding} =
               Binding.write(
                 %{
                   "workspace_id" => session_a.workspace_id,
                   "session_id" => session_a.id,
                   "agent" => "opencode"
                 },
                 tmp_dir
               )

      assert {:ok, result} =
               CkSession.call(%{
                 "session_id" => session_b.id,
                 "mode" => "switch",
                 "confirm" => true,
                 "project_root" => tmp_dir
               })

      assert result["switched"] == true
      assert result["session_id"] == session_b.id
      assert result["title"] == "Target Session"
    end

    test "returns error for non-existent target session" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "ck-session-switch-missing-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session = session_fixture()

      assert {:ok, _binding} =
               Binding.write(
                 %{
                   "workspace_id" => session.workspace_id,
                   "session_id" => session.id,
                   "agent" => "opencode"
                 },
                 tmp_dir
               )

      assert {:error, {:invalid_arguments, message}} =
               CkSession.call(%{
                 "session_id" => 999_999,
                 "mode" => "switch",
                 "confirm" => true,
                 "project_root" => tmp_dir
               })

      assert message =~ "not found"
    end

    test "returns error when no local project binding" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "ck-session-switch-nobinding-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      session = session_fixture()

      assert {:error, {:invalid_arguments, message}} =
               CkSession.call(%{
                 "session_id" => session.id,
                 "mode" => "switch",
                 "confirm" => true,
                 "project_root" => tmp_dir
               })

      assert message =~ "binding"
    end
  end

  describe "validation" do
    test "returns error for invalid mode" do
      assert {:error, {:invalid_arguments, message}} =
               CkSession.call(%{"mode" => "invalid"})

      assert message =~ "mode"
    end

    test "returns error when arguments are not a map" do
      assert {:error, {:invalid_arguments, _message}} = CkSession.call("not a map")
    end
  end
end
