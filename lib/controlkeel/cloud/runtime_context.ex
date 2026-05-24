defmodule ControlKeel.Cloud.RuntimeContext do
  @moduledoc """
  Public context for the cloud-agent runtime loop.

  Builds and tracks `ControlKeel.Cloud.RunPackage` records that represent a
  task handed off to a downstream cloud runtime. This module is the persistence
  layer for Phase 5 — the HTTP/CLI dispatch and the callback endpoint live in
  follow-on slices.

  Per architectural decision D2, runtime authorization continues to flow
  through service-account-style tokens. The callback token issued here is
  single-use and bound to one package; it is hashed at rest using the same
  SHA-256 helper Service Accounts already use, so the format is consistent.

  Naming: this module is `ControlKeel.Cloud.RuntimeContext` rather than
  `ControlKeel.Cloud.Runtime` to avoid colliding with `ControlKeel.Runtime`
  (the local-vs-cloud runtime mode helper).
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Repo

  @doc """
  Create a new cloud run package and return `{:ok, package, raw_callback_token}`.

  The raw token is returned exactly once — the caller delivers it to the cloud
  runtime out of band (in the dispatch HTTP body, typically). The package row
  stores only the SHA-256 hash.

  Required attrs:

    - `workspace_id`
    - `runtime_target` (one of `RunPackage.valid_runtimes/0`)
    - `budget_cents_allocated` (>= 0)

  Optional attrs: `session_id`, `task_id`, `scopes` (list or string), `proof_refs`
  (list or string), `payload` (map for runtime-specific fields).
  """
  @spec create_package(map()) ::
          {:ok, RunPackage.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_package(attrs) when is_map(attrs) do
    raw_token = generate_token()

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put_new("status", "pending")
      |> Map.put("callback_token_hash", token_hash(raw_token))
      |> normalize_list("scopes")
      |> normalize_list("proof_refs")

    case %RunPackage{}
         |> RunPackage.changeset(attrs)
         |> Repo.insert() do
      {:ok, package} -> {:ok, package, raw_token}
      {:error, _} = err -> err
    end
  end

  @doc "Get a package by id."
  @spec get_package(integer()) :: RunPackage.t() | nil
  def get_package(id), do: Repo.get(RunPackage, id)

  @doc """
  Authenticate a raw callback token, returning the matching package.

  Returns `:not_found` when no row matches, `{:terminal, package}` when the
  package is in a terminal status (callbacks for completed/failed/cancelled
  packages are rejected to prevent late updates from overwriting evidence).
  """
  @spec authenticate_callback(String.t()) ::
          {:ok, RunPackage.t()} | :not_found | {:terminal, RunPackage.t()}
  def authenticate_callback(raw_token) when is_binary(raw_token) do
    hash = token_hash(raw_token)

    case Repo.get_by(RunPackage, callback_token_hash: hash) do
      nil ->
        :not_found

      %RunPackage{} = package ->
        if RunPackage.terminal?(package), do: {:terminal, package}, else: {:ok, package}
    end
  end

  @doc "List packages for a workspace, newest first."
  @spec list_for_workspace(integer(), keyword()) :: [RunPackage.t()]
  def list_for_workspace(workspace_id, opts \\ []) when is_integer(workspace_id) do
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    RunPackage
    |> where([p], p.workspace_id == ^workspace_id)
    |> maybe_filter_status(status_filter)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Transition a package's status.

  Returns `{:error, :terminal}` if the package has already reached a terminal
  status (no late updates allowed).
  """
  @spec transition_status(RunPackage.t() | integer(), String.t(), keyword()) ::
          {:ok, RunPackage.t()}
          | {:error, :not_found | :terminal | :invalid_status | Ecto.Changeset.t()}
  def transition_status(package_or_id, new_status, opts \\ [])

  def transition_status(%RunPackage{id: id}, new_status, opts) do
    transition_status(id, new_status, opts)
  end

  def transition_status(id, new_status, opts) when is_integer(id) do
    cond do
      new_status not in RunPackage.valid_statuses() ->
        {:error, :invalid_status}

      true ->
        # Always re-read so a stale in-memory struct cannot trick the terminal
        # gate into letting a second update through.
        case Repo.get(RunPackage, id) do
          nil ->
            {:error, :not_found}

          %RunPackage{} = fresh ->
            if RunPackage.terminal?(fresh) do
              {:error, :terminal}
            else
              attrs =
                %{status: new_status}
                |> maybe_put_field(:result_summary, Keyword.get(opts, :result_summary))
                |> maybe_put_field(:error_summary, Keyword.get(opts, :error_summary))
                |> maybe_put_field(:proof_refs, encode_list(Keyword.get(opts, :proof_refs)))
                |> maybe_put_timestamp(new_status)

              fresh
              |> RunPackage.changeset(attrs)
              |> Repo.update()
            end
        end
    end
  end

  @doc "Count packages by status for a workspace."
  @spec status_counts(integer()) :: %{String.t() => non_neg_integer()}
  def status_counts(workspace_id) when is_integer(workspace_id) do
    RunPackage
    |> where([p], p.workspace_id == ^workspace_id)
    |> group_by([p], p.status)
    |> select([p], {p.status, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count packages by status across all workspaces."
  @spec global_status_counts() :: %{String.t() => non_neg_integer()}
  def global_status_counts do
    RunPackage
    |> group_by([p], p.status)
    |> select([p], {p.status, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Newest-first list of recent run packages across the deployment."
  @spec recent(keyword()) :: [RunPackage.t()]
  def recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)

    RunPackage
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^limit)
    |> Repo.all()
  end

  # ─────────────── helpers ───────────────

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, statuses) when is_list(statuses),
    do: where(query, [p], p.status in ^statuses)

  defp maybe_filter_status(query, status) when is_binary(status),
    do: where(query, [p], p.status == ^status)

  defp maybe_put_field(attrs, _key, nil), do: attrs
  defp maybe_put_field(attrs, key, value), do: Map.put(attrs, key, value)

  defp maybe_put_timestamp(attrs, "dispatched"),
    do: Map.put(attrs, :dispatched_at, now())

  defp maybe_put_timestamp(attrs, status) when status in ~w(completed failed cancelled),
    do: Map.put(attrs, :completed_at, now())

  defp maybe_put_timestamp(attrs, _other), do: attrs

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp normalize_list(attrs, key) do
    case Map.get(attrs, key) do
      nil -> attrs
      value -> Map.put(attrs, key, encode_list(value))
    end
  end

  defp encode_list(nil), do: nil
  defp encode_list(value) when is_binary(value), do: value
  defp encode_list(value) when is_list(value), do: Enum.map_join(value, ",", &to_string/1)

  defp generate_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp token_hash(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
