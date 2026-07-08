defmodule ControlKeel.BinWrapperTest do
  use ExUnit.Case, async: false

  @wrapper Path.expand("../../bin/controlkeel", __DIR__)

  # The wrapper runs as a *subprocess* (System.cmd), so its DB writes are
  # outside the Ecto sandbox and would leak into the shared test DB.
  # Point the subprocess at a throwaway database via CK_TEST_DB so any
  # auto-bootstrap it triggers stays isolated.
  setup do
    tmp_db =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-bin-wrapper-#{System.unique_integer([:positive])}.db"
      )

    File.rm(tmp_db)

    on_exit(fn -> File.rm(tmp_db) end)

    env = [
      {"CK_PROJECT_ROOT", File.cwd!()},
      {"CK_CLI_MODE", "1"},
      {"LOGGER_LEVEL", "error"},
      {"CK_TEST_DB", tmp_db}
    ]

    %{env: env}
  end

  test "bin/controlkeel context --json emits parseable JSON on stdout", %{env: env} do
    {output, 0} = System.cmd(@wrapper, ["context", "--session-id", "1", "--json"], env: env)

    assert output != ""
    assert {:ok, payload} = Jason.decode(output)
    assert is_map(payload)
    assert Map.has_key?(payload, "session_id")
  end

  test "bin/controlkeel validate --json emits parseable JSON on stdout", %{env: env} do
    {output, 0} =
      System.cmd(@wrapper, ["validate", "--content", "echo hello", "--kind", "shell", "--json"],
        env: env
      )

    assert output != ""
    assert {:ok, payload} = Jason.decode(output)
    assert is_map(payload)
    assert Map.has_key?(payload, "decision")
  end
end
