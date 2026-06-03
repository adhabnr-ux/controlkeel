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
end
