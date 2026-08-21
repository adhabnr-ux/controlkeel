defmodule ControlKeelWeb.ErrorHTMLTest do
  use ControlKeelWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(ControlKeelWeb.ErrorHTML, "404", "html", [])
    assert html =~ "404"
    assert html =~ "Page not found"
  end

  test "renders 500.html" do
    html = render_to_string(ControlKeelWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Internal Server Error"
  end
end
