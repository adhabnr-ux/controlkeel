defmodule ControlKeelWeb.PageHTML do
  use ControlKeelWeb, :html

  import ControlKeelWeb.AvailableInstallComponents

  embed_templates "page_html/*"
end
