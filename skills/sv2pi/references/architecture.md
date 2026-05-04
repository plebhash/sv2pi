# SRI Architecture

## Role Connection Flow

```
┌─────────────┐     IPC (node.sock)      ┌────────────────────────────┐
│  Bitcoin    │─────────────────────────►│  pool_sv2 (Pool + JDS)     │
│  Core       │                          │                            │
│  v30.2+     │                          │  Stratum endpoint: 3333    │
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

## Role Descriptions

### pool_sv2
The central SV2 pool server. It:
- Accepts mining connections via SV2 Mining Protocol on the stratum endpoint (3333)
- Runs an embedded JDS (Job Declarator Server) on port 3334
- Obtains block templates from Bitcoin Core via IPC (default) or a remote Sv2 Template Provider
- Validates shares and distributes mining jobs

Config requires: Noise authority keypair, template provider config (IPC or Sv2Tp), mining reward script

### jd_client_sv2
The Job Declarator Client. It:
- Receives block templates from Bitcoin Core via IPC
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
| pool_sv2 | 3333 | SV2 Mining Protocol | Downstream |
| pool_sv2 | 3334 | SV2 Job Declaration | Downstream |
| pool_sv2 | 9090 | HTTP Monitoring | Internal |
| jd_client | 34265 | SV2 Mining Protocol | Downstream |
| jd_client | 9091 | HTTP Monitoring | Internal |
| translator | 34255 | SV1 JSON-RPC | Downstream |
| translator | 9092 | HTTP Monitoring | Internal |

## Connection Requirements

For the deployment to work:

1. **Bitcoin Core** must be running with `-ipcbind=unix` and be synced
2. **Pool** needs read access to `node.sock` — mounted as `/bitcoin/node.sock` in container
3. **JDC** needs read access to `node.sock` — can be the same or different Bitcoin Core instance
4. **JDC→Pool** uses Noise NX handshake with pool's authority public key
5. **JDC→JDS** uses Noise NX with pool's authority public key
6. **Translator→JDC** uses Noise NX with JDC's authority public key
7. **SV1 miners→Translator** is plain JSON-RPC (no encryption)
