defmodule ControlKeelWeb.DocsLive do
  @moduledoc """
  Public docs portal at `/docs`.

  Index lists all markdown docs from the `docs/` directory.
  Individual doc pages at `/docs/:name` render markdown to HTML.
  No auth required.
  """

  use ControlKeelWeb, :live_view

  @docs_dir_static Application.compile_env(:controlkeel, :docs_dir, nil)

  # Docs that are internal/admin-only and should not appear in the portal.
  @hidden_docs ~w(CLOUD_READINESS.md cloud-parity-matrix.md cloud-enterprise-roadmap.md cloud-execution-model.md TOKEN_OPTIMIZATION_GUIDE.md ADAPTIVE_TOOL_GROUPS.md agent-support-prd.md agent-support-requirements.md)

  defp docs_dir do
    @docs_dir_static ||
      # In dev/test, the docs/ dir is at the project root.
      # Walk up from the app priv dir to find it.
      [
        # Project root (dev + test)
        Path.join(File.cwd!(), "docs"),
        # Build dir fallback
        Path.join([Application.app_dir(:controlkeel), "..", "..", "..", "..", "docs"])
      ]
      |> Enum.find(&File.dir?/1)
      |> Kernel.||(
        raise "docs/ directory not found. Set :docs_dir in config."
      )
  end

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    case read_doc(name) do
      {:ok, title, html} ->
        {:ok,
         socket
         |> assign(:page_title, "#{title} — ControlKeel Docs")
         |> assign(:doc_name, name)
         |> assign(:doc_title, title)
         |> assign(:doc_html, html)
         |> assign(:live_action, :show)}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Document not found.")
         |> push_navigate(to: ~p"/docs")}
    end
  end

  def mount(_params, _session, socket) do
    docs = list_docs()
    {:ok, assign(socket, :page_title, "Docs — ControlKeel") |> assign(:docs, docs) |> assign(:live_action, :index)}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 800px; margin: 2rem auto;">
        <.link navigate={~p"/docs"} class="text-sm text-indigo-400 hover:text-indigo-300 mb-4 inline-block">
          ← All docs
        </.link>
        <h1 class="text-3xl font-bold text-white mb-8">{@doc_title}</h1>
        <div class="prose prose-invert max-w-none">
          <%= Phoenix.HTML.raw(@doc_html) %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 800px; margin: 4rem auto;">
        <h1 class="text-4xl font-bold text-white mb-2">Documentation</h1>
        <p class="text-lg text-zinc-400 mb-8">Everything you need to know about ControlKeel.</p>

        <div class="space-y-4">
          <%= for {name, title} <- @docs do %>
            <.link
              navigate={~p"/docs/#{name}"}
              class="block rounded-lg border border-white/10 bg-zinc-900 px-6 py-4 hover:border-white/20 transition-colors"
            >
              <h2 class="text-lg font-medium text-white">{title}</h2>
              <p class="text-sm text-zinc-500">{name}.md</p>
            </.link>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # ── Private ────────────────────────────────────────────────────────

  defp list_docs do
    docs_dir()
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.reject(&(&1 in @hidden_docs))
    |> Enum.sort()
    |> Enum.map(fn filename ->
      name = String.replace_suffix(filename, ".md", "")
      title = doc_title(name)
      {name, title}
    end)
  end

  defp read_doc(name) do
    # Sanitize: only allow alphanumeric, hyphens, underscores
    if Regex.match?(~r/^[a-zA-Z0-9_-]+$/, name) do
      path = Path.join(docs_dir(), "#{name}.md")

      if File.exists?(path) do
        content = File.read!(path)
        title = doc_title(name)
        {:ok, html, _messages} = Earmark.as_html(content)
        {:ok, title, html}
      else
        :not_found
      end
    else
      :not_found
    end
  end

  defp doc_title(name) do
    name
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
