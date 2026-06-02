defmodule ControlKeel.CLI.Dispatch.Review do
  @moduledoc false

  require Logger
  alias ControlKeel.ACPRegistry
  alias ControlKeel.AgentExecution
  alias ControlKeel.AgentIntegration
  alias ControlKeel.AgentRouter
  alias ControlKeel.AttachedAgentSync
  alias ControlKeel.Analytics
  alias ControlKeel.AutonomyLoop
  alias ControlKeel.Benchmark
  alias ControlKeel.Budget
  alias ControlKeel.Budget.CostOptimizer
  alias ControlKeel.ClaudeCLI
  alias ControlKeel.CodexConfig
  alias ControlKeel.Distribution
  alias ControlKeel.Deployment.Advisor
  alias ControlKeel.Deployment.HostingCost
  alias ControlKeel.Governance
  alias ControlKeel.Governance.AgentMonitor
  alias ControlKeel.Governance.CircuitBreaker
  alias ControlKeel.Governance.PreCommitHook
  alias ControlKeel.Governance.Socket, as: GovernanceSocket
  alias ControlKeel.CLI.Catalog
  alias ControlKeel.CLI.Parser
  alias ControlKeel.Help
  alias ControlKeel.Intent
  alias ControlKeel.Findings.PlainEnglish
  alias ControlKeel.Learning.OutcomeTracker
  alias ControlKeel.LocalProject
  alias ControlKeel.Memory
  alias ControlKeel.MCP.Tools.CkContext
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeel.Observability.Telemetry, as: ObservabilityTelemetry
  alias ControlKeel.Observability.Workshop, as: ObservabilityWorkshop
  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.Platform
  alias ControlKeel.ProviderBroker
  alias ControlKeel.ProviderConfig
  alias ControlKeel.ProtocolAccess
  alias ControlKeel.ProjectBinding
  alias ControlKeel.ProjectRoot
  alias ControlKeel.ReviewBridge
  alias ControlKeel.Updater
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.Proxy
  alias ControlKeel.RuntimePaths
  alias ControlKeel.SetupAdvisor
  alias ControlKeel.Skills
  alias ControlKeel.TaskAugmentation
  alias ControlKeel.WorkspaceContext
  alias ControlKeelWeb.Endpoint
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :review_diff, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, base_ref} <- required_option(options, :base, "--base"),
         {:ok, head_ref} <- required_option(options, :head, "--head"),
         {:ok, review} <-
           Governance.review_diff(
             base_ref,
             head_ref,
             governance_opts(options, root)
           ) do
      {:ok, review_lines(review, "merge")}
    end
  end

  def run_command(%{command: :review_pr, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, review} <- review_pr_input(options, root) do
      {:ok, review_lines(review, "merge")}
    end
  end

  def run_command(%{command: :review_socket, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, report} <- socket_report_input(options),
         {:ok, dependency_review} <- GovernanceSocket.dependency_review(report),
         {:ok, review} <-
           Governance.review_patch(
             "",
             governance_opts(options, root)
             |> Keyword.put(:dependency_review, dependency_review)
             |> Keyword.put(:source, "socket_review")
             |> Keyword.put(:phase, "dependency_review")
           ) do
      {:ok, review_lines(review, "dependency")}
    end
  end

  def run_command(%{command: :review_plan_submit, options: options}, project_root) do
    project_root = resolve_project_root(options, project_root)

    with {:ok, submission_body} <- review_submission_input(options),
         {:ok, attrs} <- review_submission_attrs(options, submission_body, project_root),
         {:ok, review} <- Mission.submit_review(attrs) do
      payload =
        review_cli_payload(review, %{
          "message" => "submitted",
          "browser_url" => review_url(review.id)
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Submitted plan review ##{review.id}.",
           "Status: #{review.status}",
           "Browser URL: #{review_url(review.id)}",
           "Execution gate: task remains blocked until the plan review is approved."
         ]}
      end
    else
      {:error, reason} ->
        cli_error("Failed to submit plan review", reason, options)
    end
  end

  def run_command(%{command: :review_plan_open, options: options}, _project_root) do
    with {:ok, review_id} <- required_integer_option(options, :id, "--id"),
         {:ok, review_open} <-
           ReviewBridge.open_review(review_id, auto_open: ReviewBridge.auto_open_reviews?()) do
      review = review_open.review

      payload =
        review_cli_payload(review, %{
          "message" => "open",
          "browser_url" => review_open.url,
          "browser_embed" => review_open.browser_embed,
          "open_target" => review_open.open_target,
          "remote" => review_open.remote,
          "opened" => review_open.opened,
          "open_error" => review_open.open_error,
          "server_serving" => review_open.server_serving,
          "server_status" => review_open.server_status,
          "server_error" => review_open.server_error
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Review ##{review.id}: #{review.title}",
           "Status: #{review.status}",
           "Type: #{review.review_type}",
           "Browser URL: #{review_open.url}",
           "Browser embed: #{review_open.browser_embed}"
         ] ++
           maybe_cli_line("Open target", review_open.open_target) ++
           maybe_cli_line("Review server serving", to_string(review_open.server_serving)) ++
           maybe_cli_line("Review server error", review_open.server_error) ++
           maybe_cli_line("Opened browser", to_string(review_open.opened)) ++
           maybe_cli_line("Open error", review_open.open_error) ++
           manual_approval_lines(review, review_open)}
      end
    else
      {:error, :not_found} ->
        cli_error("Review not found", :not_found, options)

      {:error, reason} ->
        cli_error("Failed to open plan review", reason, options)
    end
  end

  def run_command(%{command: :review_plan_wait, options: options}, _project_root) do
    with {:ok, review_id} <- required_integer_option(options, :id, "--id"),
         {:ok, review} <-
           ReviewBridge.wait_for_review(review_id,
             timeout_ms: (options[:timeout] || 120) * 1000,
             interval_ms: options[:interval_ms] || 1000
           ) do
      payload =
        review_cli_payload(review, %{
          "message" => "wait",
          "browser_url" => review_url(review.id)
        })

      case review.status do
        "approved" ->
          if options[:json] do
            {:ok, [Jason.encode!(payload)]}
          else
            {:ok,
             [
               "Plan review ##{review.id} approved.",
               "Status: #{review.status}",
               "Browser URL: #{review_url(review.id)}"
             ] ++ review_feedback_lines(review)}
          end

        "denied" ->
          cli_error(
            "Plan review ##{review.id} was denied",
            {:review_denied, review},
            options,
            payload
          )

        other ->
          cli_error(
            "Plan review ##{review.id} is still #{other}",
            {:review_pending, %{review_id: review.id, review_status: other}},
            options,
            payload
          )
      end
    else
      {:error, {:timeout, review}} ->
        payload =
          review_cli_payload(review, %{
            "message" => "timeout",
            "timed_out" => true,
            "status" => review.status,
            "browser_url" => review_url(review.id)
          })

        if review.status in ["pending", "superseded"] do
          if options[:json] do
            {:ok, [Jason.encode!(payload)]}
          else
            {:ok,
             [
               "Timed out waiting for plan review ##{review.id}.",
               "Status: #{review.status}",
               "Browser URL: #{review_url(review.id)}",
               "Review is still open; keep waiting or respond in browser."
             ]}
          end
        else
          cli_error(
            "Timed out waiting for plan review ##{review.id}",
            {:timeout, review},
            options,
            payload
          )
        end

      {:error, reason} ->
        cli_error("Failed while waiting for plan review", reason, options)
    end
  end

  def run_command(
        %{command: :review_plan_respond, args: [review_id], options: options},
        _project_root
      ) do
    with {:ok, parsed_id} <- parse_id(review_id),
         {:ok, decision} <- required_option(options, :decision, "--decision"),
         attrs <- review_response_attrs(options, decision),
         {:ok, review} <- Mission.respond_review(parsed_id, attrs) do
      payload =
        review_cli_payload(review, %{
          "message" => "responded",
          "browser_url" => review_url(review.id)
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Updated plan review ##{review.id}.",
           "Status: #{review.status}",
           "Browser URL: #{review_url(review.id)}"
         ]}
      end
    else
      {:error, :invalid_id} ->
        cli_error("Review id must be an integer", :invalid_id, options)

      {:error, reason} ->
        cli_error("Failed to respond to plan review", reason, options)
    end
  end
end
