# SRI Architecture

## Role Connection Flow

### Mode A: Direct IPC (no sv2-tp)

```
┌─────────────┐     IPC (node.sock)      ┌────────────────────────────┐
│  Bitcoin    │─────────────────────────►│  pool_sv2 (Pool + JDS)     │
│  Core       │                          │                            │
│  v31.0+     │                          │  Stratum endpoint: 3333    │
│             │                          │  JDS endpoint:    3334    │
│  -ipcbind   │                          │  Monitoring API:  9090    │
│   =unix     │                          └──────────┬────────┬────────┘
└─────────────┘                                     │        │
                                                    │        │ (JD protocol)
                                                    │        ▼
┌─────────────┐     IPC (node.sock)      ┌────────────────────────────┐
│  Bitcoin    │─────────────────────────►│  jd_client_sv2 (JDC)      │
│  Core       │                          │                            │
│             │                          │  Downstream:      34265   │
│  (same or   │                          │  Upstream pool:   3333    │
│   different │                          │  Upstream JDS:    3334    │
│   node)     │                          │  Monitoring API:  9091    │
└─────────────┘                          └────────────┬───────────────┘
                                                      │
                                                      │ (SV2 Mining Protocol)
                                                      ▼
                                           ┌────────────────────────────┐
                                           │  translator_sv2            │
                                           │                            │
                                           │  SV1 Downstream:  34255    │
                                           │  SV2 Upstream:    JDC:34265│
                                           │  Monitoring API:  9092    │
                                           └────────────┬───────────────┘
                                                        │
                                                        │ (SV1 JSON-RPC)
                                          ┌─────────────▼──────────────┐
                                          │  SV1 Mining Devices        │
                                          │  (legacy hardware)         │
                                          └────────────────────────────┘
```

### Mode B: With sv2-tp (Template Distribution Protocol)

```
┌─────────────┐     IPC (node.sock)      ┌────────────────────────────┐
│  Bitcoin    │─────────────────────────►│  sv2_tp                    │
│  Core       │                          │                            │
│  v31.0+     │                          │  SV2 endpoint:     8442    │
│             │                          │  (Template Distribution    │
│  -ipcbind   │                          │   Protocol over TCP with   │
│   =unix     │                          │   Noise encryption)        │
└─────────────┘                          └────────────┬───────────────┘
                                                      │
                                          (SV2 Template Distribution)
                                                      │
                            ┌─────────────────────────┼─────────────────────┐
                            │                         │                     │
                            ▼                         ▼                     │
              ┌────────────────────────────┐  ┌────────────────────────────┐
              │  pool_sv2 (Pool + JDS)     │  │  jd_client_sv2 (JDC)      │
              │                            │  │                            │
              │  template_provider_type    │  │  template_provider_type    │
              │    .Sv2Tp                  │  │    .Sv2Tp                  │
              │  address = sv2_tp:8442     │  │  address = sv2_tp:8442     │
              │                            │  │                            │
              │  Stratum: 3333             │  │  Downstream:      34265   │
              │  JDS:     3334             │  │  Upstream pool:   3333    │
              │  Monitoring: 9090          │  │  Upstream JDS:    3334    │
              └──────────┬────────┬────────┘  │  Monitoring:      9091    │
                         │        │           └────────────┬───────────────┘
                         │        │ (JD)                   │
                         │        ▼                        │
                         │  ◄───────────────────────────── │
                         │                                 │
                         └─────────────────────────────────│
                                                           │ (SV2 Mining)
                                                           ▼
                                              ┌────────────────────────────┐
                                              │  translator_sv2            │
                                              │  SV1: 34255, SV2 Up: 34265 │
                                              │  Monitoring: 9092          │
                                              └────────────────────────────┘
```

## Role Descriptions

### sv2_tp
The SV2 Template Provider. It:
- Connects to Bitcoin Core via IPC (`-ipcconnect=unix`)
- Serves the Template Distribution Protocol over TCP with Noise encryption
- Pushes new block templates to connected Pool and JDC clients
- Handles template updates on new blocks and fee increases
- Reconnects automatically to Bitcoin Core if the IPC connection drops (retry every 10s)

