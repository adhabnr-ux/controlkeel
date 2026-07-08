defmodule ControlKeel.Scanner.Finding do
  @moduledoc false

  @enforce_keys [
    :id,
    :severity,
    :category,
    :rule_id,
    :decision,
    :plain_message,
    :location,
    :metadata
  ]

  defstruct [
    :id,
    :severity,
    :category,
    :rule_id,
    :decision,
    :plain_message,
    :location,
    :metadata
  ]

  @doc """
  Converts a scanner rule action string to a CK decision string.
  """
  def action_to_decision("block"), do: "block"
  def action_to_decision("warn"), do: "warn"
  def action_to_decision("escalate_to_human"), do: "warn"
  def action_to_decision(_action), do: "allow"

  @doc """
  Redacts a matched text value for safe inclusion in finding metadata.
  Returns nil for nil/empty input, `[redacted]` for short values,
  and a prefix...suffix form for longer values.
  """
  def redact(nil), do: nil
  def redact(""), do: nil
  def redact(value) when not is_binary(value), do: nil
  def redact(value) when byte_size(value) <= 12, do: "[redacted]"

  def redact(value) do
    prefix = binary_part(value, 0, 4)
    suffix = binary_part(value, byte_size(value) - 4, 4)
    prefix <> "..." <> suffix
  end

  def to_map(%__MODULE__{} = finding) do
    %{
      "id" => finding.id,
      "severity" => finding.severity,
      "category" => finding.category,
      "rule_id" => finding.rule_id,
      "decision" => finding.decision,
      "plain_message" => finding.plain_message,
      "location" => finding.location,
      "metadata" => finding.metadata
    }
  end
end
