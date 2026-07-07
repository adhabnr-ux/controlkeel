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