Default SV2 ports: mainnet 8442, testnet4 48442, signet 38442, regtest 18447.

### pool_sv2
The central SV2 pool server. It:
- Accepts mining connections via SV2 Mining Protocol on the stratum endpoint (3333)
- Runs an embedded JDS (Job Declarator Server) on port 3334
- Obtains block templates from Bitcoin Core via IPC (default) or a remote SV2 Template Provider (sv2-tp)
- Validates shares and distributes mining jobs

Config requires: Noise authority keypair, template provider config (IPC or Sv2Tp), mining reward script

### jd_client_sv2
The Job Declarator Client. It:
- Receives block templates from Bitcoin Core via IPC (or sv2-tp via Sv2Tp)
- Declares custom block templates to the pool's JDS
- Accepts SV2 mining connections downstream on port 34265
- Forwards shares to the pool upstream on port 3333

Supports `FULLTEMPLATE` and `COINBASEONLY` modes. In FULLTEMPLATE mode, the JDC constructs complete block templates (miner selects transactions).

### translator_sv2
SV1→SV2 Translation Proxy. It:
- Accepts legacy SV1 (JSON-RPC) mining devices on the downstream port (34255)
- Translates SV1 messages to SV2 Mining Protocol
- Connects upstream to JDC (34265) or directly to pool (3333)
- Supports channel aggregation and vardiff for downstream miners

## Default Ports

| Role | Port | Protocol | Direction |
|---|---|---|---|
| sv2_tp | 8442 | SV2 Template Distribution (Noise) | Downstream |
| pool_sv2 | 3333 | SV2 Mining Protocol | Downstream |
| pool_sv2 | 3334 | SV2 Job Declaration | Downstream |
| pool_sv2 | 9090 | HTTP Monitoring | Internal |
| jd_client | 34265 | SV2 Mining Protocol | Downstream |
| jd_client | 9091 | HTTP Monitoring | Internal |
| translator | 34255 | SV1 JSON-RPC | Downstream |
| translator | 9092 | HTTP Monitoring | Internal |

### SV2 Template Provider Ports Per Network

| Network | sv2-tp Port |
|---|---|
| mainnet | 8442 |
| testnet4 | 48442 |
| signet | 38442 |
| regtest | 18447 |

## Connection Requirements

For the deployment to work:

### Mode A (Direct IPC)
1. **Bitcoin Core** must be running with `-ipcbind=unix` and be synced
2. **Pool** needs read access to `node.sock` — mounted as `/home/bitcoin/.bitcoin/node.sock` in container
3. **JDC** needs read access to `node.sock` — can be the same or different Bitcoin Core instance
4. **JDC→Pool** uses Noise NX handshake with pool's authority public key
5. **JDC→JDS** uses Noise NX with pool's authority public key
6. **Translator→JDC** uses Noise NX with JDC's authority public key
7. **SV1 miners→Translator** is plain JSON-RPC (no encryption)

### Mode B (With sv2-tp)
1. **Bitcoin Core** must be running with `-ipcbind=unix` and be synced
2. **sv2-tp** connects to Bitcoin Core via IPC (`-ipcconnect=unix`), sharing the same Bitcoin Core datadir volume
3. **Pool** uses `template_provider_type.Sv2Tp` with `address = "sv2_tp:8442"` (or `127.0.0.1:8442`)
4. **JDC** uses `template_provider_type.Sv2Tp` with `address = "sv2_tp:8442"`
5. **JDC→Pool** uses Noise NX handshake with pool's authority public key
6. **JDC→JDS** uses Noise NX with pool's authority public key
7. **Translator→JDC** uses Noise NX with JDC's authority public key
8. **SV1 miners→Translator** is plain JSON-RPC (no encryption)
9. sv2-tp reconnects automatically to Bitcoin Core on disconnect (retry every 10s)
