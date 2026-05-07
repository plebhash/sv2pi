### Deploy Translator Proxy

*Requires: Upstream SV2 mining server (JDC, Pool, or remote).*

```bash
bash {baseDir}/scripts/deploy-translator.sh $DEPLOY_TAG
```

This:
- Creates `~/.sv2pi/translator/config/` and writes `tproxy-config.toml`
- Upstream points to JDC on localhost:34265 by default
- Exposes port 34255 (SV1 downstream), 9092 (monitoring)

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



## Crash Diagnostics

Role evidence: read `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/miner-apps/translator/src/` before grepping logs.

```bash
# Can translator reach JDC?
docker exec translator_sv2 sh -c 'echo | nc -w2 jdc_host 34265 && echo "JDC REACHABLE" || echo "JDC UNREACHABLE"'
```
