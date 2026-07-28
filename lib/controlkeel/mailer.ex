defmodule ControlKeel.Mailer do
  @moduledoc """
  Mail delivery for ControlKeel.

  Currently supports two adapters:

    * `:log`  — write a single-line JSON entry via Logger. Default in dev/prod
      until P4 ships an SMTP / SaaS-provider adapter.
    * `:test` — push the payload to `ControlKeel.Mailer.TestInbox` (an Agent)
      so tests can assert deliveries.

  Future `:http` adapter will POST to a configured relay (SendGrid, Postmark,
  AWS SES, in-org SMTP gateway). That decision is deferred to P4.

  ## Usage

      Mailer.deliver_invitation(%{email: "x@y"}, "raw_token_string")

  Returns `:ok` or `{:error, term}`. Callers should NOT fail their flow if
  delivery fails — the raw invitation token is also surfaced in the UI so
  the operator can copy/paste as a fallback.
  """

  require Logger

  alias ControlKeel.Mailer.TestInbox

  @doc """
  Deliver an invitation email payload.

  `recipient` is anything that has an `:email` field (a `User` struct or a
  plain map). `raw_token` is the invitation token returned from
  `Accounts.invite_member/3`.
  """
  @spec deliver_invitation(map(), String.t()) :: :ok | {:error, term()}
  def deliver_invitation(%{email: email}, raw_token)
      when is_binary(email) and is_binary(raw_token) do
    payload = %{
      to: email,
      token: raw_token,
      url: "/invitations/" <> raw_token
    }

    deliver(adapter(), :invitation, payload)
  end

  def deliver_invitation(_recipient, _token), do: {:error, :invalid_recipient}

  defp adapter, do: Application.get_env(:controlkeel, :mailer_adapter, :log)

  # ── Adapter dispatch ───────────────────────────────────────────────

  defp deliver(:test, kind, payload), do: TestInbox.put(kind, payload)

  defp deliver(:log, kind, payload) do
    Logger.info("[mailer] #{kind} #{Jason.encode!(payload)}")
    :ok
  end

  defp deliver(other, _kind, _payload), do: {:error, {:unsupported_mailer, other}}
end
