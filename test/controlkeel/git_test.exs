defmodule ControlKeel.GitTest do
  # async: false — these tests mutate the global :git_executable app env to
  # simulate a host without git, so they must not overlap other tests.
  use ExUnit.Case, async: false

  alias ControlKeel.Git
  alias ControlKeel.Project.WorkspaceContext

  setup do
    original = Application.get_env(:controlkeel, :git_executable)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:controlkeel, :git_executable)
        value -> Application.put_env(:controlkeel, :git_executable, value)
      end
    end)

    :ok
  end

  describe "with git present" do
    test "available?/0 is true and cmd/2 runs git" do
      assert Git.available?()
      assert {output, 0} = Git.cmd(["--version"])
      assert output =~ "git version"
    end
  end

  describe "with git absent" do
    setup do
      Application.put_env(:controlkeel, :git_executable, "ck-nonexistent-git-binary")
      :ok
    end

    test "available?/0 is false" do
      refute Git.available?()
    end

    test "cmd/2 degrades to a non-zero exit instead of raising" do
      assert {message, 127} = Git.cmd(["rev-parse", "HEAD"])
      assert is_binary(message)
    end

    test "WorkspaceContext.build/1 degrades gracefully when git is missing" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "ck-git-absent-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # A fresh-install / attach user with no git must not crash ck_context.
      context = WorkspaceContext.build(tmp_dir)
      assert context["available"] == false
      assert is_binary(context["summary_text"])
    end
  end
end
