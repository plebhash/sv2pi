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
5. `sv2-tp/` — `docker_env.example` in frozen template for sv2-tp v1.1.0 (CLI-based, no TOML)
5. `sv2-tp/` — `docker_env.example` in frozen template for sv2-tp v1.1.0 (CLI-based, no TOML)

---

## Global: Bitcoin Core IPC

```
+---------------------+------------------------------------+------------------------------------------------------------------------+
| Parameter           | Default                            | SV2-Spec Context                                                       |
+---------------------+------------------------------------+------------------------------------------------------------------------+
| BITCOIN_SOCKET_PATH | /absolute/path/to/your/node.sock   | Path to Bitcoin Core UNIX socket. Required by Pool and JDC for        |
|                     |                                    | Template Distribution. Bitcoin Core v30.2+ must use -ipcbind=unix.    |
+---------------------+------------------------------------+------------------------------------------------------------------------+
```

The `BITCOIN_SOCKET_PATH` must be a valid `node.sock` inside the Bitcoin Core datadir. The container mounts the parent directory (e.g. `/host/path/.bitcoin` → `/root/.bitcoin/node.sock` inside).

---

## Pool Configuration (`pool_sv2`)

### Identity & Security

```
+----------------------+-----------------+-----------------------------------------------------------------------------------+
| Parameter            | Default         | SV2-Spec Context                                                                  |
+----------------------+-----------------+-----------------------------------------------------------------------------------+
| authority_public_key | 9auqWEz...      | Ed25519 pubkey (base58, 44 chars). Used in Noise NX handshake. All downstream    |
|                      | (hardcoded)     | clients must reference this in their [[upstreams]].authority_pubkey.              |
|                      |                 | FOR PRODUCTION: generate a unique keypair per deployment.                         |
| authority_secret_key | mkDLTBB...      | Ed25519 secret key. Paired with above. Never leaves the pool server.              |
|                      | (hardcoded)     |                                                                                   |
| cert_validity_sec    | 3600            | Noise cert validity (seconds). After expiry clients must re-handshake.            |
+----------------------+-----------------+-----------------------------------------------------------------------------------+
```

### Stratum Endpoint

```
+----------------+----------------+-----------------------------------------------------------------------------------+
| Parameter      | Default        | SV2-Spec Context                                                                  |
+----------------+----------------+-----------------------------------------------------------------------------------+
| listen_address | 0.0.0.0:3333   | SV2 Mining Protocol endpoint. JDCs, proxies, and miners connect here via Noise.  |
+----------------+----------------+-----------------------------------------------------------------------------------+
```

### Mining Configuration

```
+----------------------+----------------------+------------------------------------------------------------------------+
| Parameter            | Default              | SV2-Spec Context                                                       |
+----------------------+----------------------+------------------------------------------------------------------------+
| coinbase_reward_script| addr(tb1q...)       | Output descriptor for coinbase. Use mainnet P2WPKH/P2WSH in prod.     |
| pool_signature       | Stratum V2 SRI Pool  | ASCII string in coinbase scriptSig. Identifies pool on-chain.          |
| server_id            | 1                    | Pool server ID. Relevant behind a load balancer.                       |
| shares_per_minute    | 6.0                  | Target share rate per downstream. Drives vardiff. Prod: 6-30.          |
| share_batch_size     | 10                   | Shares batched before sending AcceptShare. Reduces message overhead.   |
+----------------------+----------------------+------------------------------------------------------------------------+
```

### Template Provider

```
+--------------------+---------+--------------------------------------------------------------------------------+
| Parameter          | Default | SV2-Spec Context                                                               |
+--------------------+---------+--------------------------------------------------------------------------------+
| POOL_FEE_THRESHOLD | 100     | Fee delta (sats) to trigger new template from Bitcoin Core. Prod: 100 sats.   |
| POOL_MIN_INTERVAL  | 5       | Min seconds between NewTemplate messages. Prevents template spam. Prod: 3-10. |
+--------------------+---------+--------------------------------------------------------------------------------+
```

