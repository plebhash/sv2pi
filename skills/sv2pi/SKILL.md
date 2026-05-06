---
name: sv2pi
description: Agentic deployment of the Stratum V2 Reference Implementation (SRI) for Bitcoin mainnet. Use when deploying or managing Docker-based SRI apps (pool_sv2, jd_client_sv2, translator_sv2, sv2_tp) alongside Bitcoin Core with IPC. Also use for deploying sv2-cpu-miner as a testing tool to verify Pool and JDC share flow, crash diagnostics, and health monitoring of already-deployed instances. Scope is strictly production mainnet — not for development, testing, or devnet work.
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

Helper scripts at `{baseDir}/scripts/`. Reference docs at `{baseDir}/references/`.

---

## Stateful Context Model

You build a stateful mental model of deployed SRI instances from three sources:

1. **SV2 Protocol Spec** — Understand what each app does and how they connect. See `{baseDir}/references/sv2-spec-overview.md`.
2. **Log Observation** — Analyze the source code first to understand log format and error patterns, then grep logs for those patterns. NEVER load entire log files into context — they are too large and will burn tokens. Always use `--tail N` or pipe through `grep`.
3. **HTTP API Probing** — Probe monitoring endpoints described in `{baseDir}/references/sv2-apps/monitoring-api.md`. This provides real-time hashrate, channel count, connected clients, shares accepted, and block data.

Use all three sources together. Logs give operational detail. APIs give quantitative state. Source code gives authoritative semantics.

**Concurrent human operators:** The stateful model is not authoritative. Human operators may concurrently interact with containers (stop, restart, reconfigure them). Always re-validate container state with `docker ps` before running any operation that depends on a running container. Never assume a previously-running container is still up.

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

### Step 1 — Select Deployment Tag

Ask the user: **"Which SRI Docker Hub tag? (`main` or a version like `v0.3.5`)"**

Store as `DEPLOY_TAG`. If the user doesn't specify, default to `main`.

**Compatibility constraint:** The SRI tag and Bitcoin Core version must be compatible. `{baseDir}/references/sv2-apps/bitcoin-core-version.md` contains a reverse-lookup table. After deploying Bitcoin Core, when the user selects an SRI tag, check this table. If the pair is incompatible, tell the user which SRI tags are supported for that Bitcoin Core version and ask them to choose again.

### Step 2 — Load Source and Config Context

**Docker config templates for past releases are frozen in this skill** at `{baseDir}/references/sv2-apps/docker-templates/{tag}/`. No clone needed for known tags — read them directly:

```
{baseDir}/references/
├── sv2-apps/
│   ├── config-reference.md              ← semantic explanations of every parameter
│   ├── monitoring-api.md                ← HTTP monitoring API for all roles
│   ├── bitcoin-core-version.md          ← BTC Core version compatibility matrix
│   └── docker-templates/
│       ├── v1.1.0/                      ← frozen sv2-tp v1.1.0
│       ├── v0.3.5/                      ← frozen at v0.3.5
│       ├── v0.3.4/
│       ├── v0.3.3/
│       ├── v0.3.2/
│       ├── v0.3.1/
│       ├── v0.3.0/
│       ├── v0.2.0/
│       └── v0.1.0/
├── architecture.md                      ← SRI app architecture
└── sv2-spec-overview.md                 ← SV2 protocol overview
```

**If the user selected a tagged release (e.g. `v0.3.5`):**

Read the frozen Docker config templates directly:

```bash
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/docker_env.example
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/pool-jds-config.toml.template
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/jdc-config.toml.template
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/translator-proxy-config.toml.template
```

If the selected tag does not exist in the frozen references (future release), clone `sv2-apps` at that tag:

```bash
git clone --branch $DEPLOY_TAG --depth 1 https://github.com/stratum-mining/sv2-apps /tmp/sv2-apps-$DEPLOY_TAG
cat /tmp/sv2-apps-$DEPLOY_TAG/docker/docker_env.example
cat /tmp/sv2-apps-$DEPLOY_TAG/docker/config/*.toml.template
```

**If the user selected `main`:**

