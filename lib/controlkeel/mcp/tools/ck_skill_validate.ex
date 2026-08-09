defmodule ControlKeel.MCP.Tools.CkSkillValidate do
  @moduledoc false

  alias ControlKeel.Skills.Registry

  @max_output_bytes 100_000

  def call(%{"output" => _output, "schema" => _schema} = arguments) do
    with {:ok, normalized} <- normalize(arguments),
         {:ok, parsed_output} <- parse_output(normalized.output),
         {:ok, parsed_schema} <- parse_schema(normalized.schema),
         {:ok, validation} <- validate_against_schema(parsed_output, parsed_schema) do
      {:ok, result(normalized, parsed_output, validation)}
    end
  end

  def call(%{"skill_name" => skill_name} = arguments) when is_binary(skill_name) do
    # Validate against skill's built-in result_schema
    project_root = Map.get(arguments, "project_root")

    case Registry.get(skill_name, project_root) do
      nil ->
        {:error,
         {:invalid_arguments,
          "Skill '#{skill_name}' not found. Call ck_skill_list to see available skills."}}

      %{result_schema: nil} ->
        {:error,
         {:invalid_arguments,
          "Skill '#{skill_name}' does not have a result_schema defined in its frontmatter."}}

      skill ->
        output = Map.get(arguments, "output")

        if is_nil(output) or output == "" do
          {:error, {:invalid_arguments, "`output` is required when validating against a skill"}}
        else
          call(%{"output" => output, "schema" => skill.result_schema, "skill_name" => skill_name})
        end
    end
  end

  def call(_arguments) do
    {:error,
     {:invalid_arguments,
      "Either (output + schema) or (output + skill_name) is required. skill_name must be a string."}}
  end

  defp normalize(arguments) do
    output = Map.get(arguments, "output")
    schema = Map.get(arguments, "schema")
    skill_name = Map.get(arguments, "skill_name")

    cond do
      not is_binary(output) or output == "" ->
        {:error, {:invalid_arguments, "`output` is required and must be a non-empty string"}}

      byte_size(output) > @max_output_bytes ->
        {:error, {:invalid_arguments, "`output` exceeds #{@max_output_bytes} bytes"}}

      is_nil(schema) and is_nil(skill_name) ->
        {:error, {:invalid_arguments, "Either `schema` or `skill_name` is required"}}

      true ->
        {:ok,
         %{
           output: output,
           schema: schema,
           skill_name: skill_name
         }}
    end
  end

  defp parse_output(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, parsed} when is_map(parsed) or is_list(parsed) ->
        {:ok, parsed}

      {:ok, _parsed} ->
        {:ok, output}

      {:error, _} ->
        {:ok, output}
    end
  rescue
    _ -> {:ok, output}
  end

  defp parse_schema(schema) when is_binary(schema) do
    case Jason.decode(schema) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, _} ->
        {:error, {:invalid_schema, "Schema must be a JSON object"}}

      {:error, reason} ->
        {:error, {:invalid_schema, "Schema is not valid JSON: #{inspect(reason)}"}}
    end
  rescue
    _ -> {:error, {:invalid_schema, "Failed to parse schema"}}
  end

  defp parse_schema(schema) when is_map(schema), do: {:ok, schema}
  defp parse_schema(_), do: {:error, {:invalid_schema, "Schema must be a JSON object or string"}}

  defp validate_against_schema(output, schema) do
    case validate_type(output, schema) do
      {:ok, _} = result -> result
      {:error, _} = error -> error
    end
  end

  defp validate_type(output, schema) do
    type = Map.get(schema, "type")
    enum = Map.get(schema, "enum")
    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    cond do
      enum != nil ->
        validate_enum(output, enum)

      type == "string" ->
        if is_binary(output), do: {:ok, %{}}, else: type_error("string", output)

      type == "number" ->
        if is_number(output), do: {:ok, %{}}, else: type_error("number", output)

      type == "integer" ->
        if is_integer(output), do: {:ok, %{}}, else: type_error("integer", output)

      type == "boolean" ->
        if is_boolean(output), do: {:ok, %{}}, else: type_error("boolean", output)

      type == "array" ->
        if is_list(output) do
          case Map.get(schema, "items") do
            nil -> {:ok, %{}}
            items_schema -> validate_array_items(output, items_schema)
          end
        else
          type_error("array", output)
        end

      type == "object" ->
        if is_map(output) do
          additional_properties = Map.get(schema, "additionalProperties")
          validate_object(output, required, properties, additional_properties)
        else
          type_error("object", output)
        end

      type == nil ->
        {:ok, %{}}

      true ->
        # Unknown type, accept but warn
        {:ok, %{"warnings" => ["Unknown type: #{type}"]}}
    end
  end

  defp validate_enum(output, enum) when is_list(enum) do
    case output in enum do
      true ->
        {:ok, %{}}

      false ->
        {:error,
         {:validation_failed,
          %{
            reason: "enum_mismatch",
            message: "Value #{inspect(output)} is not in allowed enum: #{inspect(enum)}",
            allowed_values: enum,
            actual_value: output
          }}}
    end
  end

  defp validate_enum(_output, enum) do
    {:error,
     {:validation_failed,
      %{
        reason: "invalid_enum",
        message: "Enum must be a list, got: #{inspect(enum)}"
      }}}
  end

  defp validate_object(output, required, properties, additional_properties) do
    # Check required fields
    missing = Enum.filter(required, fn field -> not Map.has_key?(output, field) end)

    if missing != [] do
      {:error,
       {:validation_failed,
        %{
          reason: "missing_required_fields",
          message: "Missing required fields: #{Enum.join(missing, ", ")}",
          missing_fields: missing
        }}}
    else
      property_errors =
        properties
        |> Enum.flat_map(fn {key, prop_schema} ->
          case Map.fetch(output, key) do
            :error ->
              []

            {:ok, value} ->
              case validate_type(value, prop_schema) do
                {:ok, _} -> []
                {:error, error} -> [{key, error}]
              end
          end
        end)

      # Validate additional properties if additionalProperties is a schema (sibling of properties in JSON Schema)
      known_keys = MapSet.new(Map.keys(properties))

      extra_errors =
        if is_map(additional_properties) do
          output
          |> Map.keys()
          |> Enum.reject(&MapSet.member?(known_keys, &1))
          |> Enum.flat_map(fn key ->
            case Map.fetch(output, key) do
              {:ok, value} ->
                case validate_type(value, additional_properties) do
                  {:ok, _} -> []
                  {:error, error} -> [{key, error}]
                end

              :error ->
                []
            end
          end)
        else
          []
        end

      all_errors = property_errors ++ extra_errors

      if all_errors != [] do
        {:error,
         {:validation_failed,
          %{
            reason: "property_validation_failed",
            message: "Property validation failed for #{length(all_errors)} field(s)",
            property_errors: all_errors
          }}}
      else
        {:ok, %{}}
      end
    end
  end

  defp validate_array_items(array, items_schema) when is_list(array) and is_map(items_schema) do
    item_errors =
      array
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, index} ->
        case validate_type(item, items_schema) do
          {:ok, _} -> []
          {:error, error} -> [{index, error}]
        end
      end)

    if item_errors != [] do
      {:error,
       {:validation_failed,
        %{
          reason: "array_item_validation_failed",
          message: "#{length(item_errors)} array item(s) failed validation",
          item_errors: item_errors
        }}}
    else
      {:ok, %{}}
    end
  end

  defp validate_array_items(_array, _items_schema), do: {:ok, %{}}

  defp type_error(expected, actual) do
    {:error,
     {:validation_failed,
      %{
        reason: "type_mismatch",
        message: "Expected type #{expected}, got #{get_type(actual)}: #{inspect(actual)}",
        expected_type: expected,
        actual_type: get_type(actual),
        actual_value: actual
      }}}
  end

  defp result(normalized, parsed_output, validation) do
    %{
      "valid" => true,
      "skill_name" => normalized.skill_name,
      "output_type" => get_type(parsed_output),
      "validation_details" => validation
    }
  end

  defp get_type(value) when is_binary(value), do: "string"
  defp get_type(value) when is_integer(value), do: "integer"
  defp get_type(value) when is_float(value), do: "number"
  defp get_type(value) when is_boolean(value), do: "boolean"
  defp get_type(value) when is_list(value), do: "array"
  defp get_type(value) when is_map(value), do: "object"
  defp get_type(_value), do: "unknown"
end