### Template Provider Type
`[template_provider_type.BitcoinCoreIpc]` — Bitcoin Core IPC is the default and recommended template source. Alternative: `[template_provider_type.Sv2Tp]` for a remote Template Provider (not in Docker env, use `data_dir` for custom `node.sock` location).

```
+-----------+------------------+-----------------------------------------------------------------------------------+
| Parameter | Default          | SV2-Spec Context                                                                  |
+-----------+------------------+-----------------------------------------------------------------------------------+
| network   | mainnet          | Bitcoin network: mainnet, testnet4, signet, regtest.                              |
| data_dir  | (default OS path)| Override for Bitcoin Core datadir in container. Socket: {data_dir}/node.sock.    |
+-----------+------------------+-----------------------------------------------------------------------------------+
```

### Embedded JDS
`[jds]` — Enables the Job Declaration Server embedded in the pool. Without this section, the pool does not accept Job Declaration connections.

```
+--------------------+----------------+-----------------------------------------------------------------------------------+
| Parameter          | Default        | SV2-Spec Context                                                                  |
+--------------------+----------------+-----------------------------------------------------------------------------------+
| jds.listen_address | 0.0.0.0:3334   | JDS endpoint. JDCs connect here to declare custom templates via JD Protocol.     |
+--------------------+----------------+-----------------------------------------------------------------------------------+
```

### Monitoring

```
+---------------------------------+---------+------------------------------------------------------------------+
| Parameter                       | Default | SV2-Spec Context                                                 |
+---------------------------------+---------+------------------------------------------------------------------+
| monitoring_address              | 0.0.0.0:9090 | HTTP API + Prometheus metrics endpoint.                     |
| monitoring_cache_refresh_secs   | 15      | Stats cache refresh interval.                                    |
+---------------------------------+---------+------------------------------------------------------------------+
```

### Extensions

```
+----------------------+----------+------------------------------------------------------------------------+
| Parameter            | Default  | SV2-Spec Context                                                       |
+----------------------+----------+------------------------------------------------------------------------+
| supported_extensions | [] empty | Extensions advertised to clients. 0x0002 = Per-worker hashrate.        |
| required_extensions  | [] empty | Extensions clients must support. Empty = no requirements.              |
+----------------------+----------+------------------------------------------------------------------------+
```

---

## JD Client Configuration (`jd_client_sv2`)

### Identity & Security

```
+----------------------+-----------------+-----------------------------------------------------------------------------------+
| Parameter            | Default         | SV2-Spec Context                                                                  |
+----------------------+-----------------+-----------------------------------------------------------------------------------+
| authority_public_key | 9auqWEz...      | Ed25519 pubkey for this JDC. Downstream clients (Translator) connect using this. |
|                      | (hardcoded)     |                                                                                   |
| authority_secret_key | mkDLTBB...      | Ed25519 secret key.                                                               |
|                      | (hardcoded)     |                                                                                   |
| cert_validity_sec    | 3600            | Certificate validity (seconds).                                                   |
+----------------------+-----------------+-----------------------------------------------------------------------------------+
```

### Downstream Endpoint

```
+--------------------+-----------------+-----------------------------------------------------------------------------------+
| Parameter          | Default         | SV2-Spec Context                                                                  |
+--------------------+-----------------+-----------------------------------------------------------------------------------+
| listening_address  | 0.0.0.0:34265   | SV2 Mining Protocol endpoint for downstream connections (Translator Proxy).       |
+--------------------+-----------------+-----------------------------------------------------------------------------------+
```

### Protocol Versions

