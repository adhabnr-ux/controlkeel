defmodule ControlKeel.Scanner.ReliabilityTest do
  # async: false — these tests mutate the global :matcher_system app env and the
  # named Validation.Matchers.Registry Agent, so they must run in isolation.
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Scanner.FastPath
  alias ControlKeel.Validation.Matchers.Registry

  defp stop_registry do
    case Process.whereis(Registry) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end
  end

  describe "matcher Registry crash-safety" do
    setup do
      stop_registry()
      on_exit(&stop_registry/0)
      :ok
    end

    test "for_file returns [] when the Registry is not started (catches :exit, does not crash)" do
      assert Registry.for_file("lib/app.ex") == []
    end

    test "for_file returns matchers when the Registry is started" do
      {:ok, _} = Registry.start_link()
      :ok = Registry.load_built_ins()

      matchers = Registry.for_file("lib/app.ex")
      assert is_list(matchers)
      assert matchers != []
    end
  end

  describe "scanner stays available under matcher misconfiguration" do
    setup do
      stop_registry()
      Application.put_env(:controlkeel, :matcher_system, enabled: true)

      on_exit(fn ->
        Application.delete_env(:controlkeel, :matcher_system)
        stop_registry()
      end)

      :ok
    end

    test "enabling matcher_system without a running Registry does not crash the scan" do
      result =
        FastPath.scan(%{
          "content" => "const apiKey = \"abc\";\nconsole.log(apiKey)\n",
          "path" => "lib/app.js"
        })

      assert is_list(result.findings)
    end
  end

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
