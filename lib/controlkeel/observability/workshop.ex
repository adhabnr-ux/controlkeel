defmodule ControlKeel.Observability.Workshop do
  @moduledoc """
  Normalizes local Raindrop Workshop trace snapshots into ControlKeel observability previews.

  Workshop is treated as an optional local evidence source. This module only
  reads caller-provided JSON snapshots and returns redacted summaries; it does
  not contact a Workshop daemon, persist data, or promote evals/benchmarks.
  """

  @schema_version "controlkeel.workshop.preview.v1"

  def schema_version, do: @schema_version

  def preview_file(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, payload} <- Jason.decode(contents) do
      preview(payload, source: %{type: "file", path: path})
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def preview(payload, opts \\ []) do
    with {:ok, snapshot} <- normalize_snapshot(payload) do
      {:ok, build_preview(snapshot, opts)}
    end
  end

  defp normalize_snapshot(payload) when is_list(payload) do
    normalize_snapshot(%{"runs" => payload})
  end

  defp normalize_snapshot(%{"run" => run} = payload) when is_map(run) do
    normalize_snapshot(Map.put(payload, "runs", [run]))
  end

  defp normalize_snapshot(%{"runs" => runs} = payload) when is_list(runs) do
    with {:ok, spans} <- list_field(payload, "spans"),
         {:ok, live_events} <- list_field(payload, "live_events"),
         {:ok, saved_events} <- list_field(payload, "saved_events") do
      cond do
        not Enum.all?(runs, &is_map/1) ->
          {:error, {:invalid_field, "runs"}}

        not Enum.all?(spans, &is_map/1) ->
          {:error, {:invalid_field, "spans"}}

        not Enum.all?(live_events, &is_map/1) ->
          {:error, {:invalid_field, "live_events"}}

        not Enum.all?(saved_events, &is_map/1) ->
          {:error, {:invalid_field, "saved_events"}}

        true ->
          {:ok, %{runs: runs, spans: spans, live_events: live_events, saved_events: saved_events}}
      end
    end
  end

  defp normalize_snapshot(_payload), do: {:error, :invalid_workshop_snapshot}

  defp list_field(payload, key) do
    case Map.get(payload, key, []) do
      value when is_list(value) -> {:ok, value}
      _value -> {:error, {:invalid_field, key}}
    end
  end

  defp build_preview(snapshot, opts) do
    runs = Enum.map(snapshot.runs, &run_summary/1)
    spans = Enum.map(snapshot.spans, &span_summary/1)

    payload_chars = Enum.reduce(snapshot.spans, 0, &(&2 + span_payload_chars(&1)))
    tool_spans = Enum.count(spans, &(&1.type == "tool"))
    error_spans = Enum.count(spans, &(&1.status == "ERROR"))

    %{
      schema_version: @schema_version,
      source: source_metadata(opts),
      dry_run: true,
      mutation: "none",
      read_only: true,
      counts: %{
        runs: length(runs),
        spans: length(spans),
        tool_spans: tool_spans,
        error_spans: error_spans,
        live_events: length(snapshot.live_events),
        saved_events: length(snapshot.saved_events),
        payload_chars_redacted: payload_chars
      },
      redaction: %{
        policy: "summary_only",
        raw_span_payloads: false,
        raw_live_event_content: false,
        raw_saved_event_content: false,
        note:
          "Workshop preview keeps counts and metadata only; span payloads and event bodies are not returned."
      },
      integrity: %{
        fingerprint_algorithm: "sha256",
        payload_sha256: fingerprint(snapshot),
        import_mutation_allowed: false
      },
      runs: runs,
      spans: Enum.take(spans, 25),
      recommendations: recommendations(runs, spans, snapshot)
    }
  end

  defp source_metadata(opts) do
    opts
    |> Keyword.get(:source, %{})
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put_new("product", "raindrop_workshop")
    |> Map.put_new("mode", "local_snapshot_preview")
  end

  defp run_summary(run) do
    %{
      id: string_value(run, "id"),
      event_id: string_value(run, "event_id"),
      event_name: string_value(run, "event_name"),
      name: string_value(run, "name"),
      model: string_value(run, "model"),
      started_at: Map.get(run, "started_at"),
      last_updated_at: Map.get(run, "last_updated_at"),
      metadata_keys: metadata_keys(run)
    }
  end

  defp span_summary(span) do
    %{
      id: string_value(span, "id"),
      run_id: string_value(span, "run_id"),
      parent_span_id: string_value(span, "parent_span_id"),
      name: string_value(span, "name"),
      type: normalize_span_type(string_value(span, "span_type")),
      status: string_value(span, "status") || "UNSET",
      model: string_value(span, "model"),
      provider: string_value(span, "provider"),
      duration_ms: Map.get(span, "duration_ms"),
      input_tokens: Map.get(span, "input_tokens"),
      output_tokens: Map.get(span, "output_tokens"),
      payload_chars_redacted: span_payload_chars(span),
      attribute_keys: attribute_keys(span)
    }
  end

  defp metadata_keys(run) do
    case Map.get(run, "metadata") do
      value when is_map(value) -> value |> Map.keys() |> Enum.sort()
      value when is_binary(value) -> decoded_keys(value)
      _ -> []
    end
  end

  defp attribute_keys(span) do
    case Map.get(span, "attributes") do
      value when is_map(value) -> value |> Map.keys() |> Enum.sort()
      value when is_binary(value) -> decoded_keys(value)
      _ -> []
    end
  end

  defp decoded_keys(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded |> Map.keys() |> Enum.sort()
      _ -> []
    end
  end

  defp normalize_span_type(nil), do: "unknown"

  defp normalize_span_type(value) do
    normalized = String.downcase(value)

    cond do
      normalized in ["tool", "tool_call", "tool_result"] -> "tool"
      normalized in ["llm", "model", "chat", "completion"] -> "llm"
      true -> normalized
    end
  end

  defp span_payload_chars(span) do
    payload_chars(span, "input_payload") + payload_chars(span, "output_payload")
  end

  defp payload_chars(span, key) do
    case Map.get(span, key) do
      value when is_binary(value) -> String.length(value)
      value when is_map(value) or is_list(value) -> value |> Jason.encode!() |> String.length()
      _ -> 0
    end
  end

  defp string_value(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp recommendations(runs, spans, snapshot) do
    base = [
      "Use this Workshop preview as local evidence; persist only verified, redacted summaries through CK import surfaces.",
      "Map recurring tool or model failures into CK eval candidates before benchmark promotion."
    ]

    base
    |> maybe_add(runs == [], "No Workshop runs were found in the snapshot.")
    |> maybe_add(
      spans == [],
      "No spans were found; export run detail or spans for stronger eval candidates."
    )
    |> maybe_add(
      Enum.any?(spans, &(&1.status == "ERROR")),
      "Error spans are present; inspect failure clusters before drafting evals."
    )
    |> maybe_add(
      snapshot.live_events != [],
      "Live events are summarized only; keep raw streaming content in the local Workshop database or proof attachments."
    )
  end

  defp maybe_add(recommendations, true, message), do: recommendations ++ [message]
  defp maybe_add(recommendations, false, _message), do: recommendations

  defp fingerprint(snapshot) do
    snapshot
    |> canonical_term()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonical_term(item)} end)
    |> Enum.sort_by(fn {key, _item} -> key end)
  end

  defp canonical_term(value) when is_list(value), do: Enum.map(value, &canonical_term/1)
  defp canonical_term(value), do: value
end
