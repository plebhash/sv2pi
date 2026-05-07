---
name: sv2pi
description: Agentic deployment of the Stratum V2 Reference Implementation (SRI) for Bitcoin mainnet. Use when deploying or managing Docker-based SRI apps (pool_sv2, jd_client_sv2, translator_sv2, sv2_tp) alongside Bitcoin Core with IPC. Also use for deploying sv2-cpu-miner as a testing tool to verify Pool and JDC share flow, crash diagnostics, health monitoring, automated hashrate collection, and serving/publishing the sv2pi operations vault via Quartz 4 over WireGuard, and checking PPQ credit balance for the LLM provider. Scope is strictly production mainnet — not for development, testing, or devnet work.
---

# sv2pi — SRI Agentic Deployment

Agentic deployment skill for the [Stratum V2 Reference Implementation](https://github.com/stratum-mining) on Bitcoin mainnet.

This skill deploys Bitcoin Core, four SRI-related Docker roles, and one testing tool:
| Role | Docker Image |
|---|---|
| Bitcoin Core | `bitcoin/bitcoin:latest` |
| Sv2 Template Provider | `stratumv2/sv2-tp` |
| Pool (with embedded JDS) | `stratumv2/pool_sv2` |
| Job Declarator Client (JDC) | `stratumv2/jd_client_sv2` |
| Translator Proxy (SV1→SV2 bridge) | `stratumv2/translator_sv2` |
| Sv2 CPU Miner (testing) | `rust:latest` (clones `plebhash/sv2-cpu-miner`) |

**sv2-ui** (`stratumv2/sv2-ui`) is planned for a follow-up release and is currently out of scope. If a user asks about sv2-ui, acknowledge it is on the roadmap but not yet available in this skill.

Helper scripts at `{baseDir}/scripts/`. Reference docs at `{baseDir}/references/`. `{baseDir}` is the directory containing this SKILL.md (`skills/sv2pi/` within the repo).

Domain instructions live at `{baseDir}/domains/`. Load detailed domain content on demand with `read {baseDir}/domains/...`; do not load every domain by default.

---

## Stateful Context Model

You build a stateful mental model of deployed SRI instances from four sources:

1. **SV2 Operations Vault** — Persistent operator memory lives at `$HOME/vault` (`/home/sv2bot/vault` on this VPS). It is an LLM Wiki vault managed by `pi-llm-wiki`; read it before making deployment-health claims or operational recommendations.
2. **SV2 Protocol Spec** — Understand what each app does and how they connect. See `{baseDir}/references/sv2-spec-overview.md`.
3. **Log Observation** — Analyze the source code first to understand log format and error patterns, then grep logs for those patterns. NEVER load entire log files into context — they are too large and will burn tokens. Always use `--tail N` or pipe through `grep`.
4. **HTTP API Probing** — Probe monitoring endpoints described in `{baseDir}/references/sv2-apps/monitoring-api.md`. This provides real-time hashrate, channel count, connected clients, shares accepted, and block data.

Use all four sources together. The vault gives durable cross-session context and operator directives. Logs give operational detail. APIs give quantitative state. Source code gives authoritative semantics.

**Concurrent human operators:** The stateful model is not authoritative. Human operators may concurrently interact with containers (stop, restart, reconfigure them). Always re-validate container state with `docker ps` before running any operation that depends on a running container. Never assume a previously-running container is still up.

---

## Domain Dispatch

`SKILL.md` is the concise orchestrator. Use the architecture and dependency graph below to decide what the user needs, then read only the relevant domain files before acting.

| User intent | Required domain read |
|---|---|
| Any SRI app deployment or config choice | `read {baseDir}/domains/deployment-context.md` first, then the role domain |
| Deploy, reuse, snapshot, or diagnose Bitcoin Core | `read {baseDir}/domains/bitcoin-core.md` |
| Deploy or diagnose sv2-tp | `read {baseDir}/domains/sv2-tp.md` |
| Deploy or diagnose Pool/JDS | `read {baseDir}/domains/pool.md` |
| Deploy or diagnose JDC | `read {baseDir}/domains/jdc.md` |
| Deploy or diagnose Translator Proxy | `read {baseDir}/domains/translator.md` |
| Deploy or diagnose Sv2 CPU Miner | `read {baseDir}/domains/sv2-cpu-miner.md` |
| Health diagnosis, crash investigation, topology questions, persistent memory, or explicit vault queries | `read {baseDir}/domains/vault.md` |
| Serve, publish, show, expose, or repair the vault web UI | `read {baseDir}/domains/quartz.md` |
| Check PPQ credit balance or model-credit failures | `read {baseDir}/domains/ppq-monitor.md` |
| Enable or diagnose automated pool hashrate monitoring | `read {baseDir}/domains/pool-monitor.md` |

Before deployment actions, perform a quick vault check (read `$HOME/vault/README.md` for binding directives). For health diagnosis, crash investigation, or topology questions, read the vault domain and then re-validate live state. Before role-specific crash diagnosis, read the relevant role domain.

---

## Architecture Quick Reference

### Mode A: Direct IPC (no sv2-tp)

```
bitcoin_core (docker) ──(IPC)──► pool_sv2 (with embedded JDS)
  ~/.sv2pi/bitcoin/data           ├── Stratum: 0.0.0.0:3333
                                  └── JDS:     0.0.0.0:3334
                                          ▲
                                          │ (JD protocol)
bitcoin_core (same volume) ──(IPC)──► jd_client_sv2
                                          ├── Downstream: 0.0.0.0:34265
                                          └── Upstream:   pool:3333 + pool:3334 (JDS)
                                                  ▲
                                                  │ (SV2 Mining Protocol)
                                        translator_sv2
                                          ├── Downstream (SV1): 0.0.0.0:34255  ← SV1 miners connect here
                                          └── Upstream (SV2):   jdc:34265
```

### Mode B: With sv2-tp (Template Distribution Protocol)

```
bitcoin_core (docker) ──(IPC)──► sv2_tp
  ~/.sv2pi/bitcoin/data           └── Template Distribution: 0.0.0.0:8442
                                                ▲
                        ┌───────────────────────┴───────────────────────┐
                        │                                               │
              pool_sv2 (embedded JDS)                         jd_client_sv2
              ├── Stratum: 0.0.0.0:3333                      ├── Downstream: 0.0.0.0:34265
              └── JDS:     0.0.0.0:3334                      └── Upstream:   pool:3333 + pool:3334
                        ▲                                               ▲
                        │ (JD protocol)                                 │
                        └───────────────────────────────────────────────┘
                                                ▲
                                                │ (SV2 Mining Protocol)
                                      translator_sv2
                                      ├── Downstream (SV1): 0.0.0.0:34255  ← SV1 miners connect here
                                      └── Upstream (SV2):   jdc:34265
```

In Mode B, Pool and JDC use `[template_provider_type.Sv2Tp]` with `address = "127.0.0.1:8442"` instead of `BitcoinCoreIpc`.

See `{baseDir}/references/architecture.md` for full detail.

---

## Workflow

The deployment workflow is **dependency-driven, not prescribed in a fixed order**. The agent must understand what the user wants to achieve and guide them accordingly. Different users have different goals — there is no single "correct" deployment path.

### Dependency Graph

Each SRI app has prerequisites. Some prerequisites can be satisfied in multiple ways. The agent uses this graph to determine what must be deployed for the user's desired outcome.

```
                    ┌──────────────┐
                    │  Bitcoin     │
                    │  Core        │  ← required by everything
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │ IPC         │ IPC        │
              ▼             ▼            │
     ┌──────────────┐                    │
     │  sv2_tp      │  ← optional       │
     │  (standalone │    Template        │
     │   TP)        │    Provider        │
     └──────┬───────┘    alternative     │
            │                            │
            │ TCP (Template              │
            │ Distribution)              │
            │                            │
     ┌──────┴────────────────────────────┴──┐
     │                                       │
     ▼                                       ▼
┌──────────────┐                     ┌──────────────┐
│  pool_sv2    │                     │ jd_client_sv2│
│  (Pool+JDS)  │                     │ (JDC)        │
│              │                     │              │
│  Template    │                     │  Template    │
│  Provider:   │                     │  Provider:   │
│   • IPC      │                     │   • IPC      │
│   • Sv2Tp    │                     │   • Sv2Tp    │
│              │                     │              │
│  JD support: │                     │  Upstream:   │
│   • enabled  │                     │   • pool:3333│
│   • disabled │                     │   • JDS:3334 │
│              │                     │              │
└──────┬───────┘                     └──────┬───────┘
       │                                    │
       │ (JD protocol)                      │ (SV2 Mining)
       │                                    │
       └────────────────────────────────────┤
                                            ▼
                                   ┌──────────────┐
                                   │ translator   │
                                   │ _sv2         │
                                   │              │
                                   │  Upstream:   │
                                   │  • JDC:34265 │
                                   │  • pool:3333 │
                                   │  • remote    │
                                   └──────────────┘
```

**Key relationships:**

| App | Prerequisites | Alternatives |
|---|---|---|
| **sv2_tp** | Bitcoin Core (IPC) | — |
| **pool_sv2** | Template Provider | IPC (direct to BTC Core) or Sv2Tp (TCP to sv2-tp) |
| **jd_client_sv2** | Template Provider + Pool (JDS endpoint) | Template Provider: IPC or Sv2Tp. Pool: usually local but can be remote |
| **translator_sv2** | Upstream SV2 Mining Server | JDC (34265), Pool directly (3333), or any remote SV2 server |

**sv2-tp as a standalone service:** sv2-tp can be deployed independently — without any Pool or JDC — for Template-Provider-as-a-Service deployments where the TP operator provides templates to remote pools and JDCs.

**Pool without JD support:** The Pool can be deployed with JD support disabled (omit `authority_public_key`/`authority_secret_key` and JDS port). This yields a simpler pool-only deployment where miners cannot declare custom templates.

**Translator upstream flexibility:** The Translator Proxy can be pointed at any SV2 mining server — local JDC, local Pool, or a remote upstream. It is not coupled to any specific local deployment.

---

## Deployment Context

Before deploying any SRI role or Sv2 CPU Miner, read `{baseDir}/domains/deployment-context.md`. It contains tag selection, frozen/live config loading, source-code cache setup, Bitcoin Core compatibility gates, and the deploy-only-needed rule.

---

### Verify Deployment

Run health checks only for the components the user deployed. Do not assume all roles are present.

```bash
# Container status — filter only deployed components
docker ps --filter "name=pool_sv2" --filter "name=jd_client_sv2" --filter "name=translator_sv2" --filter "name=sv2_tp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Health endpoints for deployed monitoring ports
# Pool: 9090, JDC: 9091, Translator: 9092
for endpoint in 9090 9091 9092; do
  echo "--- Port $endpoint ---"
  curl -sf http://localhost:$endpoint/api/v1/health | python3 -m json.tool 2>/dev/null || echo "UNREACHABLE"
done

# sv2-tp status (if deployed)
docker logs sv2_tp --tail 10
```

### Build Stateful Representation

Probe detailed monitoring endpoints for deployed components and build a mental model:

```bash
# Pool state (if deployed)
curl -s http://localhost:9090/api/v1/server/channels | python3 -m json.tool
curl -s http://localhost:9090/api/v1/clients | python3 -m json.tool

# JDC state (if deployed)
curl -s http://localhost:9091/api/v1/server/channels | python3 -m json.tool
curl -s http://localhost:9091/api/v1/clients | python3 -m json.tool

# Translator state, including SV1 clients (if deployed)
curl -s http://localhost:9092/api/v1/sv1/clients | python3 -m json.tool
curl -s http://localhost:9092/api/v1/server/channels | python3 -m json.tool
```

Track these metrics over time:
| Metric | What it means |
|---|---|
| `server.channels` count | Active mining connections at each hop |
| `server.hashrate_total` | Aggregate hashrate |
| `clients[].hashrate_total` | Per-client hashrate |
| `shares_accepted_total` | Cumulative accepted shares |
| `sv1.clients` count | Legacy SV1 miners connected |

---

## Crash Diagnostics

When something fails:

### 1. Check Container Status
```bash
docker ps -a --filter "name=pool_sv2" --filter "name=jd_client_sv2" --filter "name=translator_sv2" --filter "name=sv2_tp" --filter "name=sv2-cpu-miner"
```

### 2. Inspect Logs Against Source

**NEVER load entire log files into context.** Logs can be hundreds of MB. Always use source-code-informed grepping.

1. **Analyze source first.** Read the relevant source files at `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/` to identify log message formats, error strings, and diagnostic patterns:

| App | Key source paths |
|---|---|---|
| sv2-tp | `src/sv2/` (template_provider, connman, messages, noise, transport) |
| Pool | `pool-apps/pool/src/` |
| JDC | `miner-apps/jd-client/src/` |
| Translator | `miner-apps/translator/src/` |
| Monitoring | `stratum-apps/src/monitoring/` |

2. **Grep with source-derived patterns.** Use the error strings and log patterns found in source code to filter logs:

```bash
# Example: grep pool logs for connection errors
docker logs pool_sv2 --tail 200 | grep -E 'error|Error|ERR|fail|timeout|rejected'

# Example: grep for IPC-related errors
docker logs pool_sv2 --tail 200 | grep -i 'ipc\|template\|socket'
```

Adjust the `--tail` count based on recency (100 for recent crashes, 500 for broader context). Always pipe through `grep` — never `cat` the raw log output.

For role-specific connectivity checks, Bitcoin Core/sv2-tp checks, and config validation, read the relevant domain file under `{baseDir}/domains/` before acting.

---

## Keypair Management

Deployment scripts use example/test keypairs by default. For production mainnet:

1. Generate unique Noise authority keypairs (ed25519-based, base58-encoded, 44 chars each)
2. Pool and JDC each need their own keypair
3. The `[[upstreams]]` section in JDC and translator configs must reference the correct `authority_pubkey` of their upstream

If `sv2-apps` includes a keygen utility, use it. Otherwise, generate with `openssl`:
```bash
openssl genpkey -algorithm ed25519 -outform DER | base64 | tr -d '/+=\n'
```

Then update `authority_public_key` and `authority_secret_key` in each app's config before deploying.

---

## Reference Files

### On-demand domain instructions
- `{baseDir}/domains/deployment-context.md` — shared deployment context, tag selection, source/config loading, compatibility gates
- `{baseDir}/domains/bitcoin-core.md` — Bitcoin Core deployment, snapshot acceleration, existing-node path, diagnostics
- `{baseDir}/domains/sv2-tp.md` — sv2-tp deployment, compatibility, Template Distribution diagnostics
- `{baseDir}/domains/pool.md` — Pool deployment, optional embedded JDS, keypair warnings, pool diagnostics
- `{baseDir}/domains/jdc.md` — Job Declarator Client deployment and diagnostics
- `{baseDir}/domains/translator.md` — Translator Proxy deployment, upstream flexibility, diagnostics
- `{baseDir}/domains/sv2-cpu-miner.md` — Sv2 CPU Miner testing workflow, verification, diagnostics
- `{baseDir}/domains/vault.md` — persistent operations vault, read-before-act workflow, wiki tooling
- `{baseDir}/domains/quartz.md` — Quartz 4 publishing workflow for the vault web UI
- `{baseDir}/domains/ppq-monitor.md` — PPQ credit balance checks and secret handling
- `{baseDir}/domains/pool-monitor.md` — automated pool hashrate monitoring and dashboard publishing

### Static references (bundled with the skill)
- `{baseDir}/references/architecture.md` — SRI app architecture and connection flow
- `{baseDir}/references/sv2-spec-overview.md` — SV2 protocol roles and sub-protocols
- `{baseDir}/references/sv2-apps/monitoring-api.md` — HTTP monitoring API reference for each app
- `{baseDir}/references/sv2-apps/config-reference.md` — every config parameter with SV2-spec context and production guidance
- `{baseDir}/references/sv2-apps/bitcoin-core-version.md` — Bitcoin Core version compatibility per SRI release
- `{baseDir}/references/sv2-apps/cpu-miner-config-reference.md` — sv2-cpu-miner config parameters and verification guide

### Frozen Docker config templates (bundled per release tag)
These ship with the skill — no clone needed for known tags:
- `{baseDir}/references/sv2-apps/docker-templates/v1.1.0/` — sv2-tp v1.1.0 frozen template
- `{baseDir}/references/sv2-apps/docker-templates/v0.4.0/` through `{baseDir}/references/sv2-apps/docker-templates/v0.1.0/` — SRI release templates

There is **no frozen snapshot for `main`**. `main` is a rolling branch; its Docker config templates must be fetched live at runtime from `https://github.com/stratum-mining/sv2-apps`.

Each frozen SRI directory contains:
- `docker_env.example` — environment variables and defaults
- `pool-jds-config.toml.template` — pool + embedded JDS
- `jdc-config.toml.template` — Job Declarator Client
- `translator-proxy-config.toml.template` — SV1→SV2 Translator Proxy

The sv2-tp frozen directory contains:
- `docker_env.example` — sv2-tp CLI flags and defaults (no TOML config needed)

### Live sources (fetched at runtime)
- `https://github.com/stratum-mining/sv2-apps` — for `main` branch Docker config templates, unknown future tags, and source code for log comparison
- `https://github.com/stratum-mining/sv2-spec` — protocol specification
- `https://github.com/plebhash/sv2-cpu-miner` — Sv2 CPU Miner source and `config.toml` template (cloned by `deploy-cpu-miner.sh`)

### Operational scripts
- `{baseDir}/scripts/check-bitcoin.sh` — detect an existing Bitcoin Core IPC path
- `{baseDir}/scripts/check-ppq-balance.py` — live PPQ credit balance probe (reads API key from Pi config, never prints it)
- `{baseDir}/scripts/deploy-bitcoin.sh` — deploy Bitcoin Core with IPC enabled
- `{baseDir}/scripts/deploy-cpu-miner.sh` — deploy Sv2 CPU Miner for share-flow testing
- `{baseDir}/scripts/deploy-jdc.sh` — deploy Job Declarator Client
- `{baseDir}/scripts/deploy-pool.sh` — deploy Pool with optional embedded JDS
- `{baseDir}/scripts/deploy-tp.sh` — deploy sv2-tp
- `{baseDir}/scripts/deploy-translator.sh` — deploy Translator Proxy
- `{baseDir}/scripts/generate-keypair.sh` — generate production keypairs via SRI key utilities
- `{baseDir}/scripts/plot-pool-hashrate.py` — render pool hashrate charts
- `{baseDir}/scripts/pool-monitor.sh` — automated pool hashrate monitoring script
- `{baseDir}/scripts/snapshot.sh` — inject Bitcoin Core snapshot blocks/chainstate
