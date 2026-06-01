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
  Returns whether the matcher system is enabled.
  """
  def matcher_system_enabled? do
    Application.get_env(:controlkeel, :matcher_system, [])
    |> Keyword.get(:enabled, false)
  end

  @doc """
  Returns whether deepsec should be used for security domain validation.
  """
  def use_for_security_domain? do
    Application.get_env(:controlkeel, :deepsec, [])
    |> Keyword.get(:use_for_security_domain, false)
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

  @doc """
  Validates the configuration.
  """
  def validate_config do
    errors = []

    errors =
      if max_scan_budget_cents() < 0 do
        ["max_scan_budget_cents must be non-negative" | errors]
      else
        errors
      end

    errors =
      if min_severity_for_investigation() not in [:low, :medium, :high, :critical] do
        ["min_severity_for_investigation must be :low, :medium, :high, or :critical" | errors]
      else
        errors
      end

    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc """
  Returns the configuration as a map for inspection.
  """
  def inspect_config do
    %{
      # Deepsec integration config
      deepsec_enabled: enabled?(),
      use_for_security_domain: use_for_security_domain?(),
      min_severity_for_investigation: min_severity_for_investigation(),
      max_scan_budget_cents: max_scan_budget_cents(),
      workspace_path: workspace_path(),
      matcher_system_enabled: matcher_system_enabled?()
    }
  end
end
