# Sv2 CPU Miner Configuration Reference

Configuration parameters for the [sv2-cpu-miner](https://github.com/plebhash/sv2-cpu-miner).
The agent reads the upstream `config.toml` template (fetched live from the repo), then maps
each parameter to this document for semantic understanding.

## Connection

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `server_addr` | `127.0.0.1:3333` | Pool or JDC Stratum endpoint. For direct pool connections use the pool's `listen_address` (e.g. `127.0.0.1:3333`). For connections via a Job Declarator Client use the JDC's `listening_address` (e.g. `127.0.0.1:34265`). Standard Sv2 TCP endpoint — the miner establishes a Noise-encrypted connection here. |
| `auth_pk` | `9auqWEz...` (SRI example) | Authority public key of the mining server (pool or JDC). Must match the upstream's `authority_public_key` exactly. If it does not match, the Noise NX handshake fails and the connection is rejected. The agent resolves this from the deployed pool or JDC config. |

## Channel Configuration

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `n_extended_channels` | `2` | Number of Extended (Group) Channels to open. Extended channels support miner-built block templates via the Job Declaration Protocol. Each channel spawns an independent tokio task. Set to 0 when connecting directly to a pool that does not have a JDS endpoint, or when only Standard channels are needed. |
| `n_standard_channels` | `2` | Number of Standard Channels to open. Standard channels use pool-provided block templates. Each channel hashes independently with its own nonce search. Useful for simulating multiple logical miners from a single host. |

## Identity

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `user_identity` | `username` | Identity string sent in the Sv2 `SetupConnection` message during channel opening. The pool or JDC uses this for connection tracking and monitoring. Set to a meaningful label (e.g. `cpu-miner-01`) for easier identification in pool monitoring dashboards. |
| `device_id` | `sv2-cpu-miner` | Device identifier sent in Sv2 connection metadata. Maps to on-chain coinbase data if the pool supports miner tagging. |

## Mining Behavior

| Parameter | Default | SV2-Spec Context |
|---|---|---|
| `cpu_usage_percent` | `100` | CPU throttle (1–100). Controls the miner loop duty cycle — the ratio of hashing time to idle time. At 100, the miner hashes continuously (full CPU). At 50, it hashes half the time and sleeps half the time. Lower values reduce host CPU load during testing or when sharing hardware with other services. |
| `nominal_hashrate_multiplier` | `1.0` | Multiplier applied to the nominal hashrate advertised during Sv2 `OpenStandardMiningChannel` or `OpenExtendedMiningChannel` messages. Values >= 0.0. Useful for testing server-side variable difficulty (vardiff) — a multiplier of 10 makes the pool think this miner is 10x faster than it actually is, causing the pool to assign higher difficulty. |
| `single_submit` | `false` | If `true`, each channel stops hashing immediately after submitting its first share. Used for quick smoke tests — verifies channel setup, Noise handshake, and share submission work end-to-end without sustained mining load. |

---

## Deployment Architecture

The sv2-cpu-miner connects to a single Sv2 Mining Protocol endpoint. It can target either
the pool directly or a JDC downstream:

### Direct to pool

```
sv2-cpu-miner (docker, --network host)
  ├── n_extended_channels: N (JDS protocol over Sv2)
  └── n_standard_channels: M (pool templates)
         │
         ▼
pool_sv2:3333  (Mining Protocol)
```

### Via Job Declarator Client

```
sv2-cpu-miner (docker, --network host)
  ├── n_extended_channels: N
  └── n_standard_channels: M
         │
         ▼
jd_client_sv2:34265  (JDC downstream)
         │
         ▼
pool_sv2:3333  (Mining Protocol)
pool_sv2:3334  (JD Protocol)
```

The miner uses `--network host` so `127.0.0.1` in `server_addr` reaches the host's Docker-mapped ports.

---

## Verification

After deployment, confirm shares are flowing:

```bash
# Check miner logs for share submissions
docker logs sv2-cpu-miner --tail 50 | grep -E 'Submitting share'

# Check pool monitoring API
curl -s http://localhost:9090/api/v1/clients | python3 -m json.tool
curl -s http://localhost:9090/api/v1/server/channels | python3 -m json.tool
```

Expected output:
- `SubmitSharesExtended(channel_id=N, ...)` — shares from Extended channels
- `SubmitSharesStandard(channel_id=M, ...)` — shares from Standard channels
- Pool API shows the cpu miner as a connected client with channel counts matching the configuration
