defmodule ControlKeel.Cloud.RuntimeDispatcherTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Cloud.RuntimeDispatcher
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Repo

  defmodule StubOkDispatcher do
    @behaviour ControlKeel.Cloud.RuntimeDispatcher

    @impl true
    def dispatch(_package, opts) do
      {:ok,
       %{
         "mode" => "stub_ok",
         "raw_token_seen?" => is_binary(Keyword.get(opts, :raw_token)),
         "ticket_id" => "tkt_42"
       }}
    end
  end

  defmodule StubFailingDispatcher do
    @behaviour ControlKeel.Cloud.RuntimeDispatcher

    @impl true
    def dispatch(_package, _opts), do: {:error, :stub_explosion}
  end

  setup do
    workspace = MissionFixtures.workspace_fixture()
    session = MissionFixtures.session_fixture(%{workspace: workspace})
    task = MissionFixtures.task_fixture(%{session: session})

    previous = Application.get_env(:controlkeel, :cloud_dispatchers, %{})
    on_exit(fn -> Application.put_env(:controlkeel, :cloud_dispatchers, previous) end)

    {:ok, workspace: workspace, session: session, task: task}
  end

  describe "RuntimeDispatcher.for_runtime/1" do
    test "defaults to Manual when no config is set" do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{})
      assert RuntimeDispatcher.for_runtime("devin") == RuntimeDispatcher.Manual
    end

    test "respects the configured override" do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{
        "devin" => StubOkDispatcher
      })

      assert RuntimeDispatcher.for_runtime("devin") == StubOkDispatcher
      # Other runtimes still fall back
      assert RuntimeDispatcher.for_runtime("open-swe") == RuntimeDispatcher.Manual
    end
  end

  describe "RuntimeDispatcher.Manual.dispatch/2" do
    test "records the manual handoff intent", %{
      workspace: workspace,
      session: session,
      task: task
    } do
      {:ok, package, _token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert {:ok, meta} = RuntimeDispatcher.Manual.dispatch(package, [])
      assert meta["mode"] == "manual"
      assert meta["runtime_target"] == "devin"
      assert is_binary(meta["note"])
    end
  end

  describe "RuntimeContext.dispatch_package/3" do
    test "transitions pending → dispatched and stores metadata", %{
      workspace: workspace,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{
        "devin" => StubOkDispatcher
      })

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert package.status == "pending"

      assert {:ok, dispatched} = RuntimeContext.dispatch_package(package, raw_token)
      assert dispatched.status == "dispatched"
      assert dispatched.dispatched_at
      assert get_in(dispatched.payload, ["dispatch_metadata", "ticket_id"]) == "tkt_42"
      assert get_in(dispatched.payload, ["dispatch_metadata", "raw_token_seen?"]) == true
    end

    test "transitions to failed and records error_summary when dispatcher errors", %{
      workspace: workspace,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{
        "open-swe" => StubFailingDispatcher
      })

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "open-swe",
          budget_cents_allocated: 0
        })

      assert {:error, :stub_explosion} = RuntimeContext.dispatch_package(package, raw_token)

      reloaded = Repo.get!(RunPackage, package.id)
      assert reloaded.status == "failed"
      assert reloaded.error_summary =~ "stub_explosion"
      assert reloaded.completed_at
    end

    test "Manual default still produces a clean dispatched transition", %{
      workspace: workspace,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{})

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert {:ok, dispatched} = RuntimeContext.dispatch_package(package, raw_token)
      assert dispatched.status == "dispatched"
      assert get_in(dispatched.payload, ["dispatch_metadata", "mode"]) == "manual"
    end
  end
end
