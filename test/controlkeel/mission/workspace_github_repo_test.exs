defmodule ControlKeel.Mission.WorkspaceGithubRepoTest do
  @moduledoc """
  Covers CK-CLOUD-GIT-001 at the Mission API layer: workspace ↔ GitHub
  repo bindings (bind, unbind, list, uniqueness, validation).
  """

  use ControlKeel.DataCase, async: false

  alias ControlKeel.Mission
  alias ControlKeel.MissionFixtures

  describe "bind_github_repo/4" do
    test "binds with required fields only" do
      ws = MissionFixtures.workspace_fixture()

      assert {:ok, binding} = Mission.bind_github_repo(ws.id, "acme", "widget")
      assert binding.workspace_id == ws.id
      assert binding.owner == "acme"
      assert binding.repo == "widget"
      assert binding.default_branch == nil
      assert binding.installation_id == nil
    end

    test "binds with default_branch and installation_id" do
      ws = MissionFixtures.workspace_fixture()

      assert {:ok, binding} =
               Mission.bind_github_repo(ws.id, "acme", "widget",
                 default_branch: "main",
                 installation_id: "12345"
               )

      assert binding.default_branch == "main"
      assert binding.installation_id == "12345"
    end

    test "rejects malformed owner" do
      ws = MissionFixtures.workspace_fixture()

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Mission.bind_github_repo(ws.id, "bad owner!", "widget")

      assert Enum.any?(errors, fn {field, _} -> field == :owner end)
    end

    test "rejects duplicate binding for the same (workspace, owner, repo)" do
      ws = MissionFixtures.workspace_fixture()

      assert {:ok, _} = Mission.bind_github_repo(ws.id, "acme", "widget")

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Mission.bind_github_repo(ws.id, "acme", "widget")

      assert Enum.any?(errors, fn {field, _} -> field == :workspace_id end)
    end

    test "the same repo can be bound to two different workspaces" do
      ws_a =
        MissionFixtures.workspace_fixture(%{slug: "ws-a-#{System.unique_integer([:positive])}"})

      ws_b =
        MissionFixtures.workspace_fixture(%{slug: "ws-b-#{System.unique_integer([:positive])}"})

      assert {:ok, _} = Mission.bind_github_repo(ws_a.id, "acme", "widget")
      assert {:ok, _} = Mission.bind_github_repo(ws_b.id, "acme", "widget")
    end
  end

  describe "unbind_github_repo/3" do
    test "removes an existing binding" do
      ws = MissionFixtures.workspace_fixture()
      {:ok, _} = Mission.bind_github_repo(ws.id, "acme", "widget")

      assert {:ok, _} = Mission.unbind_github_repo(ws.id, "acme", "widget")
      assert Mission.list_github_repos(ws.id) == []
    end

    test "returns :not_found when binding does not exist" do
      ws = MissionFixtures.workspace_fixture()
      assert {:error, :not_found} = Mission.unbind_github_repo(ws.id, "acme", "absent")
    end
  end

  describe "list_github_repos/1" do
    test "returns all bindings sorted by owner/repo" do
      ws = MissionFixtures.workspace_fixture()

      Mission.bind_github_repo(ws.id, "zebra", "tail")
      Mission.bind_github_repo(ws.id, "alpha", "head")
      Mission.bind_github_repo(ws.id, "alpha", "body")

      result = Mission.list_github_repos(ws.id)

      assert Enum.map(result, &{&1.owner, &1.repo}) == [
               {"alpha", "body"},
               {"alpha", "head"},
               {"zebra", "tail"}
             ]
    end

    test "scopes to a single workspace" do
      ws_a =
        MissionFixtures.workspace_fixture(%{slug: "ws-c-#{System.unique_integer([:positive])}"})

      ws_b =
        MissionFixtures.workspace_fixture(%{slug: "ws-d-#{System.unique_integer([:positive])}"})

      Mission.bind_github_repo(ws_a.id, "acme", "widget")
      Mission.bind_github_repo(ws_b.id, "other", "thing")

      assert [a] = Mission.list_github_repos(ws_a.id)
      assert a.owner == "acme"
      assert [b] = Mission.list_github_repos(ws_b.id)
      assert b.owner == "other"
    end
  end
end
