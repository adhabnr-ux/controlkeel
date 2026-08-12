defmodule ControlKeelWeb.Typography do
  @moduledoc """
  Typography primitives that encode the fixed heading and label patterns
  from `docs/ui-style-guide.md`. Prefer these over hand-writing classes so
  the heading hierarchy and label styles cannot drift.

  Globally imported through the `html_helpers` block in `ControlKeelWeb`.
  """

  use Phoenix.Component

  @doc """
  Page title block: an `<h1>` with an optional one-line subtitle.

      <.page_title title="Agent Control Plane" subtitle="Live session state." />

  Pass `class` to adjust the wrapper spacing (e.g. `class="mb-12"`).
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :any, default: nil

  def page_title(assigns) do
    ~H"""
    <div class={["space-y-2", @class]}>
      <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">{@title}</h1>
      <p :if={@subtitle} class="text-sm text-muted-foreground">{@subtitle}</p>
    </div>
    """
  end

  @doc """
  Section heading (`<h2>`). Uses the shared section-title styling from the UI
  style guide so it stays distinct from the page title without over-emphasizing.

      <.section_title>Delivery funnel</.section_title>
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def section_title(assigns) do
    ~H"""
    <h2 class={["text-lg sm:text-xl font-semibold text-foreground/90", @class]}>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  @doc """
  Card / panel heading (`<h3>`).

      <.card_title>Model-backed features</.card_title>
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card_title(assigns) do
    ~H"""
    <h3 class={["text-base font-semibold", @class]}>
      {render_slot(@inner_block)}
    </h3>
    """
  end
end
