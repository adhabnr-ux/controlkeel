defmodule Refactor do
  def run do
    lines = File.read!("lib/controlkeel/cli.ex") |> String.split("\n")
    # Let's write an Elixir script that reads tokens
    # Wait, `Code.string_to_quoted` provides meta: [line: X].
    # But it doesn't give the end line natively in older Elixir versions unless we inspect the AST closely.
  end
end
