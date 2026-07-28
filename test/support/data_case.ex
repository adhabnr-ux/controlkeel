defmodule ControlKeel.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ControlKeel.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias ControlKeel.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ControlKeel.DataCase
    end
  end

  setup tags do
    ControlKeel.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.

  Targets `ControlKeel.Repo.Local` because the sandbox API needs a real
  Ecto.Repo (the dispatcher at `ControlKeel.Repo` is not one). Tests run in
  `:local` runtime mode, so the dispatcher routes every query to `.Local`
  anyway — the sandbox owns the same pool that production code uses.

  Also restores any `ControlKeel.CloudRepo` config captured at setup start so a
  test that deliberately exercises cloud-mode behavior can save/restore its own
  state without this case clobbering it (issue #44). Tests that opt into cloud
  mode must start a CloudRepo sandbox in their own setup; the dispatcher routes
  accordingly.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ControlKeel.Repo.Local, shared: not tags[:async])
    # Capture the CloudRepo config as of setup start. on_exit handlers run LIFO
    # and this case registers before a test's own setup, so this on_exit runs
    # AFTER the test's. Restoring (rather than unconditionally deleting) preserves
    # the test's intended state instead of wiping a restore it just performed.
    prior_cloud_repo_config = Application.get_env(:controlkeel, ControlKeel.CloudRepo)

    on_exit(fn ->
      # Check in the connection gracefully before stopping the owner.
      # This prevents "client exited" error logs when LiveView processes
      # that shared the sandbox are still alive during cleanup.
      Ecto.Adapters.SQL.Sandbox.checkin(ControlKeel.Repo.Local, sandbox: pid)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)

      case prior_cloud_repo_config do
        nil ->
          Application.delete_env(:controlkeel, ControlKeel.CloudRepo)

        config ->
          Application.put_env(:controlkeel, ControlKeel.CloudRepo, config, persistent: true)
      end
    end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