```
+------------------------+---------+-------------------------------------------------------------------------+
| Parameter              | Default | SV2-Spec Context                                                        |
+------------------------+---------+-------------------------------------------------------------------------+
| max_supported_version  | 2       | Maximum SV2 protocol version this JDC supports.                         |
| min_supported_version  | 2       | Minimum accepted. Set both to 2 for SV2-only; min=1 for SV1 fallback.  |
+------------------------+---------+-------------------------------------------------------------------------+
```

### Mining Mode

```
+-----------+--------------+-----------------------------------------------------------------------------------+
| Parameter | Default      | SV2-Spec Context                                                                  |
+-----------+--------------+-----------------------------------------------------------------------------------+
| mode      | FULLTEMPLATE | FULLTEMPLATE: JDC builds full templates (miners choose transactions).             |
|           |              | COINBASEONLY: JDC modifies coinbase only; pool controls transaction selection.    |
+-----------+--------------+-----------------------------------------------------------------------------------+
```

### Mining Configuration

```
+----------------------------+----------------------+----------------------------------------------------------------------+
| Parameter                  | Default              | SV2-Spec Context                                                     |
+----------------------------+----------------------+----------------------------------------------------------------------+
| JDC_USER_IDENTITY          | your_username_here   | Username for pool auth. Must match mining account on pool side.      |
| JDC_SIGNATURE              | Sv2MinerSignature    | ASCII string in coinbase scriptSig. Identifies JDC on-chain.         |
| JDC_SHARES_PER_MINUTE      | 6.0                  | Target share submission rate downstream.                             |
| JDC_SHARE_BATCH_SIZE       | 10                   | Shares per batch ack.                                                |
| JDC_COINBASE_REWARD_SCRIPT | addr(tb1q...)        | Solo mining fallback address. Used when pool is offline/unreachable. |
| JDC_FEE_THRESHOLD          | 100                  | Fee threshold for template updates from Bitcoin Core.                |
| JDC_MIN_INTERVAL           | 5                    | Min interval for template updates.                                   |
+----------------------------+----------------------+----------------------------------------------------------------------+
```

### Upstream Connection
`[[upstreams]]` — Array of upstream endpoints. The JDC tries each in order for failover.

```
+-----------------+------------------------------+---------------------------------------------------------------+
| Parameter       | Default                      | SV2-Spec Context                                              |
+-----------------+------------------------------+---------------------------------------------------------------+
| authority_pubkey| JDC_UPSTREAM_AUTHORITY_PUBKEY| The pool's public key - must match pool_sv2 authority_pubkey. |
| pool_address    | JDC_POOL_ADDRESS             | Pool hostname/IP (Mining Protocol endpoint).                  |
| pool_port       | JDC_POOL_PORT                | Pool port (3333).                                             |
| jds_address     | JDC_UPSTREAM_JDS_ADDRESS     | JDS hostname/IP (Job Declaration endpoint).                   |
| jds_port        | JDC_UPSTREAM_JDS_PORT        | JDS port (3334).                                              |
+-----------------+------------------------------+---------------------------------------------------------------+
```

In a local deployment, both `pool_address` and `jds_address` point to `pool_sv2` (Docker service name) or `localhost` if using host networking.

### Monitoring

```
+--------------------+----------------+------------------------------------+
| Parameter          | Default        | SV2-Spec Context                   |
+--------------------+----------------+------------------------------------+
| monitoring_address | 0.0.0.0:9091   | HTTP API + Prometheus endpoint.    |
+--------------------+----------------+------------------------------------+
```

---

## Translator Proxy Configuration (`translator_sv2`)

### SV1 Downstream Endpoint

```
+-----------------------------+-------------------------+-----------------------------------------------------------------------+
| Parameter                   | Default                 | SV2-Spec Context                                                      |
+-----------------------------+-------------------------+-----------------------------------------------------------------------+
| downstream_address          | 0.0.0.0                 | SV1 JSON-RPC endpoint for legacy miners (Antminer S9, S19, etc.).    |
| downstream_port             | 34255                   | SV1 miners point stratum+tcp://host:34255 here.                       |
| downstream_extranonce2_size | 4                       | Extranonce2 bytes (2-8). 4 bytes = 2^32 nonces/miner/job.            |
| user_identity               | TPROXY_USER_IDENTITY    | Username for upstream. Appended with miner counter per SV1 client.   |
| aggregate_channels          | false                   | true: all SV1 miners share one SV2 channel. false: per-miner channel.|
+-----------------------------+-------------------------+-----------------------------------------------------------------------+
```

