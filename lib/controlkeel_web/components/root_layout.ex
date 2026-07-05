defmodule ControlKeelWeb.RootLayout do
  @moduledoc """
  Renders the root HTML skeleton (doctype, head, body).

  Shared by all pages — dashboard and public alike.
  Set as the root layout in the browser pipeline.
  """

  use ControlKeelWeb, :html

  embed_templates "layouts/*"
end
