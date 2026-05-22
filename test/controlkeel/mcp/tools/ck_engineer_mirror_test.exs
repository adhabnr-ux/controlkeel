defmodule ControlKeel.MCP.Tools.CkEngineerMirrorTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkEngineerMirror
  import ControlKeel.MissionFixtures

  test "call returns the engineer mirror envelope when given a session_id" do
    session = session_fixture()

    assert {:ok, payload} = CkEngineerMirror.call(%{"session_id" => session.id})
    assert payload["session_id"] == session.id
    assert is_map(payload["today"])
    assert is_map(payload["rolling_30d"])
  end

  test "call accepts a stringified session_id" do
    session = session_fixture()

    assert {:ok, payload} = CkEngineerMirror.call(%{"session_id" => Integer.to_string(session.id)})
    assert payload["session_id"] == session.id
  end

  test "call returns invalid_arguments without session_id" do
    assert {:error, {:invalid_arguments, _}} = CkEngineerMirror.call(%{})
  end

  test "call rejects non-integer session_id" do
    assert {:error, {:invalid_arguments, _}} = CkEngineerMirror.call(%{"session_id" => "abc"})
  end
end
