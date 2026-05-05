defmodule ControlKeel.Integrations.Deepsec.CustomConfig do
  @moduledoc """
  Support for custom deepsec configuration files.

  This module allows users to specify custom deepsec configuration
  files to control scan behavior, matchers, and other settings.
  """

  alias ControlKeel.Integrations.Deepsec.Config

  @default_config_file "deepsec.config.json"

  @doc """
  Loads a custom deepsec configuration from a file.

  ## Parameters
  - config_path: Path to the config file (absolute or relative to workspace)
  - workspace_path: Workspace directory for relative paths

  ## Returns
  {:ok, config} on success
  {:error, reason} on failure
  """
  def load_config(config_path, workspace_path \\ nil) do
    full_path = resolve_config_path(config_path, workspace_path)

    case File.read(full_path) do
      {:ok, content} ->
        parse_config(content)

      {:error, reason} ->
        {:error, "Failed to read config file: #{reason}"}
    end
  end

  @doc """
  Saves a custom deepsec configuration to a file.

  ## Parameters
  - config: Configuration map
  - config_path: Path to save the config file
  - workspace_path: Workspace directory for relative paths

  ## Returns
  {:ok, path} on success
  {:error, reason} on failure
  """
  def save_config(config, config_path, workspace_path \\ nil) do
    full_path = resolve_config_path(config_path, workspace_path)

    # Ensure directory exists
    dir = Path.dirname(full_path)
    File.mkdir_p!(dir)

    content = Jason.encode!(config, pretty: true)

    case File.write(full_path, content) do
      :ok ->
        {:ok, full_path}

      {:error, reason} ->
        {:error, "Failed to write config file: #{reason}"}
    end
  end

  @doc """
  Merges custom config with default config.

  ## Parameters
  - custom_config: Custom configuration map
  - default_config: Default configuration (uses Config defaults if nil)

  ## Returns
  Merged configuration map
  """
  def merge_configs(custom_config, default_config \\ nil) do
    default_config = default_config || get_default_config()

    Map.merge(default_config, custom_config, fn _key, default, custom ->
      merge_nested(default, custom)
    end)
  end

  @doc """
  Validates a deepsec configuration.

  ## Parameters
  - config: Configuration map to validate

  ## Returns
  {:ok, validated_config} on success
  {:error, reasons} on failure (list of error reasons)
  """
  def validate_config(config) do
    errors =
      []
      |> validate_matchers(config)
      |> validate_file_patterns(config)
      |> validate_severity_thresholds(config)

    if Enum.empty?(errors) do
      {:ok, config}
    else
      {:error, errors}
    end
  end

  @doc """
  Gets the default deepsec configuration.
  """
  def get_default_config do
    %{
      "matchers" => [],
      "filePatterns" => ["**/*.{js,ts,jsx,tsx,py,rb,go,java,php,ex,exs}"],
      "ignorePatterns" => ["node_modules/**", ".git/**", "dist/**", "build/**"],
      "severityThreshold" => "medium",
      "enableAI" => true,
      "enableRevalidation" => true,
      "maxFindings" => 1000,
      "timeout" => 300
    }
  end

  @doc """
  Creates a sample custom configuration file.

  ## Parameters
  - output_path: Path to save the sample config

  ## Returns
  {:ok, path} on success
  {:error, reason} on failure
  """
  def create_sample_config(output_path \\ nil) do
    output_path = output_path || Path.join(File.cwd!(), @default_config_file)

    sample_config = %{
      "matchers" => [
        %{
          "slug" => "custom-api-key",
          "pattern" => "API_KEY\\s*=\\s*[\"']([a-zA-Z0-9]{20,})[\"']",
          "severity" => "critical",
          "filePatterns" => ["**/*.{js,ts,py,rb,ex,exs}"]
        }
      ],
      "filePatterns" => ["**/*.{js,ts,jsx,tsx,py,rb,go,java,php,ex,exs}"],
      "ignorePatterns" => [
        "node_modules/**",
        ".git/**",
        "dist/**",
        "build/**",
        "_build/**",
        "deps/**"
      ],
      "severityThreshold" => "medium",
      "enableAI" => true,
      "enableRevalidation" => true,
      "maxFindings" => 1000,
      "timeout" => 300
    }

    save_config(sample_config, output_path)
  end

  @doc """
  Applies custom configuration to deepsec workspace.

  ## Parameters
  - config: Configuration map
  - workspace_path: Path to deepsec workspace

  ## Returns
  {:ok, path} on success
  {:error, reason} on failure
  """
  def apply_config(config, workspace_path) do
    config_path = Path.join(workspace_path, @default_config_file)

    case validate_config(config) do
      {:ok, _} ->
        save_config(config, config_path, workspace_path)

      {:error, errors} ->
        {:error, "Invalid config: #{Enum.join(errors, ", ")}"}
    end
  end

  ## Private Functions

  defp resolve_config_path(config_path, workspace_path) do
    if Path.type(config_path) == :absolute do
      config_path
    else
      workspace = workspace_path || Config.workspace_path() || File.cwd!()
      Path.join(workspace, config_path)
    end
  end

  defp parse_config(content) do
    case Jason.decode(content) do
      {:ok, config} when is_map(config) ->
        {:ok, config}

      {:ok, _} ->
        {:error, "Config must be a JSON object"}

      {:error, reason} ->
        {:error, "Failed to parse JSON: #{reason}"}
    end
  end

  defp merge_nested(default, custom) when is_map(default) and is_map(custom) do
    Map.merge(default, custom, fn _key, d, c -> merge_nested(d, c) end)
  end

  defp merge_nested(_default, custom), do: custom

  defp validate_matchers(errors, config) do
    matchers = Map.get(config, "matchers", [])

    if is_list(matchers) do
      invalid_matchers =
        Enum.filter(matchers, fn matcher ->
          not is_map(matcher) or
            is_nil(Map.get(matcher, "slug")) or
            is_nil(Map.get(matcher, "pattern")) or
            is_nil(Map.get(matcher, "severity"))
        end)

      if Enum.empty?(invalid_matchers) do
        errors
      else
        ["Invalid matchers: missing required fields" | errors]
      end
    else
      ["matchers must be a list" | errors]
    end
  end

  defp validate_file_patterns(errors, config) do
    patterns = Map.get(config, "filePatterns", [])

    if is_list(patterns) do
      errors
    else
      ["filePatterns must be a list" | errors]
    end
  end

  defp validate_severity_thresholds(errors, config) do
    threshold = Map.get(config, "severityThreshold", "medium")

    valid_thresholds = ["low", "medium", "high", "critical"]

    if threshold in valid_thresholds do
      errors
    else
      ["severityThreshold must be one of: #{Enum.join(valid_thresholds, ", ")}" | errors]
    end
  end
end
