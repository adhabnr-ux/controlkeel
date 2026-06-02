defmodule ControlKeel.Integrations.Deepsec do
  @moduledoc """
  Budget-aware gate for running deepsec from the fast-path scanner.
  """

  alias ControlKeel.Integrations.Deepsec.Config
  alias ControlKeel.Mission

  @doc """
  Checks if deepsec should be triggered based on budget and configuration.
  """
  def should_trigger_deepsec?(session_id, severity \\ :medium) do
    with true <- Config.enabled?(),
         true <- severity_meets_threshold?(severity),
         {:ok, within_budget} <- check_budget(session_id) do
      {:ok, within_budget}
    else
      false -> {:ok, false}
      error -> error
    end
  end

  defp severity_meets_threshold?(severity) do
    min_severity = Config.min_severity_for_investigation()
    severity_order = [:low, :medium, :high, :critical]

    min_index = Enum.find_index(severity_order, &(&1 == min_severity))
    severity_index = Enum.find_index(severity_order, &(&1 == severity))

    not is_nil(min_index) and not is_nil(severity_index) and severity_index >= min_index
  end

  defp check_budget(session_id) do
    max_budget = Config.max_scan_budget_cents()

    case Mission.get_session(session_id) do
      nil ->
        {:ok, true}

      session ->
        spent_cents = session.spent_cents || 0
        budget_cents = session.budget_cents || 0

        if budget_cents <= 0 do
          {:ok, true}
        else
          remaining = budget_cents - spent_cents
          {:ok, remaining >= max_budget}
        end
    end
  end
end
