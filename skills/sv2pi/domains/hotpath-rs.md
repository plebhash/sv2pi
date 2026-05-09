### Deploy hotpath-enabled SRI apps

`hotpath-rs` is an alternative deployment strategy of sv2pi skill.

It focuses on observability of performance, providing data of CPU and memory profiling for each SRI app.

It replaces the standard `stratumv2/*` Docker Hub images with locally-built containers from [SV2-bot/sv2-apps](https://github.com/SV2-bot/sv2-apps). The fork builds all three SRI apps with `--features hotpath`, enabling an additional hotpath-rs protocol port on each service.

Standard TOML configs are reused — hotpath deployments share the same configuration assumptions as standard SRI deployments (see `domains/{pool,jdc,translator}` for reference on each). No config changes are needed.

#### Version Support

Hotpath-enabled SRI apps are available for SRI releases **v0.4.0 and above**. Lower versions are not supported.

The fork tags follow the pattern `v{VERSION}-hotpath-rs` (e.g. `v0.4.0-hotpath-rs`).

#### Port Mapping

Each service exposes a hotpath port on the host, mapped to container port `6770`:

| Service | Host Port | Container Port |
|---|---|---|
| pool_sv2 | 6771 | 6770 |
| jd_client_sv2 | 6772 | 6770 |
| translator_sv2 | 6773 | 6770 |

Standard ports (3333, 34265, 34255) and monitoring ports (9090, 9091, 9092) remain unchanged.

#### Deployment

**Deploy only the roles the user needs** — follow the same dependency graph as standard deployments.

```bash
bash {baseDir}/scripts/deploy-hotpath.sh $VERSION [bitcoin-ipc-path] [pool] [jdc] [translator]
```

Service keywords (`pool`, `jdc`, `translator`) are optional. If none are specified, all three are deployed. Examples:

```bash
bash {baseDir}/scripts/deploy-hotpath.sh 0.4.0 pool jdc      # pool + JDC only
bash {baseDir}/scripts/deploy-hotpath.sh 0.4.0 translator    # translator only
bash {baseDir}/scripts/deploy-hotpath.sh 0.4.0               # all three
```

This:
- Validates `$VERSION` is >= 0.4.0
- Verifies Bitcoin Core IPC socket (only when pool or JDC is requested)
- Checks that standard config directories exist for the requested services
- Stops existing containers for the requested services
- Clones `SV2-bot/sv2-apps` at tag `v$VERSION-hotpath-rs` (shallow)
- Runs `docker compose build` for the requested services
- Runs `docker compose up -d` to start only the requested services

#### Verification

```bash
docker ps --filter "name=pool_sv2" --filter "name=jd_client_sv2" --filter "name=translator_sv2" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

curl -s http://localhost:9090/api/v1/health | python3 -m json.tool
curl -s http://localhost:9091/api/v1/health | python3 -m json.tool
curl -s http://localhost:9092/api/v1/health | python3 -m json.tool
```

Verify hotpath ports are reachable:

```bash
nc -z localhost 6771 && echo "pool hotpath OK"
nc -z localhost 6772 && echo "jdc hotpath OK"
nc -z localhost 6773 && echo "translator hotpath OK"
```

#### Switching Back to Standard

Stop hotpath containers and redeploy with standard scripts:

```bash
docker rm -f pool_sv2 jd_client_sv2 translator_sv2
bash {baseDir}/scripts/deploy-pool.sh main ~/.sv2pi/bitcoin/data/node.sock
bash {baseDir}/scripts/deploy-jdc.sh main ~/.sv2pi/bitcoin/data/node.sock
bash {baseDir}/scripts/deploy-translator.sh main
```

Configs in `~/.sv2pi/{pool,jdc,translator}/config/` are preserved across both deployment modes.

## Crash Diagnostics

```bash
docker ps -a --filter "name=pool_sv2" --filter "name=jd_client_sv2" --filter "name=translator_sv2"

docker logs pool_sv2 --tail 200 | grep -E 'error|Error|ERR|fail|timeout|rejected'
docker logs jd_client_sv2 --tail 200 | grep -E 'error|Error|ERR|fail|timeout|rejected'
docker logs translator_sv2 --tail 200 | grep -E 'error|Error|ERR|fail|timeout|rejected'
```

Check Bitcoin IPC visibility and hotpath port binding inside containers:

```bash
docker exec pool_sv2 ls -la /root/.bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible"
docker exec jd_client_sv2 ls -la /root/.bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible"
docker exec pool_sv2 ss -tlnp | grep 6770 || echo "hotpath port not bound"
docker exec jd_client_sv2 ss -tlnp | grep 6770 || echo "hotpath port not bound"
docker exec translator_sv2 ss -tlnp | grep 6770 || echo "hotpath port not bound"
```
