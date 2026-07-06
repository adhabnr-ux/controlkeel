defmodule ControlKeel.CLI.AuditExportTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.CLI
  alias ControlKeel.MissionFixtures

  test "audit export --template soc2 prints mapped template JSON" do
    workspace =
      MissionFixtures.workspace_fixture(%{slug: "audit-#{System.unique_integer([:positive])}"})

    session = MissionFixtures.session_fixture(%{workspace: workspace})

    _finding =
      MissionFixtures.finding_fixture(%{session: session, severity: "high", category: "security"})

    assert {:ok, [json]} =
             CLI.run_command(
               %{
                 command: :audit_export,
                 options: %{workspace: workspace.slug, template: "soc2"},
                 args: []
               },
               File.cwd!()
             )

    decoded = Jason.decode!(json)
    assert decoded["template"] == "soc2"
    assert decoded["scope"] == %{"type" => "workspace", "id" => workspace.id}
    assert Enum.any?(decoded["sections"], &(&1["id"] == "CC9" and &1["evidence_count"] == 1))
  end

  test "audit export rejects unsupported template" do
    workspace =
      MissionFixtures.workspace_fixture(%{slug: "audit-#{System.unique_integer([:positive])}"})

    assert {:error, msg} =
             CLI.run_command(
               %{
                 command: :audit_export,
                 options: %{workspace: workspace.slug, template: "pci"},
                 args: []
               },
               File.cwd!()
             )

    assert msg =~ "--template"
    assert msg =~ "soc2"
    assert msg =~ "gdpr"
  end

  test "audit export --sign wraps template output in signed envelope" do
    env = "CK_TEST_AUDIT_SIGNING_KEY"
    System.put_env(env, "signing-key")
    on_exit(fn -> System.delete_env(env) end)

    workspace =
      MissionFixtures.workspace_fixture(%{slug: "audit-#{System.unique_integer([:positive])}"})

    session = MissionFixtures.session_fixture(%{workspace: workspace})

    _finding =
      MissionFixtures.finding_fixture(%{session: session, severity: "high", category: "security"})

    assert {:ok, [json]} =
             CLI.run_command(
               %{
                 command: :audit_export,
                 options: %{
                   workspace: workspace.slug,
                   template: "soc2",
                   sign: true,
                   signing_key_env: env
                 },
                 args: []
               },
               File.cwd!()
             )

    decoded = Jason.decode!(json)
    assert decoded["kind"] == "controlkeel.audit_export.signed"
    assert decoded["payload"]["template"] == "soc2"
    assert decoded["integrity"]["key_id"] == env
    assert :ok = ControlKeel.Cloud.Audit.ExportSigner.verify(decoded, "signing-key")
  end

  test "audit export --sign requires configured env var" do
    workspace =
      MissionFixtures.workspace_fixture(%{slug: "audit-#{System.unique_integer([:positive])}"})

    assert {:error, msg} =
             CLI.run_command(
               %{
                 command: :audit_export,
                 options: %{workspace: workspace.slug, sign: true},
                 args: []
               },
               File.cwd!()
             )

    assert msg =~ "--signing-key-env"

    assert {:error, msg} =
             CLI.run_command(
               %{
                 command: :audit_export,
                 options: %{workspace: workspace.slug, sign: true, signing_key_env: "NO_SUCH_KEY"},
                 args: []
               },
               File.cwd!()
             )

    assert msg =~ "NO_SUCH_KEY"
  end
end