`main` is a **rolling branch** — it changes continuously. There is no frozen snapshot for it. You must fetch the live `docker/config` templates at runtime:

```bash
git clone --depth 1 https://github.com/stratum-mining/sv2-apps /tmp/sv2-apps-main
cat /tmp/sv2-apps-main/docker/docker_env.example
cat /tmp/sv2-apps-main/docker/config/pool-jds-config.toml.template
cat /tmp/sv2-apps-main/docker/config/jdc-config.toml.template
cat /tmp/sv2-apps-main/docker/config/translator-proxy-config.toml.template
```

File layout inside `/tmp/sv2-apps-main/docker/config/` mirrors the frozen release directories — the agent applies the same reading logic, just from a live source.

Also clone `sv2-spec` for protocol context and `sv2-apps` source for log comparison:

```bash
git clone --depth 1 https://github.com/stratum-mining/sv2-spec ~/.cache/sv2pi/sv2-spec 2>/dev/null || true
git clone --branch $DEPLOY_TAG --depth 1 https://github.com/stratum-mining/sv2-apps ~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG 2>/dev/null || \
git clone --depth 1 https://github.com/stratum-mining/sv2-apps ~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG
```

**CRITICAL: Understand every parameter.** For semantic explanations of each parameter — what it controls in the SV2 protocol, valid values, tradeoffs, and which keys must be replaced for production — load `{baseDir}/references/sv2-apps/config-reference.md`.

### Step 3 — Verify Bitcoin Core Version Compatibility

Before deploying, determine the minimum Bitcoin Core version for this SRI release:

```bash
cat {baseDir}/references/sv2-apps/bitcoin-core-version.md
```

The agent must know the required version before running `deploy-bitcoin.sh`:
- **`main`** → Bitcoin Core v31.0 (bitcoin_core_sv2 v0.2.0)
- **v0.3.5 through v0.1.0** → Bitcoin Core v30.2
- **sv2-tp v1.1.0** → Bitcoin Core v31.0 (uses `stratumv2/sv2-tp:v1.1.0`)

If using a tag not in the frozen references, clone `sv2-apps` and check `bitcoin-core-sv2/README.md` for the exact version requirement.

### Step 4 — Deploy Bitcoin Core

If the user explicitly says "deploy Bitcoin Core", run the deploy script. Do NOT run `check-bitcoin.sh` first — it's only for the "already running" case below. The user asked to deploy; deploy.

If the user didn't specify a tag, ask: *"Which tag? (`latest`, `31.0`, `30.2`)"* The compatibility matrix at `{baseDir}/references/sv2-apps/bitcoin-core-version.md` maps SRI releases to minimum BTC Core versions.

**Deploy:**

```bash
bash {baseDir}/scripts/deploy-bitcoin.sh $BTC_TAG
export BITCOIN_IPC_PATH="$HOME/.sv2pi/bitcoin/data/node.sock"
```

After running the script, export the IPC path and move immediately to Step 5. Do NOT probe the deployment (no curl health checks, no `ls -la node.sock`, no `bitcoin-cli`). The script succeeds = deployment succeeded. The host data dir is root-owned (Docker volumes), so `ls` from the host user will fail — this is normal and irrelevant; SRI containers run as root.

**After deployment:** look up the BTC Core → SRI mapping in `{baseDir}/references/sv2-apps/bitcoin-core-version.md`. When the user later picks an SRI tag, only suggest compatible ones. If the user requests an incompatible pair, refuse and show the valid mappings.

If the script fails with a Docker permission error:
```bash
sudo usermod -aG docker $USER && newgrp docker
```
Or prefix with `sg docker -c "..."` if already in the group but the current shell lacks it.

**Existing Bitcoin Core** (only if the user says they already have it running):

```bash
bash {baseDir}/scripts/check-bitcoin.sh
export BITCOIN_IPC_PATH   # use the path it outputs
```

### Step 5 — Deploy SV2 Template Provider (sv2-tp)

**sv2-tp is optional but recommended** for production deployments. It decouples the SRI apps from direct Bitcoin Core IPC by serving the Template Distribution Protocol over TCP. This provides better fault isolation — sv2-tp handles IPC reconnection so Pool and JDC don't need direct IPC socket access.

