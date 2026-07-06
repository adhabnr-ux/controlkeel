defmodule ControlKeel.Scanner.Result do
  @moduledoc false

  @enforce_keys [:allowed, :decision, :summary, :findings, :scanned_at]

  defstruct [:allowed, :decision, :summary, :findings, :scanned_at, :advisory]
end
