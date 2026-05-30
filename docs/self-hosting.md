# Self-hosting ControlKeel

ControlKeel ships as a single Phoenix release. The same binary serves three deployment topologies:

| Topology | Who runs it | What it stores |
| --- | --- | --- |
| **Local single-user** | `controlkeel` CLI on a laptop. SQLite + ETS bus. | One workspace's findings, proofs, memory. |
| **Canonical SaaS (controlkeel.com)** | Anthropic / ControlKeel team. Postgres + fly.io. | Telemetry from every laptop that opted in. |
| **Self-host SaaS** | Your team. Postgres + your fly.io / k8s / VM. | Telemetry from your team's laptops only. Air-gappable. |

This document is for **option 3** — running your own controlkeel.com inside your perimeter. Local-mode users do not need any of this; they should follow [the README](../README.md) instead.

## When to self-host

You need self-host if any of these apply:

- Regulated industry (SOC 2, HIPAA, FedRAMP, EU AI Act high-risk system) requires telemetry stays inside your data boundary.
- You need SSO/SAML against an internal-only IdP that controlkeel.com cannot reach.
- You want to retain proof bundles and audit logs longer than the canonical SaaS retention window.
- You need air-gapped operation — see also `controlkeel selfhost pack` for offline install artifacts.

Otherwise, [enrolling with controlkeel.com](#enrolling-with-the-canonical-saas) is faster and the same governance loop runs.

## Architecture parity

Self-host runs the **exact same release artifact** as controlkeel.com. The two differ only in environment variables. Every Phase 1–7 surface works identically:

- Multi-tenant `workspace_keys` registry — your instance verifies Bearer tokens from every laptop that enrolled with you, not just the receiver's own identity.
- Hosted MCP gateway, per-tool policy enforcement, supply-chain registry, signed-skill pipeline.
- Org-scoped `/cloud/projects` dashboard, per-workspace event streams.
- SSO via OIDC or SAML, RBAC, NHI lifecycle audit, signed audit export envelopes.
- Behavioral baselining, provider fallback chains, amplification ratio metrics.
- Compliance template exports (SOC 2, GDPR, EU AI Act, NIST AI RMF).

No feature gating between SaaS and self-host. If it ships in `lib/controlkeel/cloud/`, it works in your fly app.

## Fly.io quickstart

ControlKeel ships [deploy/fly.self-host.toml](../deploy/fly.self-host.toml) as a starting template.

```bash
# 1. Copy and edit the template
cp deploy/fly.self-host.toml fly.toml
$EDITOR fly.toml  # change `app`, `primary_region`, and `PHX_HOST`

# 2. Create the fly app and Postgres
fly launch --no-deploy --copy-config --name controlkeel-acme
fly postgres create --name controlkeel-acme-db
fly postgres attach controlkeel-acme-db

# 3. Secrets (never check these into git)
fly secrets set \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  AUDIT_EXPORT_SIGNING_KEY="$(openssl rand -hex 32)"

# 4. TLS for your hostname
fly certs create govern.acme.com
# Then add the DNS records fly prints (A/AAAA pointing at your fly app).

# 5. (Recommended) Pre-flight smoke against a local SQLite — same checks CI runs
PHX_HOST=govern.acme.com bash scripts/self_host_smoke.sh

# 6. Deploy
fly deploy

# 7. Post-deploy smoke test
curl -sS https://govern.acme.com/      # 200 home page
fly ssh console -C "/app/bin/controlkeel cloud doctor"
```

`cloud doctor` should report:

```
ControlKeel cloud doctor
Mode: :cloud
Overall: OK
Checks:
  [ok] Runtime mode: :cloud (source: env CONTROLKEEL_RUNTIME_MODE)
  [ok] Cloud repo: configured (DATABASE_URL set)
  [ok] Public host: govern.acme.com (self-host deployment)
  ...
```

If `Public host` reports a warn or `controlkeel.com`, your `PHX_HOST` env didn't land. Re-check `fly secrets list` / `fly config show`.

## Enrolling laptops with your self-host

From any developer laptop that has `controlkeel` installed:

```bash
controlkeel cloud connect --enroll https://govern.acme.com --name "alice-mbp"
```

This generates a local ed25519 keypair (if not already present), builds a proof-of-possession envelope, and POSTs it to `/cloud/v1/workspaces/register`. The fly app stores the public half in the `workspace_keys` registry and returns the enrolled workspace summary.

To bind the workspace to a specific org, include an invitation token issued by an org admin:

```bash
# Admin issues invite from the controlkeel UI or CLI:
controlkeel org invite --org acme-eng --email alice@acme.com

# Alice runs:
controlkeel cloud connect --enroll https://govern.acme.com --invite <token>
```

Now telemetry flows when she opts in:

```bash
controlkeel telemetry enable --level governance
# Either explicitly or via the periodic drainer:
controlkeel telemetry flush
```

Alice's project will appear at `https://govern.acme.com/cloud/projects` for anyone in the same org.

## Configuration reference

The only required env vars in self-host mode:

| Variable | Purpose | Default |
| --- | --- | --- |
| `CONTROLKEEL_RUNTIME_MODE` | Must be `cloud` to enable multi-tenant code paths. | `local` |
| `DATABASE_URL` | Postgres connection string. fly's `postgres attach` sets this automatically. | — |
| `SECRET_KEY_BASE` | Phoenix session signing key. `mix phx.gen.secret` to generate. | — |
| `PHX_HOST` | Public hostname your laptops will enrol against. | `controlkeel.com` |
| `PHX_SERVER` | Must be `true` to start the web endpoint. | unset |

Optional:

| Variable | Purpose | Default |
| --- | --- | --- |
| `AUDIT_EXPORT_SIGNING_KEY` | HMAC key for signed audit export envelopes. | unset |
| `ECTO_USE_SSL` | Enforce TLS on the Postgres connection. | `false` |
| `POOL_SIZE` | DB connection pool size. | `10` |
| `CONTROLKEEL_BUS` | `local` (default) or `nats` if you front a JetStream cluster. | `local` |
| `CONTROLKEEL_NATS_URL` | NATS connection string when `CONTROLKEEL_BUS=nats`. | unset |
| `CONTROLKEEL_CLOUD_TELEMETRY_ENDPOINT` | Override for the **sender** side (only relevant if this same release is also pushing telemetry somewhere else). | unset |
| `LOGGER_LEVEL` | Log level (`debug` / `info` / `warning` / `error`). | `info` |

## Backups and disaster recovery

- **Postgres**: rely on fly's managed Postgres snapshots, or run `fly postgres backup` to disk. The DB is the only authority — proof bundles, findings, memory all live here.
- **Workspace keys**: revoked rows are kept (soft-delete) so audit trails persist. A `fly postgres backup` is sufficient.
- **Local proofs** still live on each developer's laptop. Synced telemetry references them by hash; the self-host server does not hold the bundle bytes unless you opt in to evidence-level sync.

## Migrating from controlkeel.com → self-host

There is no automatic migration. Each laptop runs `cloud connect --enroll` against the new host. Past telemetry stays on controlkeel.com (or you can pull it down with `controlkeel audit export` while you still have access). The recommended cutover:

1. Stand up your self-host instance and verify `cloud doctor` is green.
2. On every laptop: `controlkeel cloud connect --enroll https://your-host` (this generates a fresh workspace_id and posts to the new host).
3. `controlkeel telemetry enable --level governance` against the new endpoint.
4. Optional: `controlkeel audit export --org <old-org>` from controlkeel.com and import to your self-host for continuity.

The local SQLite database (findings, proofs, memory) is untouched throughout — it's the *cloud-side* mirror that's being re-pointed.

## Air-gapped self-host

For environments without outbound internet:

```bash
# On an internet-connected build machine:
controlkeel selfhost pack --output /tmp/ck-bundle.tar.gz

# Transfer the bundle into the air-gapped network, then on the deploy host:
tar -xzf ck-bundle.tar.gz
./INSTALL.md  # follow the embedded instructions
```

JetStream / NATS is optional even in air-gapped mode — the default in-memory bus + Postgres queue table cover the dedupe contract without external dependencies.

## Enrolling with the canonical SaaS

If you decided you don't need self-host after all, point your laptops at controlkeel.com:

```bash
controlkeel cloud connect --enroll https://controlkeel.com
controlkeel telemetry enable --level governance
```

Same CLI, same governance loop, no infrastructure on your side.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `cloud doctor` reports `Public host: not set, defaulting to controlkeel.com` | `fly secrets set PHX_HOST=your-host.example.com && fly deploy` |
| Enrolment returns `400 proof_payload_mismatch` | Your laptop's clock drifted >5 min from the server. Sync NTP. |
| Enrolment returns `400 invalid_invite_token` | Invitation expired or already redeemed. Have an org admin issue a new one. |
| `/cloud/projects` shows "no membership" after SSO login | Your user landed without org binding. Have an org admin call `controlkeel org invite` or accept an outstanding invitation. |
| Telemetry flush returns `not_connected` | Run `controlkeel cloud connect --enroll <your-host>` first; the local identity must exist before the sender will run. |
| `cloud doctor` says `Cloud repo: DATABASE_URL is not set` | `fly postgres attach <db-name>` was not run, or the secret got cleared. Re-attach. |
