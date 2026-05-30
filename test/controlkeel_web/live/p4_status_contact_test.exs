defmodule ControlKeelWeb.P4StatusContactTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "status page" do
    test "renders status page without auth", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/status")
      assert html =~ "All systems operational"
    end

    test "shows health checks", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/status")
      assert html =~ "Database"
      assert html =~ "PubSub"
    end

    test "shows incident history section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/status")
      assert html =~ "Incident history"
    end
  end

  describe "contact form" do
    test "renders contact form without auth", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")
      assert html =~ "Contact us"
    end

    test "shows form fields", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")
      assert html =~ "contact[name]"
      assert html =~ "contact[email]"
      assert html =~ "contact[message]"
    end

    test "submits contact form and sends email", %{conn: conn} do
      original = Application.get_env(:controlkeel, :mailer_adapter)
      Application.put_env(:controlkeel, :mailer_adapter, :test)
      ControlKeel.Mailer.TestInbox.clear()

      on_exit(fn ->
        ControlKeel.Mailer.TestInbox.clear()
        Application.put_env(:controlkeel, :mailer_adapter, original)
      end)

      {:ok, view, _html} = live(conn, ~p"/contact")

      html =
        view
        |> element("form")
        |> render_submit(%{
          contact: %{
            name: "Test User",
            email: "test@example.com",
            message: "Hello from the contact form"
          }
        })

      assert html =~ "Message sent"

      # Verify email was delivered to TestInbox
      assert [{:generic, %{to: "support@controlkeel.com"}, _ts}] =
               ControlKeel.Mailer.TestInbox.all()
               |> Enum.filter(fn {k, _, _} -> k == :generic end)
    end
  end
end
