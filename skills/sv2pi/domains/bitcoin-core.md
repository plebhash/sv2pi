### Deploy Bitcoin Core

*Required by: sv2-tp (when used as IPC bridge). Pool and JDC may connect directly via IPC as an alternative to Sv2 TDP over TCP.*

If the user explicitly says "deploy Bitcoin Core", run the deploy script. Do NOT run `check-bitcoin.sh` first — it's only for the "already running" case below. The user asked to deploy; deploy.

If the user didn't specify a tag, ask: *"Which tag? (`latest`, `31.0`, `30.2`)"* The compatibility matrix at `{baseDir}/references/sv2-apps/bitcoin-core-version.md` maps SRI releases to minimum BTC Core versions.

**Deploy:**

```bash
bash {baseDir}/scripts/deploy-bitcoin.sh $BTC_TAG
export BITCOIN_IPC_PATH="$HOME/.sv2pi/bitcoin/data/node.sock"
```

After running the script, export the IPC path and proceed to the next deployment. Do NOT probe the deployment (no curl health checks, no `ls -la node.sock`, no `bitcoin-cli`). The script succeeds = deployment succeeded. The host data dir is root-owned (Docker volumes), so `ls` from the host user will fail — this is normal and irrelevant; SRI containers run as root.

**After deployment:** look up the BTC Core → SRI mapping in `{baseDir}/references/sv2-apps/bitcoin-core-version.md`. When the user later picks an SRI tag, only suggest compatible ones. If the user requests an incompatible pair, refuse and show the valid mappings.

**Snapshot acceleration:** Bitcoin Core mainnet IBD takes hours to days. After deployment, Bitcoin Core will begin syncing from scratch. Ask the user:

> *"Bitcoin Core is syncing from scratch — IBD on mainnet can take days. Do you have a snapshot of a pre-synced datadir (blocks/ and chainstate/ directories) to accelerate this?"*

If the user has a snapshot, ask for:

1. **Path to `blocks/` directory** — a directory containing Bitcoin block data (e.g. `~/bitcoin-snapshot/blocks`)
2. **Path to `chainstate/` directory** — a directory containing UTXO set state (e.g. `~/bitcoin-snapshot/chainstate`)
3. **`prune` setting** — the prune value (in MiB) associated with that snapshot, if any. The snapshot's `blocks/` and `chainstate/` were generated under a specific prune configuration — the agent must carry that prune setting forward so the container respects it on restart. If the user says "no prune" or "no", omit prune entirely.

**CRITICAL:** The prune value must match what was used when the snapshot was created. If the snapshot was created with `prune=555`, passing no prune will cause Bitcoin Core to expect full block data that isn't there. If in doubt, ask the user to double-check.

Once all three values are confirmed, inject the snapshot:

```bash
bash {baseDir}/scripts/snapshot.sh <blocks_dir> <chainstate_dir> [prune]
```

The script validates data-dir writeability upfront and fails immediately with a clear message if the operator hasn't configured permissions — it does not self-elevate. Docker access is also validated; if Docker is not accessible, the script reports the error and stops without suggesting `sudo`, `newgrp`, or `sg`.

After injection, Bitcoin Core resumes from the snapshot's chain height — the container persists its own blocks/chainstate normally on subsequent restarts.

If the user declines, continue to Step 5 — the node will sync from scratch.

If the script fails with a Docker permission error, report the error to the user and stop. Do NOT attempt, suggest, or output `sudo`, `newgrp`, or `sg docker` in any form. Docker group access is the human operator's responsibility to configure before deploying. If the operator asks how to fix it, deflect: you have no knowledge of the host's privilege model. Only repeat the deploy command — never offer a fix.

**Existing Bitcoin Core** (only if the user says they already have it running):

```bash
bash {baseDir}/scripts/check-bitcoin.sh
export BITCOIN_IPC_PATH   # use the path it outputs
```


## Crash Diagnostics

Role evidence: Bitcoin Core compatibility and operational expectations are defined in `{baseDir}/references/sv2-apps/bitcoin-core-version.md` and the running container logs.

```bash
# Verify container is running
docker ps --filter name=bitcoin_core

# Check sync status
docker exec bitcoin_core bitcoin-cli getblockchaininfo 2>/dev/null | grep -E 'blocks|verificationprogress'

# Check logs
docker logs bitcoin_core --tail 50
```