### Difficulty Configuration
`[downstream_difficulty_config]` — Controls difficulty for downstream SV1 miners.

```
+------------------------------+------------------------+----------------------------------------------------------------------+
| Parameter                    | Default                | SV2-Spec Context                                                     |
+------------------------------+------------------------+----------------------------------------------------------------------+
| min_individual_miner_hashrate| 10_000_000_000_000.0   | Weakest miner hashrate (H/s). Drives initial vardiff. S9~14TH/s.    |
| shares_per_minute            | 6.0                    | Target share rate.                                                   |
| enable_vardiff               | true                   | Auto-adjust difficulty per miner. Disable when JDC handles vardiff.  |
| job_keepalive_interval_secs  | 60                     | Keepalive jobs to SV1 miners every N secs. Prevents miner timeout.  |
+------------------------------+------------------------+----------------------------------------------------------------------+
```

### Upstream Connection
`[[upstreams]]` — Array of upstream SV2 Mining Protocol endpoints.

```
+------------------+------------------------------+----------------------------------------------------------------------+
| Parameter        | Default                      | SV2-Spec Context                                                     |
+------------------+------------------------------+----------------------------------------------------------------------+
| address          | TPROXY_UPSTREAM_ADDRESS      | Upstream hostname: jd_client_sv2 (JDC) or pool_sv2 (direct).        |
| port             | TPROXY_UPSTREAM_PORT         | Upstream port: 34265 (JDC) or 3333 (pool directly).                 |
| authority_pubkey | TPROXY_UPSTREAM_AUTHORITY_PK | Must match JDC or pool authority_public_key.                         |
+------------------+------------------------------+----------------------------------------------------------------------+
```

### Monitoring

```
+---------------------------------+--------------+----------------------------------------------+
| Parameter                       | Default      | SV2-Spec Context                             |
+---------------------------------+--------------+----------------------------------------------+
| monitoring_address              | 0.0.0.0:9092 | HTTP API + Prometheus endpoint.              |
| monitoring_cache_refresh_secs   | 15           | Stats refresh interval.                      |
+---------------------------------+--------------+----------------------------------------------+
```

### Protocol Versions & Extensions

```
+----------------------+----------+-----------------------------------------------------------------------------------+
| Parameter            | Default  | SV2-Spec Context                                                                  |
+----------------------+----------+-----------------------------------------------------------------------------------+
| max_supported_version| 2        | Maximum SV2 protocol version.                                                     |
| min_supported_version| 2        | Minimum SV2 protocol version.                                                     |
| supported_extensions | [0x0002] | Worker-Specific Hashrate Tracking enabled by default (unlike pool/JDC).           |
+----------------------+----------+-----------------------------------------------------------------------------------+
```

---

## SV2 Template Provider Configuration (`sv2_tp`)

sv2-tp is a C++ application that uses CLI flags (like Bitcoin Core), not TOML config files.
It is deployed via `deploy-tp.sh` which passes flags directly to the container entrypoint.

### Core Parameters

