# SRI Configuration Reference

Every parameter from the official SRI Docker config templates (`sv2-apps/docker/config/`).
This reference is authoritative — the agent loads the actual templates from the cloned
`sv2-apps` repo at the deployment tag, then maps each parameter to this document for
semantic understanding.

Source files (read in order):
1. `sv2-apps/docker/docker_env.example` — env vars and defaults
2. `sv2-apps/docker/config/pool-jds-config.toml.template` — pool + embedded JDS
3. `sv2-apps/docker/config/jdc-config.toml.template` — Job Declarator Client
4. `sv2-apps/docker/config/translator-proxy-config.toml.template` — SV1→SV2 bridge

---

## Global: Bitcoin Core IPC

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `BITCOIN_SOCKET_PATH` | `/absolute/path/to/your/node.sock` | Path to Bitcoin Core's UNIX domain socket. Required by both Pool and JDC for Template Distribution Protocol (block templates). Bitcoin Core v30.2+ must be started with `-ipcbind=unix`. |

The `BITCOIN_SOCKET_PATH` must be a valid `node.sock` inside the Bitcoin Core datadir. The container mounts the parent directory (e.g. `/host/path/.bitcoin` → `/root/.bitcoin/node.sock` inside).

---

## Pool Configuration (`pool_sv2`)

### Identity & Security
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `authority_public_key` | `9auqWEz...` (hardcoded) | **Ed25519 public key (base58, 44 chars).** Used in the Noise NX handshake for the Mining Protocol and Job Declaration Protocol. All downstream clients (JDC, Translator) must know this key in their `[[upstreams]].authority_pubkey`. **FOR PRODUCTION: generate a unique keypair per deployment.** |
| `authority_secret_key` | `mkDLTBB...` (hardcoded) | **Ed25519 secret key.** Paired with above. Never leaves the pool server. |
| `cert_validity_sec` | `3600` | Duration (seconds) for which self-signed Noise certificates are valid. After expiry, clients must re-handshake. 3600s = 1 hour is standard. |

### Stratum Endpoint
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `listen_address` | `0.0.0.0:3333` | SV2 Mining Protocol endpoint. Miners, proxies, and JDCs establish Noise-encrypted TCP connections here. Bind `0.0.0.0` for all interfaces; lock to specific interface in production. |

### Mining Configuration
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `coinbase_reward_script` | `addr(tb1q...)` | **Output descriptor for the coinbase transaction.** This is where mining rewards go. Uses Bitcoin Core `miniscript`/`addr()` syntax. For production: use a mainnet P2WPKH or P2WSH address. |
| `pool_signature` | `Stratum V2 SRI Pool` | ASCII string embedded in the coinbase transaction's scriptSig. Used for pool identification on-chain. |
| `server_id` | `1` | Identifier for this pool server. Relevant when running multiple pool instances behind a load balancer. |
| `shares_per_minute` | `6.0` | Target share submission rate per downstream connection. Drives dynamic difficulty adjustment. Lower = higher difficulty, fewer network messages. Higher = lower difficulty, finer-grained hashrate reporting. Production: 6–30 depending on miner count. |
| `share_batch_size` | `10` | Number of shares to batch before sending `AcceptShare` responses. Batching reduces message overhead. |

### Template Provider
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `POOL_FEE_THRESHOLD` | `100` | **Fee threshold (satoshis).** Triggers a new block template from Bitcoin Core when mempool fee delta exceeds this value. Lower = more frequent template updates (higher bandwidth, faster fee capture). Production: 100 sats is reasonable; 50 sats in competitive environments. |
| `POOL_MIN_INTERVAL` | `5` | **Minimum interval (seconds)** between `NewTemplate` messages from Bitcoin Core. Prevents template spam during mempool volatility. Production: 3–10 seconds. |

### Template Provider Type
`[template_provider_type.BitcoinCoreIpc]` — Bitcoin Core IPC is the default and recommended template source. Alternative: `[template_provider_type.Sv2Tp]` for a remote Template Provider (not in Docker env, use `data_dir` for custom `node.sock` location).

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `network` | `mainnet` | Bitcoin network: `mainnet`, `testnet4`, `signet`, `regtest`. |
| `data_dir` | (default OS path) | Optional override for Bitcoin Core datadir inside the container. Set to `/bitcoin` when mounting the host datadir. The socket path is `{data_dir}/node.sock`. |

### Embedded JDS
`[jds]` — Enables the Job Declaration Server embedded in the pool. Without this section, the pool does not accept Job Declaration connections.

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `jds.listen_address` | `0.0.0.0:3334` | JDS endpoint. JDCs connect here to declare custom block templates via the Job Declaration Protocol. |