**Compatibility check before deploying:** sv2-tp v1.1.0 requires Bitcoin Core v31.0+. If deploying against v30.2, use sv2-tp v1.0.6. Check `{baseDir}/references/sv2-apps/bitcoin-core-version.md` for the full matrix.

Deploy:

```bash
bash {baseDir}/scripts/deploy-tp.sh v1.1.0 $HOME/.sv2pi/bitcoin/data mainnet
```

This:
- Pulls `stratumv2/sv2-tp:v1.1.0`
- Connects to Bitcoin Core via IPC (`-ipcconnect=unix`) through the shared datadir volume
- Listens for Template Distribution Protocol connections on port 8442 (mainnet default)
- Binds `0.0.0.0:8442` by default (access from other containers)

**The script outputs the address for Pool/JDC configuration.** After deploying sv2-tp, Pool and JDC must use `Sv2Tp` instead of `BitcoinCoreIpc`:

```toml
# In pool-config.toml or jdc-config.toml:
[template_provider_type.Sv2Tp]
address = "127.0.0.1:8442"
```

Do NOT probe the deployment after the script succeeds.

### Step 6 — Deploy Pool (with embedded JDS)

**CRITICAL:** Never deploy to production with the default keypairs from the Docker config templates. The pool's `authority_public_key`/`authority_secret_key` and the JDC's keypair must be unique per deployment. Generate fresh keys:

```bash
bash {baseDir}/scripts/generate-keypair.sh
```

This uses `key-utils` (the official SRI key generation crate) inside a Dockerized Rust environment — no local Rust toolchain needed. The output is a base58-encoded secp256k1 keypair in TOML-ready format.

**Security tradeoff:** The generated private keys are exposed to the LLM context and potentially exposed to LLM providers. This is a deliberate tradeoff of agentic deployments in sv2pi — the user accepts this. Encourage the user to ask the agent to rotate keys across deployments.

Generate **two** secp256k1 keypairs: one for the pool app, one for the JDC app. Copy the pool's `authority_public_key` into the JDC's `[[upstreams]].authority_pubkey`. The JDC's own authority keypair is separate and used for downstream Translator connections.

If the user has already reviewed the config templates (Step 2) and agrees to use defaults, deploy directly:

```bash
bash {baseDir}/scripts/deploy-pool.sh $DEPLOY_TAG $BITCOIN_IPC_PATH
```

If the user's request is vague (e.g. "deploy a pool"), walk them through each configuration choice from the frozen Docker config template, offering the default value each time. Key parameters:

| Parameter | Default | Ask |
|---|---|---|
| `coinbase_reward_script` | `addr(...)` (SRI community wallet) | "What payout address? (default: SRI community wallet)" |
| `listen_address` | `0.0.0.0:3333` | "Stratum port? (default 3333)" |
| `JDS listen_address` | `0.0.0.0:3334` | "JDS port? (default 3334)" |
| `shares_per_minute` | `6.0` | "Target shares/minute? (default 6)" |
| `pool_signature` | `SRI Mainnet Pool` | "Pool signature string?" |
| Authority keypair | hardcoded example | Warn: "Replace with your own keypair for production" |

Never ask about ports/values the user already specified. If the user says "use defaults", deploy immediately.

After the script succeeds, move to Step 7. Do NOT probe the deployment.

### Step 7 — Deploy JD Client

```bash
bash {baseDir}/scripts/deploy-jd.sh $DEPLOY_TAG $BITCOIN_IPC_PATH
```

This:
- Creates `~/.sv2pi/jdc/config/` and writes `jdc-config.toml`
- Configures upstream to pool on localhost:3333 and JDS on localhost:3334
- Exposes port 34265 (downstream), 9091 (monitoring)

**If sv2-tp is deployed**, the JDC's template provider must be changed from `BitcoinCoreIpc` to `Sv2Tp`. The generated config uses IPC by default — the agent must update `[template_provider_type]` accordingly.

After deployment, verify:
```bash
docker logs jd_client_sv2 --tail 20
curl -s http://localhost:9091/api/v1/health
```

### Step 8 — Deploy Translator Proxy