```
+----------------------------+-----------------------------+----------------------------------------------------------------------+
| Flag                       | Default                     | SV2-Spec Context                                                     |
+----------------------------+-----------------------------+----------------------------------------------------------------------+
| -ipcconnect=unix           | unix                        | Connect to Bitcoin Core via IPC. Looks for socket at default path.   |
|                            |                             | Explicit path: -ipcconnect=unix:/custom/path/node.sock               |
| -chain=<chain>             | main                        | Bitcoin network: main, testnet4, signet, regtest.                    |
| -sv2bind=<addr>[:<port>]   | 127.0.0.1:(chain default)   | Bind for Template Distribution. 0.0.0.0 for all interfaces.         |
|                            |                             | Ports: 8442 mainnet, 48442 testnet4, 38442 signet, 18447 regtest.   |
| -sv2port=<port>            | (chain default)             | Override SV2 listening port.                                         |
| -debug=sv2                 | (none)                      | Enable SV2-related debug logging.                                    |
| -loglevel=sv2:trace        | (none)                      | Set log level. sv2:trace shows message-level dumps (verbose).        |
+----------------------------+-----------------------------+----------------------------------------------------------------------+
```

### Template Update Parameters

```
+----------------------------+---------+----------------------------------------------------------------------+
| Flag                       | Default | SV2-Spec Context                                                     |
+----------------------------+---------+----------------------------------------------------------------------+
| -sv2feedelta=<satoshis>    | 1000    | Min fee delta (sats) to push a new template. Lower = more frequent.  |
| -templateinterval=<secs>   | 5       | Min secs between fee-based updates. New blocks always propagate.     |
+----------------------------+---------+----------------------------------------------------------------------+
```

### Compatibility

```
+----------------+------------------+--------------------------------------------------+
| sv2-tp Version | Min Bitcoin Core | Template Provider Type for Pool/JDC              |
+----------------+------------------+--------------------------------------------------+
| v1.1.0         | v31.0            | [template_provider_type.Sv2Tp] addr=127.0.0.1:8442|
| v1.0.6         | v30.2            | [template_provider_type.Sv2Tp] addr=127.0.0.1:8442|
+----------------+------------------+--------------------------------------------------+
```

When sv2-tp is deployed, Pool and JDC configs must use `Sv2Tp` instead of `BitcoinCoreIpc`:
```toml
# Pool config: replace [template_provider_type.BitcoinCoreIpc] with:
[template_provider_type.Sv2Tp]
address = "127.0.0.1:8442"
```

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

### 5. `sv2_tp` — With SV2 Template Provider
sv2-tp + Pool + JDC + Translator + Bitcoin Core. sv2-tp bridges Bitcoin Core IPC to Template Distribution Protocol over TCP.
```
bitcoind ──(IPC)──► sv2_tp (8442) ──(SV2 TP)──► pool_sv2 (3333, JDS: 3334)
                       │
                       └──(SV2 TP)──► jd_client_sv2 (34265) ◄── translator_sv2 (34255) ◄── SV1 Miners
```
Pool and JDC use `template_provider_type.Sv2Tp` instead of `BitcoinCoreIpc`.

---

## Production Hardening Checklist

```
+------------------------+-----------------------------------------------------------------------------------+
| Concern                | Guidance                                                                          |
+------------------------+-----------------------------------------------------------------------------------+
| Keypairs               | Replace hardcoded example keypairs. Generate unique ed25519 per deployment.       |
|                        | Pool authority_public_key must be distributed to all downstream clients.          |
| Network binding        | Change 0.0.0.0 to specific interfaces in production.                              |
| coinbase_reward_script | Use a real mainnet address. P2WPKH recommended.                                   |
| user_identity          | Set meaningful identities that map to your mining accounts.                       |
| Shares per minute      | Increase for large deployments (30+). Decrease for small ones (3-6).              |
| Certificate validity   | 3600s (1 hour) is standard. Shorter = more re-handshakes but faster key rotation. |
| Extensions             | Enable 0x0002 (Worker-Specific Hashrate Tracking) for per-device monitoring.      |
| Monitoring             | Keep monitoring on localhost only if not external. Use Prometheus for metrics.    |
| Bitcoin Core           | Ensure node is fully synced before deploying SRI apps.                            |
+------------------------+-----------------------------------------------------------------------------------+
```