### Monitoring
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `monitoring_address` | `0.0.0.0:9090` | HTTP API + Prometheus metrics endpoint. |
| `monitoring_cache_refresh_secs` | `15` | Stats cache refresh interval. Affects monitoring data freshness. |

### Extensions
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `supported_extensions` | `[]` (empty) | SV2 protocol extensions advertised to clients. `0x0002` = Worker-Specific Hashrate Tracking. |
| `required_extensions` | `[]` (empty) | Extensions the pool requires clients to support. Empty = no requirements. |

---

## JD Client Configuration (`jd_client_sv2`)

### Identity & Security
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `authority_public_key` | `9auqWEz...` (hardcoded) | **Ed25519 public key** for this JDC instance. Downstream clients (Translator) connect to the JDC's Mining Protocol endpoint using this key. |
| `authority_secret_key` | `mkDLTBB...` (hardcoded) | **Ed25519 secret key.** |
| `cert_validity_sec` | `3600` | Certificate validity (seconds). |

### Downstream Endpoint
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `listening_address` | `0.0.0.0:34265` | SV2 Mining Protocol endpoint for downstream connections (typically the Translator Proxy). |

### Protocol Versions
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `max_supported_version` | `2` | Maximum SV2 protocol version this JDC supports. |
| `min_supported_version` | `2` | Minimum SV2 protocol version accepted. Set both to 2 for SV2-only; set min to 1 for SV1 fallback. |

### Mining Mode
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `mode` | `FULLTEMPLATE` | **Block template construction mode.** `FULLTEMPLATE` = JDC builds complete block templates (including transaction selection). This is the decentralization feature — miners choose what goes in blocks. `COINBASEONLY` = JDC only modifies the coinbase, pool controls transactions. |

### Mining Configuration
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `JDC_USER_IDENTITY` | `your_username_here` | Username for pool authentication. Must match the mining account on the pool side. |
| `JDC_SIGNATURE` | `Sv2MinerSignature` | ASCII string added to coinbase scriptSig. Identifies this miner/JDC on-chain. |
| `JDC_SHARES_PER_MINUTE` | `6.0` | Target share submission rate downstream. |
| `JDC_SHARE_BATCH_SIZE` | `10` | Shares per batch ack. |
| `JDC_COINBASE_REWARD_SCRIPT` | `addr(tb1q...)` | **Solo mining fallback reward address.** Used when the pool's fallback system activates (pool offline/unreachable). Set to the miner's address. |
| `JDC_FEE_THRESHOLD` | `100` | Fee threshold for template updates from Bitcoin Core. |
| `JDC_MIN_INTERVAL` | `5` | Min interval for template updates. |

### Upstream Connection
`[[upstreams]]` — Array of upstream endpoints. The JDC tries each in order for failover.

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `authority_pubkey` | `${JDC_UPSTREAM_AUTHORITY_PUBKEY}` | **The pool's public key** — must match `pool_sv2`'s `authority_public_key`. |
| `pool_address` | `${JDC_POOL_ADDRESS}` | Pool hostname/IP (Mining Protocol endpoint). |
| `pool_port` | `${JDC_POOL_PORT}` | Pool port (3333). |
| `jds_address` | `${JDC_UPSTREAM_JDS_ADDRESS}` | JDS hostname/IP (Job Declaration endpoint). |
| `jds_port` | `${JDC_UPSTREAM_JDS_PORT}` | JDS port (3334). |

In a local deployment, both `pool_address` and `jds_address` point to `pool_sv2` (Docker service name) or `localhost` if using host networking.

### Monitoring
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `monitoring_address` | `0.0.0.0:9091` | HTTP API + Prometheus endpoint. |

---

## Translator Proxy Configuration (`translator_sv2`)

### SV1 Downstream Endpoint
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `downstream_address` | `0.0.0.0` | SV1 JSON-RPC endpoint for legacy mining devices (e.g. Antminer S9, S19). |
| `downstream_port` | `34255` | SV1 downstream port. SV1 miners configure this as their pool URL (`stratum+tcp://host:34255`). |
| `downstream_extranonce2_size` | `4` | Extranonce2 size in bytes (range 2–8). Defines search space per miner. 4 bytes = 2³² nonces per miner per job. CGminer max is 8. |
| `user_identity` | `${TPROXY_USER_IDENTITY}` | Username for upstream connection. Appended with a miner counter per SV1 client. |
| `aggregate_channels` | `false` | If `true`, all downstream SV1 miners share a single upstream SV2 channel. If `false`, each miner gets its own channel (better hashrate tracking). |

