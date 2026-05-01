defmodule ControlKeel.WorktreeContextTest do
  use ExUnit.Case, async: true

  alias ControlKeel.WorkspaceContext

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-worktree-context-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  defp realpath(path) do
    path
    |> Path.expand()
    |> String.replace_prefix("/private", "")
  end

  test "build/1 includes git worktree information", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "README.md"), "# Demo\n")

    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    wt_dir =
      Path.join(Path.dirname(tmp_dir), "controlkeel-wt-#{System.unique_integer([:positive])}")

    File.rm_rf!(wt_dir)
    on_exit(fn -> File.rm_rf!(wt_dir) end)

    assert {_, 0} = System.cmd("git", ["worktree", "add", wt_dir, "-b", "feature"], cd: tmp_dir)

    context = WorkspaceContext.build(tmp_dir)

    assert context["available"] == true
    assert is_list(get_in(context, ["git", "worktrees"]))
    assert length(get_in(context, ["git", "worktrees"])) >= 2

    current = get_in(context, ["git", "current_worktree"]) || %{}
    assert realpath(current["path"]) == realpath(tmp_dir)

    assert Enum.any?(get_in(context, ["git", "worktrees"]), fn wt ->
             realpath(wt["path"]) == realpath(wt_dir) and wt["branch"] == "feature"
           end)
  end
end
