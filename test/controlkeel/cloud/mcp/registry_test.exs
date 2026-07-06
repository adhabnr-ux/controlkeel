defmodule ControlKeel.Cloud.Mcp.RegistryTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.Mcp.Registry

  setup do
    previous = Application.get_env(:controlkeel, :cloud_mcp_registry)
    Application.delete_env(:controlkeel, :cloud_mcp_registry)

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :cloud_mcp_registry, previous)
      else
        Application.delete_env(:controlkeel, :cloud_mcp_registry)
      end
    end)

    :ok
  end

  describe "lookup/2 with no registry configured" do
    test "unknown server is denied by default" do
      assert {:denied, :default_deny} = Registry.lookup("anything")
    end
  end

  describe "lookup/2 deny-list precedence" do
    setup do
      Application.put_env(:controlkeel, :cloud_mcp_registry, %{
        default_policy: :allow_unrestricted,
        allowlist: [%{name: "vendor-a", attestation: :optional}],
        denylist: ["vendor-a", "smithery-public"]
      })

      :ok
    end

    test "denylist beats allowlist" do
      assert {:denied, :explicit_deny} = Registry.lookup("vendor-a")
    end

    test "denied server stays denied even with default allow_unrestricted" do
      assert {:denied, :explicit_deny} = Registry.lookup("smithery-public")
    end

    test "default policy applies to unlisted servers" do
      assert :allowed = Registry.lookup("anything-else")
    end
  end

  describe "lookup/2 attestation gating" do
    setup do
      Application.put_env(:controlkeel, :cloud_mcp_registry, %{
        default_policy: :deny,
        allowlist: [
          %{name: "must-attest", attestation: :required},
          %{name: "optional-attest", attestation: :optional}
        ]
      })

      :ok
    end

    test "required attestation: denied without proof" do
      assert {:denied, :attestation_required} = Registry.lookup("must-attest")
    end

    test "required attestation: allowed with proof" do
      assert :allowed = Registry.lookup("must-attest", attested?: true)
    end

    test "optional attestation: allowed without proof" do
      assert :allowed = Registry.lookup("optional-attest")
    end
  end

  describe "default_policy :allow_with_attestation" do
    setup do
      Application.put_env(:controlkeel, :cloud_mcp_registry, %{
        default_policy: :allow_with_attestation
      })

      :ok
    end

    test "unknown server denied without attestation" do
      assert {:denied, :attestation_required} = Registry.lookup("anything")
    end

    test "unknown server allowed with attestation" do
      assert :allowed = Registry.lookup("anything", attested?: true)
    end
  end

  describe "entries/0 and denylist/0" do
    test "normalizes entries and exposes denylist" do
      Application.put_env(:controlkeel, :cloud_mcp_registry, %{
        allowlist: [
          %{name: "a", attestation: :required, url: "https://a"},
          "b-shorthand"
        ],
        denylist: [:bad, "evil"]
      })

      entries = Registry.entries()
      assert Enum.find(entries, &(&1.name == "a")).attestation == :required
      assert Enum.find(entries, &(&1.name == "b-shorthand")).attestation == :not_required
      assert Registry.denylist() == ["bad", "evil"]
    end
  end

  describe "summary/0" do
    test "counts entries by category" do
      Application.put_env(:controlkeel, :cloud_mcp_registry, %{
        default_policy: :allow_with_attestation,
        allowlist: [
          %{name: "a", attestation: :required},
          %{name: "b", attestation: :optional},
          %{name: "c", attestation: :required}
        ],
        denylist: ["d", "e"]
      })

      assert Registry.summary() == %{
               allowlist_count: 3,
               denylist_count: 2,
               requires_attestation: 2,
               default_policy: :allow_with_attestation
             }
    end
  end
end
