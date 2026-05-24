defmodule ControlKeel.Cloud.RunPackage do
  @moduledoc """
  Persisted handoff packet for one cloud-agent task run.

  Captures everything a downstream cloud runtime (Devin, Open SWE, Cursor Cloud
  Agents, Replit Agent, Warp Oz, Executor, Virtual Bash, Cloudflare Workers,
  or an enterprise internal agent) needs to execute the task and call back:

    - which task / session / workspace this maps to
    - which runtime is supposed to execute it
    - the allocated budget cap (cents) and the granted scopes
    - any proof references the runtime should treat as evidence (not authority)
    - a single-use callback token (stored hashed) the runtime presents to
      authenticate callbacks
    - lifecycle status and the eventual result / error summary

  Per the roadmap's round-trip handoff model:

      local session → handoff packet → cloud runtime → status events →
      result + proof bundle hash → local session resumes
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task, Workspace}

  @valid_statuses ~w(pending dispatched in_progress completed failed cancelled)
  @valid_runtimes ~w(
    devin
    open-swe
    cursor-cloud-agents
    replit-agent
    warp-oz
    executor
    virtual-bash
    cloudflare-workers
    codex-app-server
    enterprise-internal
  )

  @primary_key {:id, :id, autogenerate: true}
  schema "cloud_run_packages" do
    field :runtime_target, :string
    field :status, :string, default: "pending"
    field :callback_token_hash, :string
    field :scopes, :string
    field :budget_cents_allocated, :integer, default: 0
    field :proof_refs, :string
    field :payload, :map, default: %{}
    field :result_summary, :string
    field :error_summary, :string
    field :dispatched_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :session, Session
    belongs_to :task, Task
    # Org context comes through workspace; surfaced via association for convenience.
    field :org_id, :integer, virtual: true
    timestamps(type: :utc_datetime)
  end

  @required ~w(workspace_id runtime_target status callback_token_hash budget_cents_allocated)a

  def changeset(package, attrs) do
    package
    |> cast(attrs, [
      :workspace_id,
      :session_id,
      :task_id,
      :runtime_target,
      :status,
      :callback_token_hash,
      :scopes,
      :budget_cents_allocated,
      :proof_refs,
      :payload,
      :result_summary,
      :error_summary,
      :dispatched_at,
      :completed_at
    ])
    |> validate_required(@required)
    |> validate_inclusion(:runtime_target, @valid_runtimes)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:budget_cents_allocated, greater_than_or_equal_to: 0)
    |> assoc_constraint(:workspace)
    |> unique_constraint(:callback_token_hash)
  end

  @doc "All recognised runtime target ids."
  def valid_runtimes, do: @valid_runtimes

  @doc "All recognised status values."
  def valid_statuses, do: @valid_statuses

  @doc "Terminal statuses — package is done and cannot transition further."
  def terminal_statuses, do: ~w(completed failed cancelled)

  @doc "True when the package has reached a terminal state."
  def terminal?(%__MODULE__{status: status}), do: status in terminal_statuses()
end
