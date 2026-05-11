### Deploy Translator Proxy

*Requires: Upstream SV2 mining server (JDC, Pool, or remote).*

```bash
bash {baseDir}/scripts/deploy-translator.sh $DEPLOY_TAG [upstream-host] [upstream-port] [config-dir] [monitoring-bind-mode] [wireguard-ip]
```

This:
- Creates `~/.sv2pi/translator/config/` and writes `tproxy-config.toml`
- Upstream points to JDC on localhost:34265 by default
- Exposes port `34255` on `0.0.0.0` (SV1 downstream), and `9092` on `localhost` by default (or WireGuard when requested)

**Upstream flexibility:** The Translator Proxy is not coupled to any specific local deployment. Point it at whatever SV2 mining server the user needs:
- **Local JDC:** `localhost:34265` (default)
- **Local Pool:** `localhost:3333`
- **Remote upstream:** any reachable SV2 mining server address

After deployment, verify:
```bash
docker logs translator_sv2 --tail 20
curl -s http://localhost:9092/api/v1/health
curl -s http://localhost:9092/api/v1/sv1/clients
```

## SV1 Load Generation with minerd

The Translator Proxy terminates SV1 connections on port 34255. To generate SV1 traffic and verify end-to-end share flow through the SV2 pipeline, deploy minerd as an SV1 load generator. See `{baseDir}/domains/minerd.md` for full deployment instructions.

```
minerd ──(SV1 plain JSON-RPC)──► translator_sv2:34255
                                      └──(SV2 Noise)──► JDC:34265 or Pool:3333
```

Together, translator + minerd enable:
- **Handshake testing** — verify SV1→SV2 protocol translation works end-to-end
- **Share-flow testing** — confirm shares traverse the full SV1→SV2→upstream path
- **Sustained load** — simulate real SV1 miner traffic for pool hashrate monitoring

After deploying minerd, cross-reference translator state:
```bash
curl -s http://localhost:9092/api/v1/sv1/clients | python3 -m json.tool
journalctl --user -u minerd-1 -f
```


## Crash Diagnostics

Role evidence: read `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/miner-apps/translator/src/` before grepping logs.

```bash
# Can translator reach JDC?
docker exec translator_sv2 sh -c 'echo | nc -w2 jdc_host 34265 && echo "JDC REACHABLE" || echo "JDC UNREACHABLE"'
```