### Difficulty Configuration
`[downstream_difficulty_config]` — Controls how difficulty is managed for downstream SV1 miners.

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `min_individual_miner_hashrate` | `10_000_000_000_000.0` | **Estimated hashrate of the weakest miner (H/s).** Drives initial difficulty for vardiff. 10 TH/s is a reasonable floor. Set lower for older hardware (S9 = ~14 TH/s, S19 = ~110 TH/s). |
| `shares_per_minute` | `6.0` | Target share rate. |
| `enable_vardiff` | `true` | Variable difficulty. Automatically adjusts each miner's difficulty to hit `shares_per_minute`. Disable when behind a JDC (JDC handles difficulty). |
| `job_keepalive_interval_secs` | `60` | Sends keepalive jobs to SV1 miners every N seconds. Prevents miner timeout during low-template periods. |

### Upstream Connection
`[[upstreams]]` — Array of upstream SV2 Mining Protocol endpoints.

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `address` | `${TPROXY_UPSTREAM_ADDRESS}` | Upstream hostname — typically `jd_client_sv2` (JDC) or `pool_sv2` (direct to pool). |
| `port` | `${TPROXY_UPSTREAM_PORT}` | Upstream port — `34265` (JDC) or `3333` (pool directly). |
| `authority_pubkey` | `${TPROXY_UPSTREAM_AUTHORITY_PUBKEY}` | **Upstream's authority public key.** Must match the JDC's or pool's `authority_public_key`. |

### Monitoring
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `monitoring_address` | `0.0.0.0:9092` | HTTP API + Prometheus endpoint. |
| `monitoring_cache_refresh_secs` | `15` | Stats refresh interval. |

### Protocol Versions & Extensions
| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `max_supported_version` | `2` | Maximum SV2 protocol version. |
| `min_supported_version` | `2` | Minimum SV2 protocol version. |
| `supported_extensions` | `[0x0002]` | **Worker-Specific Hashrate Tracking** is enabled by default for the Translator (unlike pool/JDC where it's disabled). This extension allows per-device hashrate monitoring through the proxy. |

---

## Deployment Topology Configurations

From `docker-compose.yml`, four standard topologies:

### 1. `pool_apps` — Pool Only
Pool + Bitcoin Core. No JDC, no Translator. Miners/proxies connect directly to pool.
```
bitcoind ──► pool_sv2 (3333, JDS: 3334)
```

### 2. `pool_and_miner_apps` — Full Stack (Primary)
Pool + JDC + Translator + Bitcoin Core. SV1 miners → Translator → JDC → Pool.
```
bitcoind ──► pool_sv2 (3333, JDS: 3334) ◄── jd_client_sv2 (34265) ◄── translator_sv2 (34255) ◄── SV1 Miners
```

### 3. `pool_and_miner_apps_no_jd` — Pool + Translator (JDC Bypassed)
Pool + Translator + Bitcoin Core. Translator connects directly to pool on port 3333.
```
bitcoind ──► pool_sv2 (3333) ◄── translator_sv2 (34255) ◄── SV1 Miners
```

### 4. `miner_apps` — JDC + Translator (No Local Pool)
JDC + Translator + Bitcoin Core. JDC connects to a remote/hosted pool.
```
bitcoind ──► jd_client_sv2 (34265) ◄── translator_sv2 (34255) ◄── SV1 Miners
                   │
                   └──► Remote Pool (external)
```

---

## Production Hardening Checklist

| Concern | Guidance |
|---|---|
| **Keypairs** | Replace all hardcoded example keypairs. Generate unique ed25519 keys per deployment. The pool's `authority_public_key` must be distributed to all downstream clients. |
| **Network binding** | Change `0.0.0.0` to specific interfaces in production. |
| **coinbase_reward_script** | Use a real mainnet address. Verify the address type (P2WPKH recommended). |
| **user_identity** | Set meaningful identities that map to your mining accounts. |
| **Shares per minute** | Increase for large deployments (30+). Decrease for small ones (3–6). |
| **Certificate validity** | `3600` (1 hour) is standard. Shorter = more re-handshakes but faster key rotation. |
| **Extensions** | Enable `0x0002` (Worker-Specific Hashrate Tracking) if you need per-device monitoring. |
| **Monitoring** | Keep monitoring on localhost only if not needed externally. Use Prometheus for metrics aggregation. |
| **Bitcoin Core** | Ensure node is fully synced before deploying SRI apps. Check with `bitcoin-cli getblockchaininfo`. |
