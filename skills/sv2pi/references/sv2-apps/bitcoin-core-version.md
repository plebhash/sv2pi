# Bitcoin Core Version Compatibility

Each SRI release and sv2-tp release requires a specific minimum Bitcoin Core version. This document tracks the compatibility matrix.

## Per-Release Requirements

### SRI (Pool / JDC / Translator)

| SRI Tag | `bitcoin_core_sv2` Crate | Minimum Bitcoin Core | Docker Tag | Notes |
|---|---|---|---|---|---|
| `main` (rolling) | v0.2.0 | **v31.0** | `bitcoin/bitcoin:latest` or `31.0` | `bitcoin/bitcoin:latest` currently resolves to 31.0. Verify with `docker run --rm bitcoin/bitcoin:latest bitcoind --version`. |
| v0.3.5 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | `BitcoinCoreIpc` config exists. |
| v0.3.4 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | Same as above. |
| v0.3.3 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | Same as above. |
| v0.3.2 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | Same as above. |
| v0.3.1 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | Same as above. |
| v0.3.0 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | Same as above. |
| v0.2.0 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | Same as above. |
| v0.1.0 | not bundled | **v30.2** | `bitcoin/bitcoin:30.2` | Same as above. |

### sv2-tp (Template Provider)

| sv2-tp Tag | Minimum Bitcoin Core | Docker Tag | Notes |
|---|---|---|---|
| v1.1.0 | **v31.0** | `stratumv2/sv2-tp:v1.1.0` | Connects to Bitcoin Core via IPC (`-ipcconnect=unix`). Serves Template Distribution Protocol on TCP (8442 mainnet default). |
| v1.0.6 | **v30.2** | `stratumv2/sv2-tp:v1.0.6` | Last release compatible with Bitcoin Core v30.2. |

## Compatible SRI / sv2-tp Tags per Bitcoin Core Version

This is the reverse lookup. After deploying Bitcoin Core, the agent must only suggest SRI/sv2-tp tags from the matching row.

| Bitcoin Core Version | Compatible SRI Tags | Compatible sv2-tp Tags |
|---|---|---|
| **v31.0** (Docker `31.0`, `latest`) | `main` only | v1.1.0 |
| **v30.2** (Docker `30.2`) | `v0.3.5`, `v0.3.4`, `v0.3.3`, `v0.3.2`, `v0.3.1`, `v0.3.0`, `v0.2.0`, `v0.1.0` | v1.0.6 |

**Enforcement rule:** if the user asks to deploy an SRI or sv2-tp tag that is incompatible with the running Bitcoin Core version, stop and explain which tags are compatible. Never deploy a mismatched pair.

Source: `sv2-apps/docker/README.md` (states "Bitcoin Core v30.2++") and `sv2-apps/bitcoin-core-sv2/README.md` (version compatibility table for the IPC crate).

## How to Determine for Any Release

The authoritative source for Bitcoin Core version requirements lives in two places:

1. **For SRI releases that bundle `bitcoin_core_sv2`** — read `sv2-apps/bitcoin-core-sv2/README.md` (the Version Compatibility table).
2. **For SRI releases without `bitcoin_core_sv2`** — read `sv2-apps/docker/README.md` (the Requirements section).
3. **For sv2-tp releases** — read `sv2-tp/doc/stratum-v2.md` (the Requirements section) or this document's frozen matrix.

When the agent selects a deployment tag:
- If the tag is `main` (SRI), clone the repo and check both files
- If the tag is an SRI frozen release, consult this document's SRI matrix
- If the tag is an sv2-tp release, consult this document's sv2-tp matrix

If the Bitcoin Core version is incompatible, the containers will fail to connect. The typical error is a Cap'n Proto schema mismatch or IPC protocol error in the container logs.
