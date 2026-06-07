defmodule ControlKeel.Skills.Exporter.CloudflareWorkersRuntime do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")

    File.write!(
      agents_path,
      E.instructions_only_contents("cloudflare-workers", project_root, opts)
    )

    readme_path = Path.join(root, "cloudflare-workers/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.cloudflare_workers_runtime_contents(project_root, opts))

    config_path = Path.join(root, "cloudflare-workers/wrangler.toml")
    File.write!(config_path, E.cloudflare_workers_wrangler_contents(project_root, opts))

    mcp_config = Path.join(root, "cloudflare-workers/controlkeel-mcp.json")

    File.write!(
      mcp_config,
      Jason.encode!(
        %{
          "mcp_servers" => %{
            "controlkeel-governance" => %{
              "command" => "npx",
              "args" => ["-y", "@aryaminus/controlkeel-mcp"],
              "env" => %{}
            }
          }
        },
        pretty: true
      ) <> "\n"
    )

    env_example_path = Path.join(root, "cloudflare-workers/.env.example")

    File.write!(env_example_path, """
    # ControlKeel Configuration
    CK_API_URL=https://api.controlkeel.com
    CK_API_KEY=ck_your_api_key_here

    # Workers AI (optional - defaults to Workers AI)
    # AI_PROVIDER=openai
    # OPENAI_API_KEY=sk-...
    """)

    package_json_path = Path.join(root, "cloudflare-workers/package.json")

    File.write!(package_json_path, """
    {
      "name": "cloudflare-workers-agent",
      "version": "0.0.0",
      "private": true,
      "type": "module",
      "scripts": {
        "deploy": "wrangler deploy",
        "dev": "wrangler dev"
      },
      "dependencies": {
        "@cloudflare/workers-types": "^4.20241127.0",
        "agents": "^1.0.0",
        "zod": "^3.23.0"
      },
      "devDependencies": {
        "@cloudflare/workers-plugin": "^3.0.0",
        "wrangler": "^3.93.0",
        "typescript": "^5.0.0"
      }
    }
    """)

    tsconfig_path = Path.join(root, "cloudflare-workers/tsconfig.json")

    File.write!(tsconfig_path, """
    {
      "compilerOptions": {
        "target": "ES2022",
        "module": "ES2022",
        "moduleResolution": "bundler",
        "lib": ["ES2022"],
        "types": ["@cloudflare/workers-types"],
        "strict": true,
        "skipLibCheck": true,
        "noEmit": true,
        "resolveJsonModule": true,
        "isolatedModules": true
      },
      "include": ["src/**/*.ts"]
    }
    """)

    agent_src = Path.join(root, "cloudflare-workers/src/agent.ts")
    File.mkdir_p!(Path.dirname(agent_src))
    File.write!(agent_src, E.cloudflare_workers_agent_contents(opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => mcp_config, "kind" => "settings"},
        %{"path" => agent_src, "kind" => "runtime"}
      ],
      [
        "Deploy with `npm run deploy` after adding your CK API key.",
        "The agent includes built-in governance tools via MCP."
      ]
    )
  end
end
