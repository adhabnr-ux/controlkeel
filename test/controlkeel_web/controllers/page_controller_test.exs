defmodule ControlKeelWeb.PageControllerTest do
  use ControlKeelWeb.ConnCase

  test "GET / renders the controlkeel dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "Governed Delivery Monitor"
    assert body =~ "Dashboard"
    assert body =~ "Missions"
    assert body =~ "Proofs"
    assert body =~ "Benchmarks"
    assert body =~ "Ship Metrics"
    assert body =~ "Benchmark Catch Rate"
    assert body =~ "Proof Coverage"
    assert body =~ "Deploy Ready Rate"
    assert body =~ "Recent Missions"
    assert body =~ "Live Task State"
    assert body =~ "Delivery Flow"
    assert body =~ "Signal Preview"
    assert body =~ "New Mission"
  end

  test "GET /getting-started renders the install guide", %{conn: conn} do
    conn = get(conn, ~p"/getting-started")
    body = html_response(conn, 200)

    assert body =~ "Go from install to first finding in five minutes"
    assert body =~ "agent-generated work into secure, scoped, validated"
    assert body =~ "ControlKeel turns agent output into production engineering"
    assert body =~ "controlkeel attach opencode"
    assert body =~ "controlkeel bootstrap"
    assert body =~ "controlkeel attach codex-cli"
    assert body =~ "Occupation-first onboarding"
    assert body =~ "Project rescue"
    assert body =~ "Operating modes"
    assert body =~ "Governed delivery lifecycle"
  end
end
