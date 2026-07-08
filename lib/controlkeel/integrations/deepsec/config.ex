defmodule ControlKeel.Integrations.Deepsec.Config do
  @moduledoc """
  Configuration for the deepsec integration.

  This module provides configuration options for integrating
  deepsec with ControlKeel, including settings for when to
  trigger deepsec scans, budget controls, and finding behavior.
  """

  @doc """
  Returns whether deepsec integration is enabled.
  """
  def enabled? do
    Application.get_env(:controlkeel, :deepsec, [])
    |> Keyword.get(:enabled, false)
  end

  @doc """
  Returns the minimum severity level that should trigger deepsec investigation.
  Valid values: :low, :medium, :high, :critical
  """
  def min_severity_for_investigation do
    Application.get_env(:controlkeel, :deepsec, [])
    |> Keyword.get(:min_severity_for_investigation, :high)
  end

  @doc """
  Returns the maximum budget (in cents) allowed for deepsec scans.
  """
  def max_scan_budget_cents do
    Application.get_env(:controlkeel, :deepsec, [])
    # Default $100
    |> Keyword.get(:max_scan_budget_cents, 10_000)
  end

  @doc """
  Returns the path to the deepsec workspace directory.
  """
  def workspace_path do
    Application.get_env(:controlkeel, :deepsec, [])
    |> Keyword.get(:workspace_path, ".deepsec")
  end
end
