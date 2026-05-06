# Glama MCP Server Configuration

This document describes the correct Glama MCP server configuration for ControlKeel,
matching the CI build environment (OTP 27.3.4.3 + Elixir 1.19.5).

## Build Steps (JSON array for Glama)

```json
[
  "set -eux; apt-get update; apt-get install -y --no-install-recommends build-essential ca-certificates curl git wget unzip libssl-dev libncurses5-dev; rm -rf /var/lib/apt/lists/*",
  "set -eux; curl -fsSL https://raw.githubusercontent.com/kerl/kerl/master/kerl -o /usr/local/bin/kerl; chmod +x /usr/local/bin/kerl; kerl update releases",
  "set -eux; kerl build 27.3.4.3 27.3.4.3; kerl install 27.3.4.3 /usr/local/erlang-27.3.4.3; ln -sf /usr/local/erlang-27.3.4.3/bin/erl /usr/local/bin/erl; ln -sf /usr/local/erlang-27.3.4.3/bin/erlc /usr/local/bin/erlc; erl -version",
  "set -eux; curl -fsSL -o /tmp/elixir.zip https://github.com/elixir-lang/elixir/releases/download/v1.19.5/elixir-otp-27.zip; mkdir -p /usr/local/elixir-1.19.5; unzip -q /tmp/elixir.zip -d /usr/local/elixir-1.19.5; ln -sf /usr/local/elixir-1.19.5/bin/elixir /usr/local/bin/elixir; ln -sf /usr/local/elixir-1.19.5/bin/mix /usr/local/bin/mix; ln -sf /usr/local/elixir-1.19.5/bin/iex /usr/local/bin/iex; ln -sf /usr/local/elixir-1.19.5/bin/elixirc /usr/local/bin/elixirc; rm -f /tmp/elixir.zip; LANG=C.UTF-8 MIX_ENV=prod mix --version",
  "LANG=C.UTF-8 MIX_ENV=prod mix local.hex --force",
  "LANG=C.UTF-8 MIX_ENV=prod mix local.rebar --force",
  "LANG=C.UTF-8 MIX_ENV=prod mix deps.get --only prod",
  "LANG=C.UTF-8 MIX_ENV=prod mix compile",
  "LANG=C.UTF-8 MIX_ENV=prod mix release"
]
```

## CMD Arguments (JSON array for Glama)

```json
[
  "mcp-proxy",
  "--",
  "sh",
  "-c",
  "LANG=C.UTF-8 CK_MCP_MODE=1 /app/_build/prod/rel/controlkeel/bin/controlkeel start"
]
```

## Key Version Requirements

| Component | Version | Source |
|-----------|---------|--------|
| Erlang/OTP | 27.3.4.3 | kerl build from source |
| Elixir | 1.19.5 | GitHub release (otp-27 zip) |
| Base image | debian:bookworm-slim | Docker Hub |
| mcp-proxy | 6.4.3+ | npm |

## Why OTP 27, not 26?

CI uses OTP 27.3.4.3 (see `.github/workflows/release-smoke.yml`).
The project may compile on OTP 26 but runtime behavior differs — always
match CI for production builds.

## Why not hexpm/elixir Docker images?

hexpm no longer publishes OTP 27 stable tags. The available images are
OTP 26.x or OTP 28.x. Building OTP 27 from source via kerl is the
reliable path to match CI exactly.

## Updating After a New Release

When a new version is released:

1. Update the pinned commit SHA in Glama to the new release tag commit
2. The build steps above are version-agnostic — no changes needed
3. Verify on Glama by clicking "Test locally" with the new Dockerfile
