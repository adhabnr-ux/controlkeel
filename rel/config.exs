import Config

release :controlkeel do
  set version: current_version(:controlkeel)
  set applications: [
    :runtime_tools
  ]

  # Exclude development and governance files from the release
  # These are internal tooling not needed by end users
  set overlays: [
    {:copy, "rel/vm.args.eex", "releases/<%= release %>/vm.args"},
    {:template, "rel/vm.args.eex", "releases/<%= release %>/vm.args"}
  ]

  # Strip debug information from BEAM files to reduce size
  set strip_beams: [
    keep: ["Docs"]
  ]
end