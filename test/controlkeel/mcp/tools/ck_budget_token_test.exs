defmodule ControlKeel.MCP.Tools.CkBudgetTokenTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkBudget

  import ControlKeel.MissionFixtures

  setup do
    tmp = System.tmp_dir!() |> Path.join("ck_budget_token_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "include_token_overhead attaches rules/skills/tools audit to budget response", %{tmp: tmp} do
    session = session_fixture()
    File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 1500))

    assert {:ok, result} =
             CkBudget.call(%{
               "session_id" => session.id,
               "mode" => "status",
               "project_root" => tmp,
               "include_token_overhead" => true
             })

    assert Map.has_key?(result, "token_overhead")
    overhead = result["token_overhead"]
    assert Map.has_key?(overhead, "rules")
    assert Map.has_key?(overhead, "skills")
    assert Map.has_key?(overhead, "tools")

    # rules should show oversized
    assert overhead["rules"]["estimated_tokens"] > 0
    assert is_list(overhead["rules"]["recommendations"])
    assert length(overhead["rules"]["recommendations"]) > 0

    # tools should always have a token estimate
    assert overhead["tools"]["estimated_tokens"] > 0
  end

  test "include_token_overhead is not attached when false", %{tmp: tmp} do
    session = session_fixture()

    assert {:ok, result} =
             CkBudget.call(%{
               "session_id" => session.id,
               "mode" => "status",
               "project_root" => tmp,
               "include_token_overhead" => false
             })

    refute Map.has_key?(result, "token_overhead")
  end

  test "include_token_overhead is not attached when project_root is missing" do
    session = session_fixture()

    assert {:ok, result} =
             CkBudget.call(%{
               "session_id" => session.id,
               "mode" => "status",
               "include_token_overhead" => true
             })

    refute Map.has_key?(result, "token_overhead")
  end
end
