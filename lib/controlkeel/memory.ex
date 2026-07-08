defmodule ControlKeel.Memory do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Memory.{Embeddings, Record, Store}
  alias ControlKeel.Repo

  @record_types ~w(brief task finding proof checkpoint budget decision incident review goal regression)

  def record_types, do: @record_types

  def get_record(id), do: Repo.get(Record, id)
  def get_record!(id), do: Repo.get!(Record, id)

  def record(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, record} <- upsert_record(attrs) do
      _ = Embeddings.upsert_record_embedding(record)
      {:ok, record}
    end
  end

  defp upsert_record(
         %{workspace_id: workspace_id, source_type: source_type, source_id: source_id} = attrs
       )
       when is_integer(workspace_id) and is_binary(source_type) and is_binary(source_id) and
              source_id != "" do
    case Repo.get_by(Record,
           workspace_id: workspace_id,
           source_type: source_type,
           source_id: source_id
         ) do
      nil ->
        %Record{}
        |> Record.changeset(attrs)
        |> Repo.insert()

      %Record{} = existing ->
        existing
        |> Record.changeset(attrs)
        |> Repo.update()
    end
  end

  defp upsert_record(attrs) do
    %Record{}
    |> Record.changeset(attrs)
    |> Repo.insert()
  end

  def archive_record(%Record{} = record) do
    record
    |> Record.changeset(%{archived_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def archive_record(id) when is_integer(id) do
    case get_record(id) do
      nil -> {:error, :not_found}
      record -> archive_record(record)
    end
  end

  @stale_default_days 90
  @stale_default_types ~w(task checkpoint budget)

  @doc """
  Archive (soft-delete) stale memory records to keep the company-brain bounded.

  Archives records whose `record_type` is in `opts[:record_types]` (default the
  transient status types `task`/`checkpoint`/`budget`) and whose `inserted_at` is
  older than `opts[:max_age_days]` (default 90), excluding records already archived.
  Durable evidence types (proof/finding/decision/review/goal/brief/incident) are not
  touched by the defaults, so the audit corpus is preserved.

  Caller-driven (a scheduled job or operator) so the retention policy stays explicit
  and overridable rather than a hidden background mutation. Returns
  `{:ok, %{archived: count, ids: [id]}}`.
  """
  def archive_stale_records(opts \\ []) do
    max_age_days = Keyword.get(opts, :max_age_days, @stale_default_days)
    types = Keyword.get(opts, :record_types, @stale_default_types)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    cutoff = DateTime.add(now, -max_age_days * 86_400, :second)

    ids =
      from(r in Record,
        where:
          is_nil(r.archived_at) and r.record_type in ^types and
            r.inserted_at < ^cutoff,
        select: r.id
      )
      |> Repo.all()

    {count, _} =
      Repo.update_all(
        from(r in Record, where: r.id in ^ids),
        set: [archived_at: now, updated_at: now]
      )

    {:ok, %{archived: count, ids: ids}}
  end

  def search(query, opts \\ []) when is_binary(query) do
    Store.search(query, normalize_search_opts(opts))
  end

  def retrieve_for_task(session, task, opts \\ [])

  def retrieve_for_task(_session, nil, _opts) do
    %{entries: [], query: nil, total_count: 0, semantic_available: false}
  end

  def retrieve_for_task(session, task, opts) do
    findings = opts[:findings] || []
    domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"])

    query =
      [
        session.objective,
        task.title,
        task.validation_gate,
        Enum.map(findings, & &1.category) |> Enum.uniq() |> Enum.join(" "),
        domain_pack
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    search(
      query,
      workspace_id: session.workspace_id,
      session_id: session.id,
      task_id: task.id,
      domain_pack: domain_pack,
      top_k: opts[:top_k] || Store.top_k()
    )
  end

  def list_related_to_task(task_id, limit \\ 5) when is_integer(task_id) do
    Record
    |> where([r], r.task_id == ^task_id and is_nil(r.archived_at))
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp normalize_attrs(attrs) do
    attrs =
      Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)

    %{
      workspace_id: attrs["workspace_id"],
      session_id: attrs["session_id"],
      task_id: attrs["task_id"],
      record_type: normalize_record_type(attrs["record_type"]),
      title: attrs["title"] || "Untitled memory record",
      summary: attrs["summary"] || attrs["title"] || "Recorded event",
      body: attrs["body"] || attrs["summary"] || "",
      tags: normalize_tags(attrs["tags"], attrs["metadata"]),
      source_type: attrs["source_type"] || "system",
      source_id: normalize_source_id(attrs["source_id"]),
      metadata: normalize_metadata(attrs["metadata"]),
      archived_at: attrs["archived_at"],
      visibility: normalize_visibility(attrs["visibility"]),
      shared_org_id: attrs["shared_org_id"],
      synced_at: attrs["synced_at"]
    }
  end

  defp normalize_search_opts(opts) do
    opts
    |> Enum.into(%{})
    |> Enum.into([], fn {key, value} -> {key, value} end)
  end

  defp normalize_tags(value, _metadata) when is_list(value), do: Enum.map(value, &to_string/1)

  defp normalize_tags(_value, metadata) when is_map(metadata) do
    metadata
    |> Map.take(["domain_pack", "rule_id", "status"])
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp normalize_tags(_value, _metadata), do: []

  defp normalize_record_type(nil), do: "decision"

  defp normalize_record_type(value) do
    value = to_string(value)
    if value in @record_types, do: value, else: "decision"
  end

  defp normalize_source_id(nil), do: nil
  defp normalize_source_id(value) when is_binary(value), do: value
  defp normalize_source_id(value), do: to_string(value)

  defp normalize_metadata(metadata) when is_map(metadata),
    do: ControlKeel.Utils.stringify_keys_deep(metadata)

  defp normalize_metadata(_value), do: %{}

  defp normalize_visibility(nil), do: "workspace"
  defp normalize_visibility(value) when value in ["workspace", "org", "admin"], do: value
  defp normalize_visibility(value), do: to_string(value)
end
