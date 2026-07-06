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
end
