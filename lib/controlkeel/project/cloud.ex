defmodule ControlKeel.Project.Cloud do
  @moduledoc false

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Project.Binding
  alias ControlKeel.Project.Local
  alias ControlKeel.Project.Root

  def init(attrs, project_root \\ File.cwd!()) when is_map(attrs) do
    root = Root.resolve(project_root)

    case Binding.read(root) do
      {:ok, binding} ->
        case Mission.get_session(binding["session_id"]) do
          nil -> create_and_bind(attrs, root)
          _session -> {:ok, binding, :existing}
        end

      {:error, :not_found} ->
        create_and_bind(attrs, root)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_and_bind(attrs, root) do
    with :ok <- validate_targeting(attrs),
         {:ok, org} <- resolve_org(attrs),
         {:ok, workspace} <- resolve_workspace(org, attrs),
         launch_attrs <- Local.default_init_attrs(root, attrs),
         launch_attrs <- Map.put(launch_attrs, "workspace_id", workspace.id),
         {:ok, session} <- Mission.create_launch(launch_attrs),
         :ok <- Binding.ensure_gitignore(root),
         :ok <- Binding.ensure_mcp_wrapper(root),
         {:ok, binding} <-
           Binding.write(
             %{
               "workspace_id" => session.workspace_id,
               "session_id" => session.id,
               "org_id" => workspace.org_id,
               "agent" => Map.get(launch_attrs, "agent", "claude"),
               "attached_agents" => %{}
             },
             root
           ),
         {:ok, _updated_session} <-
           Mission.attach_session_runtime_context(session.id, %{"project_root" => root}) do
      {:ok, binding, :created}
    end
  end

  defp validate_targeting(attrs) do
    workspace = trimmed(Map.get(attrs, "workspace")) != nil
    org = trimmed(Map.get(attrs, "org")) != nil

    cond do
      workspace and not org ->
        {:error, {:workspace_without_org}}

      true ->
        :ok
    end
  end

  defp resolve_org(attrs) do
    case trimmed(Map.get(attrs, "org")) do
      nil ->
        prompt_org()

      slug ->
        case Accounts.get_org_by_slug(slug) do
          nil ->
            {:error, {:org_not_found, slug, org_slugs()}}

          org ->
            {:ok, org}
        end
    end
  end

  defp resolve_workspace(org, attrs) do
    cond do
      slug = trimmed(Map.get(attrs, "workspace")) ->
        find_workspace_in_org(org, slug)

      true ->
        resolve_or_prompt_default_workspace(org)
    end
  end

  @default_workspace_slug "default-workspace"

  defp resolve_or_prompt_default_workspace(org) do
    case find_workspace_in_org(org, @default_workspace_slug) do
      {:ok, workspace} -> {:ok, workspace}
      _ -> prompt_workspace(org)
    end
  end

  defp find_workspace_in_org(org, slug) do
    workspaces = Mission.list_workspaces_for_org(org.id)

    case Enum.find(workspaces, &(&1.slug == String.downcase(slug))) do
      nil -> {:error, {:workspace_not_found, org.slug, slug, Enum.map(workspaces, & &1.slug)}}
      workspace -> {:ok, workspace}
    end
  end

  defp prompt_org do
    orgs = Accounts.list_orgs()

    case choose(
           "Select an organization",
           orgs,
           &"#{&1.slug} (#{&1.name})"
         ) do
      {:ok, org} -> {:ok, org}
      :cancelled -> {:error, :init_cancelled}
    end
  end

  defp prompt_workspace(org) do
    workspaces = Mission.list_workspaces_for_org(org.id)

    case workspaces do
      [] ->
        {:error, {:no_workspaces, org.slug, workspace_hint()}}

      _ ->
        case choose(
               "Select a workspace under #{org.slug}",
               workspaces,
               &"#{&1.slug} (#{&1.name})"
             ) do
          {:ok, workspace} -> {:ok, workspace}
          :cancelled -> {:error, :init_cancelled}
        end
    end
  end

  defp choose(title, items, label) do
    chooser = Application.get_env(:controlkeel, :cloud_init_chooser, &default_chooser/3)
    chooser.(title, items, label)
  end

  defp default_chooser(title, items, label) do
    IO.puts(title)
    Enum.with_index(items, 1)
    |> Enum.each(fn {item, i} -> IO.puts("  #{i}. #{label.(item)}") end)
    IO.write("Enter a number (blank to cancel): ")

    case IO.gets("") do
      :eof ->
        :cancelled

      {:error, _reason} ->
        :cancelled

      input ->
        case Integer.parse(String.trim(input)) do
          {n, ""} when n >= 1 and n <= length(items) ->
            case Enum.at(items, n - 1) do
              nil -> :cancelled
              item -> {:ok, item}
            end

          _ ->
            :cancelled
        end
    end
  end

  defp workspace_hint, do: "pass --workspace <slug>"

  defp org_slugs, do: Enum.map(Accounts.list_orgs(), & &1.slug)

  @doc false
  def error_message({:org_not_found, slug, available}) do
    base = "Organization \"#{slug}\" not found. Available orgs: #{format_list(available)}."
    if available == [], do: "Organization \"#{slug}\" not found. Create an organization first.", else: base
  end

  @doc false
  def error_message({:workspace_not_found, org_slug, slug, available}) do
    "Workspace \"#{slug}\" not found under organization \"#{org_slug}\". " <>
      "Available workspaces: #{format_list(available)}."
  end

  @doc false
  def error_message({:no_workspaces, org_slug, hint}) do
    "Organization \"#{org_slug}\" has no workspaces. #{String.capitalize(hint)}."
  end

  @doc false
  def error_message({:workspace_without_org}) do
    "--workspace requires --org: pass --org <slug> to select the organization " <>
      "that owns the target workspace."
  end

  @doc false
  def error_message(:init_cancelled), do: "Initialization cancelled."

  @doc false
  def error_message(reason), do: inspect(reason)

  defp format_list([]), do: "none"

  defp format_list(items) do
    items |> Enum.join(", ")
  end

  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed(_value), do: nil
end