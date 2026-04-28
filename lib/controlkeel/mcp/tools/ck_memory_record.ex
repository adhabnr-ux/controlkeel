defmodule ControlKeel.MCP.Tools.CkMemoryRecord do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    with {:ok, task_id} <- Arguments.optional_integer(arguments, "task_id"),
         {:ok, memory} <- normalize_memory(arguments),
         {:ok, session} <- Arguments.fetch_session(arguments),
         :ok <- Arguments.validate_task(task_id, session.id),
         {:ok, record} <- create_record(arguments, session, task_id, memory) do
      {:ok,
       %{
         "recorded" => true,
         "memory_id" => record.id,
         "record_type" => record.record_type,
         "title" => record.title,
         "session_id" => record.session_id,
         "task_id" => record.task_id
       }}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp create_record(arguments, session, task_id, memory) do
    payload = merged_payload(arguments, memory)

    metadata =
      Map.get(payload, "metadata", %{})
      |> ensure_map()
      |> Map.put_new("source", "mcp")

    Memory.record(%{
      workspace_id: session.workspace_id,
      session_id: session.id,
      task_id: task_id,
      record_type: Map.get(payload, "record_type", "decision"),
      title: title_for(payload, memory),
      summary: summary_for(payload, memory),
      body: body_for(payload, memory),
      tags: normalize_tags(Map.get(payload, "tags")),
      source_type: Map.get(payload, "source_type", "generated"),
      source_id: Map.get(payload, "source_id"),
      metadata: metadata
    })
  end

  defp normalize_memory(arguments) do
    case Map.get(arguments, "memory") do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> {:error, {:invalid_arguments, "`memory` is required"}}
          trimmed -> {:ok, trimmed}
        end

      value when is_map(value) ->
        content =
          first_present_binary([
            Map.get(value, "content"),
            Map.get(value, "memory"),
            Map.get(value, "body"),
            Map.get(value, :content),
            Map.get(value, :memory),
            Map.get(value, :body)
          ])

        case content do
          nil -> {:error, {:invalid_arguments, "`memory` is required"}}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, {:invalid_arguments, "`memory` is required"}}
    end
  end

  defp merged_payload(arguments, memory) do
    case Map.get(arguments, "memory") do
      value when is_map(value) ->
        value
        |> stringify_keys()
        |> Map.put_new("memory", memory)
        |> Map.merge(Map.delete(arguments, "memory"), fn _key, memory_value, arg_value ->
          if blank_value?(arg_value), do: memory_value, else: arg_value
        end)

      _ ->
        arguments
    end
  end

  defp title_for(arguments, memory) do
    case Map.get(arguments, "title") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> memory |> String.trim() |> String.slice(0, 80)
    end
  end

  defp summary_for(arguments, memory) do
    case Map.get(arguments, "summary") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> memory |> String.trim() |> String.slice(0, 160)
    end
  end

  defp body_for(arguments, memory) do
    case Map.get(arguments, "body") do
      value when is_binary(value) and value != "" -> value
      _ -> memory
    end
  end

  defp normalize_tags(tags) when is_list(tags), do: Enum.map(tags, &to_string/1)

  defp normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tags(_tags), do: []

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp first_present_binary(values) do
    Enum.find_value(values, fn
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end)
  end

  defp blank_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_value?(nil), do: true
  defp blank_value?(value) when is_list(value), do: value == []
  defp blank_value?(value) when is_map(value), do: map_size(value) == 0
  defp blank_value?(_value), do: false
end
