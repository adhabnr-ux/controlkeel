defmodule ControlKeelWeb.SignupLive do
  @moduledoc """
  Self-serve org signup at `/signup`.

  Creates a new Org + initial admin User + active owner Membership atomically.
  On success, mints a signed completion token via `AuthController.sign_completion_token/2`
  and redirects to `/auth/complete/:token` so the controller can set session keys.

  ## Local-mode guard

  In `:local` runtime mode, signup makes no sense (single-user, no orgs).
  The page renders a polite redirect instead.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.{Membership, Org, User}
  alias ControlKeel.Repo
  alias ControlKeel.RuntimeMode
  alias ControlKeelWeb.AuthController

  alias Ecto.Multi

  @impl true
  def mount(_params, _session, socket) do
    case RuntimeMode.current() do
      :local ->
        {:ok,
         socket
         |> assign(:page_title, "Signup")
         |> assign(:mode, :local)}

      _mode ->
        {:ok,
         socket
         |> assign(:page_title, "Create your organization")
         |> assign(:mode, :cloud)
         |> assign(:form, to_form(empty_params(), as: :signup))
         |> assign(:errors, [])}
    end
  end

  @impl true
  def handle_event("submit", %{"signup" => params}, %{assigns: %{mode: :cloud}} = socket) do
    case do_signup(params) do
      {:ok, %{user: user, org: org}} ->
        token = AuthController.sign_completion_token(user.id, org.id)
        {:noreply, redirect(socket, to: ~p"/auth/complete/#{token}")}

      {:error, errors} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :signup))
         |> assign(:errors, errors)}
    end
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  @impl true
  def render(%{mode: :local} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 480px; margin: 6rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Local mode</p>
            <h1 class="ck-section-title">Signup is for cloud deployments</h1>
            <p class="ck-lead ck-lead-tight">
              You're running ControlKeel locally. There's no signup needed — your single workspace is already governed.
            </p>
          </div>
        </div>
        <div class="ck-card mt-6">
          <p>
            To use cloud mode, set <code>CONTROLKEEL_RUNTIME_MODE=cloud</code>
            and configure <code>:cloud_sync_endpoint</code>
            in your release.
          </p>
          <.link navigate={~p"/"} class="ck-btn ck-btn-secondary mt-4">Back to dashboard</.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(%{mode: :cloud} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 560px; margin: 4rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">ControlKeel Cloud</p>
            <h1 class="ck-section-title">Create your organization</h1>
            <p class="ck-lead ck-lead-tight">
              You'll be the first owner. After signup, configure your SSO provider so teammates can join.
            </p>
          </div>
        </div>

        <.form for={@form} phx-submit="submit" class="mt-6 flex flex-col gap-4">
          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Your email</label>
            <input
              type="email"
              name="signup[email]"
              value={@form[:email].value || ""}
              required
              autocomplete="email"
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2.5 text-white placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-lime-300"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Your name</label>
            <input
              type="text"
              name="signup[name]"
              value={@form[:name].value || ""}
              autocomplete="name"
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2.5 text-white placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-lime-300"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Organization name</label>
            <input
              type="text"
              name="signup[org_name]"
              value={@form[:org_name].value || ""}
              required
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2.5 text-white placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-lime-300"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Organization slug</label>
            <input
              type="text"
              name="signup[org_slug]"
              value={@form[:org_slug].value || ""}
              required
              pattern="[a-z0-9][a-z0-9\-]*"
              placeholder="acme"
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2.5 text-white placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-lime-300"
            />
            <p class="mt-1 text-xs text-zinc-500">
              Lowercase letters, numbers, and dashes only. This becomes your sign-in identifier.
            </p>
          </div>

          <%= if @errors != [] do %>
            <div class="rounded-lg border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
              <ul class="list-disc pl-5">
                <%= for {field, msg} <- @errors do %>
                  <li><strong>{field}:</strong> {msg}</li>
                <% end %>
              </ul>
            </div>
          <% end %>

          <button
            type="submit"
            class="rounded-lg bg-lime-300 px-5 py-2.5 text-sm font-semibold text-zinc-950 hover:bg-lime-200 transition"
          >
            Create organization
          </button>
        </.form>

        <p class="mt-8 text-sm text-zinc-500">
          Already have an account?
          <.link navigate={~p"/auth/login"} class="text-lime-300 hover:underline">Sign in</.link>
        </p>
      </section>
    </Layouts.app>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp do_signup(params) do
    email = params["email"] |> to_string() |> String.downcase() |> String.trim()
    name = params["name"] |> to_string() |> String.trim()
    org_name = params["org_name"] |> to_string() |> String.trim()
    org_slug = params["org_slug"] |> to_string() |> String.downcase() |> String.trim()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Pre-flight: surface friendly errors for existing email or slug.
    cond do
      email == "" or org_name == "" or org_slug == "" ->
        {:error, [{"form", "Email, organization name, and slug are required"}]}

      Accounts.get_user_by_email(email) != nil ->
        {:error, [{"email", "An account with this email already exists. Sign in instead."}]}

      Accounts.get_org_by_slug(org_slug) != nil ->
        {:error, [{"org_slug", "This slug is already taken. Choose another."}]}

      true ->
        run_signup_transaction(email, name, org_name, org_slug, now)
    end
  end

  defp run_signup_transaction(email, name, org_name, org_slug, now) do
    user_attrs = %{email: email, name: name, status: "active"}
    org_attrs = %{name: org_name, slug: org_slug, status: "active"}

    Multi.new()
    |> Multi.insert(:user, User.changeset(%User{}, user_attrs))
    |> Multi.insert(:org, Org.changeset(%Org{}, org_attrs))
    |> Multi.insert(:membership, fn %{user: user, org: org} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        org_id: org.id,
        role: "owner",
        status: "active",
        accepted_at: now
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, org: org}} ->
        {:ok, %{user: user, org: org}}

      {:error, step, %Ecto.Changeset{} = cs, _changes} ->
        {:error, format_changeset_errors(step, cs)}

      {:error, _step, reason, _changes} ->
        {:error, [{"form", inspect(reason)}]}
    end
  end

  defp format_changeset_errors(step, %Ecto.Changeset{errors: errors}) do
    Enum.map(errors, fn {field, {msg, _}} -> {"#{step}.#{field}", msg} end)
  end

  defp empty_params, do: %{"email" => "", "name" => "", "org_name" => "", "org_slug" => ""}
end
