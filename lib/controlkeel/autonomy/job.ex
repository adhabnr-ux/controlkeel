defmodule ControlKeel.Autonomy.Job do
  @moduledoc """
  A scheduled autonomy job.

  Fires on a fixed interval and produces a governed wake-up (a session + task +
  audit event). When a `launcher` is configured AND shell launching is enabled,
  the wake-up also invokes a configured agent program on schedule.

  Jobs are defined in config, never in code, so an operator's filesystem (not the
  model) decides what runs unattended:

      config :controlkeel,
        autonomy: [
          enabled: true,
          allow_shell: true,
          workspace_id: 1,
          jobs: [
            %{
              name: :daily_triage,
              interval_ms: :timer.hours(6),
              title: "Scheduled support triage",
              task: "Triage open support tickets and close or escalate each one.",
              agent: :opencode,
              launcher: %{adapter: :shell, command: "opencode", args: ["run", :task]}
            }
          ]
        ]

  The `:task` placeholder in `launcher.args` receives the job's task text as a
  single discrete argv element (never interpolated into a shell string).
  """

  @enforce_keys [:name, :interval_ms, :title, :task]
  defstruct [:name, :interval_ms, :title, :task, :agent, :launcher]

  @type launcher :: %{adapter: :shell, command: binary(), args: [binary() | :task]}
  @type t :: %__MODULE__{
          name: atom(),
          interval_ms: pos_integer(),
          title: String.t(),
          task: String.t(),
          agent: atom() | nil,
          launcher: launcher() | nil
        }

  @doc """
  Parse a single job from a config map or keyword list.

  Returns `{:ok, %__MODULE__{}}` or `{:error, reason}`.
  """
  def from_config(config) when is_list(config) or is_map(config) do
    config = normalize(config)

    with {:ok, name} <- parse_name(config[:name]),
         {:ok, interval_ms} <- parse_interval(config[:interval_ms]),
         {:ok, title} <- require_string(config[:title], :title),
         {:ok, task} <- require_string(config[:task], :task),
         {:ok, launcher} <- parse_launcher(config[:launcher]) do
      {:ok,
       %__MODULE__{
         name: name,
         interval_ms: interval_ms,
         title: title,
         task: task,
         agent: to_atom(config[:agent]),
         launcher: launcher
       }}
    end
  end

  @doc """
  Parse a list of job configs, enforcing unique names.

  Returns `{:ok, [job]}` or `{:error, reason}`.
  """
  def from_config_all(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn raw, {:ok, acc, seen} ->
      case from_config(raw) do
        {:ok, %__MODULE__{name: name} = job} ->
          if MapSet.member?(seen, name) do
            {:halt, {:error, {:duplicate_name, name}}}
          else
            {:cont, {:ok, [job | acc], MapSet.put(seen, name)}}
          end

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, jobs, _seen} -> {:ok, Enum.reverse(jobs)}
      {:error, _} = err -> err
    end
  end

  @doc "Whether this job has a launcher configured."
  def launcher?(%__MODULE__{launcher: nil}), do: false
  def launcher?(%__MODULE__{launcher: _}), do: true

  # --- parsers ---

  defp normalize(config) when is_list(config), do: Keyword.new(config)
  defp normalize(config) when is_map(config), do: Map.to_list(config)

  defp parse_name(nil), do: {:error, {:missing, :name}}
  defp parse_name(name) when is_atom(name), do: {:ok, name}
  defp parse_name(name) when is_binary(name), do: {:ok, String.to_atom(name)}
  defp parse_name(other), do: {:error, {:invalid_name, other}}

  defp parse_interval(nil), do: {:error, {:missing, :interval_ms}}

  defp parse_interval(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    {:ok, interval_ms}
  end

  defp parse_interval(other), do: {:error, {:invalid_interval_ms, other}}

  defp require_string(nil, field), do: {:error, {:missing, field}}

  defp require_string(value, _field) when is_binary(value) and byte_size(value) > 0 do
    {:ok, value}
  end

  defp require_string(other, field), do: {:error, {:invalid, field, other}}

  defp parse_launcher(nil), do: {:ok, nil}

  defp parse_launcher(%{adapter: :shell} = launcher) do
    command = Map.get(launcher, :command) || Map.get(launcher, "command")
    args = Map.get(launcher, :args) || Map.get(launcher, "args")

    cond do
      not is_binary(command) or byte_size(command) == 0 ->
        {:error, {:invalid_launcher, :command}}

      not is_list(args) or args == [] ->
        {:error, {:invalid_launcher, :args}}

      not Enum.all?(args, &valid_arg?/1) ->
        {:error, {:invalid_launcher, :args_template}}

      true ->
        {:ok, %{adapter: :shell, command: command, args: args}}
    end
  end

  defp parse_launcher(other), do: {:error, {:unknown_launcher, other}}

  defp valid_arg?(:task), do: true
  defp valid_arg?(arg) when is_binary(arg), do: true
  defp valid_arg?(_), do: false

  defp to_atom(nil), do: nil
  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)
end
