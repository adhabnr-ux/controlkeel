defmodule ControlKeel.BinWrapperTest do
  use ExUnit.Case, async: false

  @wrapper Path.expand("../../bin/controlkeel", __DIR__)

  test "bin/controlkeel context --json emits parseable JSON on stdout" do
    env = [
      {"CK_PROJECT_ROOT", File.cwd!()},
      {"CK_CLI_MODE", "1"},
      {"LOGGER_LEVEL", "error"}
    ]

    {output, 0} = System.cmd(@wrapper, ["context", "--session-id", "1", "--json"], env: env)

    assert output != ""
    assert {:ok, payload} = Jason.decode(output)
    assert is_map(payload)
    assert Map.has_key?(payload, "session_id")
  end

  test "bin/controlkeel validate --json emits parseable JSON on stdout" do
    env = [
      {"CK_PROJECT_ROOT", File.cwd!()},
      {"CK_CLI_MODE", "1"},
      {"LOGGER_LEVEL", "error"}
    ]

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
