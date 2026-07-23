defmodule ControlKeel.Autonomy.Launcher.Shell do
  @moduledoc """
  Capability-gated shell launcher: invokes a configured agent program on schedule.

  ## Security model

  This is the only module in the autonomy subsystem that executes an external
  process, so its trust boundary is intentionally narrow:

  * **argv, not an implicit shell string.** Execution uses `System.cmd/3` with an
    explicit argument list. The job's task text is substituted as a *single
    discrete argv element* via the `:task` placeholder. ControlKeel does not
    implicitly invoke a shell; an operator who explicitly configures `sh -c`,
    `bash -c`, or another interpreter can reintroduce shell parsing and owns that
    trust boundary.
  * **Explicit opt-in.** Gated on the `CK_AUTONOMY_ALLOW_SHELL` environment
    variable or `config :controlkeel, autonomy: [allow_shell: true]`. When neither
    is set, `run/1` returns `{:error, :shell_not_allowed}` and launches nothing.
  * **Trusted template.** The `command` and `args` template are operator-configured
    (trusted source). Only the `:task` placeholder receives job-supplied text, and
    only as an argv element.
  * **Captured, never streamed.** Output is captured and truncated; every launch
    result (exit status + truncated output) is returned to the dispatcher, which
    records it in a governed session event for audit.

  ## Example

      %ControlKeel.Autonomy.Job{
        launcher: %{adapter: :shell, command: "opencode", args: ["run", :task]}
      }

  resolves, for `task: "Triage open tickets"`, to:

      System.cmd("opencode", ["run", "Triage open tickets"], stderr_to_stdout: true)
  """

  alias ControlKeel.Autonomy.Job

  @max_output_bytes 8_192
  @default_timeout_ms 300_000

  @type launch_result ::
          {:ok, %{exit_status: non_neg_integer(), output: binary()}} | {:error, term()}

  @doc "Whether shell launching is explicitly enabled."
  def enabled? do
    env_enabled?() or config_enabled?()
  end

  @doc """
  Execute the launcher for `job`.

  Returns `{:ok, %{exit_status, output}}` on execution (including non-zero exits,
  which are captured, not raised) or `{:error, reason}` when launching is disabled
  or the program is missing.
  """
  @spec run(Job.t(), keyword()) :: launch_result()
  def run(job, opts \\ [])

  def run(%Job{launcher: %{adapter: :shell}} = job, opts) do
    unless enabled?(), do: throw(:shell_not_allowed)

    %{command: command, args: template} = job.launcher
    args = resolve_args(template, job)
    timeout_ms = launch_timeout_ms(job, opts)

    task = Task.async(fn -> execute(command, args) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:launch_failed, inspect(reason)}}
      nil -> {:error, {:launch_timeout, timeout_ms}}
    end
  catch
    :shell_not_allowed ->
      {:error, :shell_not_allowed}

    :error, :enoent ->
      {:error, {:launch_failed, :enoent}}

    kind, reason ->
      {:error, {:launch_failed, {kind, reason}}}
  end

  def run(_job, _opts), do: {:error, :no_shell_launcher}

  defp execute(command, args) do
    {output, status} = System.cmd(command, args, stderr_to_stdout: true)
    {:ok, %{exit_status: status, output: truncate(output)}}
  catch
    :error, :enoent -> {:error, {:launch_failed, :enoent}}
    kind, reason -> {:error, {:launch_failed, {kind, inspect(reason)}}}
  end

  defp resolve_args(template, %Job{task: task}) when is_list(template) do
    Enum.map(template, fn
      :task -> task
      other when is_binary(other) -> other
    end)
  end

  defp truncate(output) when is_binary(output) do
    output =
      if byte_size(output) > @max_output_bytes do
        binary_part(output, 0, @max_output_bytes)
      else
        output
      end

    String.replace_invalid(output)
  end

  defp launch_timeout_ms(job, opts) do
    Keyword.get(opts, :timeout_ms) || job.launcher.timeout_ms ||
      Application.get_env(:controlkeel, :autonomy, [])
      |> Keyword.get(:launch_timeout_ms, @default_timeout_ms)
  end

  defp env_enabled? do
    System.get_env("CK_AUTONOMY_ALLOW_SHELL") in ~w(1 true TRUE yes YES)
  end

  defp config_enabled? do
    Application.get_env(:controlkeel, :autonomy, []) |> Keyword.get(:allow_shell, false)
  end
end