```bash
bash {baseDir}/scripts/deploy-translator.sh $DEPLOY_TAG
```

This:
- Creates `~/.sv2pi/translator/config/` and writes `tproxy-config.toml`
- Upstream points to JDC on localhost:34265
- Exposes port 34255 (SV1 downstream), 9092 (monitoring)

After deployment, verify:
```bash
docker logs translator_sv2 --tail 20
curl -s http://localhost:9092/api/v1/health
curl -s http://localhost:9092/api/v1/sv1/clients
```

### Step 9 — Verify Full Deployment

Run a comprehensive health check across all roles:

```bash
# All monitoring endpoints
for endpoint in 9090 9091 9092; do
  echo "--- Port $endpoint ---"
  curl -sf http://localhost:$endpoint/api/v1/health | python3 -m json.tool 2>/dev/null || echo "UNREACHABLE"
done

# Container status (including sv2-tp)
docker ps --filter "name=pool_sv2" --filter "name=jd_client_sv2" --filter "name=translator_sv2" --filter "name=sv2_tp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# SV2 Template Provider status
docker logs sv2_tp --tail 10
```

### Step 10 — Build Stateful Representation

Probe detailed monitoring endpoints and build a mental model:

```bash
# Pool state
curl -s http://localhost:9090/api/v1/server/channels | python3 -m json.tool
curl -s http://localhost:9090/api/v1/clients | python3 -m json.tool

# JDC state
curl -s http://localhost:9091/api/v1/server/channels | python3 -m json.tool
curl -s http://localhost:9091/api/v1/clients | python3 -m json.tool

# Translator state (includes SV1 clients)
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

### Step 11 — Deploy Sv2 CPU Miner

The Sv2 CPU miner is a testing tool (`github.com/plebhash/sv2-cpu-miner`). It is not part of the SRI suite. Deploy it to verify Pool and JDC deployments by simulating real miners that submit shares over SV2 channels.

**Prerequisites:** A running pool (Step 6) or JDC (Step 7) must be up and accepting connections. The miner connects directly to whichever Sv2 endpoint the user specifies.

#### Configuration Parameters

Load `{baseDir}/references/sv2-apps/cpu-miner-config-reference.md` for semantic explanations of every parameter. Key parameters the agent MUST resolve:

| Parameter | Default | How to resolve |
|---|---|---|
| `server_addr` | `127.0.0.1:3333` | Pool's `listen_address` (direct) or JDC's `listening_address` (via JDC). Default 3333 for pool, 34265 for JDC. |
| `auth_pk` | `9auqWEz...` (SRI example) | The pool's or JDC's `authority_public_key`. Read from `~/.sv2pi/pool/config/pool-config.toml` or `~/.sv2pi/jdc/config/jdc-config.toml`. |
| `n_extended_channels` | `2` | Number of Extended Channels. Set to 0 when connecting directly to a pool (no JDS intermediary). |
| `n_standard_channels` | `2` | Number of Standard Channels. Always valid. At least one channel type must be > 0. |
| `cpu_usage_percent` | `100` | CPU throttle 1–100. Default 100 (full speed). Lower for testing without maxing out the host. |

Additional parameters with defaults: `user_identity` (`username`), `device_id` (`sv2-cpu-miner`), `nominal_hashrate_multiplier` (`1.0`), `single_submit` (`false`).

#### User intent extraction

When the user asks to deploy the cpu miner, extract intent from their phrasing:
- **"connect to the pool"** → `server_addr` = `127.0.0.1:3333`, `auth_pk` from pool config
- **"connect to the JDC"** → `server_addr` = `127.0.0.1:34265`, `auth_pk` from JDC config
- **"X extended, Y standard channels"** → set `n_extended_channels` and `n_standard_channels`
- **"N% CPU"** → set `cpu_usage_percent`
- If the user says "use defaults" or doesn't specify, apply the defaults in the table above

**CRITICAL: Always resolve `auth_pk` from the deployed config files.** Never guess it. If neither pool nor JDC is deployed, tell the user a pool or JDC must be deployed first.

#### Deployment

```bash
bash {baseDir}/scripts/deploy-cpu-miner.sh \
  <server_addr> <auth_pk> <n_extended_channels> <n_standard_channels> <cpu_usage_percent>
