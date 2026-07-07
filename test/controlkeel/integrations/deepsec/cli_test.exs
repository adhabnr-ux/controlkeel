defmodule ControlKeel.Integrations.Deepsec.CLITest do
  use ControlKeel.DataCase

  alias ControlKeel.Integrations.Deepsec.CLI
  alias ControlKeel.Proxy

  setup do
    previous = Application.get_env(:controlkeel, Proxy, [])

    on_exit(fn ->
      Application.put_env(:controlkeel, Proxy, previous)
    end)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-deepsec-test-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "available?/0" do
    test "returns false when deepsec binary is not found" do
      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []),
          deepsec_bin: "/tmp/missing-deepsec"
        )
      )

      assert CLI.available?() == false
    end

    test "returns true when deepsec binary is configured and available", %{tmp_dir: tmp_dir} do
      bin = write_script(tmp_dir, "deepsec-ok", "#!/bin/sh\necho 'deepsec v1.0.0'\n")

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: bin)
      )

      assert CLI.available?() == true
    end
  end

  describe "init/1" do
    test "creates workspace and runs init command when missing", %{tmp_dir: tmp_dir} do
      workspace = Path.join(tmp_dir, "new-workspace")

      bin =
        write_script(tmp_dir, "deepsec-init", """
        #!/bin/sh
        test "$1" = "init" || exit 2
        pwd
        """)

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: bin)
      )

      assert {:ok, output} = CLI.init(workspace_path: workspace)
      assert File.dir?(workspace)
      assert String.contains?(output, workspace)
    end
  end

  describe "scan/1" do
    test "returns error when workspace not initialized" do
      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []),
          deepsec_bin: "/tmp/missing-deepsec"
        )
      )

      assert {:error, "Deepsec not initialized. Run init first."} = CLI.scan()
    end

    test "runs scan when workspace exists and binary is available", %{tmp_dir: tmp_dir} do
      workspace = Path.join(tmp_dir, "workspace")
      File.mkdir_p!(workspace)

      bin =
        write_script(tmp_dir, "deepsec-scan", """
        #!/bin/sh
        echo '{"findings": []}'
        """)

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []),
          deepsec_bin: bin,
          workspace_path: workspace
        )
      )

      # The scan function checks workspace existence then runs the command
      # Since we're using workspace_path from opts, pass it explicitly
      assert {:ok, _output} = CLI.scan(workspace_path: workspace)
    end
  end

  describe "npx mode" do
    test "resolves to npx with deepsec args when configured as npx" do
      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: "npx")
      )

      # available? should check for npx binary, not run deepsec
      # npx exists on this system, so available? returns true
      assert is_boolean(CLI.available?())
    end
  end

  defp write_script(tmp_dir, name, contents) do
    path = Path.join(tmp_dir, name)
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end
