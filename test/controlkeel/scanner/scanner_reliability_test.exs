defmodule ControlKeel.Scanner.ReliabilityTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Scanner.FastPath

  describe "PackLoader resilience to a malformed pack" do
    test "load_from_path reports an error for a malformed pack (so load_all_packs can skip it)" do
      path =
        Path.join(System.tmp_dir!(), "ck-bad-pack-#{System.unique_integer([:positive])}.json")

      File.write!(path, "{ this is not valid json")
      on_exit(fn -> File.rm(path) end)

      assert {:error, _reason} = PackLoader.load_from_path(path)
    end

    test "core packs still load (regression)" do
      assert {:ok, baseline} = PackLoader.load("baseline")
      assert is_list(baseline) and baseline != []
      assert {:ok, cost} = PackLoader.load("cost")
      assert is_list(cost)
    end
  end

  describe "scoped ai_tools policy enforcement" do
    setup do
      previous = Application.get_env(:controlkeel, :enforce_ai_tools_policy)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:controlkeel, :enforce_ai_tools_policy)
        else
          Application.put_env(:controlkeel, :enforce_ai_tools_policy, previous)
        end
      end)

      :ok
    end

    test "does not globally enforce ai_tools block rules on unrelated paths" do
      result =
        FastPath.scan(%{
          "content" => ~s({"allowed_commands": "*"}),
          "path" => "config/app.json",
          "kind" => "config"
        })

      refute Enum.any?(result.findings, &(&1.rule_id == "security.ai_agent_tool_escalation"))
    end

    test "enforces ai_tools for AI tool config paths" do
      result =
        FastPath.scan(%{
          "content" => ~s({"allowed_commands": "*"}),
          "path" => ".cursor/settings.json",
          "kind" => "config"
        })

      assert Enum.any?(result.findings, &(&1.rule_id == "security.ai_agent_tool_escalation"))
    end

    test "enforces ai_tools when explicitly requested" do
      result =
        FastPath.scan(%{
          "content" => ~s({"allowed_commands": "*"}),
          "path" => "config/app.json",
          "kind" => "config",
          "policy_packs" => ["ai_tools"]
        })

      assert Enum.any?(result.findings, &(&1.rule_id == "security.ai_agent_tool_escalation"))
    end
  end
end