```

This:
- Clones `https://github.com/plebhash/sv2-cpu-miner` to `~/.sv2pi/cpu-miner/src/`
- Writes `config.toml` with the specified parameters
- Pulls `rust:latest` Docker image
- Starts a container (`sv2-cpu-miner`) with `--network host`, builds `--release`, and runs the miner

Compilation takes 2–5 minutes (Rust release build + dependency fetching). The script handles the Docker pull separately to avoid timeout issues.

#### Verification

After compiling, the miner logs show share submissions. Verify:

```bash
# Check miner share submissions (wait 2-3 minutes for compilation first)
docker logs sv2-cpu-miner --tail 50 | grep -E 'Submitting share'

# Verify extended shares
docker logs sv2-cpu-miner --tail 50 | grep "SubmitSharesExtended"

# Verify standard shares
docker logs sv2-cpu-miner --tail 50 | grep "SubmitSharesStandard"
```

Cross-reference with pool monitoring API:

```bash
# Confirm client is connected
curl -s http://localhost:9090/api/v1/clients | python3 -m json.tool

# Count active channels
curl -s http://localhost:9090/api/v1/server/channels | python3 -m json.tool
```

Expected: the pool API shows one client with `extended_channels_count` and `standard_channels_count` matching the deployment parameters. Shares appear in both the miner logs and the pool's `shares_accepted_total`.

#### Crash Diagnostics

If the miner container exits or logs show errors:

```bash
# Is the container running?
docker ps --filter "name=sv2-cpu-miner"

# Check exit status if stopped
docker ps -a --filter "name=sv2-cpu-miner" --format "{{.Status}}"

# Compilation errors (during build phase)
docker logs sv2-cpu-miner --tail 30 | grep -i 'error'

# Connectivity errors (after build, during runtime)
docker logs sv2-cpu-miner --tail 30 | grep -iE 'connect|reject|timeout|fail'
```

Common failure modes:
- **`edition2024` not stabilized** → wrong Rust image (must be `rust:latest`, not older slim tags)
- **`Noise handshake failed`** → `auth_pk` doesn't match the server's `authority_public_key`
- **`Connection refused`** → `server_addr` is wrong or the target service isn't running
- **Container exits immediately** → compile error; check full logs for the specific Rust error

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

### 3. Check Connectivity
```bash
# Can JDC reach pool?
docker exec jd_client_sv2 sh -c 'echo | nc -w2 pool_host 3333 && echo "POOL REACHABLE" || echo "POOL UNREACHABLE"'

# Can translator reach JDC?
docker exec translator_sv2 sh -c 'echo | nc -w2 jdc_host 34265 && echo "JDC REACHABLE" || echo "JDC UNREACHABLE"'

# Is Bitcoin IPC mounted?
docker exec pool_sv2 ls -la /bitcoin/node.sock
```

### 4. Check Bitcoin Core and sv2-tp
```bash
# Verify container is running
docker ps --filter name=bitcoin_core
docker ps --filter name=sv2_tp

# Check IPC socket inside SRI containers
docker exec pool_sv2 ls -la /bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible to pool"
docker exec sv2_tp ls -la /home/bitcoin/.bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible to sv2-tp"

# Check sv2-tp IPC connection status
docker logs sv2_tp --tail 20 | grep -i 'connect\|ipc\|error'

# Check sync status
docker exec bitcoin_core bitcoin-cli getblockchaininfo 2>/dev/null | grep -E 'blocks|verificationprogress'

# Check logs
docker logs bitcoin_core --tail 50
docker logs sv2_tp --tail 50
```

### 5. Config Validation
Compare running configs against example configs from the source:

```bash
diff ~/.sv2pi/pool/config/pool-config.toml ~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/config-examples/mainnet/pool-config-bitcoin-core-ipc-example.toml || true
```

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
- `{baseDir}/references/sv2-apps/docker-templates/v0.3.5/` through `{baseDir}/references/sv2-apps/docker-templates/v0.1.0/` — SRI release templates

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
