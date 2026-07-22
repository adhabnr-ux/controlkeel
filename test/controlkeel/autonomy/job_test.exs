defmodule ControlKeel.Autonomy.JobTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Autonomy.Job

  describe "from_config/1" do
    test "parses a valid map config" do
      assert {:ok, %Job{} = job} =
               Job.from_config(%{
                 name: :daily_triage,
                 interval_ms: :timer.hours(6),
                 title: "Triage",
                 task: "Triage open tickets.",
                 agent: :opencode,
                 launcher: %{adapter: :shell, command: "opencode", args: ["run", :task]}
               })

      assert job.name == :daily_triage
      assert job.interval_ms == 21_600_000
      assert job.agent == :opencode
      assert job.launcher.command == "opencode"
      assert job.launcher.args == ["run", :task]
    end

    test "parses a keyword-list config and string name" do
      assert {:ok, %Job{name: :nightly}} =
               Job.from_config(
                 name: "nightly",
                 interval_ms: 60_000,
                 title: "Nightly",
                 task: "Run nightly."
               )
    end

    test "accepts a job with no launcher (default safe dispatch)" do
      assert {:ok, %Job{launcher: nil}} =
               Job.from_config(%{
                 name: :bare,
                 interval_ms: 1_000,
                 title: "Bare",
                 task: "Do a thing."
               })
    end

    test "rejects missing required fields" do
      assert {:error, {:missing, :name}} =
               Job.from_config(%{interval_ms: 1, title: "x", task: "y"})

      assert {:error, {:missing, :interval_ms}} =
               Job.from_config(%{name: :a, title: "x", task: "y"})

      assert {:error, {:missing, :title}} =
               Job.from_config(%{name: :a, interval_ms: 1, task: "y"})

      assert {:error, {:missing, :task}} =
               Job.from_config(%{name: :a, interval_ms: 1, title: "x"})
    end

    test "rejects non-positive interval_ms" do
      assert {:error, {:invalid_interval_ms, 0}} =
               Job.from_config(%{name: :a, interval_ms: 0, title: "x", task: "y"})

      assert {:error, {:invalid_interval_ms, -1}} =
               Job.from_config(%{name: :a, interval_ms: -1, title: "x", task: "y"})
    end

    test "rejects blank strings" do
      assert {:error, {:invalid, :title, ""}} =
               Job.from_config(%{name: :a, interval_ms: 1, title: "", task: "y"})
    end
  end

  describe "launcher validation" do
    test "accepts args with or without the :task placeholder" do
      # The task text only ever enters argv via :task (as a discrete element);
      # a launcher may legitimately run a fixed command with no task input.
      assert {:ok, _} =
               Job.from_config(%{
                 name: :a,
                 interval_ms: 1,
                 title: "x",
                 task: "y",
                 launcher: %{adapter: :shell, command: "opencode", args: ["run", :task]}
               })

      assert {:ok, _} =
               Job.from_config(%{
                 name: :b,
                 interval_ms: 1,
                 title: "x",
                 task: "y",
                 launcher: %{adapter: :shell, command: "bin/maintenance", args: ["--quiet"]}
               })
    end

    test "rejects unknown launcher adapters" do
      assert {:error, {:unknown_launcher, _}} =
               Job.from_config(%{
                 name: :a,
                 interval_ms: 1,
                 title: "x",
                 task: "y",
                 launcher: %{adapter: :kubernetes, command: "x", args: [:task]}
               })
    end

    test "rejects missing command or empty args" do
      assert {:error, {:invalid_launcher, :command}} =
               Job.from_config(%{
                 name: :a,
                 interval_ms: 1,
                 title: "x",
                 task: "y",
                 launcher: %{adapter: :shell, command: "", args: [:task]}
               })

      assert {:error, {:invalid_launcher, :args}} =
               Job.from_config(%{
                 name: :a,
                 interval_ms: 1,
                 title: "x",
                 task: "y",
                 launcher: %{adapter: :shell, command: "opencode", args: []}
               })
    end
  end

  describe "from_config_all/1" do
    test "parses multiple jobs preserving order" do
      configs = [
        %{name: :a, interval_ms: 1_000, title: "A", task: "ta"},
        %{name: :b, interval_ms: 2_000, title: "B", task: "tb"}
      ]

      assert {:ok, [%Job{name: :a}, %Job{name: :b}]} = Job.from_config_all(configs)
    end

    test "rejects duplicate names" do
      configs = [
        %{name: :dup, interval_ms: 1_000, title: "A", task: "ta"},
        %{name: :dup, interval_ms: 2_000, title: "B", task: "tb"}
      ]

      assert {:error, {:duplicate_name, :dup}} = Job.from_config_all(configs)
    end

    test "returns [] for empty list" do
      assert {:ok, []} = Job.from_config_all([])
    end

    test "propagates parse errors" do
      assert {:error, {:missing, :name}} =
               Job.from_config_all([%{interval_ms: 1, title: "x", task: "y"}])
    end
  end

  describe "launcher?/1" do
    test "true when a launcher is configured" do
      {:ok, job} =
        Job.from_config(%{
          name: :a,
          interval_ms: 1,
          title: "x",
          task: "y",
          launcher: %{adapter: :shell, command: "x", args: [:task]}
        })

      assert Job.launcher?(job)
    end

    test "false when no launcher" do
      {:ok, job} = Job.from_config(%{name: :a, interval_ms: 1, title: "x", task: "y"})
      refute Job.launcher?(job)
    end
  end
end
