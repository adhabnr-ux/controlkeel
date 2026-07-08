defmodule ControlKeel.Intent.BoundarySummary do
  @moduledoc false

  alias ControlKeel.Intent.{ExecutionPosture, HarnessPolicy}

  def build(brief)

  def build(%{__struct__: _} = brief) do
    brief
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
    |> then(&build/1)
  end

  def build(brief) when is_map(brief) do
    compiler = Map.get(brief, "compiler") || %{}
    answers = Map.get(compiler, "interview_answers") || %{}

    %{
      "risk_tier" => optional_string(brief, "risk_tier"),
      "budget_note" => optional_string(brief, "budget_note"),
      "data_summary" => optional_string(brief, "data_summary"),
      "compliance" => normalize_list(Map.get(brief, "compliance")),
      "constraints" => normalize_constraints(Map.get(answers, "constraints")),
      "open_questions" => normalize_list(Map.get(brief, "open_questions")),
      "launch_window" => optional_string(brief, "launch_window"),
      "next_step" => optional_string(brief, "next_step"),
      "execution_posture" => ExecutionPosture.build(brief),
      "harness_policy" => HarnessPolicy.build(brief)
    }
  end

  def build(_brief), do: empty_summary()

  defp optional_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp normalize_constraints(value) when is_binary(value) do
    value
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_constraints(value), do: normalize_list(value)

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(value) when is_binary(value), do: normalize_constraints(value)
  defp normalize_list(_value), do: []

  defp empty_summary do
    %{
      "risk_tier" => nil,
      "budget_note" => nil,
      "data_summary" => nil,
      "compliance" => [],
      "constraints" => [],
      "open_questions" => [],
      "launch_window" => nil,
      "next_step" => nil,
      "execution_posture" => ExecutionPosture.build(nil),
      "harness_policy" => HarnessPolicy.build(nil)
    }
  end
end
