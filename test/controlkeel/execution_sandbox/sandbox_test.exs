defmodule ControlKeel.ExecutionSandboxTest do
  # async: false — these tests toggle the global CK_ENFORCE_SANDBOX env var.
  use ExUnit.Case, async: false

  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.ExecutionSandbox.Docker

  setup do
    System.delete_env("CK_ENFORCE_SANDBOX")
    on_exit(fn -> System.delete_env("CK_ENFORCE_SANDBOX") end)
    :ok
  end

  describe "adapter_name/1" do
    test "nil sandbox falls back to the configured default (local)" do
      assert ExecutionSandbox.adapter_name(sandbox: nil) == "local"
      assert ExecutionSandbox.adapter_name([]) == "local"
    end

    test "an explicit sandbox choice is honored" do
      assert ExecutionSandbox.adapter_name(sandbox: "docker") == "docker"
    end
  end

  describe "enforce_sandbox?/0" do
    test "is off by default and on via CK_ENFORCE_SANDBOX" do
      refute ExecutionSandbox.enforce_sandbox?()

      System.put_env("CK_ENFORCE_SANDBOX", "1")
      assert ExecutionSandbox.enforce_sandbox?()
    end
  end

  describe "run/3 host-execution guard" do
    test "blocks host (local) execution when enforce_sandbox is enabled" do
      System.put_env("CK_ENFORCE_SANDBOX", "1")

      assert {:error, {:blocked_by_policy, msg}} =
               ExecutionSandbox.run("echo", ["hi"], sandbox: "local")

      assert msg =~ "enforce_sandbox"
    end

    test "allows host execution with an explicit force override even when enforced" do
      System.put_env("CK_ENFORCE_SANDBOX", "1")

      assert {:ok, %{exit_status: 0, output: output}} =
               ExecutionSandbox.run("echo", ["forced"], sandbox: "local", force: true)

      assert output =~ "forced"
    end

    test "allows host execution by default when enforcement is off" do
      assert {:ok, %{exit_status: 0, output: output}} =
               ExecutionSandbox.run("echo", ["ok"], sandbox: "local")

      assert output =~ "ok"
    end
  end

  describe "strict adapter resolution" do
    test "refuses to fall back to host execution when an explicit non-local adapter is unavailable" do
      unless ControlKeel.ExecutionSandbox.E2B.available?() do
        assert {:error, {:sandbox_unavailable, msg}} =
                 ExecutionSandbox.run("echo", ["must-not-run-locally"], sandbox: "e2b")

        assert msg =~ "e2b"
        assert msg =~ "refusing to fall back"
      end
    end
  end

  describe "Docker.ensure_image_available/1 fail-fast" do
    test "returns an actionable :image_unavailable error for a missing image (or when docker is absent)" do
      assert {:error, {:image_unavailable, msg}} =
               Docker.run("echo", ["x"],
                 docker_image: "ghcr.io/controlkeel/definitely-not-real-xyz:latest"
               )

      assert is_binary(msg)
    end
  end
end
