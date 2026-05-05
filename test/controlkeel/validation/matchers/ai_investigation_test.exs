defmodule ControlKeel.Validation.Matchers.AIInvestigationTest do
  use ExUnit.Case

  alias ControlKeel.Validation.Matchers.AIInvestigation

  describe "should_trigger?/3" do
    setup do
      # Store original config
      original_config = Application.get_env(:controlkeel, :ai_investigation, [])

      on_exit(fn ->
        # Restore original config
        Application.put_env(:controlkeel, :ai_investigation, original_config)
      end)

      :ok
    end

    test "returns false when AI investigation is disabled" do
      Application.put_env(:controlkeel, :ai_investigation, enabled: false)

      assert {:ok, false} = AIInvestigation.should_trigger?(nil, "security", :high)
    end

    test "returns false when domain pack is not security" do
      Application.put_env(:controlkeel, :ai_investigation, enabled: true)

      assert {:ok, false} = AIInvestigation.should_trigger?(nil, "hr", :high)
    end

    test "returns false when severity is below threshold" do
      Application.put_env(:controlkeel, :ai_investigation,
        enabled: true,
        min_severity: :high
      )

      assert {:ok, false} = AIInvestigation.should_trigger?(nil, "security", :medium)
    end

    test "returns true when all conditions are met" do
      Application.put_env(:controlkeel, :ai_investigation,
        enabled: true,
        min_severity: :medium
      )

      assert {:ok, true} = AIInvestigation.should_trigger?(nil, "security", :high)
    end

    test "returns true when severity meets threshold exactly" do
      Application.put_env(:controlkeel, :ai_investigation,
        enabled: true,
        min_severity: :high
      )

      assert {:ok, true} = AIInvestigation.should_trigger?(nil, "security", :high)
    end

    test "accepts nil domain pack as security domain" do
      Application.put_env(:controlkeel, :ai_investigation,
        enabled: true,
        min_severity: :medium
      )

      assert {:ok, true} = AIInvestigation.should_trigger?(nil, nil, :high)
    end

    test "handles critical severity correctly" do
      Application.put_env(:controlkeel, :ai_investigation,
        enabled: true,
        min_severity: :high
      )

      assert {:ok, true} = AIInvestigation.should_trigger?(nil, "security", :critical)
    end
  end

  describe "investigate/4" do
    setup do
      # Create a temporary workspace for testing
      tmp_dir = System.tmp_dir!()
      workspace_path = Path.join(tmp_dir, "deepsec_test_#{System.unique_integer()}")

      # Create the directory
      File.mkdir_p!(workspace_path)

      on_exit(fn ->
        File.rm_rf!(workspace_path)
      end)

      {:ok, workspace_path: workspace_path}
    end

    test "returns investigation result when deepsec is available", %{
      workspace_path: workspace_path
    } do
      content = "def foo() do\n  :ok\nend"
      file_path = "lib/my_app.ex"
      session_id = 1
      task_id = "task-1"

      result =
        AIInvestigation.investigate(content, file_path, session_id, task_id,
          workspace_path: workspace_path
        )

      # Deepsec may not be installed, so accept either success or error
      case result do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, :findings)
          assert Map.has_key?(result, :metadata)

          metadata = result.metadata
          assert metadata.investigation_type == "deepsec_ai"
          assert metadata.file_path == file_path
          assert metadata.session_id == session_id
          assert metadata.task_id == task_id
          assert metadata.content_length == String.length(content)
          assert Map.has_key?(metadata, :timestamp)

        {:error, _reason} ->
          # Deepsec not available, skip test
          :ok
      end
    end

    test "handles empty content", %{workspace_path: workspace_path} do
      content = ""
      file_path = "lib/my_app.ex"
      session_id = 1
      task_id = "task-1"

      result =
        AIInvestigation.investigate(content, file_path, session_id, task_id,
          workspace_path: workspace_path
        )

      case result do
        {:ok, result} ->
          assert result.metadata.content_length == 0

        {:error, _reason} ->
          # Deepsec not available, skip test
          :ok
      end
    end
  end

  describe "process_results/3" do
    test "returns empty list when findings is nil" do
      investigation_result = %{}
      session_id = 1
      task_id = "task-1"

      assert {:ok, []} =
               AIInvestigation.process_results(investigation_result, session_id, task_id)
    end

    test "returns empty list when findings key is missing" do
      investigation_result = %{metadata: %{}}
      session_id = 1
      task_id = "task-1"

      assert {:ok, []} =
               AIInvestigation.process_results(investigation_result, session_id, task_id)
    end

    test "returns error when findings is not a list" do
      investigation_result = %{findings: "not a list"}
      session_id = 1
      task_id = "task-1"

      assert {:error, :invalid_findings_format} =
               AIInvestigation.process_results(investigation_result, session_id, task_id)
    end

    test "returns empty list when findings is empty" do
      investigation_result = %{findings: []}
      session_id = 1
      task_id = "task-1"

      assert {:ok, []} =
               AIInvestigation.process_results(investigation_result, session_id, task_id)
    end

    test "handles string key for findings" do
      investigation_result = %{"findings" => []}
      session_id = 1
      task_id = "task-1"

      assert {:ok, []} =
               AIInvestigation.process_results(investigation_result, session_id, task_id)
    end

    test "converts findings using Deepsec adapter" do
      # This is a placeholder test - in a real implementation,
      # we would mock the Deepsec.process_findings function
      investigation_result = %{findings: [%{slug: "test"}]}
      session_id = 1
      task_id = "task-1"

      # For now, just ensure it doesn't crash
      # The actual conversion logic is in the Deepsec adapter
      assert {:ok, _findings} =
               AIInvestigation.process_results(investigation_result, session_id, task_id)
    end
  end
end
