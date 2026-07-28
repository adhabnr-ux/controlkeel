defmodule ControlKeel.Repo do
  @moduledoc """
  Public Ecto repo API for ControlKeel.

  All context modules, LiveViews, controllers, and CLI tooling call this module
  (`Repo.all/2`, `Repo.insert/2`, …). It forwards each call to the active
  underlying repo at runtime:

    * `:local` runtime mode → `ControlKeel.Repo.Local` (SQLite)
    * `:cloud` / `:self_hosted` runtime mode → `ControlKeel.CloudRepo` (Postgres)

  Selection goes through `ControlKeel.Runtime.cloud_repo_enabled?/0`, which
  requires a remote runtime mode **and** a configured `ControlKeel.CloudRepo`
  `:url`. This means a misconfigured cloud deployment fails closed against
  Postgres instead of silently falling back to a local SQLite file, and a
  `:self_hosted` box without `DATABASE_URL` keeps using SQLite as intended.

  ## Why a dispatcher instead of a single Repo with a runtime adapter

  `use Ecto.Repo, adapter:` binds the adapter at compile time. A single Phoenix
  release must serve both SQLite (local laptops) and Postgres (cloud), so the
  adapter cannot be baked in. Routing to two compiled repos at runtime is the
  minimal-risk fix and leaves every call site unchanged.

  ## Transaction consistency

  `Runtime.mode/0` is process-stable for the lifetime of a transaction, so
  every inner `Repo.*` call inside a `Repo.transaction/2` resolves to the same
  underlying repo. Ecto tracks the live transaction in the process dictionary
  keyed by repo module, so `Repo.transaction` + inner `Repo.insert` stay bound
  to the same connection.

  ## Forwarded surface

  Forwards the full query/write/transaction API used across the codebase
  (`all`, `aggregate`, `get`, `get!`, `get_by`, `get_by!`, `one`, `one!`,
  `preload`, `query`, `query!`, `insert`, `insert!`, `insert_all`,
  `insert_or_update`, `insert_or_update!`, `update`, `update!`, `update_all`,
  `delete`, `delete!`, `delete_all`, `transaction`, `rollback`) plus the
  introspection callbacks `__adapter__/0` and `config/0` used by
  `ControlKeel.Ops.Database` and `ControlKeel.Memory.Store.PgVector`.

  Callers that need a real `Ecto.Repo` for adapter-level APIs
  (`Ecto.Adapters.SQL.query/4`, sandbox, connection checkout) must use
  `ControlKeel.Repo.active/0` — the dispatcher itself is not registered with
  `Ecto.Repo.Registry`.
  """

  alias ControlKeel.Repo.Local
  alias ControlKeel.CloudRepo

  @doc """
  Resolve the active underlying repo for the current runtime mode.

  Returns `ControlKeel.CloudRepo` when cloud-mode is enabled (remote runtime
  mode and CloudRepo configured), otherwise `ControlKeel.Repo.Local`.
  """
  @spec active() :: module()
  def active do
    if ControlKeel.Runtime.cloud_repo_enabled?(), do: CloudRepo, else: Local
  end

  # -- Introspection ---------------------------------------------------------

  def __adapter__, do: active().__adapter__()
  def config, do: active().config()

  # -- Read ------------------------------------------------------------------

  def all(queryable, opts \\ []), do: active().all(queryable, opts)

  def one(queryable, opts \\ []), do: active().one(queryable, opts)
  def one!(queryable, opts \\ []), do: active().one!(queryable, opts)

  def aggregate(queryable, aggregate, opts \\ []),
    do: active().aggregate(queryable, aggregate, opts)

  def get(queryable, id, opts \\ []), do: active().get(queryable, id, opts)

  def get!(queryable, id, opts \\ []), do: active().get!(queryable, id, opts)

  def get_by(queryable, clauses, opts \\ []),
    do: active().get_by(queryable, clauses, opts)

  def get_by!(queryable, clauses, opts \\ []),
    do: active().get_by!(queryable, clauses, opts)

  def preload(struct_or_structs, preloads, opts \\ []),
    do: active().preload(struct_or_structs, preloads, opts)

  def query(sql, params \\ [], opts \\ []), do: active().query(sql, params, opts)
  def query!(sql, params \\ [], opts \\ []), do: active().query!(sql, params, opts)

  # -- Write -----------------------------------------------------------------

  def insert(struct_or_changeset, opts \\ []),
    do: active().insert(struct_or_changeset, opts)

  def insert!(struct_or_changeset, opts \\ []),
    do: active().insert!(struct_or_changeset, opts)

  def insert_all(schema_or_source, entries, opts \\ []),
    do: active().insert_all(schema_or_source, entries, opts)

  def insert_or_update(struct_or_changeset, opts \\ []),
    do: active().insert_or_update(struct_or_changeset, opts)

  def insert_or_update!(struct_or_changeset, opts \\ []),
    do: active().insert_or_update!(struct_or_changeset, opts)

  def update(struct_or_changeset, opts \\ []),
    do: active().update(struct_or_changeset, opts)

  def update!(struct_or_changeset, opts \\ []),
    do: active().update!(struct_or_changeset, opts)

  def update_all(queryable, updates, opts \\ []),
    do: active().update_all(queryable, updates, opts)

  def delete(struct_or_changeset, opts \\ []),
    do: active().delete(struct_or_changeset, opts)

  def delete!(struct_or_changeset, opts \\ []),
    do: active().delete!(struct_or_changeset, opts)

  def delete_all(queryable, opts \\ []), do: active().delete_all(queryable, opts)

  # -- Transactions ----------------------------------------------------------

  def transaction(fun_or_multi, opts \\ []),
    do: active().transaction(fun_or_multi, opts)

  def rollback(value), do: active().rollback(value)
end
