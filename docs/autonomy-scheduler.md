# Governed Autonomy Scheduler

ControlKeel is **reactive** by default: a session starts when an operator or host
agent triggers it. The autonomy scheduler adds the missing piece — a governed,
timer-driven heartbeat — so CK can run unattended jobs the way a cron-driven
agent (e.g. gumclaw) does, but with every wake-up recorded as a governed session.

This closes the one structural gap surfaced by comparing ControlKeel to
cron-driven agent deployments: "cron fires → wake → work → report" becomes
"timer fires → governed wake-up → agent runs inside a real session → audit
trail + recoverable memory."

## How it works

1. A `GenServer` (`ControlKeel.Autonomy.Scheduler`) runs inside the CK
   application and arms a `Process.send_after` timer per configured job.
2. When a job's timer fires, the dispatcher creates a **governed wake-up**: a
   session + task + `autonomy.wake` audit event.
3. If the job has a launcher **and** shell launching is enabled, the dispatcher
   also invokes the configured agent program. Otherwise the wake-up is recorded
   and an external launcher (or a later run) picks it up.
4. The timer re-arms. The heartbeat continues until the app stops.

Off by default. Never starts inside an MCP stdio server process.

## Configuration

```elixir
config :controlkeel,
  autonomy: [
    enabled: true,
    allow_shell: false,
    launch_timeout_ms: 300_000,
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
```

| key            | required | meaning                                                              |
| -------------- | -------- | -------------------------------------------------------------------- |
| `enabled`      | no       | Arm timers on boot. Also set via `CK_AUTONOMY_SCHEDULER=1`.          |
| `allow_shell`  | no       | Permit launchers to execute. Also via `CK_AUTONOMY_ALLOW_SHELL=1`.   |
| `launch_timeout_ms` | no  | Default external-launch timeout (5 minutes).                         |
| `workspace_id` | yes      | Workspace wake-up sessions bind to. No cross-tenant fallback.        |
| `jobs`         | yes      | List of job maps (see below).                                        |

### Job fields

| field         | required | type                  | notes                                                       |
| ------------- | -------- | --------------------- | ----------------------------------------------------------- |
| `name`        | yes      | atom / string         | Unique identifier.                                          |
| `interval_ms` | yes      | pos integer           | Time between fires.                                         |
| `title`       | yes      | string                | Human label; becomes the session title.                     |
| `task`        | yes      | string                | Task body; becomes the session objective + task text.       |
| `agent`       | no       | atom / string         | Target agent hint (informational).                          |
| `launcher`    | no       | map                   | `%{adapter: :shell, command: binary, args: [binary \| :task]}`. |

The `:task` placeholder in `launcher.args` is replaced with the job's task text
as a **single discrete argv element** — never interpolated into a shell string.
A launcher may legitimately omit `:task` (e.g. a fixed maintenance command).

## Security model for launchers

The shell launcher is the only module in the autonomy subsystem that executes an
external process. Its trust boundary is intentionally narrow:

- **argv, not an implicit shell.** `System.cmd/3` receives an explicit argument
  list. ControlKeel does not invoke a shell automatically. An operator who
  explicitly configures `sh -c`, `bash -c`, or another interpreter can
  reintroduce shell parsing and owns that trust boundary.
- **Explicit opt-in.** Gated on `CK_AUTONOMY_ALLOW_SHELL` or `allow_shell: true`.
  Disabled → launchers are skipped, wake-ups still recorded.
- **Trusted template.** `command` and `args` come from operator config (trusted).
  Only `:task` receives job text, and only as an argv element.
- **Audited.** Session + task + pre-launch wake event commit atomically before
  execution. Launch results are written to a separate audit event.
- **Bounded.** Launches time out (five minutes by default; configurable globally
  or per launcher with `timeout_ms`) and timed dispatches run under a
  `Task.Supervisor`, so one slow agent does not block unrelated timers.
- **Tree-safe timeout.** Each Unix launch uses a Python `os.setsid()+execv()`
  wrapper so the tracked PID remains its OS process-group leader; timeout signals
  terminate the entire group. Windows uses `taskkill /T`. Launching fails closed
  when process-tree isolation cannot be established. A timeout is returned only
  after Unix has no runnable process-group members, or Windows reports successful
  `taskkill /T /F` and the original PID disappears. Signal, `taskkill`, or
  confirmation failures return an explicit `launch_termination_failed` error.
- **No overlap per job.** While a job is in flight, later ticks for that same job
  are skipped and re-armed rather than duplicating external side effects.

## Mix task

```
mix ck.autonomy                # status + job list
mix ck.autonomy list           # list configured jobs
mix ck.autonomy status         # enabled / workspace / shell-launch state
mix ck.autonomy run <name>     # fire a job once now
mix ck.autonomy run <name> --dry-run   # show what would happen, record nothing
```

`run` works whether or not the scheduler is enabled.

## Relation to external schedulers

You do not need the BEAM scheduler to run autonomous jobs — an external cron
calling `mix ck.autonomy run <name>` produces the same governed wake-up. The
BEAM scheduler is for deployments that want an always-on heartbeat inside the CK
process, matching cron-driven agent models. Both paths produce identical audit
trails.

## See also

- `lib/controlkeel/autonomy/scheduler.ex`
- `lib/controlkeel/autonomy/dispatcher.ex`
- `lib/controlkeel/autonomy/launcher/shell.ex`
- `lib/controlkeel/memory/retention_scheduler.ex` (the pattern this mirrors)
