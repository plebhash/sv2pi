# Sv2 CPU Miner

### Step 11 — Deploy Sv2 CPU Miner

The Sv2 CPU miner is a testing tool (`github.com/plebhash/sv2-cpu-miner`). It is not part of the SRI suite. Deploy it to verify Pool and JDC deployments by simulating real miners that submit shares over SV2 channels.

**Prerequisites:** A running pool (Step 6) or JDC (Step 7) must be up and accepting connections. The miner connects directly to whichever Sv2 endpoint the user specifies.

#### Configuration Parameters

Load `{baseDir}/references/sv2-apps/cpu-miner-config-reference.md` for semantic explanations of every parameter. Key parameters the agent MUST resolve:

```
+---------------------+-------------------+------------------------------------------------------------------------+
| Parameter           | Default           | How to resolve                                                         |
+---------------------+-------------------+------------------------------------------------------------------------+
| server_addr         | 127.0.0.1:3333    | Pool listen_address (direct) or JDC listening_address (via JDC).      |
|                     |                   | Default: 3333 for pool, 34265 for JDC.                                 |
| auth_pk             | 9auqWEz... (SRI)  | Pool or JDC authority_public_key. Read from deployed config toml.      |
| n_extended_channels | 2                 | Extended Channels. Set to 0 when connecting directly to pool (no JDS). |
| n_standard_channels | 2                 | Standard Channels. Always valid. At least one type must be > 0.        |
| cpu_usage_percent   | 100               | CPU throttle 1-100. Lower for testing without maxing out host.         |
+---------------------+-------------------+------------------------------------------------------------------------+
```

Additional parameters with defaults: `user_identity` (`username`), `device_id` (`sv2-cpu-miner`), `nominal_hashrate_multiplier` (`1.0`), `single_submit` (`false`).

#### User intent extraction

When the user asks to deploy the cpu miner, extract intent from their phrasing:
- **"connect to the pool"** → `server_addr` = `127.0.0.1:3333`, `auth_pk` from pool config
- **"connect to the JDC"** → `server_addr` = `127.0.0.1:34265`, `auth_pk` from JDC config
- **"X extended, Y standard channels"** → set `n_extended_channels` and `n_standard_channels`
- **"N% CPU"** → set `cpu_usage_percent`
- If the user says "use defaults" or doesn't specify, apply the defaults in the table above

**CRITICAL: Always resolve `auth_pk` from the deployed config files.** Never guess it. If neither pool nor JDC is deployed, tell the user a pool or JDC must be deployed first.

#### Deployment

```bash
bash {baseDir}/scripts/deploy-cpu-miner.sh \
  <server_addr> <auth_pk> <n_extended_channels> <n_standard_channels> <cpu_usage_percent>
```

This:
- Clones `https://github.com/plebhash/sv2-cpu-miner` to `~/.sv2pi/cpu-miner/src/`
- Writes `config.toml` with the specified parameters
- Pulls `rust:latest` Docker image
- Starts a container (`sv2-cpu-miner`) with `--network host`, builds `--release`, and runs the miner

Compilation takes 2–5 minutes (Rust release build + dependency fetching). The script handles the Docker pull separately to avoid timeout issues.

#### Verification

After compiling, the miner logs show share submissions. Verify:

```bash
# Check miner share submissions (wait 2-3 minutes for compilation first)
docker logs sv2-cpu-miner --tail 50 | grep -E 'Submitting share'

# Verify extended shares
docker logs sv2-cpu-miner --tail 50 | grep "SubmitSharesExtended"

# Verify standard shares
docker logs sv2-cpu-miner --tail 50 | grep "SubmitSharesStandard"
```

Cross-reference with pool monitoring API:

```bash
# Confirm client is connected
curl -s http://localhost:9090/api/v1/clients | python3 -m json.tool

# Count active channels
curl -s http://localhost:9090/api/v1/server/channels | python3 -m json.tool
```

Expected: the pool API shows one client with `extended_channels_count` and `standard_channels_count` matching the deployment parameters. Shares appear in both the miner logs and the pool's `shares_accepted_total`.

#### Crash Diagnostics

If the miner container exits or logs show errors:

```bash
# Is the container running?
docker ps --filter "name=sv2-cpu-miner"

# Check exit status if stopped
docker ps -a --filter "name=sv2-cpu-miner" --format "{{.Status}}"

# Compilation errors (during build phase)
docker logs sv2-cpu-miner --tail 30 | grep -i 'error'

# Connectivity errors (after build, during runtime)
docker logs sv2-cpu-miner --tail 30 | grep -iE 'connect|reject|timeout|fail'
```

Common failure modes:
- **`edition2024` not stabilized** → wrong Rust image (must be `rust:latest`, not older slim tags)
- **`Noise handshake failed`** → `auth_pk` doesn't match the server's `authority_public_key`
- **`Connection refused`** → `server_addr` is wrong or the target service isn't running
- **Container exits immediately** → compile error; check full logs for the specific Rust error

---
