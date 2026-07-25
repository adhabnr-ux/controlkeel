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

  Also cleans up any leaked `ControlKeel.CloudRepo` config after each test
  so no test accidentally routes queries to an unstarted Postgres repo
  (issue #44). Tests that deliberately exercise cloud-mode behavior should
  set CloudRepo config AND a sandbox for it within their own setup; they
  will restore the original state via their own `on_exit` handlers.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ControlKeel.Repo.Local, shared: not tags[:async])

    on_exit(fn ->
      # Check in the connection gracefully before stopping the owner.
      # This prevents "client exited" error logs when LiveView processes
      # that shared the sandbox are still alive during cleanup.
      Ecto.Adapters.SQL.Sandbox.checkin(ControlKeel.Repo.Local, sandbox: pid)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)

      # Prevent leaked CloudRepo config from routing subsequent tests'
      # queries to an unstarted Postgres repo. This runs before the test's
      # own `on_exit` (LIFO), so tests that explicitly save/restore
      # CloudRepo config will have their original restored properly.
      Application.delete_env(:controlkeel, ControlKeel.CloudRepo)
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
