# HTTP Monitoring API

All SRI apps expose an HTTP JSON API on their configured `monitoring_address`. This is the primary mechanism for building a stateful representation of deployed instances.

## Endpoints

| Endpoint | All Roles | Pool | JDC | Translator |
|---|---|---|---|---|
| `/swagger-ui` | ✓ | | | |
| `/api-docs/openapi.json` | ✓ | | | |
| `/api/v1/health` | ✓ | | | |
| `/api/v1/global` | ✓ | | | |
| `/api/v1/server` | ✓ | | | |
| `/api/v1/server/channels` | ✓ | | | |
| `/api/v1/clients` | ✓ | | | |
| `/api/v1/clients/{id}` | ✓ | | | |
| `/api/v1/clients/{id}/channels` | ✓ | | | |
| `/api/v1/sv1/clients` | | | | ✓ |
| `/api/v1/sv1/clients/{id}` | | | | ✓ |
| `/metrics` (Prometheus) | ✓ | | | |

## Default Monitoring Ports

| Role | Default Port |
|---|---|
| pool_sv2 | 9090 |
| jd_client_sv2 | 9091 |
| translator_sv2 | 9092 |

## Key Endpoint Details

### GET /api/v1/health
Quick liveness check. Useful for: basic connectivity verification.

### GET /api/v1/server
Server metadata: uptime, server status.

### GET /api/v1/server/channels
All active mining channels on this server. Paginated via `?offset=&limit=`. Each channel includes hashrate, status, and uptime data.

### GET /api/v1/clients
All connected SV2 clients (upstream/downstream peers). Paginated. Shows per-client hashrate, channel count, shares accepted, blocks found.

### GET /api/v1/sv1/clients (Translator only)
Legacy SV1 mining devices connected to the translator proxy. Shows per-device hashrate.

## Prometheus Metrics

Available at `/metrics`:

| Metric | Description |
|---|---|
| `sv2_uptime_seconds` | Server uptime |
| `sv2_server_channels` | Active channel count |
| `sv2_server_hashrate_total` | Aggregate server hashrate |
| `sv2_server_channel_hashrate` | Per-channel hashrate |
| `sv2_server_shares_accepted_total` | Cumulative accepted shares |
| `sv2_server_blocks_found_total` | Blocks found |
| `sv2_clients_total` | Connected client count |
| `sv2_client_channels` | Per-client channel count |
| `sv2_client_hashrate_total` | Per-client hashrate |
| `sv2_client_shares_accepted_total` | Per-client share acceptance |
| `sv1_clients_total` | SV1 client count (Translator only) |
| `sv1_hashrate_total` | Aggregate SV1 hashrate (Translator only) |

## Probing Strategy

1. **Health first** — Confirm each role is alive: `curl -sf http://localhost:{port}/api/v1/health`
2. **Topology** — Map channels and clients to understand the connection graph: `/api/v1/server/channels` + `/api/v1/clients`
3. **Performance** — Monitor hashrate and share acceptance over time
4. **Anomaly detection** — Drops in hashrate, client disconnections, stale channels
5. **Cross-reference** — Compare monitoring data against docker logs for correlation

## Stateful Representation

Build a mental model like:

```
pool_sv2 (port 3333)
├── channels: 3
├── hashrate: 150 TH/s
├── clients:
│   └── jd_client_sv2 (upstream peer, port 34265)
│       ├── hashrate: 120 TH/s
│       ├── shares_accepted: 1423
│       └── sv1_clients (via translator): 2 devices
│           ├── device_001: 60 TH/s
│           └── device_002: 60 TH/s
```

Update this representation on each probe to detect state transitions.
