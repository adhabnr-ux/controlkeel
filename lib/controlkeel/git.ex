defmodule ControlKeel.Git do
  @moduledoc """
  Thin, crash-safe wrapper around the `git` executable.

  CK can be installed from a GitHub release or attached to a host before the
  user has git available. `System.cmd/3` raises `ErlangError` when the binary
  is missing, so every git shell-out must degrade gracefully. `cmd/2` mirrors
  `System.cmd/3` but rescues a missing/broken executable into a non-zero exit
  (`127`), which existing `case {_, 0}` call sites already treat as failure.

  The executable name is read from `:controlkeel, :git_executable` (default
  `"git"`) so tests can point it at a non-existent binary to exercise the
  git-absent path.
  """

  @missing_exit 127

  @doc "Whether a usable git executable is on PATH."
  @spec available?() :: boolean()
  def available?, do: System.find_executable(binary()) != nil

  @doc """
  Run git with the given args/opts. Returns `{output, exit_code}` exactly like
  `System.cmd/3` when git is present; returns `{message, 127}` instead of
  raising when the executable is missing or the spawn fails.
  """
  @spec cmd([String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def cmd(args, opts \\ []) when is_list(args) do
    System.cmd(binary(), args, opts)
  rescue
    _ -> {"git executable not available", @missing_exit}
  end

  defp binary, do: Application.get_env(:controlkeel, :git_executable, "git")
end
