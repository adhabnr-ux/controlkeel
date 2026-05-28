defmodule ControlKeel.Governance.CopilotChannelTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.CopilotChannel

  describe "publish/4 and history/2" do
    test "publishes events and retrieves history" do
      session_id = 999_999

      CopilotChannel.publish(session_id, "human.viewing", %{"file" => "test.ex"})
      CopilotChannel.publish(session_id, "human.editing", %{"file" => "test.ex", "line" => 42})

      {:ok, events} = CopilotChannel.history(session_id)
      assert length(events) == 2
      assert hd(events).event_type == "human.editing"
    end

    test "returns empty history for unknown session" do
      {:ok, events} = CopilotChannel.history(888_888)
      assert events == []
    end
  end

  describe "subscribe/1" do
    test "subscribes the current process" do
      CopilotChannel.subscribe(777_777)
      CopilotChannel.publish(777_777, "human.approving", %{"review_id" => 1})

      CopilotChannel.history(777_777)

      assert_received {:copilot_event, event}
      assert event.event_type == "human.approving"
      assert event.payload == %{"review_id" => 1}
    end
  end

  describe "presence/1" do
    test "returns presence info" do
      {:ok, info} = CopilotChannel.presence(555_555)
      assert info["session_id"] == 555_555
    end
  end
end
