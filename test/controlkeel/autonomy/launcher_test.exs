defmodule ControlKeel.Autonomy.Launcher.ShellTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Autonomy.Job
  alias ControlKeel.Autonomy.Launcher.Shell

  # Build a job without touching Application env; launcher.enable? reads env+config.
  defp job(task, opts \\ []) do
    {:ok, job} =
      Job.from_config(%{
        name: :launch_test,
        interval_ms: 1_000,
        title: "Launch",
        task: task,
        launcher: %{
          adapter: :shell,
          command: Keyword.get(opts, :command, "echo"),
          args: Keyword.get(opts, :args, [:task]),
          timeout_ms: Keyword.get(opts, :timeout_ms)
        }
      })

    job
  end

  describe "run/1 gating" do
    test "returns {:error, :shell_not_allowed} when shell launching is disabled" do
      restore_env(fn ->
        System.delete_env("CK_AUTONOMY_ALLOW_SHELL")

        prev = Application.get_env(:controlkeel, :autonomy, [])
        Application.put_env(:controlkeel, :autonomy, Keyword.put(prev, :allow_shell, false))

        assert {:error, :shell_not_allowed} = Shell.run(job("hello"))
      end)
    end
  end

  describe "run/1 argv substitution" do
    test "substitutes :task as a single argv element via System.cmd (no shell)" do
      with_shell_enabled(fn ->
        # `echo` prints its args joined by spaces; we assert the task text appears
        # verbatim, proving it was passed as an argv element rather than shell-parsed.
        task = "Triage open tickets; rm -rf / && whoami"
        assert {:ok, %{exit_status: 0, output: output}} = Shell.run(job(task))
        assert output =~ "Triage open tickets"
        # The literal `&&` survives because it never reached a shell.
        assert output =~ "&&"
      end)
    end

    test "captures non-zero exit status instead of raising" do
      with_shell_enabled(fn ->
        # `false` always exits 1.
        {:ok, j} =
          Job.from_config(%{
            name: :failing,
            interval_ms: 1,
            title: "F",
            task: "ignored",
            launcher: %{adapter: :shell, command: "sh", args: ["-c", "exit 3"]}
          })

        assert {:ok, %{exit_status: 3}} = Shell.run(j)
      end)
    end

    test "truncates large output" do
      with_shell_enabled(fn ->
        {:ok, j} =
          Job.from_config(%{
            name: :noisy,
            interval_ms: 1,
            title: "N",
            task: "ignored",
            launcher: %{
              adapter: :shell,
              command: "sh",
              args: ["-c", "printf 'x%.0s' $(seq 1 20000)"]
            }
          })

        assert {:ok, %{output: output}} = Shell.run(j)
        assert byte_size(output) <= 8_192
      end)
    end

    test "returns valid UTF-8 when command output contains invalid bytes" do
      with_shell_enabled(fn ->
        assert {:ok, %{output: output}} =
                 Shell.run(job("ignored", command: "sh", args: ["-c", "printf '\\377'"]))

        assert String.valid?(output)
      end)
    end

    test "terminates a launcher that exceeds its timeout" do
      with_shell_enabled(fn ->
        assert {:error, {:launch_timeout, 20}} =
                 Shell.run(
                   job("ignored",
                     command: "sh",
                     args: ["-c", "sleep 2"],
                     timeout_ms: 20
                   )
                 )
      end)
    end

    test "timeout terminates descendant processes in the launch process group" do
      with_shell_enabled(fn ->
        pid_file =
          Path.join(
            System.tmp_dir!(),
            "controlkeel-launch-child-#{System.unique_integer([:positive])}.pid"
          )

        on_exit(fn -> File.rm(pid_file) end)

        script = "sleep 30 & echo $! > #{pid_file}; wait"

        assert {:error, {:launch_timeout, 200}} =
                 Shell.run(
                   job("ignored",
                     command: "sh",
                     args: ["-c", script],
                     timeout_ms: 200
                   )
                 )

        child_pid = pid_file |> File.read!() |> String.trim()
        refute process_running?(child_pid)
      end)
    end
  end

  describe "run/1 missing program" do
    test "returns {:error, {:launch_failed, :enoent}} for a missing binary" do
      with_shell_enabled(fn ->
        {:ok, j} =
          Job.from_config(%{
            name: :missing,
            interval_ms: 1,
            title: "M",
            task: "ignored",
            launcher: %{adapter: :shell, command: "this-binary-does-not-exist-xyz", args: [:task]}
          })

        assert {:error, {:launch_failed, :enoent}} = Shell.run(j)
      end)
    end
  end

  defp with_shell_enabled(fun) do
    restore_env(fn ->
      System.put_env("CK_AUTONOMY_ALLOW_SHELL", "1")
      fun.()
    end)
  end

  defp process_running?(pid) do
    {_output, status} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)

    status == 0 and proc_state(pid) not in ["Z", "X"]
  end

  defp proc_state(pid) do
    with {:ok, stat} <- File.read("/proc/#{pid}/stat"),
         [_, state] <- Regex.run(~r/^\d+ \(.*\) ([A-Z]) /, stat) do
      state
    else
      _ -> nil
    end
  end

  defp restore_env(fun) do
    prev_env = System.get_env("CK_AUTONOMY_ALLOW_SHELL")
    prev_cfg = Application.get_env(:controlkeel, :autonomy, [])

    try do
      fun.()
    after
      if prev_env,
        do: System.put_env("CK_AUTONOMY_ALLOW_SHELL", prev_env),
        else: System.delete_env("CK_AUTONOMY_ALLOW_SHELL")

      Application.put_env(:controlkeel, :autonomy, prev_cfg)
    end
  end
end
