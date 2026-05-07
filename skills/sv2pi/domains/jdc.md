### Deploy JD Client (JDC)

*Requires: Template Provider (Bitcoin Core IPC or sv2-tp) + Pool with JDS enabled.*

```bash
bash {baseDir}/scripts/deploy-jd.sh $DEPLOY_TAG $BITCOIN_IPC_PATH
```

This:
- Creates `~/.sv2pi/jdc/config/` and writes `jdc-config.toml`
- Configures upstream to pool on localhost:3333 and JDS on localhost:3334
- Exposes port 34265 (downstream), 9091 (monitoring)

**If sv2-tp is deployed**, the JDC's template provider must be changed from `BitcoinCoreIpc` to `Sv2Tp`. The generated config uses IPC by default — the agent must update `[template_provider_type]` accordingly.

After deployment, verify:
```bash
docker logs jd_client_sv2 --tail 20
curl -s http://localhost:9091/api/v1/health
```



## Crash Diagnostics

Role evidence: read `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/miner-apps/jd-client/src/` before grepping logs.

```bash
# Can JDC reach pool?
docker exec jd_client_sv2 sh -c 'echo | nc -w2 pool_host 3333 && echo "POOL REACHABLE" || echo "POOL UNREACHABLE"'
```
