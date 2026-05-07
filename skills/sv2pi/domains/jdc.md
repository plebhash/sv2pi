### Deploy JD Client (JDC)

*Requires: Pool with JDS enabled + a Template Provider (Bitcoin Core IPC or Sv2Tp over TCP).*

The upstream pool and JDS addresses are user-selected. The SRI community defaults are:

- **Pool:** `75.119.150.111:3333`
- **JDS:**  `75.119.150.111:3334`

When deploying, the agent must ask the user which Template Provider to use: **Sv2Tp over TCP** or **Bitcoin Core IPC**. Do not infer the choice from whether sv2-tp is running — the user must be asked or must explicitly state their preference. The agent must also react if the user volunteers this choice without being prompted.

```bash
bash {baseDir}/scripts/deploy-jdc.sh $DEPLOY_TAG $BITCOIN_IPC_PATH [pool-host] [pool-port] [jds-port]
```

This:
- Creates `~/.sv2pi/jdc/config/` and writes `jdc-config.toml`
- Uses SRI community defaults (`75.119.150.111:3333` / `75.119.150.111:3334`) when no overrides are supplied
- Exposes port 34265 (downstream), 9091 (monitoring)

After deployment, verify:

```
docker logs jd_client_sv2 --tail 20
curl -s http://localhost:9091/api/v1/health
```

Then deploy **sv2-cpu-miner** pointed at JDC as a smoke test. Configure it with **1 extended channel** and **1 standard channel**. Confirm both channels open successfully:

```
OpenExtendedMiningChannel.Success
OpenStandardMiningChannel.Success
```

Stop sv2-cpu-miner after validation passes.

## Crash Diagnostics

Role evidence: read `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/miner-apps/jd-client/src/` before grepping logs.

```bash
# Can JDC reach pool?
docker exec jd_client_sv2 sh -c 'echo | nc -w2 pool_host 3333 && echo "POOL REACHABLE" || echo "POOL UNREACHABLE"'
```
