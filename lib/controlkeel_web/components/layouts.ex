defmodule ControlKeelWeb.Layouts do
  @moduledoc """
  This module holds the root layout used by your application.

  The root layout is the HTML skeleton rendered around every page.
  Page-level layouts, such as `ControlKeelWeb.DashboardLayout`, are
  rendered inside the root's `@inner_content`.
  """
  use ControlKeelWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"
end
