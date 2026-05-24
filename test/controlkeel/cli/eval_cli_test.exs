defmodule ControlKeel.CLI.EvalTest do
  use ExUnit.Case, async: false

  alias ControlKeel.CLI

  describe "eval list" do
    test "lists available suites" do
      assert {:ok, lines} =
               CLI.run_command(%{command: :eval_list, options: %{}, args: []}, File.cwd!())

      assert Enum.any?(lines, &(&1 =~ "Eval suites:"))
      assert Enum.any?(lines, &(&1 =~ "governance-regression"))
    end
  end

  describe "eval run" do
    test "returns OK when the default suite passes" do
      assert {:ok, lines} =
               CLI.run_command(%{command: :eval_run, options: %{}, args: []}, File.cwd!())

      assert Enum.any?(lines, &(&1 =~ "Eval suite:"))
      assert Enum.any?(lines, &(&1 =~ "Failed: 0"))
      refute Enum.any?(lines, &(&1 =~ "[FAIL]"))
    end

    test "errors clearly for an unknown suite" do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :eval_run, options: %{suite: "nope-not-real"}, args: []},
                 File.cwd!()
               )

      assert msg =~ "Unknown eval suite"
    end
  end

  describe "CLI.parse/1" do
    test "parses eval run" do
      assert {:ok, parsed} = CLI.parse(["eval", "run"])
      assert parsed.command == :eval_run
    end

    test "parses eval list" do
      assert {:ok, parsed} = CLI.parse(["eval", "list"])
      assert parsed.command == :eval_list
    end
  end
end
