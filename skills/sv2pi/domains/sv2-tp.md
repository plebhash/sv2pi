### Deploy sv2-tp (SV2 Template Provider)

*Requires: Bitcoin Core (IPC).*
*Required by: Pool and JDC (when using Sv2 TDP over TCP). Direct IPC remains an alternative — sv2-tp is one of many possible TDP-compliant template providers.*

sv2-tp is an **optional** standalone Template Provider that bridges Bitcoin Core IPC to the Template Distribution Protocol over TCP. Use cases:

- **Decoupled deployments:** Pool and JDC don't need direct IPC socket access — sv2-tp handles IPC reconnection
- **TP-as-a-Service:** Run sv2-tp independently to serve templates to remote pools and JDCs
- **Multi-tenant:** One sv2-tp instance can serve multiple downstream consumers (Pool, JDC, or both)

**Compatibility check before deploying:** sv2-tp v1.1.0 requires Bitcoin Core v31.0+. If deploying against v30.2, use sv2-tp v1.0.6. Check `{baseDir}/references/sv2-apps/bitcoin-core-version.md` for the full matrix.

Deploy:

```bash
bash {baseDir}/scripts/deploy-tp.sh v1.1.0 $HOME/.sv2pi/bitcoin/data mainnet
```

This:
- Pulls `stratumv2/sv2-tp:v1.1.0`
- Connects to Bitcoin Core via IPC (`-ipcconnect=unix`) through the shared datadir volume
- Listens for Template Distribution Protocol connections on port 8442 (mainnet default)
- Binds `0.0.0.0:8442` by default (access from other containers)

**If sv2-tp is deployed, Pool and JDC must use `Sv2Tp` instead of `BitcoinCoreIpc`:**

```toml
# In pool-config.toml or jdc-config.toml:
[template_provider_type.Sv2Tp]
address = "127.0.0.1:8442"
```

Do NOT probe the deployment after the script succeeds.



## Crash Diagnostics

Role evidence: read `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/src/sv2/` (template_provider, connman, messages, noise, transport) before grepping logs.

```bash
# Verify container is running
docker ps --filter name=sv2_tp

# Check IPC socket inside sv2-tp
docker exec sv2_tp ls -la /home/bitcoin/.bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible to sv2-tp"

# Check sv2-tp IPC connection status
docker logs sv2_tp --tail 20 | grep -i 'connect\|ipc\|error'

# Check logs
docker logs sv2_tp --tail 50
```
