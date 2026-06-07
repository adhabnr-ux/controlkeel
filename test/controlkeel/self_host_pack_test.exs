defmodule ControlKeel.SelfHostPackTest do
  use ExUnit.Case, async: false

  alias ControlKeel.SelfHost

  setup do
    tmp = Path.join(System.tmp_dir!(), "ck-pack-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "pack/2" do
    test "returns error when release artifact is missing", %{tmp: tmp} do
      assert {:error, msg} = SelfHost.pack(tmp)
      assert msg =~ "Release artifact not found"
    end

    test "creates a tar.gz and returns path + sha256", %{tmp: tmp} do
      release_dir = Path.join([tmp, "_build", "prod", "rel", "controlkeel"])
      File.mkdir_p!(release_dir)
      File.write!(Path.join(release_dir, "start.sh"), "#!/bin/sh\necho ok\n")

      migrations_dir = Path.join(tmp, "priv/repo/migrations")
      File.mkdir_p!(migrations_dir)
      File.write!(Path.join(migrations_dir, "001.exs"), "# migration")

      install_md = Path.join(tmp, "INSTALL.md")
      File.write!(install_md, "# Install")

      output = Path.join(tmp, "bundle.tar.gz")
      assert {:ok, result} = SelfHost.pack(tmp, output: output)

      assert result.path == output
      assert File.exists?(output)
      assert is_binary(result.sha256)
      assert byte_size(result.sha256) == 64
    end

    test "sha256 is stable for the same content", %{tmp: tmp} do
      release_dir = Path.join([tmp, "_build", "prod", "rel", "controlkeel"])
      File.mkdir_p!(release_dir)
      File.write!(Path.join(release_dir, "app"), "content")

      output1 = Path.join(tmp, "bundle1.tar.gz")
      output2 = Path.join(tmp, "bundle2.tar.gz")

      {:ok, r1} = SelfHost.pack(tmp, output: output1)
      {:ok, r2} = SelfHost.pack(tmp, output: output2)

      assert r1.sha256 == r2.sha256
    end
  end

  describe "CLI: selfhost pack" do
    test "errors with helpful message when release is missing" do
      tmp = Path.join(System.tmp_dir!(), "ck-cli-pack-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:error, msg} =
               ControlKeel.CLI.run_command(
                 %{command: :selfhost_pack, options: %{}, args: []},
                 tmp
               )

      assert msg =~ "Release artifact not found"
    end
  end
end
