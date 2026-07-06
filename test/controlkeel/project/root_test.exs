defmodule ControlKeel.Project.RootTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Project.Root

  test "resolve walks up to the nearest project marker" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-project-root-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "lib/trial"))
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert Root.resolve(Path.join(tmp_dir, "lib/trial")) == Root.resolve(tmp_dir)
  end

  test "resolve falls back to the provided directory when no marker exists" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-project-root-none-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert Root.resolve(tmp_dir) == Root.resolve(Path.expand(tmp_dir))
  end

  test "project_root? reflects whether the resolved directory has a project marker" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-project-root-flag-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "lib/trial"))
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert Root.project_root?(Path.join(tmp_dir, "lib/trial"))

    other_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-project-root-flag-other-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(other_dir)
    File.mkdir_p!(other_dir)
    on_exit(fn -> File.rm_rf!(other_dir) end)

    refute Root.project_root?(other_dir)
  end
end
