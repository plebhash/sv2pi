# Sv2 CPU Miner Configuration Reference

Configuration parameters for the [sv2-cpu-miner](https://github.com/plebhash/sv2-cpu-miner).
The agent reads the upstream `config.toml` template (fetched live from the repo), then maps
each parameter to this document for semantic understanding.

## Connection

```
+-------------+-------------------+-------------------------------------------------------------------------------------+
| Parameter   | Default           | SV2-Spec Context                                                                    |
+-------------+-------------------+-------------------------------------------------------------------------------------+
| server_addr | 127.0.0.1:3333    | Pool or JDC Stratum endpoint. Direct pool: pool listen_address (3333).              |
|             |                   | Via JDC: JDC listening_address (34265). Noise-encrypted Sv2 TCP connection.         |
| auth_pk     | 9auqWEz... (SRI)  | Authority pubkey of the mining server. Must match upstream authority_public_key.    |
|             |                   | Mismatch = Noise NX handshake failure. Agent resolves from deployed pool/JDC config.|
+-------------+-------------------+-------------------------------------------------------------------------------------+
```

## Channel Configuration

```
+---------------------+---------+-----------------------------------------------------------------------------------+
| Parameter           | Default | SV2-Spec Context                                                                  |
+---------------------+---------+-----------------------------------------------------------------------------------+
| n_extended_channels | 2       | Extended (Group) channels for miner-built templates via JD Protocol.              |
|                     |         | Set to 0 when connecting to a pool without JDS, or when only Standard needed.    |
| n_standard_channels | 2       | Standard channels using pool-provided templates. Each hashes independently.       |
|                     |         | Useful for simulating multiple logical miners from one host.                      |
+---------------------+---------+-----------------------------------------------------------------------------------+
```

## Identity

```
+---------------+----------------+-----------------------------------------------------------------------------------+
| Parameter     | Default        | SV2-Spec Context                                                                  |
+---------------+----------------+-----------------------------------------------------------------------------------+
| user_identity | username       | Identity in Sv2 SetupConnection. Used by pool/JDC for tracking. Use a label      |
|               |                | like cpu-miner-01 for easier identification in monitoring dashboards.             |
| device_id     | sv2-cpu-miner  | Device identifier in Sv2 connection metadata. Maps to on-chain coinbase data.    |
+---------------+----------------+-----------------------------------------------------------------------------------+
```

## Mining Behavior

```
+-----------------------------+---------+-----------------------------------------------------------------------------------+
| Parameter                   | Default | SV2-Spec Context                                                                  |
+-----------------------------+---------+-----------------------------------------------------------------------------------+
| cpu_usage_percent           | 100     | CPU throttle (1-100). Duty cycle: hashing vs idle time ratio.                     |
|                             |         | 100=continuous, 50=half time. Lower reduces host load during testing.             |
| nominal_hashrate_multiplier | 1.0     | Multiplier on advertised hashrate in OpenStandardMiningChannel messages.          |
|                             |         | multiplier=10 makes pool think miner is 10x faster -> higher difficulty assigned. |
| single_submit               | false   | If true, each channel stops after its first share. Quick smoke test mode.         |
+-----------------------------+---------+-----------------------------------------------------------------------------------+
```

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
