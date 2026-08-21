defmodule ControlKeelWeb.ErrorJSONTest do
  use ControlKeelWeb.ConnCase, async: true

  test "renders 404" do
    assert %{
             error: %{
               code: "not_found",
               message: _,
               resolution: _
             }
           } = ControlKeelWeb.ErrorJSON.render("404.json", %{})
  end

  test "renders 500" do
    assert %{
             error: %{
               code: "internal_server_error",
               message: _,
               resolution: _
             }
           } = ControlKeelWeb.ErrorJSON.render("500.json", %{})
  end
end
