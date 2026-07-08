defmodule ControlKeel.Integrations.Deepsec.ScannerTest do
  use ControlKeel.DataCase

  alias ControlKeel.Integrations.Deepsec.{CLI, Scanner}
  alias ControlKeel.Proxy

  setup do
    previous = Application.get_env(:controlkeel, Proxy, [])

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-deepsec-scan-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      Application.put_env(:controlkeel, Proxy, previous)
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  defp write_script(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, body)
    File.chmod!(path, 0o755)
    path
  end

  describe "deepsec_scan/1 error paths" do
    test "returns error when deepsec CLI is not available", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "missing-deepsec")

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: missing)
      )

      assert {:error, reason} = Scanner.deepsec_scan([])
      assert reason =~ "Deepsec CLI is not available"
    end

    test "returns error when init step fails", %{tmp_dir: tmp_dir} do
      # Binary exists so available?/0 is true, but init exits non-zero.
      bin = write_script(tmp_dir, "deepsec-init-fail", "#!/bin/sh\nexit 1\n")

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: bin)
      )

      workspace = Path.join(tmp_dir, "ws")
      File.mkdir_p!(workspace)

      assert {:error, _reason} = Scanner.deepsec_scan(workspace_path: workspace)
    end

    test "returns error when scan step fails", %{tmp_dir: tmp_dir} do
      # init succeeds, scan exits non-zero.
      bin =
        write_script(
          tmp_dir,
          "deepsec-scan-fail",
          ~S"""
          #!/bin/sh
          case "$1" in
            init) exit 0;;
            scan) exit 2;;
            *) exit 0;;
          esac
          """
        )

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: bin)
      )

      workspace = Path.join(tmp_dir, "ws")
      File.mkdir_p!(workspace)

      assert {:error, _reason} = Scanner.deepsec_scan(workspace_path: workspace)
    end

    test "returns error when export step fails", %{tmp_dir: tmp_dir} do
      # init + scan + process succeed, export exits non-zero.
      bin =
        write_script(
          tmp_dir,
          "deepsec-export-fail",
          ~S"""
          #!/bin/sh
          case "$1" in
            init|scan|process) exit 0;;
            export) exit 3;;
            *) exit 0;;
          esac
          """
        )

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: bin)
      )

      workspace = Path.join(tmp_dir, "ws")
      File.mkdir_p!(workspace)

      assert {:error, reason} = Scanner.deepsec_scan(workspace_path: workspace)
      assert reason =~ "Failed to export findings"
    end
  end

  describe "deepsec_scan/1 happy path" do
    test "returns findings when export produces valid JSON", %{tmp_dir: tmp_dir} do
      export_dir = Path.join(tmp_dir, "export")
      File.mkdir_p!(export_dir)

      findings_json =
        ~s({"findings": [{"vulnSlug": "test-vuln", "severity": "HIGH", "title": "Test", "filePath": "app.ex" }]})

      bin =
        write_script(
          tmp_dir,
          "deepsec-ok",
          ~s"""
          #!/bin/sh
          case "$1" in
            init|scan|process) exit 0;;
            export) mkdir -p "$5"; echo '#{findings_json}' > "$5/findings.json"; exit 0;;
            *) exit 0;;
          esac
          """
        )

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: bin)
      )

      workspace = Path.join(tmp_dir, "ws")
      File.mkdir_p!(workspace)

      assert {:ok, findings} = Scanner.deepsec_scan(workspace_path: workspace)
      assert is_list(findings)
      assert length(findings) == 1
    end
  end

  describe "CLI.available?/0" do
    test "returns false when binary is missing", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "no-such-binary")

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: missing)
      )

      assert CLI.available?() == false
    end

    test "returns true when binary exists", %{tmp_dir: tmp_dir} do
      bin = write_script(tmp_dir, "deepsec-present", "#!/bin/sh\nexit 0\n")

      Application.put_env(
        :controlkeel,
        Proxy,
        Keyword.merge(Application.get_env(:controlkeel, Proxy, []), deepsec_bin: bin)
      )

      assert CLI.available?() == true
    end
  end
end
