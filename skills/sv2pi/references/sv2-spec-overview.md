# SV2 Protocol Overview

Source: [stratum-mining/sv2-spec](https://github.com/stratum-mining/sv2-spec)

## Sub-Protocols

SV2 defines three sub-protocols layered on top of a common binary framing format:

| Sub-Protocol | Purpose | Participants |
|---|---|---|
| **Mining Protocol** | Job distribution, share submission, difficulty control | Mining Device ↔ Pool / Proxy |
| **Job Declaration Protocol** | Custom block template declaration by miners | JDC ↔ JDS |
| **Template Distribution Protocol** | Block template data retrieval | JDC ↔ Template Provider, Pool ↔ Template Provider |

All messages use binary encoding (not JSON), significantly reducing bandwidth.

## Roles

### Mining Device
The hardware computing hashes. Connects to a Pool (or Proxy) via Mining Protocol. Receives mining jobs, submits shares.

### Pool Service
Central coordinator. Produces jobs, validates shares, propagates found blocks. In SRI, this is `pool_sv2`.

### Mining Proxy (Optional)
Intermediary between Mining Devices and Pool. Aggregates connections. Translates between protocol versions. SRI's `translator_sv2` and `jd_client_sv2` both act as proxies.

### Job Declarator
Split into client (JDC) and server (JDS). Allows miners to declare custom block templates (transaction selection) rather than using pool-provided templates. This is the decentralization mechanism — miners choose what goes in blocks.

### Template Provider
Source of block templates. Typically a Bitcoin Core full node. Provides `NewTemplate` messages with block data. In SRI, accessed either directly via Bitcoin Core IPC or through `sv2-tp` (sv2_tp) as a standalone Template Provider that bridges Bitcoin Core IPC to the Template Distribution Protocol over TCP.

The standalone `sv2-tp` (`stratumv2/sv2-tp`) connects to Bitcoin Core via IPC and serves templates to Pool and JDC over the Template Distribution Protocol (Noise-encrypted TCP, default port 8442 on mainnet). It handles reconnection, fee monitoring, and rate-limited template updates.

## Protocol Layering

```
┌─────────────────────────────────────┐
│  Mining Protocol                    │  ← Job negotiation, share submission
├─────────────────────────────────────┤
│  Job Declaration Protocol           │  ← Custom template declaration
├─────────────────────────────────────┤
│  Template Distribution Protocol     │  ← Block template retrieval
├─────────────────────────────────────┤
│  Common Binary Framing              │  ← Message types, framing, encryption
└─────────────────────────────────────┘
```

## Security

- **Encryption:** All SV2 connections use Noise protocol for authenticated encryption
- **Authentication:** Authority keypairs (ed25519) identify servers and clients
- **No plaintext shares:** Unlike SV1, shares and jobs are not visible to network intermediaries
- Sub-protocols can be used independently — adopt incrementally

## Key Concepts for Deployment

- The **Pool** must be the first role deployed — all other roles connect upstream to it
- **sv2-tp** is an optional standalone Template Provider that bridges Bitcoin Core IPC to Template Distribution Protocol over TCP
- **JDC** bridges between Bitcoin Core (template source) and Pool (template consumer); it can use either direct IPC or sv2-tp
- **Translator** enables incremental adoption — SV1 hardware works with SV2 pool
- `authority_public_key` must match between downstream clients and their upstream server
- Certificates are self-signed with `cert_validity_sec` (typically 3600s / 1 hour)
