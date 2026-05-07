### Deploy Pool (with optional embedded JDS)

*Requires: Template Provider (Bitcoin Core IPC or sv2-tp).*
*Required by: JDC (if JD support enabled), Translator (if connecting directly to Pool).*

**CRITICAL:** Never deploy to production with the default keypairs from the Docker config templates. The pool's `authority_public_key`/`authority_secret_key` and the JDC's keypair must be unique per deployment. Generate fresh keys:

```bash
bash {baseDir}/scripts/generate-keypair.sh
```

This uses `key-utils` (the official SRI key generation crate) inside a Dockerized Rust environment — no local Rust toolchain needed. The output is a base58-encoded secp256k1 keypair in TOML-ready format.

**Security tradeoff:** The generated private keys are exposed to the LLM context and potentially exposed to LLM providers. This is a deliberate tradeoff of agentic deployments in sv2pi — the user accepts this. Encourage the user to ask the agent to rotate keys across deployments.

Generate **two** secp256k1 keypairs: one for the pool app, one for the JDC app. Copy the pool's `authority_public_key` into the JDC's `[[upstreams]].authority_pubkey`. The JDC's own authority keypair is separate and used for downstream Translator connections.

**JD support is optional.** If the user does not need Job Declaration (miners declaring custom templates), omit the JDS port and authority keypair from the pool config. This yields a simpler pool-only deployment.

If the user has already reviewed the config templates (Step 2) and agrees to use defaults, deploy directly:

```bash
bash {baseDir}/scripts/deploy-pool.sh $DEPLOY_TAG $BITCOIN_IPC_PATH
```

If the user's request is vague (e.g. "deploy a pool"), walk them through each configuration choice from the frozen Docker config template, offering the default value each time. Key parameters:

| Parameter | Default | Ask |
|---|---|---|
| `coinbase_reward_script` | `addr(...)` (SRI community wallet) | "What payout address? (default: SRI community wallet)" |
| `listen_address` | `0.0.0.0:3333` | "Stratum port? (default 3333)" |
| `JDS listen_address` | `0.0.0.0:3334` | "JDS port? (default 3334, or disable JD support)" |
| `shares_per_minute` | `6.0` | "Target shares/minute? (default 6)" |
| `pool_signature` | `SRI Mainnet Pool` | "Pool signature string?" |
| Authority keypair | hardcoded example | Warn: "Replace with your own keypair for production" |

Never ask about ports/values the user already specified. If the user says "use defaults", deploy immediately.

After the script succeeds, proceed to the next deployment. Do NOT probe the deployment.



## Crash Diagnostics

Role evidence: read `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/pool-apps/pool/src/` before grepping logs.

```bash
# Example: grep pool logs for connection errors
docker logs pool_sv2 --tail 200 | grep -E 'error|Error|ERR|fail|timeout|rejected'

# Example: grep for IPC-related errors
docker logs pool_sv2 --tail 200 | grep -i 'ipc\|template\|socket'

# Is Bitcoin IPC mounted?
docker exec pool_sv2 ls -la /bitcoin/node.sock

# Check IPC socket inside the pool container
docker exec pool_sv2 ls -la /bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible to pool"
```

### Config Validation

Compare running configs against example configs from the source:

```bash
diff ~/.sv2pi/pool/config/pool-config.toml ~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/config-examples/mainnet/pool-config-bitcoin-core-ipc-example.toml || true
```
