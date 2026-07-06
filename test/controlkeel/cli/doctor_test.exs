defmodule ControlKeel.CLI.DoctorTest do
  use ControlKeel.DataCase

  alias ControlKeel.CLI.Doctor

  setup do
    tmp = Path.join(System.tmp_dir!(), "ck-doctor-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "install_health" do
    test "reports gitignore incomplete and surfaces it in status/lines for a bare repo", %{
      tmp: tmp
    } do
      payload = Doctor.payload(tmp, "9.9.9")

      health = payload["install_health"]
      assert is_map(health)
      assert is_boolean(health["git_available"])
      assert health["gitignore"]["complete"] == false
      assert "/.controlkeel/" in health["gitignore"]["missing"]
      assert health["ok"] == false
      # Top-level status stays "ok" (command ran); health lives in install_health.
      assert payload["status"] == "ok"

      lines = Doctor.lines(payload)
      assert Enum.any?(lines, &(&1 =~ "Install health: attention"))
      assert Enum.any?(lines, &(&1 =~ "gitignore: incomplete"))
    end

    test "reports gitignore complete once the CK managed block is present", %{tmp: tmp} do
      :ok = ControlKeel.Project.Binding.ensure_gitignore(tmp)

      health = Doctor.payload(tmp, "9.9.9")["install_health"]
      assert health["gitignore"]["complete"] == true
      assert health["gitignore"]["missing"] == []
    end

    test "reports skill manifest drift across attached agent destinations", %{tmp: tmp} do
      a = Path.join(tmp, ".a/skills")
      b = Path.join(tmp, ".b/skills")
      File.mkdir_p!(a)
      File.mkdir_p!(b)

      File.write!(
        Path.join(a, ".controlkeel-skills.json"),
        Jason.encode!(%{"skills" => ["one", "two"]})
      )

      File.write!(Path.join(b, ".controlkeel-skills.json"), Jason.encode!(%{"skills" => ["one"]}))

      {:ok, binding, _session, _state} = ControlKeel.Project.Local.load_or_bootstrap(tmp)

      binding =
        binding
        |> ControlKeel.Project.Binding.update_attached_agent("a", %{
          "controlkeel_version" => "9.9.9",
          "skills_destination" => a
        })
        |> ControlKeel.Project.Binding.update_attached_agent("b", %{
          "controlkeel_version" => "9.9.9",
          "skills_destination" => b
        })

      {:ok, _} = ControlKeel.Project.Binding.write_effective(binding, tmp, mode: :project)

      health = Doctor.payload(tmp, "9.9.9")["install_health"]
      assert health["skill_consistency"]["ok"] == false

      assert [%{"skill" => "two", "direction" => "missing"} | _] =
               health["skill_consistency"]["drifted"]
    end
  end
end
