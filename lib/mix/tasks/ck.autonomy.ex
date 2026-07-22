defmodule Mix.Tasks.Ck.Autonomy do
  @shortdoc "List, run, and inspect governed autonomy jobs"

  @moduledoc """
  Operates the governed autonomy scheduler.

  ## Usage

      mix ck.autonomy              # list configured jobs + scheduler status (default)
      mix ck.autonomy list         # list configured jobs
      mix ck.autonomy status       # show enabled state + workspace resolution
      mix ck.autonomy run <name>   # fire a job once now
      mix ck.autonomy run <name> --dry-run   # show what would happen, record nothing

  Jobs are defined in `config :controlkeel, autonomy: [jobs: [...]]`. The
  scheduler must be enabled (`CK_AUTONOMY_SCHEDULER=1` or `autonomy: [enabled: true]`)
  to arm timers automatically; `run` works regardless.
  """

  use Mix.Task

  alias ControlKeel.Autonomy.Scheduler

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, argv, _} = OptionParser.parse(args, strict: [dry_run: :boolean])

    shell = Mix.shell()

    case {argv, opts[:dry_run]} do
      {["list" | _], _} ->
        print_jobs(shell)

      {["status" | _], _} ->
        print_status(shell)

      {["run", name | _], dry?} ->
        run_job(shell, name, dry?)

      {[], _} ->
        print_status(shell)
        shell.info("")
        print_jobs(shell)

      _ ->
        shell.info(@moduledoc)
    end
  end

  defp print_jobs(shell) do
    jobs = Scheduler.jobs()

    if jobs == [] do
      shell.info("No autonomy jobs configured.")
    else
      shell.info(String.duplicate("─", 70))
      shell.info("Autonomy jobs (#{length(jobs)})")

      Enum.each(jobs, fn job ->
        shell.info(
          "  • #{String.pad_trailing(to_string(job.name), 24)} " <>
            "every #{format_ms(job.interval_ms)}  " <>
            if(ControlKeel.Autonomy.Job.launcher?(job),
              do: "[launcher]",
              else: ""
            )
        )

        shell.info("      #{String.slice(job.title, 0, 64)}")
      end)

      shell.info(String.duplicate("─", 70))
    end
  end

  defp print_status(shell) do
    enabled = Scheduler.enabled?()
    workspace = Scheduler.workspace_id()

    shell.info("Autonomy scheduler")
    shell.info(String.duplicate("─", 70))
    shell.info("  enabled?       #{format_bool(enabled)}")
    shell.info("  workspace_id   #{workspace || "(resolved per-run)"}")
    shell.info("  shell launch   #{format_bool(ControlKeel.Autonomy.Launcher.Shell.enabled?())}")
    shell.info(String.duplicate("─", 70))
  end

  defp run_job(shell, name, dry?) do
    opts = if dry?, do: [dry_run: true], else: []

    case Scheduler.run_once(String.to_atom(name), opts) do
      {:ok, %{dry_run: true} = result} ->
        shell.info("DRY RUN — nothing recorded, nothing launched.")
        shell.info("  job:           #{result.job}")
        shell.info("  workspace_id:  #{result.workspace_id}")
        shell.info("  would launch:  #{result.launched}")

      {:ok, %{session_id: sid, task_id: tid, launched: launched}} ->
        shell.info("Fired -> session ##{sid}, task ##{tid}")
        shell.info("  launched: #{format_launched(launched)}")

      {:error, {:unknown_job, name}} ->
        Mix.raise("Unknown autonomy job: #{inspect(name)}")

      {:error, reason} ->
        Mix.raise("Autonomy run failed: #{inspect(reason)}")
    end
  end

  defp format_ms(ms) when ms >= 3_600_000, do: "#{div(ms, 3_600_000)}h"
  defp format_ms(ms) when ms >= 60_000, do: "#{div(ms, 60_000)}m"
  defp format_ms(ms), do: "#{ms}ms"

  defp format_bool(true), do: "yes"
  defp format_bool(_), do: "no"

  defp format_launched(nil), do: "no (wake-up only)"
  defp format_launched(false), do: "no (wake-up only)"
  defp format_launched(%{exit_status: 0}), do: "yes (exit 0)"
  defp format_launched(%{exit_status: n}), do: "yes (exit #{n})"
  defp format_launched(%{error: _} = err), do: "failed (#{inspect(err)})"
end
