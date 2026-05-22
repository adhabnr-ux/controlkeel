defmodule ControlKeel.Learning.EngineerMirrorTest do
  use ControlKeel.DataCase

  alias ControlKeel.Learning.EngineerMirror
  import ControlKeel.MissionFixtures

  test "build returns the expected envelope shape for an empty session" do
    session = session_fixture()

    payload = EngineerMirror.build(session.id)

    assert payload["session_id"] == session.id
    assert is_map(payload["today"])
    assert is_map(payload["rolling_30d"])
    assert Map.has_key?(payload["today"], "plans_submitted")
    assert Map.has_key?(payload["today"], "first_pass_approvals")
    assert Map.has_key?(payload["today"], "denials")
    assert Map.has_key?(payload["today"], "outcomes")
    assert Map.has_key?(payload["rolling_30d"], "outcome_breakdown")
    assert Map.has_key?(payload, "top_signal")
    assert Map.has_key?(payload, "one_suggestion")
  end

  test "build returns error envelope for invalid input" do
    payload = EngineerMirror.build(nil)
    assert is_map(payload)
    assert Map.has_key?(payload, "error")
  end
end
